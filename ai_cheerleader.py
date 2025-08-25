import json
import os
import requests
from flask import Flask, request, jsonify
from openai import OpenAI
from supabase import create_client, Client

app = Flask(__name__)

# Load env vars (use dotenv if needed - add 'from dotenv import load_dotenv; load_dotenv()' if using .env file)
OPENAI_API_KEY = os.getenv('OPENAI_API_KEY')
SUPABASE_URL = os.getenv('SUPABASE_URL')
SUPABASE_KEY = os.getenv('SUPABASE_KEY')
# Use service role key for backend operations that need to bypass RLS
SUPABASE_SERVICE_ROLE_KEY = os.getenv('SUPABASE_SERVICE_ROLE_KEY')

openai_client = OpenAI(api_key=OPENAI_API_KEY)
# Use service role for this backend service to bypass RLS when fetching user history
supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY or SUPABASE_KEY)

# Firebase Remote Config integration
FIREBASE_PROJECT_ID = os.getenv('FIREBASE_PROJECT_ID', 'getrucky-app')  # Add to your env vars
FIREBASE_API_KEY = os.getenv('FIREBASE_API_KEY')  # Add tosu your env vars

# Default prompts (fallback if Remote Config fails)
DEFAULT_SYSTEM_PROMPT = """You are an enthusiastic AI cheerleader for rucking workouts. 
Analyze the provided context JSON: 
- 'current_session': Real-time stats like distance, pace, duration.
- 'historical': Past rucks, splits, achievements, user profile, notifications, and ai_cheerleader_history (your previous messages to this user).
Generate personalized, motivational messages. Reference historical trends (e.g., 'Faster than your last 3 rucks!') and achievements (e.g., 'Building on your 10K badge!') to encourage based on current progress. Avoid repeating similar messages from your ai_cheerleader_history - be creative and vary your encouragement style. Keep responses under 150 words, positive, and action-oriented."""

DEFAULT_USER_PROMPT_TEMPLATE = "Context data:\n{context}\nGenerate encouragement for this ongoing ruck session."

# Cache for prompts (refresh every 5 minutes)
_prompt_cache = None
_cache_timestamp = None
CACHE_DURATION = 300  # 5 minutes in seconds

def get_remote_config_prompts():
    """Fetch AI cheerleader prompts from Firebase Remote Config with caching"""
    global _prompt_cache, _cache_timestamp
    
    import time
    current_time = time.time()
    
    # Check if we have valid cached prompts
    if _prompt_cache and _cache_timestamp and (current_time - _cache_timestamp) < CACHE_DURATION:
        return _prompt_cache
    
    try:
        if not FIREBASE_API_KEY or not FIREBASE_PROJECT_ID:
            app.logger.warning("Firebase credentials not configured, using default prompts")
            prompts = (DEFAULT_SYSTEM_PROMPT, DEFAULT_USER_PROMPT_TEMPLATE)
            _prompt_cache = prompts
            _cache_timestamp = current_time
            return prompts
            
        # Firebase Remote Config REST API endpoint
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
            
            app.logger.info(f"Successfully fetched and cached prompts from Remote Config")
            return prompts
        else:
            app.logger.warning(f"Failed to fetch Remote Config: {response.status_code}, using cached/default prompts")
            # Use cached prompts if available, otherwise defaults
            prompts = _prompt_cache or (DEFAULT_SYSTEM_PROMPT, DEFAULT_USER_PROMPT_TEMPLATE)
            return prompts
            
    except Exception as e:
        app.logger.error(f"Error fetching Remote Config: {str(e)}, using cached/default prompts")
        # Use cached prompts if available, otherwise defaults
        prompts = _prompt_cache or (DEFAULT_SYSTEM_PROMPT, DEFAULT_USER_PROMPT_TEMPLATE)
        return prompts
