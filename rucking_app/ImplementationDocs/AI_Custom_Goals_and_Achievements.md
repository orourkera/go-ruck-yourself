# AI-Powered Personal Goals & Custom Achievements

Status: Draft v1
Owner: Mobile + Backend
Last updated: 2025-08-24

## Summary
Enables users to define personal goals via a chat UX embedded in the Achievements pages. The assistant (OpenAI via backend) clarifies/normalizes the goal into a measurable target tied to existing telemetry (distance, sessions/week, streak, elevation, weight load, steps, duration, power points, etc.). Creating a goal provisions:
- A new custom achievement record (per-user)
- Continuous progress tracking and persistence
- A custom notification schedule
- AI-generated notifications informed by goal progress
- AI Cheerleader messages (in-session and out-of-session) tailored to the goal

No new mobile-side dependencies required; AI calls are handled by backend endpoints. Mobile uses existing networking and messaging patterns.

## Non-Goals
- Coaching/medical advice beyond fitness telemetry
- Arbitrary custom metrics outside app’s collected data
- New push infrastructure (reuse existing notification + cheerleader systems)

---

## UX Flow
1) Chat-to-Goal (Achievements Hub)
- Entry point: Achievements home → “Set a Personal Goal” button → opens chat sheet/modal.
- User free texts intent (e.g., “I want to ruck 50 km this month with a 20 lb pack.”).
- Assistant asks clarifiers only if required (time window, unit prefs, constraints like min weight).
- Assistant shows a structured preview: metric, target, window, constraints, deadline.
- User confirms → goal created.

2) Goal Card + Progress
- Goal appears in Achievements list with a progress bar, ETA, and streak indicator if applicable.
- Tapping shows details: definition, current stats, reminders, pause/delete.

3) Notifications + AI Cheerleader
- Scheduled reminders (time-based + progress-based) begin.
- In-session: Cheerleader uses goal context to motivate when applicable (optional, user-toggle).

4) Completion & Celebration
- On goal completion, show an unlock animation (reuse achievement unlock), share prompt, and optional auto-renew/duplicate (e.g., next month).

---

## Data Model (New Tables)
Note: We’re creating dedicated tables for custom goals to avoid impacting core achievements. Names are suggestions; adjust to backend conventions.

1) user_custom_goals
- id (PK)
- user_id (FK → users)
- title (text) — short label
- description (text) — user-friendly phrasing
- metric (text enum) — see Supported Metrics
- target_value (double precision)
- unit (text) — canonical unit key (e.g., km, mi, steps, minutes, kg)
- window (text) — e.g., 7d, 30d, weekly, monthly, until_deadline
- constraints_json (jsonb) — optional (e.g., min_weight_kg, min_distance_per_day_km)
- start_at (timestamptz) — default now
- end_at (timestamptz) — optional (derived from window or explicit)
- deadline_at (timestamptz) — optional
- status (text enum) — active, paused, completed, canceled, expired
- created_at, updated_at (timestamptz)

2) user_goal_progress
- id (PK)
- goal_id (FK → user_custom_goals)
- user_id (FK → users)
- current_value (double precision)
- progress_percent (double precision) — 0..100
- last_evaluated_at (timestamptz)
- breakdown_json (jsonb) — e.g., daily totals, session IDs contributing
- created_at, updated_at (timestamptz)

3) user_goal_notification_schedules
- id (PK)
- goal_id (FK)
- user_id (FK)
- schedule_type (text enum) — time_based, progress_based, milestone_based
- schedule_rules_json (jsonb) — e.g., {"time":"07:30","days":["Mon","Wed","Fri"]} or {"on_behind":true,"milestones":[25,50,75]}
- timezone (text)
- next_run_at (timestamptz)
- enabled (boolean)
- created_at, updated_at (timestamptz)

