from flask import request, g
from flask_restful import Resource
import logging
import json
import os
import requests
import time
from openai import OpenAI
from ..supabase_client import get_supabase_client, get_supabase_admin_client

logger = logging.getLogger(__name__)

# OpenAI client
OPENAI_API_KEY = os.getenv('OPENAI_API_KEY')
openai_client = OpenAI(api_key=OPENAI_API_KEY) if OPENAI_API_KEY else None

# Firebase Remote Config integration for backend
FIREBASE_PROJECT_ID = os.getenv('FIREBASE_PROJECT_ID', 'getrucky-app')
FIREBASE_API_KEY = os.getenv('FIREBASE_API_KEY')

# Default prompts (fallback if Remote Config fails)
DEFAULT_SYSTEM_PROMPT = """You are an enthusiastic AI cheerleader for rucking workouts.
Analyze the provided context JSON and generate personalized, motivational messages.
Focus on current performance, progress, and achievements.
Be encouraging, positive, and action-oriented.
Reference historical trends and achievements when relevant.
Avoid repeating similar messages from your ai_cheerleader_history - be creative and vary your encouragement style."""

DEFAULT_USER_PROMPT_TEMPLATE = "Context data:\n{context}\nGenerate encouragement for this ongoing ruck session."

# Cache for prompts (refresh every 5 minutes)
_prompt_cache = None
_cache_timestamp = None
CACHE_DURATION = 300  # 5 minutes in seconds

def get_remote_config_prompts():
    """Fetch AI cheerleader prompts from Firebase Remote Config with caching"""
    global _prompt_cache, _cache_timestamp

    current_time = time.time()

    # Check if we have valid cached prompts
    if _prompt_cache and _cache_timestamp and (current_time - _cache_timestamp) < CACHE_DURATION:
        return _prompt_cache

    try:
        if not FIREBASE_API_KEY or not FIREBASE_PROJECT_ID:
            logger.warning("Firebase credentials not configured, using default prompts")
            prompts = (DEFAULT_SYSTEM_PROMPT, DEFAULT_USER_PROMPT_TEMPLATE)
            _prompt_cache = prompts
            _cache_timestamp = current_time
            return prompts

        url = f"https://firebaseremoteconfig.googleapis.com/v1/projects/{FIREBASE_PROJECT_ID}/remoteConfig"
        headers = {
            'Authorization': f'Bearer {FIREBASE_API_KEY}',
            'Content-Type': 'application/json'
        }

        response = requests.get(url, headers=headers, timeout=5)

        if response.status_code == 200:
            config_data = response.json()
            parameters = config_data.get('parameters', {})

            system_prompt = parameters.get('ai_cheerleader_system_prompt', {}).get('defaultValue', {}).get('value', DEFAULT_SYSTEM_PROMPT)
            user_prompt_template = parameters.get('ai_cheerleader_user_prompt_template', {}).get('defaultValue', {}).get('value', DEFAULT_USER_PROMPT_TEMPLATE)

            prompts = (system_prompt, user_prompt_template)
            _prompt_cache = prompts
            _cache_timestamp = current_time

            logger.info(f"Successfully fetched and cached prompts from Remote Config")
            return prompts
        else:
            logger.warning(f"Failed to fetch Remote Config: {response.status_code}, using cached/default prompts")
            prompts = _prompt_cache or (DEFAULT_SYSTEM_PROMPT, DEFAULT_USER_PROMPT_TEMPLATE)
            return prompts

    except Exception as e:
        logger.error(f"Error fetching Remote Config: {str(e)}, using cached/default prompts")
        prompts = _prompt_cache or (DEFAULT_SYSTEM_PROMPT, DEFAULT_USER_PROMPT_TEMPLATE)
        return prompts

class AICheerleaderLogResource(Resource):
    """AI cheerleader endpoint that handles both generation and logging"""
    
    def post(self):
        try:
            data = request.get_json()
            
            if not data:
                return {"error": "No data provided"}, 400
            
            # Check if this is an AI generation request (from Flutter)
            if 'user_id' in data and 'current_session' in data:
                return self._handle_ai_generation(data)
            
            # Otherwise, handle as logging request
            return self._handle_logging(data)
                
        except Exception as e:
            logger.error(f"Error in AI cheerleader endpoint: {str(e)}")
            return {"error": "Internal server error"}, 500
    
    def _handle_ai_generation(self, data):
        """Handle AI generation request from Flutter app"""
        try:
            if not openai_client:
                return {"error": "OpenAI not configured"}, 500
            
            user_id = data.get('user_id')
            current_session = data.get('current_session', {})
            
            if not user_id:
                return {"error": "Missing user_id"}, 400
            
            logger.info(f"[AI_CHEERLEADER] Generating AI response for user {user_id}")
            
            # Get user history using admin client to bypass RLS
            supabase_admin = get_supabase_admin_client()
            
            # Fetch user history (recent rucks, achievements, AI history)
            try:
                # Get recent AI responses
                ai_logs_resp = supabase_admin.table('ai_cheerleader_logs').select(
                    'session_id, personality, openai_response, created_at'
                ).eq('user_id', user_id).order('created_at', desc=True).limit(20).execute()
                ai_logs = ai_logs_resp.data or []
                logger.info(f"[AI_CHEERLEADER] Found {len(ai_logs)} previous AI responses for user {user_id}")
                
                # Get recent rucks
                rucks_resp = supabase_admin.table('ruck_session').select('*').eq(
                    'user_id', user_id
                ).order('created_at', desc=True).limit(10).execute()
                recent_rucks = rucks_resp.data or []
                
                # Get recent achievements
                achievements_resp = supabase_admin.table('user_achievement').select(
                    '*, achievements(*)'
                ).eq('user_id', user_id).order('earned_at', desc=True).limit(10).execute()
                achievements = achievements_resp.data or []
                
            except Exception as e:
                logger.error(f"[AI_CHEERLEADER] Error fetching user history: {e}")
                ai_logs = []
                recent_rucks = []
                achievements = []
            
            # Build context
            context = {
                'current_session': current_session,
                'recent_rucks': recent_rucks,
                'achievements': achievements,
                'ai_cheerleader_history': ai_logs,
                'aggregates': {
                    'total_ai_messages': len(ai_logs),
                    'total_recent_rucks': len(recent_rucks),
                    'total_achievements': len(achievements)
                }
            }
            
            # Get prompts from Remote Config
            system_prompt, user_prompt_template = get_remote_config_prompts()
            
            # Format the context as JSON string
            context_str = json.dumps(context, indent=2, default=str)
            user_prompt = user_prompt_template.replace('{context}', context_str)
            
            logger.info(f"[AI_CHEERLEADER] Calling OpenAI with {len(context_str)} chars of context")
            
            # Call OpenAI
            completion = openai_client.chat.completions.create(
                model="gpt-4o",
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                max_tokens=150,
                temperature=0.8,
            )
            
            ai_message = completion.choices[0].message.content.strip()
            logger.info(f"[AI_CHEERLEADER] Generated AI response: {ai_message[:100]}...")
            
            return {"message": ai_message}, 200
            
        except Exception as e:
            logger.error(f"[AI_CHEERLEADER] Error generating AI response: {str(e)}")
            return {"error": f"AI generation failed: {str(e)}"}, 500
    
    def _handle_logging(self, data):
        """Handle logging request (original functionality)"""
        try:
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
