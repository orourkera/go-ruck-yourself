from flask import request, g, jsonify
from flask_restful import Resource
import logging
import time
from typing import Any, Dict
import re
from datetime import datetime, timezone, timedelta
import os
import json

from ..supabase_client import get_supabase_client
from ..services.arize_observability import observe_openai_call
from .schemas import GoalCreateSchema, SUPPORTED_METRICS, SUPPORTED_UNITS, SUPPORTED_WINDOWS
from ..utils.ai_guardrails import prefilter_user_input, validate_goal_draft_payload

logger = logging.getLogger(__name__)

# ---- Optional OpenAI client (safe import / init) ----
try:
    from openai import OpenAI  # type: ignore
except Exception:
    OpenAI = None  # type: ignore

OPENAI_API_KEY = os.getenv('OPENAI_API_KEY')
openai_client = None
if OpenAI is None:
    logger.warning("[GOALS_PARSE] OpenAI library not available; LLM parsing disabled")
else:
    try:
        openai_client = OpenAI(api_key=OPENAI_API_KEY) if OPENAI_API_KEY else None
        if not openai_client:
            logger.warning("[GOALS_PARSE] OPENAI_API_KEY not configured; LLM parsing disabled")
    except Exception as _:
        openai_client = None
        logger.warning("[GOALS_PARSE] Failed to initialize OpenAI client; LLM parsing disabled")


def _require_auth() -> tuple[bool, Dict[str, Any] | None]:
    if not getattr(g, 'user', None):
        return False, ({"error": "Authentication required"}, 401)
    return True, None


def _parse_goal_text(text: str) -> Dict[str, Any] | None:
    """Very lightweight, rule-based parser to map common phrases to a goal draft.

    Supports metrics: distance_km_total, duration_minutes_total, steps_total,
    elevation_gain_m_total, power_points_total.

    Returns a dict compatible with GoalDraftSchema or None if not parseable.
    """
    low = text.lower()

    # Window parsing
    window = None
    if any(kw in low for kw in ["this week", "weekly"]):
        window = "weekly"
    elif any(kw in low for kw in ["this month", "monthly"]):
        window = "monthly"
    else:
        # in N days -> 7d or 30d
        m_days = re.search(r"\b(in|over|within)\s+(7|30)\s+days\b", low)
        if m_days:
            window = f"{m_days.group(2)}d"

    # Distance: e.g., "ruck 20 miles", "walk 15 km"
    m_dist = re.search(r"\b(\d+(?:\.\d+)?)\s*(mi|mile|miles|km|kilometer|kilometers|kilometre|kilometres)\b", low)
    if m_dist:
        val = float(m_dist.group(1))
        unit_raw = m_dist.group(2)
        unit = "mi" if unit_raw.startswith("mi") else "km"
        title = f"Distance: {val:g} {unit}"
        return {
            "title": title,
            "description": None,
            "metric": "distance_km_total",
            "target_value": val,
            "unit": unit,
            "window": window,
            "constraints_json": None,
            "start_at": None,
            "end_at": None,
            "deadline_at": None,
        }

    # Duration: e.g., "300 minutes", "min"
    m_dur = re.search(r"\b(\d+)\s*(minutes|min|minute)\b", low)
    if m_dur:
        val = float(m_dur.group(1))
        title = f"Duration: {int(val)} minutes"
        return {
            "title": title,
            "description": None,
            "metric": "duration_minutes_total",
            "target_value": val,
            "unit": "minutes",
            "window": window,
            "constraints_json": None,
            "start_at": None,
            "end_at": None,
            "deadline_at": None,
        }

    # Steps: e.g., "10000 steps"
    m_steps = re.search(r"\b(\d{3,})\s*steps?\b", low)
    if m_steps:
        val = float(m_steps.group(1))
        title = f"Steps: {int(val)}"
        return {
            "title": title,
            "description": None,
            "metric": "steps_total",
            "target_value": val,
            "unit": "steps",
            "window": window,
            "constraints_json": None,
            "start_at": None,
            "end_at": None,
            "deadline_at": None,
        }

    # Elevation: e.g., "1000 m elevation", "3000 ft climb"
    m_elev = re.search(r"\b(\d+(?:\.\d+)?)\s*(m|meter|meters|metre|metres|ft|feet)\b.*\b(elevation|gain|climb)?", low)
    if m_elev and ("elevation" in low or "gain" in low or "climb" in low):
        val = float(m_elev.group(1))
        unit_raw = m_elev.group(2)
        if unit_raw in ("ft", "feet"):
            val = val * 0.3048  # convert feet to meters
        title = f"Elevation gain: {int(round(val))} m"
        return {
            "title": title,
            "description": None,
            "metric": "elevation_gain_m_total",
            "target_value": float(round(val, 2)),
            "unit": "m",
            "window": window,
            "constraints_json": None,
            "start_at": None,
            "end_at": None,
            "deadline_at": None,
        }

    # Power points: e.g., "5000 points"
    m_pts = re.search(r"\b(\d{2,})\s*(points?|pts)\b", low)
    if m_pts:
        val = float(m_pts.group(1))
        title = f"Power points: {int(val)}"
        return {
            "title": title,
            "description": None,
            "metric": "power_points_total",
            "target_value": val,
            "unit": "points",
            "window": window,
            "constraints_json": None,
            "start_at": None,
            "end_at": None,
            "deadline_at": None,
        }

    return None


