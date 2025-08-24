# AI Cheerleader Historical Context Implementation

## Overview
This document outlines the implementation for generating a JSON block containing historical user data (previous rucks, split times, achievements, etc.) to enrich the AI Cheerleader's context. The JSON will be merged with current session data in `ai_cheerleader.py` before feeding to the AI model (e.g., OpenAI). 

Key goals:
- Provide comprehensive historical context without overwhelming the AI prompt (limit to recent/relevant data).
- Include **all columns** from core tables for full detail, but aggregate/summarize where possible to keep JSON concise.
- Ensure low-latency fetching via optimized Supabase queries.

This builds on the existing AI Cheerleader flow, which already handles current session data via API.

## Data Sources
We pull from the following Supabase tables. **Important: Include ALL columns from each table** in the raw query results, then format/aggregate in code as needed. This ensures no data loss—filtering happens post-query.

1. **ruck_sessions** (Previous rucks for the user):
   - All columns: `id`, `user_id`, `start_time`, `end_time`, `duration_seconds`, `distance_km`, `elevation_gain_m`, `elevation_loss_m`, `calories_burned`, `weight_kg`, `ruck_weight_kg`, `average_pace`, `is_manual`, `created_at`, `updated_at`, etc.
   - Query: Last 10-20 sessions, ordered by `created_at` DESC.

2. **users** (User profile basics):
   - All columns: `id`, `username`, `email`, `weight_kg`, `height_cm`, `gender`, `date_of_birth`, `prefer_metric`, `calorie_method`, `resting_hr`, `max_hr`, `created_at`, etc.
   - Query: Single row for the user_id.

3. **user_achievements** (Achievements unlocked):
   - All columns: `id`, `user_id`, `achievement_id`, `unlocked_at`, `progress`, `name`, `description`, etc. (assuming this is the join table; if separate `achievements` table, join accordingly).
   - Query: All unlocked or last 20, ordered by `unlocked_at` DESC.

4. **session_splits** (Split times from rucks; note: user said "split_splits" but this is likely session_splits):
   - All columns: `id`, `session_id`, `split_number`, `distance_km`, `duration_seconds`, `pace`, `elevation_gain_m`, `elevation_loss_m`, `calories_burned`, `average_hr`, etc.
   - Query: Splits for the session_ids from ruck_sessions (e.g., join on session_id).

Additional tables if relevant (e.g., `notifications` for social context): Include all columns, query recent 5-10.

## Implementation Options
### Option 1: New Flask API Endpoint (Recommended)
- Endpoint: `/api/user-history/<user_id>` in `ai_cheerleader.py`.
- Logic:
  - Authenticate request.
  - Query Supabase for all tables (use joins where possible, e.g., ruck_sessions LEFT JOIN session_splits).
  - Fetch ALL columns as raw data.
  - Aggregate/format into JSON (e.g., compute averages like avg_pace from ruck_sessions).
- Sample Code Snippet:
  ```python
  def get_user_history(user_id):
      supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
      
      # Fetch with all columns
      rucks = supabase.table('ruck_sessions').select('*').eq('user_id', user_id).order('created_at', desc=True).limit(10).execute().data
      user = supabase.table('users').select('*').eq('id', user_id).single().execute().data
      achievements = supabase.table('user_achievements').select('*').eq('user_id', user_id).order('unlocked_at', desc=True).limit(20).execute().data
      splits = supabase.table('session_splits').select('*').in_('session_id', [r['id'] for r in rucks]).execute().data
      
      history_json = {
          'user': user,  # All columns
          'recent_rucks': rucks,  # All columns per ruck
          'splits': splits,  # All columns per split
          'achievements': achievements,  # All columns
          # Aggregates (computed)
          'total_rucks': len(rucks),
          'average_pace': sum(r['average_pace'] for r in rucks) / len(rucks) if rucks else 0,
          # ... more aggregates ...
      }
      return history_json
  ```
- In AI flow: `full_context = {**current_session, 'history': get_user_history(user_id)}`

### Other Options
- **Option 2: Supabase Edge Function**: Similar queries in JS, called via HTTP from Flask. Good for lower latency.
- **Option 3: Precompute via Triggers**: Store summarized JSON in a table, updated on inserts. Fetch is instant but may be stale.

## Sample JSON Structure
```json
{
  "user": { "id": "...", "username": "...", /* all other user columns */ },
  "recent_rucks": [ { "id": "...", "distance_km": 5.2, /* all ruck_session columns */ } ],
  "splits": [ { "id": "...", "session_id": "...", "pace": 360, /* all session_splits columns */ } ],
  "achievements": [ { "id": "...", "name": "10K Ruck", /* all user_achievements columns */ } ],
  "aggregates": { "total_rucks": 45, "avg_pace": 420, "total_distance_km": 250 }
}
```

## Optimization and Best Practices
- **Latency**: Expect 50-300ms; use limits/indexes on user_id/created_at.
- **Security**: Enforce RLS on tables.
- **Testing**: Mock data; test AI outputs with full vs. summarized JSON.
- **Versioning**: Start with v1; add params like date_range later.

Last Updated: [Current Date]
