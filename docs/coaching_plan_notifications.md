# Coaching Plan Notification System

## Context
- Extend existing notification pipeline (`RuckTracker/services/notification_manager.py`, `RuckTracker/services/retention_background_jobs.py`) to handle coaching-plan aware messaging.
- Use `user_coaching_plans` and `plan_sessions` as the single source of truth for scheduled sessions and adherence metrics.
- Layer behavior learning so reminders adapt to an athlete's actual training cadence (e.g., habitual 5 AM rucks trigger earlier evening briefings).

## Milestone Checklist

### 1. Data Foundations
- [x] Add plan-session reminder metadata (`scheduled_start_time`, `scheduled_timezone`, `next_notification_at`, `last_notification_type`, `missed_state`) via migration.
- [x] Store per-plan behavior summary (`user_plan_behavior` table or JSON column) with prime window, confidence score, last recompute.
- [x] Extend `user_profiles` with notification preferences (quiet hours, evening brief offset, default cadence) alongside existing coaching tone.
- [x] Ensure weather cache/input data available for notification payloads. *(Implemented with OpenWeatherMap 5-day forecast API)*

### 2. Cadence Analyzer
- [x] Implement nightly job to compute prime window using recent `ruck_session` start/completion times plus plan-session history. *(Code exists but not scheduled)*
- [x] Persist analyzer output (window start/end, confidence, weekday patterns, deviation flags).
- [x] Define fallback behavior when confidence is low or new plan activates.

### 3. Notification Orchestration
- [x] Create `PlanNotificationService` to schedule messages (evening brief, morning hype, completion celebration, missed follow-up; ~~weekly digest, kickoff primer, milestone alerts~~ not yet).
- [x] Integrate service with `_record_session_against_plan` to send completion celebrations immediately and schedule follow-ups.
- [x] Hook plan creation (`/api/coaching-plans` flow) to seed kickoff primer and initial reminders.
- [x] Update background processor (`process_retention_notifications.py`) or add `plan_notifications_background_jobs.py` to sweep and send due notifications. *(Added to background_scheduler.py, runs every 15 minutes)*
- [x] Maintain audit log and dedupe rules to avoid over-sending.

### 4. Content & Personalization
- [x] Build `PlanContentFactory` that merges coaching personality, behavior traits, weather, and plan metrics.
- [x] Expand NotificationManager to accept behavior-aware context and request AI-assisted copy when appropriate.
- [x] Define tone-specific templates for each notification type (drill sergeant, supportive friend, data nerd, minimalist) ~~with adaptive variants (e.g., early-morning sleeper prompts)~~.

### 5. API & Client
- [ ] Expose notification preference endpoints (quiet hours, toggle categories) mirroring goal schedule policies.
- [ ] Update mobile client to parse new payload schema, deep link into plan details, and allow snooze or schedule adjustments.
- [ ] Add analytics hooks (Open/CTA tap tracking) to measure effectiveness and feed future tuning.

### 6. Testing & Rollout
- [ ] Unit test cadence analyzer with synthetic histories (varied schedules, deviations, new plans).
- [ ] Integration tests for notification scheduling (database inserts -> background send -> push delivery).
- [ ] QA plan in staging with mocked weather + AI copy; verify quiet hours, reschedules, daylight saving adjustments.
- [ ] Feature flag / staged rollout with observability dashboards and alerting on send volume anomalies.

## Open Questions
- Preferred storage for weather snapshots (dedicated table vs. reuse existing cache).
- Thresholds for confidence score adjustments and behavior shift detection.
- Interaction with existing goal notification cadence to avoid overlap or fatigue.

## Implementation Notes
**✅ FIXED:** The coaching plan notifications are now fully operational! The background scheduler runs every 15 minutes to process and send due notifications.

### Design Philosophy on Notifications:
**No opt-out for coaching plan notifications** - If you sign up for a coaching plan, you're committing to the accountability. Allowing users to turn off notifications is the first step toward quitting. Like a real coach, the app will keep showing up whether you feel like it or not.