def _llm_parse_goal(cleaned_text: str) -> Dict[str, Any] | None:
    """Attempt to parse goal via OpenAI with strict JSON-only output.

    Returns a dict matching GoalDraftSchema on success, or None on any failure.
    """
    if not openai_client:
        return None

    # System and user prompts designed for deterministic, bounded JSON
    sys_prompt = (
        "You parse short fitness goal requests into STRICT JSON that matches a schema. "
        "Only output the JSON object with these keys: "
        "['title','description','metric','target_value','unit','window','constraints_json','start_at','end_at','deadline_at']. "
        "Never include explanations. If request is off-topic or unsafe, output exactly {}."
    )

    # Insert allow-lists to minimize hallucination
    enum_info = {
        "metrics": SUPPORTED_METRICS,
        "units": SUPPORTED_UNITS,
        "windows": SUPPORTED_WINDOWS,
    }

    user_prompt = (
        "Input: " + json.dumps({"text": cleaned_text}, ensure_ascii=False) + "\n" +
        "Rules:\n" +
        "- metric must be one of: " + ", ".join(SUPPORTED_METRICS) + "\n" +
        "- unit must be one of: " + ", ".join(SUPPORTED_UNITS) + "\n" +
        "- window is optional; if present, one of: " + ", ".join(SUPPORTED_WINDOWS) + "\n" +
        "- target_value is a non-negative number.\n" +
        "- Use null for any unknown optional fields.\n" +
        "- For distance goals, metric must be 'distance_km_total' and unit either 'km' or 'mi'.\n" +
        "- For duration goals, metric 'duration_minutes_total' and unit 'minutes'.\n" +
        "- For steps goals, metric 'steps_total' and unit 'steps'.\n" +
        "- For elevation goals, metric 'elevation_gain_m_total' and unit 'm'.\n" +
        "- For power points, metric 'power_points_total' and unit 'points'.\n" +
        "Return ONLY a compact JSON object without markdown fencing."
    )

    try:
        start_time = time.time()
        completion = openai_client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {"role": "system", "content": sys_prompt},
                {"role": "user", "content": user_prompt},
            ],
            max_tokens=200,
            temperature=0.2,
        )
        latency_ms = (time.time() - start_time) * 1000
        content = (completion.choices[0].message.content or "").strip()

        try:
            observe_openai_call(
                model="gpt-4o",
                messages=[
                    {"role": "system", "content": sys_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                response=content,
                latency_ms=latency_ms,
                user_id=getattr(getattr(g, 'user', None), 'id', None),
                context_type='goal_draft_parser',
                prompt_tokens=getattr(getattr(completion, 'usage', None), 'prompt_tokens', None),
                completion_tokens=getattr(getattr(completion, 'usage', None), 'completion_tokens', None),
                total_tokens=getattr(getattr(completion, 'usage', None), 'total_tokens', None),
                temperature=0.2,
                max_tokens=200,
                metadata={
                    'original_text_sample': cleaned_text[:200],
                },
            )
        except Exception as telemetry_err:
            logger.debug(f"[GOALS_PARSE] Telemetry logging failed: {telemetry_err}")
        # Must be raw JSON; attempt to find JSON object boundaries if any extra text leaked
        start = content.find('{')
        end = content.rfind('}')
        if start == -1 or end == -1 or end < start:
            logger.warning(f"[GOALS_PARSE] LLM returned non-JSON content: {content[:120]}")
            return None
        json_str = content[start:end + 1]
        data = json.loads(json_str)
        if not isinstance(data, dict) or not data:
            return None
        # Validate against schema and guardrails
        validated = validate_goal_draft_payload(data)
        return validated
    except Exception as e:
        logger.warning(f"[GOALS_PARSE] LLM parse failed: {e}")
        return None


def _llm_compose_message(original_text: str, draft: Dict[str, Any] | None) -> str | None:
    """Compose a short natural-language assistant response.

    - If draft is provided, acknowledge the interpreted goal briefly and invite confirmation/refinement.
    - If draft is None, ask a concise clarifying question.
    Returns a single short line (<= 140 chars preferred). If LLM is unavailable, returns a templated message.
    """
    try:
        if not openai_client:
            # Fallback templates
            if draft:
                title = draft.get('title') or 'your goal'
                return f"Proposed: {title}. Want to confirm or refine anything?"
            return "I couldn’t quite parse that. Can you add units or timeframe (e.g., 20 mi this month)?"

        sys = (
            "You are a concise assistant. Reply with a SINGLE short sentence (<=140 chars). "
            "If a goal draft is provided, confirm it briefly and invite confirmation/refinement. "
            "If not, ask one clarifying question to help parse the goal."
        )
        user_payload = {
            'original_text': original_text,
            'parsed_draft': draft or {},
        }
        user = (
            "Context:" + json.dumps(user_payload, ensure_ascii=False) + "\n"
            "Rules:\n"
            "- One sentence only, friendly and direct.\n"
            "- No markdown, no lists, no emojis.\n"
        )
        start_time = time.time()
        resp = openai_client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": sys},
                {"role": "user", "content": user},
            ],
            max_tokens=60,
            temperature=0.3,
        )
        latency_ms = (time.time() - start_time) * 1000
        msg = (resp.choices[0].message.content or '').strip()

        try:
            observe_openai_call(
                model="gpt-4o-mini",
                messages=[
                    {"role": "system", "content": sys},
                    {"role": "user", "content": user},
                ],
                response=msg,
                latency_ms=latency_ms,
                user_id=getattr(getattr(g, 'user', None), 'id', None),
                context_type='goal_helper_reply',
                prompt_tokens=getattr(getattr(resp, 'usage', None), 'prompt_tokens', None),
                completion_tokens=getattr(getattr(resp, 'usage', None), 'completion_tokens', None),
                total_tokens=getattr(getattr(resp, 'usage', None), 'total_tokens', None),
                temperature=0.3,
                max_tokens=60,
                metadata={
                    'original_text_sample': original_text[:200],
                    'has_draft': bool(draft),
                },
            )
        except Exception as telemetry_err:
            logger.debug(f"[GOALS_PARSE] Telemetry logging failed: {telemetry_err}")
        if msg:
            return msg
    except Exception as e:
        logger.warning(f"[GOALS_PARSE] compose message failed: {e}")
    # Final fallback
    if draft:
        title = draft.get('title') or 'your goal'
        return f"Proposed: {title}. Want to confirm or refine anything?"
    return "I couldn’t quite parse that. Can you add units or timeframe (e.g., 20 mi this month)?"