4) user_goal_messages (AI notification/cheer log)
- id (PK)
- goal_id (FK)
- user_id (FK)
- channel (text enum) — push, in_session, email(optional)
- message_type (text enum) — reminder, milestone, on_track, behind_pace, completion
- content (text)
- metadata_json (jsonb) — prompt version, model, variables used (safe, no PII beyond goal context)
- sent_at (timestamptz)
- created_at

---

## Supported Metrics (Initial)
- distance_km_total — sum of session distances in window
- session_count — number of ruck sessions in window
- streak_days — consecutive days achieving min_daily_distance
- elevation_gain_m_total — sum elevation gain in window
- load_kg_min_sessions — number of sessions at or above min load
- duration_minutes_total — sum session durations in window
- steps_total — sum steps in window (if user enabled live steps)
- power_points_total — sum of calculated power points in window

Constraints (examples):
- min_weight_kg, max_hr_bpm, min_distance_km_per_day, session_min_distance_km, route_terrain_preference (informal), etc.

Units: normalize to canonical storage (km, m, minutes, kg, steps) and convert for display using user preferences.

---

## Evaluation Logic
- Triggers:
  - On session saved/completed → enqueue goal evaluation for that user.
  - Daily cron at user’s local morning time → evaluate windows and schedule reminders.
- Windowing:
  - rolling windows (e.g., last 30d), calendar windows (weekly, monthly), or explicit start/end.
- Progress:
  - Compute `current_value` per metric within window and constraints.
  - `progress_percent = clamp((current_value / target_value) * 100, 0, 100)`.
- Streak:
  - Calculate with local timezone; DST-safe; day-level granularity.
- Completion:
  - Mark goal completed when percent >= 100; freeze final progress; emit completion event.
- Expiry:
  - If `end_at` or `deadline_at` passes without completion → set status = expired; optionally suggest renewal.

Edge Cases:
- Backfilled sessions re-evaluate window.
- Goal edits recalc immediately and reset schedules.
- Conflicting constraints → validation rejects with actionable errors.

---

## Notifications & AI Generation
- Scheduling:
  - time_based: e.g., 7:30 AM Mon/Wed/Fri
  - progress_based: on milestones (25/50/75%), on behind/on-track transitions
  - milestone_based: streak starts/extends, biggest day, PRs (optional)
- Generation:
  - Backend generates message strings at send time using progress snapshot and persona.
  - Safety: positive, non-judgmental tone; no medical claims.
- Rate limiting:
  - Per-goal daily cap (e.g., ≤1 scheduled and ≤1 reactive per day by default).
- Opt-in Controls:
  - Per-goal notification toggle; in-session cheerleader toggle.

### AI Push Notification Copy (LLM, Option B)

We will use an LLM to craft push copy with strict guardrails and JSON-only output. Prompt selection is versioned server-side via Remote Config.

- Remote Config: client sends `ai_notification_prompt_version` from `RemoteConfigService.instance.getAINotificationPromptVersion()`; backend selects the system prompt by version.
- Output must pass schema validation and content checks; otherwise fallback to deterministic templates or refusal.

System Prompt (server-side):
```text
You craft concise push notification copy for a rucking app.
Task: Given goal context and a message category, produce short, motivational, safe copy.
Constraints:
- Max 140 chars for body, max 30 chars for title.
- No medical advice or unverifiable claims.
- No code, no SQL, no URLs.
- Respect provided units (mi/km/min/etc.).
- Tone: supportive, specific, action-oriented; no guilt.
- Use provided variables only; do not invent data.

Output JSON only in the final message with this schema.
```

JSON Schema (enforced server-side):
```json
{
  "type": "object",
  "additionalProperties": false,
  "required": ["title", "body", "category", "uses_emoji"],
  "properties": {
    "title": { "type": "string", "maxLength": 30 },
    "body": { "type": "string", "maxLength": 140 },
    "category": {
      "type": "string",
      "enum": [
        "behind_pace", "on_track", "milestone", "completion", "deadline_urgent", "inactivity"
      ]
    },
    "uses_emoji": { "type": "boolean" }
  }
}
```

Prefilter (before LLM):
- Reject if input contains code fences/backticks, coding/SQL keywords, or URLs.

