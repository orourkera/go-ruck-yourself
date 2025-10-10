# Streak Calculation Fix Summary

## Issue
The user history endpoint (`/api/ai-cheerleader/user-history` -> now `/api/user-insights`) was not correctly calculating streak days. The `current_streak_days` and `longest_streak_days` fields were missing from the database function.

## Root Cause
1. The `compute_user_facts` SQL function in the database was not calculating streak values
2. The `upsert_user_insights` function was not populating the `insights` JSONB column with these values
3. The AI cheerleader and other features were expecting these fields but getting 0 values

## Solution

### 1. Fixed SQL Function (`fix_streak_calculation.sql`)
- Added proper daily streak calculation using window functions
- Calculates both current streak and longest streak
- Current streak accounts for "yesterday" - if no ruck today but there was one yesterday, streak continues
- Uses proper date arithmetic to handle timezone and consecutive day logic

### 2. Updated Insights Population (`update_insights_column.sql`)
- Modified `upsert_user_insights` to populate the `insights` JSONB column
- Includes all commonly accessed fields for easy retrieval by APIs
- Ensures streak values are available in the insights column

## Implementation Steps

1. **Deploy SQL fixes to production:**
```bash
# Run on production database
psql $DATABASE_URL < fix_streak_calculation.sql
psql $DATABASE_URL < update_insights_column.sql
```

2. **Refresh existing user insights:**
```sql
-- Refresh insights for all active users (last 90 days)
SELECT upsert_user_insights(id, 'adhoc')
FROM "user"
WHERE last_active_at >= NOW() - INTERVAL '90 days';
```

3. **Verify the fix:**
```sql
-- Check a specific user's streak
SELECT
  user_id,
  facts->>'current_streak_days' as current_streak,
  facts->>'longest_streak_days' as longest_streak,
  insights->>'current_streak_days' as insights_current,
  insights->>'longest_streak_days' as insights_longest
FROM user_insights
WHERE user_id = 'YOUR_USER_ID';
```

## Key Logic Points

### Current Streak Calculation
- Groups consecutive days with sessions
- Checks if the most recent streak includes today OR yesterday
- If last session was yesterday, streak is still active
- If last session was 2+ days ago, streak is 0

### Longest Streak Calculation
- Finds all streak groups in user's history
- Returns the maximum streak length ever achieved

## Files Modified
- Created `/Users/rory/RuckingApp/fix_streak_calculation.sql`
- Created `/Users/rory/RuckingApp/update_insights_column.sql`
- Created this summary document

## Android AAB Status
✅ Successfully built Android AAB bundle:
- Version: 4.1.2+200
- Location: `build/app/outputs/bundle/release/app-release.aab`
- Size: 109.9 MB
- Ready for upload to Google Play Console