def _km_to_mi(km: float) -> float:
    try:
        return float(km) * 0.621371
    except Exception:
        return 0.0


def _compute_window_bounds(goal: Dict[str, Any]) -> tuple[str, str]:
    """Compute [start_iso, end_iso] bounds for evaluation based on goal window and explicit dates.

    Priority rules:
    - Start: max(window_start, start_at, created_at)
    - End: min(window_end, end_at, deadline_at, now)
    Window mappings:
      '7d' -> now-7d..now
      '30d' -> now-30d..now
      'weekly' -> start of current ISO week (Mon 00:00 UTC)..now
      'monthly' -> first day of current month 00:00 UTC..now
      'until_deadline' -> start_at/created_at .. min(deadline_at, now)
    """
    now = datetime.now(timezone.utc)

    window = goal.get('window')
    # Window-derived start/end
    window_start = None
    window_end = now

    if window == '7d':
        window_start = now - timedelta(days=7)
    elif window == '30d':
        window_start = now - timedelta(days=30)
    elif window == 'weekly':
        # Monday as start of ISO week
        today_utc = datetime(now.year, now.month, now.day, tzinfo=timezone.utc)
        window_start = today_utc - timedelta(days=today_utc.weekday())
    elif window == 'monthly':
        window_start = datetime(now.year, now.month, 1, tzinfo=timezone.utc)
    elif window == 'until_deadline':
        # Leave window_start None to be filled from start_at/created_at; end bound will be deadline
        pass

    # Explicit bounds from goal
    # Note: Supabase returns ISO strings; parse safely if present
    def _parse_dt(val):
        if not val:
            return None
        try:
            # Ensure timezone-aware
            dt = datetime.fromisoformat(str(val).replace('Z', '+00:00'))
            return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
        except Exception:
            return None

    start_at = _parse_dt(goal.get('start_at'))
    end_at = _parse_dt(goal.get('end_at'))
    deadline_at = _parse_dt(goal.get('deadline_at'))
    created_at = _parse_dt(goal.get('created_at'))

    # Determine start bound
    candidates_start = [c for c in [window_start, start_at, created_at] if c is not None]
    start_bound = max(candidates_start) if candidates_start else (now - timedelta(days=30))  # default to 30d window

    # Determine end bound
    candidates_end = [c for c in [window_end, end_at, deadline_at] if c is not None]
    end_bound = min(candidates_end) if candidates_end else now

    # Ensure start <= end; if not, collapse to a 0-length at end
    if start_bound > end_bound:
        start_bound = end_bound

    return start_bound.isoformat(), end_bound.isoformat()