Post-validation (after LLM):
- Must be valid JSON; must conform to schema and char limits.
- Reject if contains URLs, contact info, medical claims, or disallowed tokens.
- On reject: retry once with stricter guidance or fallback to template.

Backend Orchestration (pseudocode):
```python
def craft_push_copy(user_id, goal_context, category, prompt_version):
    if is_offtopic_prefilter(goal_context, category):
        return template_copy(goal_context, category)

    system = select_notification_prompt(prompt_version)
    user_payload = minimal_goal_snapshot(goal_context, category)
    resp = call_llm(system=system, user=user_payload)

    if not is_json(resp):
        return template_copy(goal_context, category)
    msg = parse_json(resp)
    if not validate_schema(msg):
        return template_copy(goal_context, category)
    if contains_forbidden_content(msg):
        return template_copy(goal_context, category)

    return msg
```

## Smart Notification Policy — Relevance-Driven, Not Spammy

Goal: deliver helpful, timely nudges with minimal noise by combining event-driven triggers with a single daily poll, governed by a relevance score and strict guardrails. No new dependencies; logic runs server-side using JSON rules in `user_goal_notification_schedules` and logs in `user_goal_messages`.

### Strategy
- Event-driven first: Evaluate goals immediately on high-signal events (e.g., session completion, chunk finalize).
- Daily poll second: Once per day (user local time) to assess pacing, inactivity, and deadline proximity.
- Relevance scoring: Send only when value exceeds thresholds and cooldowns.
- Adaptive timing: Prefer the user’s typical workout window; otherwise use their chosen time.
- Strict guardrails: Quiet hours, cooldowns, per-day caps, de-duplication, batching.

### Core Signals
- On-track vs behind pace
  - expected_progress = days_elapsed / days_total
  - progress = current_value / target_value
  - delta = progress − expected_progress
  - thresholds: delta < −0.10 → behind; delta < −0.20 → severely behind; delta > +0.05 → ahead
- Inactivity: N days since last contributing session in window
- Milestones: 25/50/75/100% (adaptive; see below)
- Deadline proximity: days_remaining and remaining_value
- Habit-time match: within typical workout window from last N sessions

### Relevance Score
score = w1*behind_severity + w2*milestone + w3*inactivity + w4*deadline_urgency + w5*habit_time_match − penalties

Suggested weights (tunable): behind=0.6, milestone=0.4, inactivity=0.5, deadline=0.5, habit=0.2, threshold=0.6.
Penalties: recent_message_noise, quiet_hours_violation, cooldown_active, daily_cap_reached.

### Smart Cadence Rules
- Cooldowns: 12–24h per goal between pushes (rules in `schedule_rules_json`).
- Daily cap: ≤1 scheduled + ≤1 reactive per goal/day.
- Quiet hours: e.g., 21:00–07:00 (user-editable) → defer to next allowed slot.
- Priority: if behind and milestone occur close together, send behind (actionable) and skip milestone that day.
- Adaptive milestones: small goals use 10/30/60/100; long goals use 25/50/75/100 or 33/66/100 depending on duration/target size.
- De-escalation: when moving from behind → on track, send “back on track” once, then cooldown.

### Next Best Action (NBA)
Compute concrete recommendation to close the gap:
- needed_today = max(0, target_value * expected_progress_tomorrow − current_value)
- Present in user’s units (mi/km/min) and clamp to sane ranges.
- Use in both push and AI Cheerleader copy.

Examples:
- “You’re 8% behind pace. A 3.2 km ruck today puts you back on track.”
- “75% milestone hit! 12 km remain this week—2 light sessions will do it.”

### Execution Model
- Event-driven evaluator: after session completion (and when data chunks finalize), evaluate affected goals and send if relevant.
- Daily evaluator: run per user at local morning time (or preferred time) to check pacing/inactivity/deadline, apply relevance score, then send or schedule.
- Habit-hour bounce: if approved message is outside habit window, schedule to next habit slot within allowed hours unless urgent.

