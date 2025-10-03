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
from ..services.arize_observability import observe_openai_call

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


def _get_from_session(session: dict, *path_variants, default=None):
    """Safely extract nested values from the client-provided session payload.

    Supports multiple path variants (snake_case, camelCase, nested) so we stay
    compatible with the Flutter context payload without silently dropping data.
    """

    for variant in path_variants:
        value = session
        for key in variant:
            if not isinstance(value, dict):
                value = None
                break
            value = value.get(key)
        if value not in (None, ''):
            return value
    return default


def _coerce_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _coerce_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None

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

            # Simple rate limiting to prevent overwhelming the system
            session_id = current_session.get('session_id') or 'unknown'
            from datetime import datetime, timedelta

            # Check if this user has made a request recently (cache for 30 seconds)
            cache_key = f"ai_cheerleader_ratelimit_{user_id}_{session_id}"
            try:
                supabase_admin = get_supabase_admin_client()
                # Check for recent request in last 30 seconds
                recent_check = supabase_admin.table('ai_cheerleader_logs').select('created_at').eq(
                    'user_id', user_id
                ).eq('session_id', session_id).gte(
                    'created_at', (datetime.utcnow() - timedelta(seconds=30)).isoformat()
                ).limit(1).execute()

                if recent_check.data:
                    logger.info(f"[AI_CHEERLEADER] Rate limited for user {user_id} - too frequent")
                    return {"message": "Keep going strong!"}, 200  # Simple fallback
            except Exception:
                pass  # Don't fail on rate limit check

            logger.info(f"[AI_CHEERLEADER] Generating AI response for user {user_id}")

            # Get user insights (structured data) and AI history
            supabase_admin = get_supabase_admin_client()

            try:
                # Get user insights for structured historical data - select only needed fields
                insights_resp = supabase_admin.table('user_insights').select(
                    'facts, insights'
                ).eq('user_id', user_id).limit(1).execute()

                insights = {}
                if insights_resp.data:
                    raw = insights_resp.data[0]
                    facts = raw.get('facts') or {}
                    insights_blob = raw.get('insights') or {}

                    totals_all = facts.get('all_time', {})
                    totals_30d = facts.get('totals_30d', {})
                    recency = facts.get('recency', {})

                    streaks = insights_blob.get('streaks', {})

                    insights = {
                        'total_sessions': totals_all.get('sessions', 0),
                        'total_distance_km': totals_all.get('distance_km', 0.0),
                        'total_duration_hours': totals_all.get('duration_s', 0) / 3600 if totals_all.get('duration_s') else 0,
                        'recent_avg_distance_km': totals_30d.get('distance_km', 0.0),
                        'recent_avg_pace_per_km_seconds': recency.get('last_pace_s_per_km'),
                        'current_streak_days': streaks.get('current_streak_days', 0),
                        'longest_streak_days': streaks.get('longest_streak_days', 0),
                    }

                logger.info(f"[AI_CHEERLEADER] Retrieved user insights for user {user_id}: keys={list(insights.keys())}")

                # Get recent AI responses to avoid repetition - reduce limit for performance
                ai_logs_resp = supabase_admin.table('ai_cheerleader_logs').select(
                    'openai_response'
                ).eq('user_id', user_id).order('created_at', desc=True).limit(5).execute()  # Reduced from 20 to 5
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

            # Harmonize incoming session payload (Flutter camelCase) with backend expectations
            distance_km = _get_from_session(
                current_session,
                ('distance_km',),
                ('distanceKm',),
                ('distance', 'distanceKm'),
            )
            distance_miles = _get_from_session(
                current_session,
                ('distance_miles',),
                ('distanceMiles',),
                ('distance', 'distanceMiles'),
            )
            elapsed_seconds = _get_from_session(
                current_session,
                ('duration_seconds',),
                ('elapsedSeconds',),
                ('elapsedTime', 'elapsedSeconds'),
            )
            elapsed_minutes = _get_from_session(
                current_session,
                ('elapsedMinutes',),
                ('elapsedTime', 'elapsedMinutes'),
            )
            current_pace = _get_from_session(
                current_session,
                ('pace',),
                ('pace', 'pace'),
                ('average_pace',),
            )
            average_pace = _get_from_session(
                current_session,
                ('average_pace',),
                ('pace', 'average'),
            )
            steps_count = _get_from_session(current_session, ('steps',))
            calories = _get_from_session(
                current_session,
                ('calories',),
                ('performance', 'calories'),
            )
            elevation_gain = _get_from_session(
                current_session,
                ('elevation_gain_m',),
                ('elevationGain',),
                ('performance', 'elevationGain'),
            )
            elevation_loss = _get_from_session(
                current_session,
                ('elevation_loss_m',),
                ('elevationLoss',),
            )
            heart_rate = _get_from_session(
                current_session,
                ('avg_heart_rate',),
                ('heartRate',),
                ('performance', 'heartRate'),
            )
            ruck_weight = _get_from_session(
                current_session,
                ('ruck_weight_kg',),
                ('ruckWeightKg',),
                ('ruckWeight',),
            )
            is_paused = _get_from_session(current_session, ('is_paused',), ('isPaused',))

            session_identifier = current_session.get('session_id') or current_session.get('sessionId') or session_id

            compact_current = {
                'session_id': session_identifier,
                'distance_km': _coerce_float(distance_km),
                'distance_miles': _coerce_float(distance_miles),
                'elapsed_seconds': _coerce_int(elapsed_seconds),
                'elapsed_minutes': _coerce_int(elapsed_minutes),
                'pace_current': _coerce_float(current_pace),
                'pace_average': _coerce_float(average_pace),
                'steps': _coerce_int(steps_count),
                'calories': _coerce_float(calories),
                'elevation_gain_m': _coerce_float(elevation_gain),
                'elevation_loss_m': _coerce_float(elevation_loss),
                'heart_rate': _coerce_int(heart_rate),
                'ruck_weight_kg': _coerce_float(ruck_weight),
                'is_paused': bool(is_paused) if is_paused is not None else None,
                'raw': current_session,
            }
            # Remove None values to keep prompt concise
            compact_current = {k: v for k, v in compact_current.items() if v not in (None, '')}

            # Add environment/weather data (not in insights)
            if environment:
                compact_current['environment'] = environment
            if location_ctx:
                compact_current['location'] = location_ctx

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
            
            # Format the context as JSON string with size limit for older phones
            context_str = json.dumps(context, indent=2, default=str)

            # Limit context size to prevent memory issues on older devices
            MAX_CONTEXT_CHARS = 2000  # Reasonable limit
            if len(context_str) > MAX_CONTEXT_CHARS:
                # Trim less important data to stay under limit
                if 'avoid_repeating_lines' in context:
                    context['avoid_repeating_lines'] = context['avoid_repeating_lines'][:2]  # Keep only 2 recent
                if 'user_insights' in context:
                    # Keep only essential insights
                    essential_insights = {
                        'total_sessions': context['user_insights'].get('total_sessions', 0),
                        'current_streak_days': context['user_insights'].get('current_streak_days', 0),
                        'recent_avg_pace_per_km_seconds': context['user_insights'].get('recent_avg_pace_per_km_seconds', 0)
                    }
                    context['user_insights'] = essential_insights

                context_str = json.dumps(context, indent=2, default=str)
                # If still too large, truncate
                if len(context_str) > MAX_CONTEXT_CHARS:
                    context_str = context_str[:MAX_CONTEXT_CHARS] + "..."

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
                    "\n- Act as a {personality} character with wit and swagger."\
                    "\n- Deliver 2 short sentences (max ~45 words total). Encourage, tease, or celebrate with confidence."\
                    "\n- Reference specific context: distance, elapsed time, pace trend, heart rate, goals, or streaks. Pick the most interesting stat."\
                    "\n- If location or weather is present, weave it in once with a clever nod—avoid repeating the same weather line back to back."\
                    "\n- Draw on historical insights or coaching plan tidbits when available (e.g., streaks, recent wins, plan week)."\
                    "\n- Vary language every time. No stock phrases. Avoid 'Keep it up' unless you twist it uniquely."\
                    "\n- Never mention BPM explicitly unless the coaching prompt demands heart-rate guidance."\
                    "\n- Sound like a charismatic friend giving inside jokes or bold comparisons. No hashtags or internet slang."\
                ).format(personality=personality)

            user_prompt = user_prompt_template.replace('{context}', context_str + extra_instructions)
            
            logger.info(f"[AI_CHEERLEADER] Calling OpenAI with {len(context_str)} chars of context")
            
            # Call OpenAI with timeout and error handling
            try:
                model_name = os.getenv(
                    'OPENAI_CHEERLEADER_MODEL',
                    os.getenv('OPENAI_DEFAULT_MODEL', 'gpt-5'),
                )

                # Track timing for Arize
                start_time = time.time()

                completion = openai_client.chat.completions.create(
                    model=model_name,
                    messages=[
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": user_prompt},
                    ],
                    max_tokens=120,  # Increased for 2-3 sentences
                    temperature=0.7,
                    timeout=5.0  # 5 second timeout for API call
                )

                latency_ms = (time.time() - start_time) * 1000

                ai_message = (completion.choices[0].message.content or "").strip()

                # Log to Arize for observability
                try:
                    observe_openai_call(
                        model=model_name,
                        messages=[
                            {"role": "system", "content": system_prompt},
                            {"role": "user", "content": user_prompt},
                        ],
                        response=ai_message,
                        latency_ms=latency_ms,
                        user_id=user_id,
                        session_id=request_body.get('session_id'),
                        context_type='ai_cheerleader',
                        prompt_tokens=completion.usage.prompt_tokens if completion.usage else None,
                        completion_tokens=completion.usage.completion_tokens if completion.usage else None,
                        total_tokens=completion.usage.total_tokens if completion.usage else None,
                        temperature=0.7,
                        max_tokens=120,
                        metadata={
                            'personality': personality,
                            'has_coaching_prompt': bool(active_coaching_prompt),
                            'coaching_prompt_type': active_coaching_prompt.get('type') if active_coaching_prompt else None,
                        }
                    )
                except Exception as arize_error:
                    logger.error(f"[AI_CHEERLEADER] Failed to log to Arize: {arize_error}", exc_info=True)
            except Exception as openai_error:
                logger.warning(
                    f"[AI_CHEERLEADER] OpenAI call failed (model={model_name}), using fallback: {openai_error}",
                    exc_info=True,
                )
                # Fallback to simple encouraging message
                fallback_messages = {
                    'intervals': "Time to push! You've got this!",
                    'tempo': "Keep that steady pace going strong!",
                    'recovery': "Nice easy pace, recover well!",
                    'milestone': "Great milestone! Keep moving forward!",
                    'default': "You're doing great! Keep it up!"
                }

                if active_coaching_prompt:
                    prompt_type = active_coaching_prompt.get('type', 'default')
                    ai_message = fallback_messages.get(prompt_type, fallback_messages['default'])
                else:
                    ai_message = fallback_messages['default']

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