def _evaluate_goal_once(client, user_id: str, goal_id: str) -> Dict[str, Any]:
    """Core evaluation logic extracted for reuse. Returns progress row dict.
    Raises on unexpected failures; callers should handle exceptions.
    """
    goal_resp = client.table('user_custom_goals').select(
        'id, user_id, title, description, metric, target_value, unit, window, constraints_json, '
        'start_at, end_at, deadline_at, created_at, status'
    ).eq('id', goal_id).eq('user_id', user_id).single().execute()

    goal = goal_resp.data if goal_resp and goal_resp.data else None
    if not goal:
        raise ValueError("Goal not found")

    metric = goal.get('metric')
    target_value = float(goal.get('target_value') or 0)
    unit = goal.get('unit')

    supported = {
        'distance_km_total',
        'duration_minutes_total',
        'steps_total',
        'elevation_gain_m_total',
        'power_points_total',
    }
    if metric not in supported:
        raise ValueError(f"Metric '{metric}' not yet supported for evaluation")

    start_iso, end_iso = _compute_window_bounds(goal)

    select_cols = 'id,distance_km,duration_seconds,steps,elevation_gain_m,power_points,completed_at'
    sessions_resp = client.table('ruck_session').select(select_cols) \
        .eq('user_id', user_id) \
        .eq('status', 'completed') \
        .gte('completed_at', start_iso) \
        .lte('completed_at', end_iso) \
        .limit(10000) \
        .execute()

    sessions = sessions_resp.data or []

    total_distance_km = 0.0
    total_duration_seconds = 0.0
    total_steps = 0
    total_elevation_m = 0.0
    total_power_points = 0.0

    for s in sessions:
        try:
            if s.get('distance_km') is not None:
                total_distance_km += float(s.get('distance_km') or 0)
            if s.get('duration_seconds') is not None:
                total_duration_seconds += float(s.get('duration_seconds') or 0)
            if s.get('steps') is not None:
                total_steps += int(s.get('steps') or 0)
            if s.get('elevation_gain_m') is not None:
                total_elevation_m += float(s.get('elevation_gain_m') or 0)
            if s.get('power_points') is not None:
                total_power_points += float(s.get('power_points') or 0)
        except Exception:
            continue

    current_value = 0.0
    breakdown_totals = {}

    if metric == 'distance_km_total':
        distance_in_goal_unit = _km_to_mi(total_distance_km) if unit == 'mi' else total_distance_km
        current_value = distance_in_goal_unit
        breakdown_totals = {
            'distance_km': round(total_distance_km, 3),
            'distance_mi': round(_km_to_mi(total_distance_km), 3),
        }
    elif metric == 'duration_minutes_total':
        minutes = total_duration_seconds / 60.0
        current_value = minutes
        breakdown_totals = {
            'duration_seconds': int(total_duration_seconds),
            'duration_minutes': round(minutes, 2),
        }
    elif metric == 'steps_total':
        current_value = float(total_steps)
        breakdown_totals = {
            'steps': int(total_steps),
        }
    elif metric == 'elevation_gain_m_total':
        current_value = float(total_elevation_m)
        breakdown_totals = {
            'elevation_gain_m': round(total_elevation_m, 1),
        }
    elif metric == 'power_points_total':
        current_value = float(total_power_points)
        breakdown_totals = {
            'power_points': round(total_power_points, 1),
        }

    progress_percent = 0.0
    if target_value > 0:
        progress_percent = max(0.0, min(100.0, (current_value / float(target_value)) * 100.0))

    breakdown = {
        'metric': metric,
        'unit': unit,
        'window': {'start': start_iso, 'end': end_iso, 'source': goal.get('window') or 'custom'},
        'totals': breakdown_totals,
        'session_count': len(sessions),
        'session_ids': [s.get('id') for s in sessions],
    }

    progress_lookup = client.table('user_goal_progress').select('id') \
        .eq('goal_id', goal_id).eq('user_id', user_id).limit(1).execute()

    now_iso = datetime.now(timezone.utc).isoformat()
    payload = {
        'goal_id': goal_id,
        'user_id': user_id,
        'current_value': float(round(current_value, 3)),
        'progress_percent': float(round(progress_percent, 2)),
        'last_evaluated_at': now_iso,
        'breakdown_json': breakdown,
    }

    if progress_lookup.data:
        progress_id = progress_lookup.data[0]['id']
        upd = client.table('user_goal_progress').update(payload).eq('id', progress_id).execute()
        progress_row = upd.data[0] if upd and upd.data else None
    else:
        ins = client.table('user_goal_progress').insert(payload).execute()
        progress_row = ins.data[0] if ins and ins.data else None

    if not progress_row:
        raise RuntimeError("Failed to record goal progress")
    return progress_row
