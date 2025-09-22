from flask import request, g
from flask_restful import Resource
import logging
import json
import os
import requests
import time

# Safe import for OpenAI to avoid boot failure if dependency is missing
try:
    from openai import OpenAI  # type: ignore
except Exception:  # ModuleNotFoundError or any import-time error
    OpenAI = None  # type: ignore

from ..supabase_client import get_supabase_client, get_supabase_admin_client

logger = logging.getLogger(__name__)

# OpenAI client (only initialize if library and API key are available)
OPENAI_API_KEY = os.getenv('OPENAI_API_KEY')
if OpenAI is None:
    logger = logging.getLogger(__name__)
    logger.warning("OpenAI library not available; AI Cheerleader generation disabled")
    openai_client = None
else:
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
            # Optional personality and environment/location passthrough from client
            personality = data.get('personality') or 'AI Cheerleader'
            environment = data.get('environment') or current_session.get('environment') or {}
            location_ctx = data.get('location') or current_session.get('location') or {}

            if not user_id:
                return {"error": "Missing user_id"}, 400

            logger.info(f"[AI_CHEERLEADER] Generating AI response for user {user_id}")

            # Get user insights (structured data) and AI history
            supabase_admin = get_supabase_admin_client()

            try:
                # Get user insights for structured historical data
                insights_resp = supabase_admin.table('user_insights').select('*').eq('user_id', user_id).limit(1).execute()
                insights = insights_resp.data[0] if insights_resp.data else {}
                logger.info(f"[AI_CHEERLEADER] Retrieved user insights for user {user_id}")

                # Get recent AI responses to avoid repetition
                ai_logs_resp = supabase_admin.table('ai_cheerleader_logs').select(
                    'session_id, personality, openai_response, created_at'
                ).eq('user_id', user_id).order('created_at', desc=True).limit(20).execute()
                ai_logs = ai_logs_resp.data or []
                logger.info(f"[AI_CHEERLEADER] Found {len(ai_logs)} previous AI responses for user {user_id}")

                # Get active coaching plan and current session's coaching points
                coaching_points = {}
                try:
                    # Get active plan
                    plan_resp = supabase_admin.table('user_coaching_plans').select(
                        'id, current_week, start_date'
                    ).eq('user_id', user_id).eq('current_status', 'active').limit(1).execute()

                    if plan_resp.data:
                        plan_id = plan_resp.data[0]['id']
                        current_week = plan_resp.data[0]['current_week']

                        # Get today's plan session with coaching points
                        from datetime import datetime
                        today = datetime.now().date().isoformat()

                        session_resp = supabase_admin.table('plan_sessions').select(
                            'coaching_points, planned_session_type'
                        ).eq('user_coaching_plan_id', plan_id).eq('scheduled_date', today).limit(1).execute()

                        if session_resp.data and session_resp.data[0].get('coaching_points'):
                            coaching_points = session_resp.data[0]['coaching_points']
                            logger.info(f"[AI_CHEERLEADER] Found coaching points for today's session")
                except Exception as cp_error:
                    logger.warning(f"[AI_CHEERLEADER] Could not fetch coaching points: {cp_error}")

            except Exception as e:
                logger.error(f"[AI_CHEERLEADER] Error fetching user insights: {e}")
                insights = {}
                ai_logs = []
                coaching_points = {}
            
            # Build compact context using structured insights + current session
            def _pick(d, keys):
                return {k: d.get(k) for k in keys if k in d}

            cs_keys = [
                'status', 'distance_km', 'duration_seconds', 'average_pace', 'steps', 'is_paused',
                'elevation_gain_m', 'elevation_loss_m', 'ruck_weight_kg', 'avg_heart_rate'
            ]
            compact_current = _pick(current_session, cs_keys)
            
            # Add environment/weather data (not in insights)
            if environment:
                compact_current['environment'] = _pick(environment, ['weather', 'temperature_c', 'temperature_f', 'conditions']) or environment
            if location_ctx:
                compact_current['location'] = _pick(location_ctx, ['city', 'region', 'country', 'lat', 'lng']) or location_ctx

            # Extract last few AI lines to avoid repeating phrasing
            avoid_lines = []
            for it in ai_logs:
                t = (it or {}).get('openai_response')
                if isinstance(t, str) and t.strip():
                    t = ' '.join(t.split())
                    avoid_lines.append(t[:120])
                    if len(avoid_lines) >= 4:
                        break

            # Check coaching points for current interval/trigger
            active_coaching_prompt = None
            if coaching_points and current_session:
                elapsed_minutes = current_session.get('duration_seconds', 0) / 60
                current_distance_km = current_session.get('distance_km', 0)
                current_hr = current_session.get('avg_heart_rate', 0)

                # Check interval coaching
                intervals = coaching_points.get('intervals', [])
                if intervals:
                    cumulative_minutes = 0
                    for interval in intervals:
                        interval_duration = interval.get('duration_minutes', 0)
                        if cumulative_minutes <= elapsed_minutes < cumulative_minutes + interval_duration:
                            active_coaching_prompt = {
                                'type': 'interval',
                                'instruction': interval.get('instruction', ''),
                                'interval_type': interval.get('type', 'work')
                            }
                            break
                        cumulative_minutes += interval_duration

                # Check milestone triggers
                milestones = coaching_points.get('milestones', [])
                for milestone in milestones:
                    trigger_distance = milestone.get('distance_km', 0)
                    # Trigger within 100m of milestone
                    if abs(current_distance_km - trigger_distance) < 0.1:
                        active_coaching_prompt = {
                            'type': 'milestone',
                            'message': milestone.get('message', '')
                        }
                        break

                # Check time triggers
                time_triggers = coaching_points.get('time_triggers', [])
                for trigger in time_triggers:
                    trigger_minutes = trigger.get('elapsed_minutes', 0)
                    # Trigger within 30 seconds of time
                    if abs(elapsed_minutes - trigger_minutes) < 0.5:
                        active_coaching_prompt = {
                            'type': 'time_trigger',
                            'message': trigger.get('message', '')
                        }
                        break

                # Check heart rate zones
                if current_hr > 0:
                    hr_zones = coaching_points.get('heart_rate_zones', [])
                    for zone in hr_zones:
                        min_bpm = zone.get('min_bpm', 0)
                        max_bpm = zone.get('max_bpm', 999)
                        if current_hr < min_bpm:
                            active_coaching_prompt = {
                                'type': 'heart_rate',
                                'instruction': f"Pick up the pace! Target heart rate: {min_bpm}-{max_bpm} bpm"
                            }
                            break
                        elif current_hr > max_bpm:
                            active_coaching_prompt = {
                                'type': 'heart_rate',
                                'instruction': f"Ease up a bit! Target heart rate: {min_bpm}-{max_bpm} bpm"
                            }
                            break

            # Use structured insights data instead of manual fetching
            context = {
                'current_session': compact_current,
                'user_insights': {
                    'total_sessions': insights.get('total_sessions', 0),
                    'total_distance_km': insights.get('total_distance_km', 0),
                    'total_duration_hours': insights.get('total_duration_hours', 0),
                    'avg_pace_per_km_seconds': insights.get('avg_pace_per_km_seconds', 0),
                    'total_elevation_gain_m': insights.get('total_elevation_gain_m', 0),
                    'recent_sessions_count': insights.get('recent_sessions_count', 0),
                    'recent_avg_distance_km': insights.get('recent_avg_distance_km', 0),
                    'recent_avg_pace_per_km_seconds': insights.get('recent_avg_pace_per_km_seconds', 0),
                    'achievements_total': insights.get('achievements_total', 0),
                    'achievements_recent': insights.get('achievements_recent', 0),
                    'current_streak_days': insights.get('current_streak_days', 0),
                    'longest_streak_days': insights.get('longest_streak_days', 0),
                },
                'avoid_repeating_lines': avoid_lines,
                'active_coaching_prompt': active_coaching_prompt,  # CRITICAL: Include coaching trigger
                'session_goals': coaching_points.get('session_goals', {}) if coaching_points else {}
            }
            
            # Get prompts from Remote Config
            system_prompt, user_prompt_template = get_remote_config_prompts()
            
            # Format the context as JSON string
            context_str = json.dumps(context, indent=2, default=str)

            # Build instructions with coaching priority
            if active_coaching_prompt:
                # When there's an active coaching trigger, prioritize it
                extra_instructions = (
                    "\nINSTRUCTIONS - CRITICAL COACHING MOMENT:"\
                    "\n- There is an ACTIVE COACHING PROMPT that MUST be addressed!"\
                    "\n- active_coaching_prompt contains the specific instruction/message to deliver"\
                    "\n- If type is 'interval': Tell them about the interval change (e.g., 'Time to push hard!' or 'Recovery time - ease up')"\
                    "\n- If type is 'milestone': Celebrate the distance milestone"\
                    "\n- If type is 'time_trigger': Use the provided message"\
                    "\n- If type is 'heart_rate': Guide them on pace adjustment"\
                    "\n- Make it personal and motivating while delivering the coaching instruction"\
                    "\n- Act as a {personality} character."\
                    "\n- Keep it to 2-3 sentences that deliver the coaching point clearly"\
                    "\n- Do NOT ignore the active_coaching_prompt - it's time-sensitive!"
                ).format(personality=personality)
            else:
                # Normal cheerleading when no specific trigger
                extra_instructions = (
                    "\nInstructions:"\
                    "\n- Act as a {personality} character."\
                    "\n- Keep it SHORT: 20 words MAX. Hard cap."\
                    "\n- Vary wording every time. Do NOT repeat prior lines shown in avoid_repeating_lines."\
                    "\n- If session_goals exist, occasionally reference them for motivation"\
                    "\n- Mention location or weather ONCE if present (natural, brief)."\
                    "\n- Do NOT mention BPM/heart rate unless explicitly addressing a heart_rate coaching prompt"\
                    "\n- No hashtags. No internet slang. Sound natural and encouraging."
                ).format(personality=personality)

            user_prompt = user_prompt_template.replace('{context}', context_str + extra_instructions)
            
            logger.info(f"[AI_CHEERLEADER] Calling OpenAI with {len(context_str)} chars of context")
            
            # Call OpenAI with moderate length for 2-3 sentences
            completion = openai_client.chat.completions.create(
                model=os.getenv('OPENAI_CHEERLEADER_MODEL', os.getenv('OPENAI_DEFAULT_MODEL', 'gpt-5')),
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                max_tokens=120,  # Increased for 2-3 sentences
                temperature=0.7,
            )
            
            ai_message = (completion.choices[0].message.content or "").strip()

            # Moderate word cap for 2-3 sentences and cleanup (no deps)
            words = ai_message.split()
            if len(words) > 75:  # Increased from 20 to 75 words for 2-3 sentences
                ai_message = ' '.join(words[:75])
            # Remove hashtags entirely
            ai_message = ' '.join(w for w in ai_message.split() if not w.startswith('#'))
            # Final trim
            ai_message = ai_message.strip()
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


# AICheerleaderUserHistoryResource removed - now using user-insights endpoint for structured data
