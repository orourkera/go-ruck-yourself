#!/usr/bin/env python3
"""Generate a ruck highlight video using OpenAI's Sora 2 model.

Workflow:
  1. Render a branded route card with the ruck path + key stats.
  2. Submit the card and prompt to the Sora 2 API.
  3. Save the returned MP4 for quick sharing experiments.

Requirements
-----------
  * Python 3.9+
  * pip install openai requests Pillow polyline
  * Environment variables:
        OPENAI_API_KEY        – Sora access
        STADIA_MAPS_API_KEY   – for the static map tiles (Stadia Maps Static API)

Usage
-----
    python scripts/generate_sora_ruck_video.py \
        --output ./ruck_summary.mp4 \
        --route-card ./route_card.png

You can plug in your own stats/geometry by swapping SAMPLE_STATS/SAMPLE_ROUTE
or by pointing --route-json to a file containing {"stats": {...}, "route": [...] }.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path
from typing import Iterable, List, Sequence, Tuple

import polyline
import requests
from openai import OpenAI
from PIL import Image, ImageDraw, ImageFont


MAPBOX_STYLE = "mapbox/outdoors-v12"
SORA_MODEL = "sora-2"
CARD_WIDTH = 1280
CARD_HEIGHT = 720


@dataclass
class RuckStats:
    user: str
    distance_km: float
    duration_hms: str
    elevation_gain_m: float
    pace: str
    location: str
    date: str

    @classmethod
    def from_dict(cls, data: dict) -> "RuckStats":
        return cls(
            user=data.get("user", "Rucker"),
            distance_km=float(data.get("distance_km", 0.0)),
            duration_hms=data.get("duration_hms", "0m"),
            elevation_gain_m=float(data.get("elevation_gain_m", 0.0)),
            pace=data.get("pace", "0:00 / km"),
            location=data.get("location", "Unknown"),
            date=data.get("date", ""),
        )


# Sample payload for fast iteration (Chicago Lakefront trail out-and-back)
SAMPLE_STATS = RuckStats(
    user="Al",
    distance_km=8.2,
    duration_hms="1h 10m",
    elevation_gain_m=34,
    pace="8:32 / km",
    location="Chicago Lakefront Trail",
    date="2025-10-05",
)

SAMPLE_ROUTE: List[Tuple[float, float]] = [
    (-87.620693, 41.875866),
    (-87.620506, 41.879842),
    (-87.619857, 41.884125),
    (-87.618027, 41.889795),
    (-87.617356, 41.894815),
    (-87.615189, 41.900036),
    (-87.61322, 41.905187),
    (-87.612305, 41.909377),
    (-87.609863, 41.913896),
    (-87.606621, 41.918086),
    (-87.603378, 41.921742),
    (-87.600563, 41.925237),
    (-87.598076, 41.928151),
    (-87.595589, 41.93149),
    (-87.593445, 41.935015),
    (-87.592331, 41.939203),
    (-87.591705, 41.943327),
    (-87.591362, 41.947898),
    (-87.591705, 41.95228),
    (-87.592674, 41.9563),
    (-87.594147, 41.960161),
    (-87.596077, 41.963677),
    (-87.598221, 41.967011),
    (-87.600021, 41.970114),
    (-87.602119, 41.973065),
    (-87.603958, 41.975726),
    (-87.606102, 41.979042),
]


PROMPT_TEMPLATE = """You are a motion graphics director.
Using the supplied route card, create a cinematic {duration}s video summary for a ruck session.