class GoalsListResource(Resource):
    """List and create user goals."""

    def get(self):
        ok, err = _require_auth()
        if not ok:
            return err
        try:
            user_id = g.user.id
            status = request.args.get('status')
            page = int(request.args.get('page', 1))
            limit = min(int(request.args.get('limit', 50)), 100)
            offset = (page - 1) * limit

            client = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            query = client.table('user_custom_goals').select(
                'id, title, description, metric, target_value, unit, window, status, start_at, end_at, deadline_at, created_at, updated_at'
            ).eq('user_id', user_id)
            if status:
                query = query.eq('status', status)
            resp = query.order('created_at', desc=True).range(offset, offset + limit - 1).execute()
            data = resp.data or []
            return jsonify({
                'goals': data,
                'count': len(data),
                'page': page,
                'limit': limit,
                'has_more': len(data) == limit
            })
        except Exception as e:
            logger.error(f"GET /api/goals failed: {e}")
            return {"error": "Internal server error"}, 500

    def post(self):
        """Create a new user goal. Minimal validation; aligns with GoalCreateSchema fields."""
        ok, err = _require_auth()
        if not ok:
            return err
        try:
            payload = request.get_json() or {}
            # Allow only known fields to be set by clients
            allowed = {
                'title', 'description', 'metric', 'target_value', 'unit', 'window',
                'constraints_json', 'start_at', 'end_at', 'deadline_at', 'status'
            }
            insert = {k: v for k, v in payload.items() if k in allowed}

            # Basic required fields
            if not insert.get('title') or not insert.get('metric') or insert.get('target_value') is None:
                return {"error": "Missing required fields: title, metric, target_value"}, 400

            # Default status
            if 'status' not in insert:
                insert['status'] = 'active'

            client = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            insert['user_id'] = g.user.id

            res = client.table('user_custom_goals').insert(insert).execute()
            row = res.data[0] if res and res.data else None
            if not row:
                return {"error": "Failed to create goal"}, 500
            return {"goal": row}, 201
        except Exception as e:
            logger.error(f"POST /api/goals failed: {e}")
            return {"error": "Internal server error"}, 500


class GoalsWithProgressResource(Resource):
    """List user's goals with latest progress embedded to reduce client roundtrips."""

    def get(self):
        ok, err = _require_auth()
        if not ok:
            return err
        try:
            user_id = g.user.id
            status = request.args.get('status')
            page = int(request.args.get('page', 1))
            limit = min(int(request.args.get('limit', 50)), 100)
            offset = (page - 1) * limit

            client = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            # Fetch goals page
            gquery = client.table('user_custom_goals').select(
                'id, title, description, metric, target_value, unit, window, status, start_at, end_at, deadline_at, created_at, updated_at'
            ).eq('user_id', user_id)
            if status:
                gquery = gquery.eq('status', status)
            gres = gquery.order('created_at', desc=True).range(offset, offset + limit - 1).execute()
            goals = gres.data or []
            if not goals:
                return jsonify({'goals': [], 'count': 0, 'page': page, 'limit': limit, 'has_more': False})

            goal_ids = [g['id'] for g in goals]

            # Fetch latest progress rows for these goals in one call using OR filters if needed
            # Supabase python client supports .in_ for PostgREST
            pres = client.table('user_goal_progress').select(
                'goal_id, current_value, progress_percent, last_evaluated_at, breakdown_json'
            ).eq('user_id', user_id).in_('goal_id', goal_ids).order('last_evaluated_at', desc=True).limit(10000).execute()
            progress_rows = pres.data or []
            latest_by_goal: Dict[str, Dict[str, Any]] = {}
            for row in progress_rows:
                gid = row.get('goal_id')
                if gid and gid not in latest_by_goal:
                    latest_by_goal[gid] = row

            # Attach
            enriched = []
            for gobj in goals:
                gid = gobj['id']
                enriched.append({**gobj, 'latest_progress': latest_by_goal.get(gid)})

            return jsonify({
                'goals': enriched,
                'count': len(enriched),
                'page': page,
                'limit': limit,
                'has_more': len(goals) == limit
            })
        except Exception as e:
            logger.error(f"GET /api/goals-with-progress failed: {e}")
            return {"error": "Internal server error"}, 500


