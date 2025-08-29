# User Insights: Roadmap & Ideas

## Overview
- The `user_insights` snapshot provides a compact, RLS‑protected JSON summary per user for personalization, UI hints, and (later) notifications.
- It is refreshed on ruck completion and can be recomputed ad‑hoc (`GET /api/user-insights?fresh=1`).
- Optional: nightly batch refresh and LLM candidate generation (`with_llm=1`).

## Current Snapshot (high‑level)
- facts.totals_30d / facts.totals_90d / facts.all_time
- facts.recency (last_completed_at, days_since_last, last_ruck_distance_km, last_ruck_weight_kg)
- facts.splits (avg pace by split 1–10, negative split frequency)
- facts.recent_splits (last 3 sessions, ≤40 splits each; empty array if none)
- facts.achievements_recent (last 10)
- facts.user (sanitized `public.user`, tokens excluded)
- facts.profile (has_avatar, has_strava, strava_connected_at)
- facts.logins (last_login_at, days_since_last_login)
- facts.demographics (gender, date_of_birth)
- facts.activity
  - active_session { id, started_at, status } if in_progress/paused
  - last_activity_at = max of session signals (completed_at, GPS/HR, state), community interactions (likes/comments), and notification reads/receipts
  - days_since_last_activity (clamped ≥ 0)

## Proposed Additions

### 1) Login Frequency & Patterns
- Daily/weekly login counts:
  - facts.logins.logins_7d, logins_30d, logins_90d
  - facts.logins.last_7d_hist_by_weekday (array of 7) and last_30d_hist_by_hour (array of 24)
- Streaks:
  - facts.logins.login_streak_days (consecutive days with at least 1 app open/login)
- Use cases:
  - Habit nudges (“It’s your usual Tuesday afternoon window”).
  - Re‑engagement (“You’re one day away from a 3‑day login streak”).

### 2) Leaderboard Position History (Global Distance)
- Persist daily rank snapshots:
  - Table `leaderboard_history(user_id, date, metric, rank, total_users, value)`
  - Nightly job computes rank by 30d distance and all‑time distance
- In snapshot:
  - facts.leaderboard.distance_30d { km, rank, total, percentile }
  - facts.leaderboard_all_time { km, rank, total, percentile }
  - facts.leaderboard_trend { rank_delta_7d, rank_delta_30d }
- Use cases:
  - Positive movement (“Up 12 spots this week”).
  - Gentle reframe (“Holding steady in the top 30%”).

### 3) Session Frequency & Cadence
- facts.sessions:
  - sessions_last_7d, sessions_last_30d, avg_sessions_per_week_90d
  - preferred_windows: top 2 weekday+hour buckets
- Use cases:
  - “This matches your usual Thursday slot.”

### 4) Heart Rate & Physiology Readiness (if available)
- From `public.user`: resting_hr, max_hr present
- From sessions: HR sample coverage (%) per session; time_in_zones aggregates
- facts.hr:
  - has_hr, avg_coverage_30d, zone_time_ratios_30d
- Use cases:
  - Coach tone (“Aim to stay in Z2 for most of today”).

### 5) Profile Completeness
- facts.profile_completeness score with reasons:
  - missing avatar, missing weight/height/gender/dob, strava disconnected
- Use cases:
  - Subtle UI banners over hard blocks; improve personalization accuracy.

### 6) Weather Awareness
- Already used ad‑hoc in client prompt; optionally persist last_ruck_weather and today_weather summary to enable server‑driven insights.

## Triggers & Notifications (Future)
- Target: server‑side, scheduled or event‑driven using snapshot + triggers.
- Examples:
  - Consistency: “Same time you usually ruck on Tuesdays.” (weekday/hour histogram)
  - Leaderboard: “Up 12 spots this week.” (rank_delta_7d)
  - Milestone: “0.2 mi to your next distance milestone.” (facts.triggers)
  - Onboarding: First session encouragement (5 minutes, even without weight)
  - Weather: “Cooler than your last ruck — perfect to go longer.”
- Delivery:
  - Feature flag `enableInsightsNotifications`
  - Quiet hours & batching; opt‑out categories.

## Data Pipeline & Storage
- Tables
  - `user_login_history` (user_id, logged_in_at, provider, platform, app_version)
  - `leaderboard_history` (user_id, date, metric, rank, total_users, value)
  - Existing: ruck_session, location_point, heart_rate_sample, notifications, ruck_likes, ruck_comments
- Workers
  - Nightly: update `user_insights`, compute leaderboard snapshots, optionally add LLM candidates
  - Ad‑hoc recompute: `/api/user-insights?fresh=1`

## Privacy & Security
- RLS on `user_insights` (owner‑only). Snapshot contains only the requesting user’s data.
- Sanitize tokens/secrets from `public.user` in snapshot (no access/refresh tokens).
- Soft guidance in LLM prompts: avoid medical advice; JSON‑only output.

## API & Client
- Endpoint: `GET /api/user-insights` with `?fresh=1` and optional `&with_llm=1`
- Client merges snapshot + current weather + time‑of‑day to craft prompts.
- Tone rules in prompt:
  - Women: empowering/empathetic
  - Men: tough/playful (respectful)
  - First‑time: thank/encourage “5 minutes, even without weight”

## Backfill Plan
- Create `user_login_history` and begin recording on successful login.
- Initialize `leaderboard_history` from current 30d/all‑time distance ranks.
- Run nightly worker to populate new fields.

## Open Questions
- Which global metric is most meaningful for rank (30d distance vs. activity count vs. elevation)?
- Event‑specific rank: pick “active event(s)” or expose top N events with rank.
- Notification cadence & quiet hours defaults.