### Data & APIs (reuse)
- `user_goal_notification_schedules.schedule_rules_json` fields:
  - cooldown_hours, daily_cap, quiet_hours {start,end}, preferred_time, habit_learning, milestones [..]
- `user_goal_messages` stores history for dedupe, cooldown, analytics.
- No schema changes beyond JSON rules defined in this doc.

### Pseudocode
```python
def evaluate_goal(goal, now, user_prefs, history):
    progress = goal.current_value / goal.target_value
    days_elapsed = (now - goal.start_at).days
    days_total = max(1, (goal.end_at - goal.start_at).days)
    expected = days_elapsed / days_total
    delta = progress - expected

    signals = {
        "behind": 1 if delta < -0.10 else 0,
        "severely_behind": 1 if delta < -0.20 else 0,
        "milestone": next_unhit_milestone(progress),
        "inactivity": days_since_last_contribution(goal) >= N,
        "deadline_urgency": urgency(goal, now),
        "habit_match": in_habit_window(now, user_prefs.habit_window),
    }

    score = (
        0.6 * (2 if signals["severely_behind"] else signals["behind"]) +
        0.4 * (1 if signals["milestone"] else 0) +
        0.5 * (1 if signals["inactivity"] else 0) +
        0.5 * signals["deadline_urgency"] +
        0.2 * (1 if signals["habit_match"] else 0)
    ) - penalties(history, goal, user_prefs)

    if score >= THRESHOLD and eligible_by_cooldown_quiet_hours(goal, now, user_prefs):
        nba = next_best_action(goal, now)
        msg = craft_message(goal, signals, nba)
        send_or_schedule(goal, msg, now, user_prefs)
```

### In-Session Intelligence (optional)
- Show a subtle chip when goal is relevant; allow at most one voice nudge per session for thresholds like “back on pace.”
- Respect in-session cooldown and per-session cap.

### Defaults
- Daily reminder at preferred time only if no relevant message sent in last 24h.
- Milestones at 25/50/75/100 but suppressed if a behind/urgent message already sent that day.
- Behind thresholds: −10% (nudge), −20% (urgent).
- Cooldown: 18h; Daily cap: 1 per goal; Quiet hours: 21:00–07:00.
- Habit learning enabled; fallback to preferred time.

### Implementation Notes
- Use existing scheduler (daily cron/Heroku Scheduler) for daily evaluator.
- Trigger event-driven evaluations on session completion and when all chunks are stored (see `RuckTracker/api/ruck.py`).
- All governance knobs live in `schedule_rules_json` so tuning requires no schema changes.
- Route all sends through `user_goal_messages` for dedupe and analytics.

---

## Scope & Safety Enforcement (Goal Chat)

Goal: lock the goal-creation assistant to app-relevant topics only (rucking goals) and prevent misuse (e.g., SQL/coding/general Q&A). All AI calls are backend-only; the client never sends or stores raw prompts.

### Policy
- Only help define measurable rucking goals supported by this app’s data.
- Disallowed: coding, SQL, general Q&A, medical advice, or anything unrelated.
- Final assistant turn must be structured JSON that passes validation; otherwise refuse with in-scope suggestions.

### Remote Config Control
- Client passes a version, not the prompt text: `ai_goal_prompt_version`.
- Mobile getter: `RemoteConfigService.instance.getAIGoalPromptVersion()`.
- Backend selects the server-side system prompt by version; can be updated without redeploy.

### System Prompt (server-side template)
```text
You are GoalBuilder. You ONLY help users define personal rucking goals measurable by this app.
Disallowed: coding, SQL, general-purpose tasks, medical advice, math problems, or anything unrelated.

Process:
1) Ask up to 2 clarifying questions if needed (units, time window, constraints).
2) Produce a draft goal JSON that strictly follows the schema enumerated by the backend.
3) If the user asks for anything outside scope, briefly refuse and suggest in-scope goal types.

Never include code blocks. Never include SQL. Output JSON only in the final message.
```