class GoalDetailsResource(Resource):
    """Consolidated view for a single goal: definition, latest progress, schedule, recent messages."""

    def get(self, goal_id: str):
        ok, err = _require_auth()
        if not ok:
            return err
        try:
            user_id = g.user.id
            client = get_supabase_client(user_jwt=getattr(g, 'access_token', None))

            # Fetch goal (owner only via RLS)
            goal_resp = client.table('user_custom_goals').select(
                'id, user_id, title, description, metric, target_value, unit, window, constraints_json, '
                'start_at, end_at, deadline_at, status, created_at, updated_at'
            ).eq('id', goal_id).eq('user_id', user_id).single().execute()
            goal = goal_resp.data if goal_resp and goal_resp.data else None
            if not goal:
                return {"error": "Goal not found"}, 404

            # Latest progress
            prog_resp = client.table('user_goal_progress').select(
                'id, current_value, progress_percent, last_evaluated_at, breakdown_json, created_at, updated_at'
            ).eq('goal_id', goal_id).eq('user_id', user_id).order('last_evaluated_at', desc=True).limit(1).execute()
            progress = (prog_resp.data or [None])[0]

            # Schedule (if any)
            sched_resp = client.table('user_goal_notification_schedules').select(
                'id, schedule_rules_json, next_run_at, last_sent_at, status, enabled, created_at, updated_at'
            ).eq('goal_id', goal_id).eq('user_id', user_id).limit(1).execute()
            schedule = (sched_resp.data or [None])[0]

            # Recent messages (limit 10)
            msg_resp = client.table('user_goal_messages').select(
                'id, channel, message_type, content, metadata_json, sent_at, created_at'
            ).eq('goal_id', goal_id).eq('user_id', user_id).order('created_at', desc=True).limit(10).execute()
            messages = msg_resp.data or []

            return {
                'goal': goal,
                'progress': progress,
                'schedule': schedule,
                'recent_messages': messages,
            }, 200
        except Exception as e:
            logger.error(f"GET /api/goals/{goal_id}/details failed: {e}")
            return {"error": "Internal server error"}, 500


class GoalResource(Resource):
    """Patch an existing user goal (owner-only)."""

    def patch(self, goal_id: str):
        ok, err = _require_auth()
        if not ok:
            return err
        try:
            # Only allow a strict subset of fields to be updated by clients
            allowed_fields = {
                'title', 'description', 'status', 'end_at', 'deadline_at'
            }
            payload = request.get_json() or {}
            update = {k: v for k, v in payload.items() if k in allowed_fields}
            if not update:
                return {"error": "No updatable fields provided"}, 400

            # Guard: status must be one of allowed values (mirror SQL)
            if 'status' in update and update['status'] not in (
                'active', 'paused', 'completed', 'canceled', 'expired'
            ):
                return {"error": "Invalid status value"}, 400

            client = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            result = client.table('user_custom_goals').update(update).eq('id', goal_id).eq('user_id', g.user.id).execute()
            if not result.data:
                return {"error": "Goal not found or not updated"}, 404
            return {"goal": result.data[0]}, 200
        except Exception as e:
            logger.error(f"PATCH /api/goals/{goal_id} failed: {e}")
            return {"error": "Internal server error"}, 500


class GoalParseResource(Resource):
    """Parse a freeform user request into a validated goal draft (rule-based v1)."""

    def post(self):
        ok, err = _require_auth()
        if not ok:
            return err
        try:
            body = request.get_json() or {}
            text = body.get('text', '')
            cleaned = prefilter_user_input(text)

            # First try LLM-based parser if available
            draft = _llm_parse_goal(cleaned)
            parser_used = 'llm_v1' if draft else None

            # Fallback to rule-based if LLM is unavailable or failed
            if not draft:
                draft = _parse_goal_text(cleaned)
                parser_used = parser_used or 'rule_based_v1'

            assistant_message = _llm_compose_message(text, draft)

            if not draft:
                # Conversational mode: return helper message even when we have no draft
                return {
                    "assistant_message": assistant_message,
                    "input_preview": cleaned[:100],
                    "parser": parser_used,
                    "needs_clarification": True,
                }, 200

            # Validate and normalize via guardrails/schema (LLM result already validated, but re-validate safely)
            validated = validate_goal_draft_payload(draft)
            return {
                "assistant_message": assistant_message,
                "draft": validated,
                "input_preview": cleaned[:100],
                "parser": parser_used,
                "needs_clarification": False,
            }, 200
        except ValueError as ve:
            return {"error": str(ve)}, 400
        except Exception as e:
            logger.error(f"POST /api/goals/parse failed: {e}")
            return {"error": "Internal server error"}, 500


class GoalEvaluateResource(Resource):
    """Trigger evaluation of a goal's progress (stub until scheduler/service implemented)."""

    def post(self, goal_id: str):
        ok, err = _require_auth()
        if not ok:
            return err
        try:
            user_id = g.user.id
            client = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            try:
                progress_row = _evaluate_goal_once(client, user_id, goal_id)
            except ValueError as ve:
                return {"error": str(ve)}, 404 if "not found" in str(ve).lower() else 422
            return {
                'status': 'success',
                'goal_id': goal_id,
                'progress': progress_row,
            }, 200
        except Exception as e:
            logger.error(f"POST /api/goals/{goal_id}/evaluate failed: {e}")
            return {"error": "Internal server error"}, 500