# Historical fetch function (fetches all columns from relevant tables)
def get_user_history(user_id: str) -> dict:
    try:
        # Query ruck_sessions (all columns, last 10)
        rucks_resp = supabase.table('ruck_sessions').select('*').eq('user_id', user_id).order('created_at', desc=True).limit(10).execute()
        rucks = rucks_resp.data
        
        # Query users (all columns, single)
        user_resp = supabase.table('users').select('*').eq('id', user_id).single().execute()
        user = user_resp.data
        
        # Query user_achievements (all columns, last 20)
        achievements_resp = supabase.table('user_achievements').select('*').eq('user_id', user_id).order('unlocked_at', desc=True).limit(20).execute()
        achievements = achievements_resp.data
        
        # Query session_splits (all columns, for above ruck IDs)
        session_ids = [r['id'] for r in rucks]
        splits_resp = supabase.table('session_splits').select('*').in_('session_id', session_ids).execute()
        splits = splits_resp.data
        
        # Query notifications (all columns, last 10; assuming table exists)
        notifications_resp = supabase.table('notifications').select('*').eq('user_id', user_id).order('created_at', desc=True).limit(10).execute()
        notifications = notifications_resp.data
        
        # Query AI cheerleader logs (previous AI messages for context)
        # Try both tables - simple logs and detailed interactions
        ai_logs_resp = supabase.table('ai_cheerleader_logs').select('*').eq('user_id', user_id).order('created_at', desc=True).limit(20).execute()
        ai_logs = ai_logs_resp.data or []
        app.logger.info(f"[AI_HISTORY_DEBUG] ai_cheerleader_logs query returned {len(ai_logs)} records for user {user_id}")
        
        # Also check the interactions table for more comprehensive logging
        try:
            interactions_resp = supabase.table('ai_cheerleader_interactions').select('session_id, personality, openai_response, created_at').eq('user_id', user_id).order('created_at', desc=True).limit(20).execute()
            interactions = interactions_resp.data or []
            # Combine both sources, preferring interactions if available
            if interactions:
                ai_logs.extend(interactions)
                # Sort by created_at and limit to 20 most recent
                ai_logs.sort(key=lambda x: x.get('created_at', ''), reverse=True)
                ai_logs = ai_logs[:20]
        except Exception as e:
            logger.warning(f"Could not fetch AI interactions: {e}")
            # Continue with just simple logs
        
        # Build JSON with aggregates
        history = {
            'user': user,
            'recent_rucks': rucks,
            'splits': splits,
            'achievements': achievements,
            'notifications': notifications,
            'ai_cheerleader_history': ai_logs,
            'aggregates': {
                'total_rucks': len(rucks),
                'average_pace': sum(r.get('average_pace', 0) for r in rucks) / len(rucks) if rucks else 0,
                'total_distance_km': sum(r.get('distance_km', 0) for r in rucks),
                'total_ai_messages': len(ai_logs),
                # Add more aggregates as needed (e.g., total_achievements: len(achievements))
            }
        }
        return history
    except Exception as e:
        app.logger.error(f"History fetch failed for user {user_id}: {str(e)}")
        return {}  # Fallback: empty history

# AI Cheerleader endpoint
@app.route('/api/ai-cheerleader', methods=['POST'])
def ai_cheerleader():
    try:
        data = request.get_json()
        user_id = data.get('user_id')  # TODO: Validate with auth (e.g., JWT)
        current_session = data.get('current_session')  # e.g., {"distance_km": 3.2, "pace": 420, "duration_seconds": 1200, ... all session fields}

        if not user_id or not isinstance(current_session, dict):
            return jsonify({"error": "Invalid request: missing user_id or current_session"}), 400

        # Step 1: Fetch historical
        historical = get_user_history(user_id)

        # Step 2: Merge
        full_context = {
            "current_session": current_session,
            "historical": historical
        }

        # Step 3: Format for prompt (concise JSON string)
        context_str = json.dumps(full_context, indent=2)  # Human-readable for debugging

        # Step 4: Get prompts from Remote Config
        system_prompt, user_prompt_template = get_remote_config_prompts()
        user_prompt = user_prompt_template.replace('{context}', context_str)
        
        # Debug logging
        app.logger.info(f"[AI_DEBUG] System prompt length: {len(system_prompt)}")
        app.logger.info(f"[AI_DEBUG] System prompt preview: {system_prompt[:200]}...")
        app.logger.info(f"[AI_DEBUG] User prompt preview: {user_prompt[:300]}...")
        app.logger.info(f"[AI_DEBUG] Context length: {len(context_str)} characters")
        app.logger.info(f"[AI_DEBUG] Historical data keys: {list(historical.keys()) if historical else 'None'}")
        if historical and 'ai_cheerleader_history' in historical:
            app.logger.info(f"[AI_DEBUG] AI history count: {len(historical['ai_cheerleader_history'])}")
        else:
            app.logger.info(f"[AI_DEBUG] No AI history found in context")
        
        # Step 5: OpenAI call
        completion = openai_client.chat.completions.create(
            model="gpt-4o",  # Or gpt-3.5-turbo for cheaper/faster
            messages=[
                # System prompt: From Remote Config
                {"role": "system", "content": system_prompt},
                # User message: From Remote Config template
                {"role": "user", "content": user_prompt}
            ],
            max_tokens=300,  # Limits response length/cost
            temperature=0.8,  # Balances creativity and coherence
            top_p=0.9  # For varied but focused outputs
        )

        # Extract and clean response
        ai_response = completion.choices[0].message.content.strip()

        # Step 6: Return (optionally log usage)
        app.logger.info(f"AI call for user {user_id}: tokens used {completion.usage.total_tokens}")
        return jsonify({"message": ai_response})

    except Exception as e:
        app.logger.error(f"AI Cheerleader error: {str(e)}")
        return jsonify({"error": "Failed to generate message. Please try again.", "details": str(e)}), 500

if __name__ == '__main__':
    app.run(debug=True, port=5000)  # For local testing; use gunicorn for production