### Deterministic Prefilter (backend, before LLM)
- Reject outright if message contains code fences/backticks or obvious coding/SQL keywords:
  - "```", "`", "SELECT", "INSERT", "UPDATE", "DELETE", "DROP", "ALTER", "CREATE TABLE"
  - "function(", "class ", "import ", "console.log", "SQL", "Python", "Dart", "GitHub", "StackOverflow"
- Return a short refusal plus in-scope templates (distance/month, sessions/week, streak, elevation, duration, load, steps, power points).

### Schema + Allow-lists
- Backend validates JSON output strictly (enum allow-lists):
  - metrics: see Supported Metrics in this doc
  - units: [km, mi, minutes, steps, m, kg, points]
  - window: [7d, 30d, weekly, monthly, until_deadline]
- Enforce numeric bounds, string lengths, and `additionalProperties=false`.

### Post-Model Output Guards
- Reject if:
  - Not valid JSON per schema
  - Contains code fences or coding/SQL keywords
  - Uses metrics/units/windows outside allow-lists
- On reject: brief refusal + offer in-scope goal templates.

### Turn & Rate Limits
- Max 6 turns per goal creation.
- Min 10s between turns.
- Daily cap on off-topic refusals per user to reduce abuse loops.

### Logging & Audit
- Store only: intent classification flags (blocked keywords), chosen prompt version, final validated JSON.
- Do not persist raw off-topic content; keep minimal moderation metadata.

### Frontend UX Guardrails
- Render only clarifying questions and the structured draft preview; never show raw model text.
- Chips for unit/window choices to constrain drift.
- Disclosure: “This assistant only creates rucking goals. It can’t write code or answer general questions.”

### Backend Orchestration (pseudocode)
```python
def handle_goal_chat(user_id, text, prompt_version):
    if is_offtopic_prefilter(text):
        return refusal_with_templates()

    response = call_llm(system=select_prompt(prompt_version), user=text)

    if not is_json(response):
        return refusal_with_templates()

    draft = parse_json(response)
    if not validate_schema(draft):
        return refusal_with_templates()

    if contains_forbidden_tokens(response):
        return refusal_with_templates()

    if not validate_allowlists(draft):
        return refusal_with_templates()

    return draft_confirmation_preview(draft)
```

---

## AI Cheerleader Integration
- New trigger categories: goal_progress, goal_milestone, goal_risk, goal_completion.
- In-session prompts include: current pace vs. needed pace to stay on track, distance remaining today, load praise, etc.
- Out-of-session pushes share similar copy but without audio.
- Persona: reuse existing personalities; template variables include goal title, progress%, ETA, remaining value, window.

---

## APIs (Backend)
- POST /api/goals/parse
  - body: { text, user_prefs(optional) }
  - returns: { draft_goal: { metric, target_value, unit, window, constraints_json, title, description, start_at, end_at, deadline_at } }
- POST /api/goals
  - create a goal from a confirmed draft
  - returns: goal + initial progress
- GET /api/goals
  - list user goals with computed progress
- PATCH /api/goals/{id}
  - pause/resume, edit title/description/constraints/schedule
- POST /api/goals/{id}/evaluate
  - force evaluation (admin/dev only)
- GET /api/goals/{id}/notifications
  - schedules and history
- POST /api/goals/{id}/notifications/schedules
  - create/update schedule rules

Implementation Notes:
- AI calls originate from backend; mobile never talks directly to OpenAI.
- Validation strictly clamps to known metrics/units.


## Implementation Files & Proposed Structure

The following enumerates edits to existing files and a proposed, additive file structure for new components. This aligns with current patterns (no new dependencies) and avoids regressions.

### Existing Files to Edit