class GoalEvaluateAllResource(Resource):
    """Evaluate all active goals for the authenticated user (manual trigger/cron-safe)."""

    def post(self):
        ok, err = _require_auth()
        if not ok:
            return err
        try:
            user_id = g.user.id
            client = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            # Fetch user's active goals
            goals_resp = client.table('user_custom_goals').select('id').eq('user_id', user_id).eq('status', 'active').limit(1000).execute()
            goal_ids = [g['id'] for g in (goals_resp.data or [])]

            evaluated = 0
            errors: Dict[str, str] = {}
            for gid in goal_ids:
                try:
                    _evaluate_goal_once(client, user_id, gid)
                    evaluated += 1
                except Exception as ex:
                    errors[str(gid)] = str(ex)

            return {
                'status': 'success',
                'evaluated_count': evaluated,
                'total': len(goal_ids),
                'errors': errors,
            }, 200
        except Exception as e:
            logger.error(f"POST /api/goals/evaluate-all failed: {e}")
            return {"error": "Internal server error"}, 500


def _templated_copy(goal_title: str, category: str, progress_percent: float) -> Dict[str, Any]:
    """Deterministic, safe templates as a fallback until LLM integration is wired.
    Returns fields aligned to DB schema: message_type, content, plus minimal metadata.
    """
    pct = int(round(progress_percent))
    if category == 'behind_pace':
        return {
            'message_type': 'behind_pace',
            'content': f"'{goal_title}' is at {pct}% — a short ruck today keeps you on track.",
            'metadata_json': {'title': 'Stay on it', 'uses_emoji': False},
        }
    if category == 'on_track':
        return {
            'message_type': 'on_track',
            'content': f"You're on track for '{goal_title}' — keep the momentum.",
            'metadata_json': {'title': 'Nice pace', 'uses_emoji': False},
        }
    if category == 'milestone':
        return {
            'message_type': 'milestone',
            'content': f"Great work! '{goal_title}' just passed {pct}%.",
            'metadata_json': {'title': 'Milestone hit', 'uses_emoji': False},
        }
    if category == 'completion':
        return {
            'message_type': 'completion',
            'content': f"You completed '{goal_title}' — time to celebrate!",
            'metadata_json': {'title': 'Goal complete', 'uses_emoji': False},
        }
    if category == 'deadline_urgent':
        return {
            'message_type': 'reminder',
            'content': f"'{goal_title}' deadline is close. A quick session can push you over.",
            'metadata_json': {'title': 'Deadline soon', 'uses_emoji': False, 'reason': 'deadline_urgent'},
        }
    if category == 'inactivity':
        return {
            'message_type': 'reminder',
            'content': f"Haven't moved toward '{goal_title}' lately — a short ruck helps.",
            'metadata_json': {'title': 'Quick check-in', 'uses_emoji': False, 'reason': 'inactivity'},
        }
    # Default
    return {
        'message_type': 'on_track',
        'content': f"Progress adds up for '{goal_title}'.",
        'metadata_json': {'title': 'Keep going', 'uses_emoji': False},
    }


class GoalNotificationSendResource(Resource):
    """Generate deterministic copy and log it to user_goal_messages. No external send here."""

    def post(self, goal_id: str):
        ok, err = _require_auth()
        if not ok:
            return err
        try:
            user_id = g.user.id
            client = get_supabase_client(user_jwt=getattr(g, 'access_token', None))

            body = request.get_json() or {}
            category = body.get('category') or 'on_track'

            # Fetch goal for title and latest progress for percent
            goal_resp = client.table('user_custom_goals').select('id,title').eq('id', goal_id).eq('user_id', user_id).single().execute()
            goal = goal_resp.data if goal_resp and goal_resp.data else None
            if not goal:
                return {"error": "Goal not found"}, 404

            prog_resp = client.table('user_goal_progress').select('progress_percent').eq('goal_id', goal_id).eq('user_id', user_id).order('last_evaluated_at', desc=True).limit(1).execute()
            pct = float((prog_resp.data or [{}])[0].get('progress_percent') or 0.0)

            msg = _templated_copy(goal.get('title') or 'Your goal', category, pct)

            # Validate content length constraints (align with ImplementationDocs limits)
            title = (msg.get('metadata_json') or {}).get('title', '')
            if len(title) > 30 or len(msg['content']) > 140:
                return {"error": "Generated copy exceeds length limits"}, 422

            ins = client.table('user_goal_messages').insert({
                'goal_id': goal_id,
                'user_id': user_id,
                'channel': 'push',
                'message_type': msg['message_type'],
                'content': msg['content'],
                'metadata_json': msg.get('metadata_json'),
                'sent_at': datetime.now(timezone.utc).isoformat(),
            }).execute()

            row = ins.data[0] if ins and ins.data else None
            if not row:
                return {"error": "Failed to log message"}, 500
            return {"message": row}, 201
        except Exception as e:
            logger.error(f"POST /api/goals/{goal_id}/notify failed: {e}")
            return {"error": "Internal server error"}, 500


