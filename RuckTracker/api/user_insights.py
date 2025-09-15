from flask import g, request
from flask_restful import Resource
from ..supabase_client import get_supabase_client
from ..services.user_insights_llm import refresh_user_insights_with_llm
import logging
from datetime import datetime, timedelta
from typing import Optional, Tuple, List, Dict, Any

logger = logging.getLogger(__name__)

class UserInsightsResource(Resource):
    """Return the latest user_insights snapshot for the authenticated user."""

    def get(self):
        if not getattr(g, 'user', None):
            return {"error": "Unauthorized"}, 401

        try:
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))

            # Get query parameters
            fresh = request.args.get('fresh') in ("1", "true", "True")
            with_llm = request.args.get('with_llm') in ("1", "true", "True")
            time_range = request.args.get('time_range', None)  # last_ruck, week, month, all_time
            date_from = request.args.get('date_from', None)
            date_to = request.args.get('date_to', None)
            include_photos = request.args.get('include_photos') in ("1", "true", "True")

            # Optional on-demand recompute: /api/user-insights?fresh=1
            if fresh:
                try:
                    supabase.rpc('upsert_user_insights', { 'u_id': str(g.user.id), 'src': 'adhoc' }).execute()
                except Exception as e:
                    logger.info(f"[INSIGHTS] upsert_user_insights adhoc failed/ignored for {g.user.id}: {e}")

            # Optional LLM candidates: /api/user-insights?with_llm=1 (runs after facts refresh)
            if with_llm:
                try:
                    refresh_user_insights_with_llm(str(g.user.id))
                except Exception as e:
                    logger.info(f"[INSIGHTS] LLM refresh failed for {g.user.id}: {e}")

            # Get base insights
            resp = (
                supabase
                .table('user_insights')
                .select('*')
                .eq('user_id', g.user.id)
                .limit(1)
                .execute()
            )

            insights_data = resp.data[0] if hasattr(resp, 'data') and resp.data else None

            # Add time range specific data if requested
            if insights_data and time_range:
                insights_data = self._add_time_range_data(
                    supabase=supabase,
                    insights=insights_data,
                    time_range=time_range,
                    date_from_str=date_from,
                    date_to_str=date_to,
                    include_photos=include_photos,
                    user_id=g.user.id
                )

            if insights_data:
                return {"insights": insights_data}, 200
            else:
                return {"insights": None}, 200
        except Exception as e:
            logger.error(f"GET /api/user-insights failed: {e}")
            return {"error": "Internal server error"}, 500

    # ---- Helpers ----
    def _parse_date_range(self, time_range: str, date_from_str: Optional[str], date_to_str: Optional[str]) -> Tuple[Optional[str], Optional[str]]:
        """Return ISO date strings (UTC) for from/to based on inputs.
        time_range: one of last_ruck | week | month | all_time
        If date_from/to provided, pass them through.
        """
        if date_from_str or date_to_str:
            return date_from_str, date_to_str

        now = datetime.utcnow()
        if time_range == 'week':
            start = now - timedelta(days=7)
            return start.isoformat(), now.isoformat()
        if time_range == 'month':
            start = now - timedelta(days=30)
            return start.isoformat(), now.isoformat()
        if time_range == 'all_time':
            return None, now.isoformat()
        # last_ruck handled separately by querying latest session
        return None, None

    def _add_time_range_data(
        self,
        *,
        supabase,
        insights: Dict[str, Any],
        time_range: str,
        date_from_str: Optional[str],
        date_to_str: Optional[str],
        include_photos: bool,
        user_id: str,
    ) -> Dict[str, Any]:
        """Augment insights with time-range specific summary, photos, and achievements."""
        start_iso, end_iso = self._parse_date_range(time_range, date_from_str, date_to_str)

        # Determine sessions to include
        sessions: List[Dict[str, Any]] = []
        session_ids: List[int] = []

        if time_range == 'last_ruck':
            try:
                resp = (
                    supabase.table('ruck_session')
                    .select('id, completed_at, distance_km, duration_seconds, calories, elevation_gain_m, has_photos')
                    .eq('user_id', user_id)
                    .eq('status', 'completed')
                    .order('completed_at', desc=True)
                    .limit(1)
                    .execute()
                )
                sessions = resp.data or []
            except Exception as e:
                logger.info(f"[INSIGHTS] last_ruck query failed: {e}")
        else:
            try:
                query = (
                    supabase.table('ruck_session')
                    .select('id, completed_at, distance_km, duration_seconds, calories, elevation_gain_m, has_photos')
                    .eq('user_id', user_id)
                    .eq('status', 'completed')
                    .order('completed_at', desc=True)
                )
                if start_iso:
                    query = query.gte('completed_at', start_iso)
                if end_iso:
                    query = query.lte('completed_at', end_iso)
                resp = query.execute()
                sessions = resp.data or []
            except Exception as e:
                logger.info(f"[INSIGHTS] time-range sessions query failed: {e}")

        session_ids = [s['id'] for s in sessions if 'id' in s]

        # Aggregate summary
        total_distance_km = sum((s.get('distance_km') or 0.0) for s in sessions)
        total_duration_seconds = sum((s.get('duration_seconds') or 0) for s in sessions)
        total_calories = sum((s.get('calories') or 0) for s in sessions)
        elevation_gain_m = sum((s.get('elevation_gain_m') or 0) for s in sessions)

        time_range_summary = {
            'range': time_range,
            'date_from': start_iso,
            'date_to': end_iso,
            'sessions_count': len(sessions),
            'total_distance_km': round(total_distance_km, 3),
            'total_duration_seconds': int(total_duration_seconds),
            'total_calories': int(total_calories),
            'elevation_gain_m': int(elevation_gain_m),
            'session_ids': session_ids,
        }

        # Photos (top limited)
        photos: List[Dict[str, Any]] = []
        if include_photos and session_ids:
            try:
                # Query photos for sessions in range, newest first, cap to 24
                resp = (
                    supabase.table('ruck_photos')
                    .select('id, ruck_id, url, thumbnail_url, created_at')
                    .in_('ruck_id', session_ids)
                    .order('created_at', desc=True)
                    .limit(24)
                    .execute()
                )
                photos = resp.data or []
            except Exception as e:
                logger.info(f"[INSIGHTS] photos query failed: {e}")

        # Achievements in range
        achievements: List[Dict[str, Any]] = []
        try:
            ach_query = (
                supabase.table('user_achievements')
                .select('id, session_id, earned_at, achievements(name, tier, category, icon_name, achievement_key)')
                .eq('user_id', user_id)
                .order('earned_at', desc=True)
            )
            if time_range == 'last_ruck' and session_ids:
                ach_query = ach_query.in_('session_id', session_ids)
            else:
                if start_iso:
                    ach_query = ach_query.gte('earned_at', start_iso)
                if end_iso:
                    ach_query = ach_query.lte('earned_at', end_iso)
            ach_resp = ach_query.limit(50).execute()
            achievements = ach_resp.data or []
        except Exception as e:
            logger.info(f"[INSIGHTS] achievements query failed: {e}")

        enriched = dict(insights or {})
        enriched['time_range'] = time_range_summary
        if include_photos:
            enriched['photos'] = photos
        enriched['achievements'] = achievements
        return enriched