- __Mobile (Flutter)__
  - `rucking_app/lib/features/achievements/presentation/screens/achievements_hub_screen.dart`
    - Add “Set a Personal Goal” entry point that navigates to the goal chat screen.
  - `rucking_app/lib/features/achievements/presentation/widgets/achievement_progress_card.dart`
    - Include custom goals alongside existing achievements (progress bar, ETA). Non-destructive.
  - `rucking_app/lib/core/services/remote_config_service.dart`
    - Already includes `getAIGoalPromptVersion()` and `getAINotificationPromptVersion()` with safe defaults.
    - Ensure defaults are logged for diagnostics; forward versions in requests from the new datasource.

- __Backend (Python)__
  - `RuckTracker/app.py`
    - Register new resources (`/api/goals/parse`, `/api/goals`, `/api/goals/{id}`, `/api/goals/{id}/evaluate`). Add rate limits for chat parse and push-copy craft.
  - `RuckTracker/api/schemas.py`
    - Add strict JSON schemas: goal draft, goal create/update, and notification copy output.
  - `RuckTracker/api/notifications_resource.py`
    - Accept structured copy (title/body/category) or route through new AI copy service; log prompt version in metadata when present.
  - `RuckTracker/api/ruck.py`
    - On session completion, enqueue/evaluate impacted goals (event-driven path).
  - `RuckTracker/background_scheduler.py`
    - Add daily evaluator job (respect quiet hours and cadence rules).
  - `RuckTracker/services/push_notification_service.py`
    - Support structured copy payload and include `prompt_version` in `user_goal_messages.metadata_json`.

### Proposed New Files & Directories

- __Mobile (Flutter)__ — new feature module following existing `data/`, `domain/`, `presentation/` pattern
  - `rucking_app/lib/features/custom_goals/`
    - `data/datasources/custom_goals_remote_datasource.dart` — backend calls: parse/create/list/update; attaches RC versions.
    - `data/repositories/custom_goals_repository_impl.dart`
    - `domain/entities/custom_goal.dart`
    - `domain/repositories/custom_goals_repository.dart`
    - `domain/usecases/parse_goal_usecase.dart`
    - `domain/usecases/create_goal_usecase.dart`
    - `domain/usecases/get_goals_usecase.dart`
    - `presentation/bloc/custom_goals_bloc.dart` (with `event`/`state` files)
    - `presentation/screens/goal_chat_screen.dart` — chat-to-goal UX with clarifier chips and preview
    - `presentation/widgets/goal_confirmation_sheet.dart`

- __Backend (Python)__ — resources/services/utils consistent with current naming
  - `RuckTracker/api/goals.py`
    - `GoalParseResource` — POST `/api/goals/parse` (LLM call; prefilter + schema validation + allow-lists)
    - `GoalsResource` — `/api/goals` list/create and `/api/goals/{id}` patch
    - `GoalEvaluateResource` — POST `/api/goals/{id}/evaluate` (admin/dev)
  - `RuckTracker/services/ai_goal_parser_service.py`
    - Selects system prompt by `ai_goal_prompt_version`; applies deterministic prefilter, LLM call, strict validation.
  - `RuckTracker/services/ai_notification_copy_service.py`
    - Selects system prompt by `ai_notification_prompt_version`; prefilter, LLM, schema validation, post-filters, template fallback.
  - `RuckTracker/services/goals_evaluator_service.py`
    - Computes progress, detects signals (behind/on_track/milestones), derives Next Best Action, schedules sends.
  - `RuckTracker/utils/ai_guardrails.py`
    - Shared forbidden keyword sets (code/SQL/URLs), JSON validators, character-limit checks.

- __Database SQL__ — align with existing top-level SQL pattern (mirror in `RuckTracker/migrations/` if preferred)
  - `create_user_custom_goals.sql` — create `user_custom_goals`
  - `create_user_goal_progress.sql` — create `user_goal_progress`
  - `create_user_goal_notification_schedules.sql` — create `user_goal_notification_schedules`
  - `create_user_goal_messages.sql` — create `user_goal_messages`

Notes:
- Additive changes only; no new dependencies.
- Mobile sends only `ai_goal_prompt_version` and `ai_notification_prompt_version`; backend owns prompts and guardrails.
- Logging is minimal and metadata-only as defined in this doc.