class GoalProgressResource(Resource):
    """Read-only view of current progress for a goal (owner-only)."""

    def get(self, goal_id: str):
        ok, err = _require_auth()
        if not ok:
            return err
        try:
            user_id = g.user.id
            client = get_supabase_client(user_jwt=getattr(g, 'access_token', None))

            resp = client.table('user_goal_progress').select(
                'id, goal_id, user_id, current_value, progress_percent, last_evaluated_at, breakdown_json, created_at, updated_at'
            ).eq('goal_id', goal_id).eq('user_id', user_id).order('last_evaluated_at', desc=True).limit(1).execute()

            data = resp.data or []
            if not data:
                return {"progress": None}, 200
            return {"progress": data[0]}, 200
        except Exception as e:
            logger.error(f"GET /api/goals/{goal_id}/progress failed: {e}")
            return {"error": "Internal server error"}, 500


class GoalScheduleResource(Resource):
    """Get or upsert the user's notification schedule for a goal (owner-only)."""

    def get(self, goal_id: str):
        ok, err = _require_auth()
        if not ok:
            return err
        try:
            user_id = g.user.id
            client = get_supabase_client(user_jwt=getattr(g, 'access_token', None))

            resp = client.table('user_goal_notification_schedules').select(
                'id, goal_id, user_id, schedule_rules_json, next_run_at, last_sent_at, status, enabled, created_at, updated_at'
            ).eq('goal_id', goal_id).eq('user_id', user_id).limit(1).execute()

            data = resp.data or []
            return {"schedule": data[0] if data else None}, 200
        except Exception as e:
            logger.error(f"GET /api/goals/{goal_id}/schedule failed: {e}")
            return {"error": "Internal server error"}, 500

    def put(self, goal_id: str):
        ok, err = _require_auth()
        if not ok:
            return err
        try:
            user_id = g.user.id
            client = get_supabase_client(user_jwt=getattr(g, 'access_token', None))

            payload = request.get_json() or {}
            # Allow controlled fields only
            allowed = {'schedule_rules_json', 'next_run_at', 'status', 'enabled'}
            update = {k: v for k, v in payload.items() if k in allowed}
            if not update:
                return {"error": "No updatable fields provided"}, 400

            # See if schedule exists
            existing = client.table('user_goal_notification_schedules').select('id') \
                .eq('goal_id', goal_id).eq('user_id', user_id).limit(1).execute()

            if existing.data:
                sid = existing.data[0]['id']
                res = client.table('user_goal_notification_schedules').update(update).eq('id', sid).execute()
                row = res.data[0] if res and res.data else None
            else:
                insert = {
                    'goal_id': goal_id,
                    'user_id': user_id,
                    **update,
                }
                res = client.table('user_goal_notification_schedules').insert(insert).execute()
                row = res.data[0] if res and res.data else None

            if not row:
                return {"error": "Failed to save schedule"}, 500
            return {"schedule": row}, 200
        except Exception as e:
            logger.error(f"PUT /api/goals/{goal_id}/schedule failed: {e}")
            return {"error": "Internal server error"}, 500


class GoalMessagesResource(Resource):
    """List AI cheerleader messages for a goal (owner-only)."""

    def get(self, goal_id: str):
        ok, err = _require_auth()
        if not ok:
            return err
        try:
            user_id = g.user.id
            page = int(request.args.get('page', 1))
            limit = min(int(request.args.get('limit', 50)), 100)
            offset = (page - 1) * limit
            channel = request.args.get('channel')  # push | in_session | email
            message_type = request.args.get('message_type')  # reminder | milestone | on_track | behind_pace | completion
            since = request.args.get('since')  # ISO8601 timestamp filter on created_at

            client = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            query = client.table('user_goal_messages').select(
                'id, goal_id, user_id, channel, message_type, content, metadata_json, sent_at, created_at'
            ).eq('goal_id', goal_id).eq('user_id', user_id)
            if channel:
                query = query.eq('channel', channel)
            if message_type:
                query = query.eq('message_type', message_type)
            if since:
                try:
                    # Basic validation to avoid bad inputs; rely on DB for actual comparison
                    _ = datetime.fromisoformat(since.replace('Z', '+00:00'))
                    query = query.gte('created_at', since)
                except Exception:
                    pass
            resp = query.order('created_at', desc=True).range(offset, offset + limit - 1).execute()

            data = resp.data or []
            return {
                'messages': data,
                'count': len(data),
                'page': page,
                'limit': limit,
                'has_more': len(data) == limit
            }, 200
        except Exception as e:
            logger.error(f"GET /api/goals/{goal_id}/messages failed: {e}")
            return {"error": "Internal server error"}, 500