- Animate the route trace with energetic motion graphics that build over time.
- Overlay key stats: distance {distance_km:.1f} km, time {duration_hms}, elevation +{elevation_gain_m:.0f} m, pace {pace}.
- Include a short title "{user}'s Ruck – {location}" and the date {date}.
- Layer an upbeat synth soundtrack that matches a motivational post-workout vibe.
- Use bold typography, outdoor-inspired colors, and light grain for texture.
"""


def encode_route_polyline(points: Sequence[Tuple[float, float]] | Sequence[Sequence[float]]) -> str:
    """Return an encoded polyline for Mapbox (expects input as (lon, lat))."""

    if not points:
        raise ValueError("Route points are required to render the map")

    converted = []
    for pt in points:
        if isinstance(pt, dict):
            lon = float(pt.get("lon"))
            lat = float(pt.get("lat"))
        else:
            lon = float(pt[0])
            lat = float(pt[1])
        converted.append((lat, lon))
    return polyline.encode(converted)


def fetch_stadia_static(route: Sequence[Tuple[float, float]], token: str) -> Image.Image:
    """Retrieve a static map image with the route overlayed using Stadia Maps."""

    # Calculate bounds for the route
    lons = [p[0] for p in route]
    lats = [p[1] for p in route]
    min_lon, max_lon = min(lons), max(lons)
    min_lat, max_lat = min(lats), max(lats)

    # Add 10% padding
    lon_pad = (max_lon - min_lon) * 0.1
    lat_pad = (max_lat - min_lat) * 0.1
    bbox = f"{min_lon-lon_pad},{min_lat-lat_pad},{max_lon+lon_pad},{max_lat+lat_pad}"

    # Build path parameter (lon,lat pairs separated by |)
    path_coords = "|".join([f"{lon},{lat}" for lon, lat in route])

    url = (
        f"https://tiles.stadiamaps.com/static/outdoors/"
        f"path({path_coords})/"
        f"{CARD_WIDTH}x{CARD_HEIGHT}@2x.png"
        f"?api_key={token}"
    )

    resp = requests.get(url, timeout=20)
    resp.raise_for_status()
    return Image.open(BytesIO(resp.content)).convert("RGB")


def _load_font(size: int) -> ImageFont.FreeTypeFont:
    """Try to load a nicer font; fall back to default if unavailable."""

    preferred = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/SFNSDisplay.ttf",
        "/System/Library/Fonts/SFNSText.ttf",
        "/Library/Fonts/Arial.ttf",
    ]
    for path in preferred:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size)
            except Exception:  # pragma: no cover - font loading best effort
                continue
    return ImageFont.load_default()


def render_route_card(
    route: Sequence[Tuple[float, float]],
    stats: RuckStats,
    token: str,
    outfile: Path,
) -> Path:
    """Fetch the static map, overlay stats, and save to PNG."""

    base_img = fetch_stadia_static(route, token)
    draw = ImageDraw.Draw(base_img)

    title_font = _load_font(52)
    stats_font = _load_font(34)

    # Translucent panel for stats
    panel_height = 180
    panel = Image.new("RGBA", (CARD_WIDTH, panel_height), (0, 0, 0, 128))
    base_img.paste(panel, (0, CARD_HEIGHT - panel_height), panel)

    margin = 50
    y = CARD_HEIGHT - panel_height + 30

    title = f"{stats.user}'s Ruck – {stats.location}".strip()
    draw.text((margin, y), title, font=title_font, fill=(255, 255, 255))

    stat_line = (
        f"Distance {stats.distance_km:.1f} km   •   Time {stats.duration_hms}   •   "
        f"Elevation +{stats.elevation_gain_m:.0f} m   •   Pace {stats.pace}"
    )
    draw.text((margin, y + 72), stat_line, font=stats_font, fill=(235, 235, 235))

    if stats.date:
        draw.text((margin, y + 120), stats.date, font=stats_font, fill=(200, 200, 200))

    outfile.parent.mkdir(parents=True, exist_ok=True)
    base_img.save(outfile, format="PNG")
    return outfile


def build_sora_prompt(stats: RuckStats, duration: int) -> str:
    return PROMPT_TEMPLATE.format(duration=duration, **stats.__dict__)


def call_sora(
    client: OpenAI,
    prompt: str,
    route_card_path: Path,
    duration_seconds: int,
    output_path: Path,
) -> Path:
    image_b64 = base64.b64encode(route_card_path.read_bytes()).decode("utf-8")

    response = client.responses.create(
        model=SORA_MODEL,
        input=[
            {
                "role": "user",
                "content": [
                    {"type": "input_text", "text": prompt},
                    {"type": "input_image", "image_base64": image_b64},
                ],
            }
        ],
        video={"duration_seconds": duration_seconds, "format": "mp4"},
    )

    try:
        video_part = response.output[0].content[0].video
        video_data = getattr(video_part, "data", None) or getattr(video_part, "b64_json", None)
        if video_data is None:
            raise ValueError("Sora response missing video content")
    except (AttributeError, IndexError) as exc:  # pragma: no cover - defensive parsing
        raise ValueError(f"Unexpected Sora response structure: {response}") from exc

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(base64.b64decode(video_data))
    return output_path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate a Sora-based ruck highlight video")
    parser.add_argument("--route-card", type=Path, default=Path("./route_card.png"), help="Where to save the generated route card PNG")
    parser.add_argument("--output", type=Path, default=Path("./ruck_summary.mp4"), help="Where to save the generated MP4")
    parser.add_argument("--duration", type=int, default=12, help="Requested video duration in seconds")
    parser.add_argument("--route-json", type=Path, help="Optional JSON file containing {\"stats\": {...}, \"route\": [[lon,lat], ...]} ")
    return parser.parse_args()


def load_payload(route_json: Path | None) -> tuple[RuckStats, Sequence[Tuple[float, float]]]:
    if not route_json:
        return SAMPLE_STATS, SAMPLE_ROUTE

    data = json.loads(route_json.read_text())
    stats = RuckStats.from_dict(data.get("stats", {}))
    route_raw = data.get("route")
    if not route_raw:
        raise ValueError("Route JSON must include a 'route' key with coordinate pairs")
    route = [(float(pt[0]), float(pt[1])) for pt in route_raw]
    return stats, route


def ensure_env_var(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Environment variable {name} is required")
    return value


def main() -> None:
    args = parse_args()
    stats, route = load_payload(args.route_json)

    stadia_token = ensure_env_var("STADIA_MAPS_API_KEY")
    openai_api_key = ensure_env_var("OPENAI_API_KEY")

    print("Rendering route card with Stadia Maps…")
    render_route_card(route, stats, stadia_token, args.route_card)

    client = OpenAI(api_key=openai_api_key)
    prompt = build_sora_prompt(stats, args.duration)

    print("Requesting Sora video (this can take ~1 minute)…")
    output_path = call_sora(
        client=client,
        prompt=prompt,
        route_card_path=args.route_card,
        duration_seconds=args.duration,
        output_path=args.output,
    )

    print(f"Saved video to {output_path.resolve()}")


if __name__ == "__main__":
    main()