---

## Implementation Plan Checklist

Be precise; follow existing patterns to avoid regressions or new pipelines. Check off as we implement.

### Database (SQL + RLS)
 - [x] Create `create_user_custom_goals.sql` (table: `user_custom_goals`) with `user_id` and timestamps.
 - [x] Create `create_user_goal_progress.sql` (table: `user_goal_progress`).
 - [x] Create `create_user_goal_notification_schedules.sql` (table: `user_goal_notification_schedules`).
 - [x] Create `create_user_goal_messages.sql` (table: `user_goal_messages`).
 - [x] Add RLS policies mirroring existing per-row `user_id` ownership; only owners can select/insert/update; admins via service role.
 - [x] Add indexes: `(user_id)`, `(goal_id)`, `(status)`, `(next_run_at)`, `(created_at)`; partial index for active schedules/goals.
 - [ ] Verify RLS with both `user_jwt` and service-role clients; ensure no admin-only paths in user requests.
- __Indexes__
  - Add BTREE indexes for common filters/joins: `(user_id)`, `(goal_id)`, `(status)`, `(next_run_at)`, `(created_at)` as appropriate.
  - Consider partial indexes for active rows (e.g., `status = 'active'`) on schedules and goals to speed evaluators.
  - Follow existing top-level SQL/migration patterns (e.g., `create_*_indexes.sql`) and place scripts alongside other SQL files or in `RuckTracker/migrations/` per repo convention.

- __Supabase Client Usage__
  - Reuse `RuckTracker/supabase_client.py` exclusively. For user-scoped requests, call `get_supabase_client(user_jwt=g.access_token)` to preserve RLS.
  - Do not instantiate ad-hoc clients in new modules; keep the single-source pattern for keys and initialization.

- __Notification Patterns__
  - Do not create new push pipelines. Always route sends through `RuckTracker/services/push_notification_service.py` and existing device token flows.
  - Keep categories and payload structure consistent with `RuckTracker/api/notifications_resource.py`.
  - Persist message history to `user_goal_messages` with `metadata_json` including `prompt_version`, model, and safety flags.
  - Respect existing cooldown/quiet-hours patterns and scheduler integration via `RuckTracker/background_scheduler.py`.

---

## Flutter Integration (Achievements Pages)
- Entry: Achievements screen adds a “Personal Goals” section.
- Chat UI: simple threaded view (existing design language) with: input box, typing indicator, clarifier chips.
- Confirmation Sheet: shows structured goal; edit quickly (target/window), Confirm.
- Goal Cards: list with progress bar, upcoming reminder, ETA, overflow menu (pause/edit/delete).
- Detail: progress breakdown, schedule controls, notification toggle, cheerleader toggle.
- In-Session: if applicable, show a compact chip with progress toward today’s/period target.

---

## Privacy & Safety
- Opt-in for steps and weight-derived constraints.
- Never reveal sensitive data in prompts beyond necessary metrics.
- Users can delete goals; we soft-delete and stop schedules immediately.
- No medical advice; copy is motivational and goal-focused.

---

## Rollout Plan
- P0 (Wizard-only, no AI):
  - Implement UI wizard presets (distance/month, sessions/week, streak) → create goals directly.
  - Build data model, evaluator, schedules, progress cards.
- P1 (AI Assist):
  - Enable /api/goals/parse and chat UX; confirmation step required.
  - Add AI copy generation for reminders and cheerleader messages.
- P2 (Depth & Polish):
  - More metrics (HR zones, terrain-aware goals), analytics, templates library, goal renewal automation.

---

## Open Questions
- Confirm canonical metric list for P0 (recommend: distance_km_total, session_count, streak_days, duration_minutes_total, elevation_gain_m_total).
- Default schedules: one time-based + progress milestones at 25/50/75/100?
- Renewal behavior for calendar goals (auto-create next month upon completion?).
- Any org-level limits on number of active goals per user (sane default: 5)?
- Should cheerleader speak automatically when a goal milestone is hit mid-session?
