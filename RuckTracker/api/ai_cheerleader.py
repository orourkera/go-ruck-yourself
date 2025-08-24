from flask import request, g
from flask_restful import Resource
import logging
from ..supabase_client import get_supabase_client

logger = logging.getLogger(__name__)

class AICheerleaderLogResource(Resource):
    """Simple logging endpoint for AI cheerleader responses"""
    
    def post(self):
        try:
            data = request.get_json()
            
            if not data:
                return {"error": "No data provided"}, 400
            
            session_id = data.get('session_id')
            personality = data.get('personality')
            openai_response = data.get('openai_response')
            is_explicit = data.get('is_explicit', False)  # Default to False if not provided
            
            if not all([session_id, personality, openai_response]):
                return {"error": "Missing required fields: session_id, personality, openai_response"}, 400
            
            # Get Supabase client with user JWT for RLS
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Insert log entry with user_id for RLS
            result = supabase.table('ai_cheerleader_logs').insert({
                'session_id': session_id,
                'personality': personality,
                'openai_response': openai_response,
                'user_id': g.user.id,
                'is_explicit': is_explicit
            }).execute()
            
            if result.data:
                logger.info(f"AI cheerleader response logged for session {session_id}")
                return {"status": "success", "message": "AI response logged"}, 201
            else:
                logger.error(f"Failed to log AI response: {result}")
                return {"error": "Failed to log response"}, 500
                
        except Exception as e:
            logger.error(f"Error logging AI cheerleader response: {str(e)}")
            return {"error": "Internal server error"}, 500


class AICheerleaderLogsResource(Resource):
    """Retrieve AI cheerleader logs for the authenticated user."""

    def get(self):
        try:
            # Auth context populated in app.before_request
            if not getattr(g, 'user', None):
                return {"error": "Unauthorized"}, 401

            session_id = request.args.get('session_id')
            # Pagination params (index-based for Supabase .range)
            try:
                limit = min(max(int(request.args.get('limit', 100)), 1), 500)
            except Exception:
                limit = 100
            try:
                offset = max(int(request.args.get('offset', 0)), 0)
            except Exception:
                offset = 0

            order_dir = request.args.get('order', 'desc').lower()
            desc = order_dir != 'asc'

            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))

            query = supabase.table('ai_cheerleader_logs') \
                .select('*') \
                .eq('user_id', g.user.id)

            if session_id:
                query = query.eq('session_id', session_id)

            query = query.order('created_at', desc=desc)

            # Supabase range is inclusive; compute end index accordingly
            start = offset
            end = offset + limit - 1
            result = query.range(start, end).execute()

            data = result.data or []
            return {"logs": data, "count": len(data), "offset": offset, "limit": limit}, 200

        except Exception as e:
            logger.error(f"Error fetching AI cheerleader logs: {str(e)}")
            return {"error": "Internal server error"}, 500


class AICheerleaderUserHistoryResource(Resource):
    """Return historical user data to enrich AI Cheerleader context.

    Includes:
    - user profile (all columns)
    - recent rucks (all columns, limited by query param)
    - splits for those rucks (all columns)
    - recent achievements with joined achievement details
    - basic aggregates over returned rucks
    """

    def get(self):
        try:
            if not getattr(g, 'user', None):
                return {"error": "Unauthorized"}, 401

            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))

            # Limits via query params
            def _get_int(name, default, min_v=1, max_v=500):
                try:
                    v = int(request.args.get(name, default))
                    return max(min_v, min(v, max_v))
                except Exception:
                    return default

            rucks_limit = _get_int('rucks_limit', 20, 1, 200)
            achievements_limit = _get_int('achievements_limit', 50, 1, 500)

            user_id = g.user.id

            # Fetch user profile (all columns)
            user_resp = supabase.table('user').select('*').eq('id', user_id).single().execute()
            user_profile = user_resp.data if hasattr(user_resp, 'data') else None

            # Fetch recent rucks (all columns). Use started_at desc when available.
            rucks_resp = supabase.table('ruck_session').select('*') \
                .eq('user_id', user_id) \
                .order('started_at', desc=True) \
                .limit(rucks_limit) \
                .execute()
            recent_rucks = rucks_resp.data or []

            # Fetch splits for those rucks
            splits = []
            if recent_rucks:
                ruck_ids = [r['id'] for r in recent_rucks if 'id' in r]
                try:
                    splits_resp = supabase.table('session_splits').select('*').in_('session_id', ruck_ids).execute()
                    splits = splits_resp.data or []
                except Exception as e:
                    logger.warning(f"User history: splits fetch failed: {e}")

            # Fetch recent achievements with achievement details
            achievements = []
            try:
                ach_resp = supabase.table('user_achievements').select(
                    'id, achievement_id, session_id, earned_at, progress_value, metadata, '
                    'achievements(name, description, tier, category, icon_name, achievement_key)'
                ).eq('user_id', user_id).order('earned_at', desc=True).limit(achievements_limit).execute()
                achievements = ach_resp.data or []
            except Exception as e:
                logger.warning(f"User history: achievements fetch failed: {e}")

            # Aggregates over returned rucks only (lightweight; full totals available via profile stats if needed)
            def _sum(field):
                total = 0.0
                for r in recent_rucks:
                    v = r.get(field)
                    if isinstance(v, (int, float)):
                        total += float(v)
                return total

            aggregates = {
                'returned_rucks': len(recent_rucks),
                'total_distance_km_returned': _sum('distance_km'),
                'total_duration_seconds_returned': _sum('duration_seconds'),
                'total_elevation_gain_m_returned': _sum('elevation_gain_m'),
                'total_calories_returned': _sum('calories_burned'),
            }

            payload = {
                'user': user_profile,
                'recent_rucks': recent_rucks,
                'splits': splits,
                'achievements': achievements,
                'aggregates': aggregates,
            }

            return payload, 200

        except Exception as e:
            logger.error(f"Error building AI user history: {str(e)}")
            return {"error": "Internal server error"}, 500
