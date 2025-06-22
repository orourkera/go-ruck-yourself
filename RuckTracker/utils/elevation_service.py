import requests
import logging
from functools import lru_cache

logger = logging.getLogger(__name__)

@lru_cache(maxsize=5000)
def get_elevation(lat: float, lon: float) -> float | None:
    """Fetch ground elevation (meters) for a coordinate using the Open-Topo-Data API.

    Results are cached in-process via ``lru_cache`` so subsequent calls for the
    same coordinate pair are free. If the service is unreachable, *None* is
    returned so callers can gracefully degrade.
    """
    try:
        resp = requests.get(
            "https://api.opentopodata.org/v1/srtm90m",
            params={"locations": f"{lat},{lon}"},
            timeout=3,
        )
        if resp.status_code == 200:
            data = resp.json()
            results = data.get("results")
            if results and "elevation" in results[0]:
                return float(results[0]["elevation"])
    except Exception as e:
        logger.warning(f"Elevation lookup failed for {lat},{lon}: {e}")
    return None
