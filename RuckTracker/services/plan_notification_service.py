"""Behavior-aware coaching plan notification scheduling and delivery."""

from __future__ import annotations

import logging
import os
import requests
from dataclasses import dataclass
from datetime import datetime, timedelta, time
from statistics import median, pstdev
from typing import Any, Dict, List, Optional, Tuple

from dateutil import parser
from datetime import timezone

from .notification_manager import notification_manager
from ..supabase_client import get_supabase_admin_client

logger = logging.getLogger(__name__)

DEFAULT_EVENING_OFFSET_MINUTES = 540  # 9 hours before prime window by default
MORNING_HYPE_OFFSET_MINUTES = 60
MISSED_FOLLOWUP_GRACE_MINUTES = 120
MIN_HISTORY_FOR_CONFIDENCE = 5


@dataclass
class PlanBehaviorSnapshot:
    user_id: str
    plan_id: int
    timezone: str
    prime_window_start_minute: Optional[int]
    prime_window_end_minute: Optional[int]
    confidence: float
    weekday_pattern: Dict[str, int]
    metadata: Dict[str, Any]

    def is_confident(self) -> bool:
        return (self.prime_window_start_minute is not None and
                self.prime_window_end_minute is not None and
                self.confidence >= 0.5)


class PlanCadenceAnalyzer:
    """Derives habitual training windows from recent ruck history."""

    def __init__(self, admin_client=None):
        self.admin_client = admin_client or get_supabase_admin_client()

    def ensure_behavior_snapshot(self, user_id: str, plan_id: int, timezone_name: str) -> PlanBehaviorSnapshot:
        existing = self._fetch_snapshot(user_id, plan_id)
        if existing and not self._needs_refresh(existing):
            return existing

        return self._recompute_snapshot(user_id, plan_id, timezone_name)

    def _fetch_snapshot(self, user_id: str, plan_id: int) -> Optional[PlanBehaviorSnapshot]:
        try:
            resp = self.admin_client.table('user_plan_behavior').select('*').eq(
                'user_id', user_id
            ).eq('user_coaching_plan_id', plan_id).limit(1).execute()
            if resp.data:
                payload = resp.data[0]
                return PlanBehaviorSnapshot(
                    user_id=user_id,
                    plan_id=plan_id,
                    timezone=payload.get('metadata', {}).get('timezone', 'UTC'),
                    prime_window_start_minute=payload.get('prime_window_start_minute'),
                    prime_window_end_minute=payload.get('prime_window_end_minute'),
                    confidence=float(payload.get('confidence_score', 0.0) or 0.0),
                    weekday_pattern=payload.get('weekday_pattern') or {},
                    metadata=payload.get('metadata') or {}
                )
        except Exception as exc:
            logger.error(f"Failed to fetch user_plan_behavior for {user_id}/{plan_id}: {exc}")
        return None

    def _needs_refresh(self, snapshot: PlanBehaviorSnapshot) -> bool:
        last_recomputed = snapshot.metadata.get('last_recomputed_at')
        if not last_recomputed:
            return True
        try:
            ts = parser.isoparse(last_recomputed)
        except Exception:
            return True
        return (datetime.utcnow() - ts).days >= 3

    def _recompute_snapshot(self, user_id: str, plan_id: int, timezone_name: str) -> PlanBehaviorSnapshot:
        # Use plan timezone (session-specific timezone handled elsewhere)
        session_timezone = timezone_name

        # Use pytz for proper timezone handling
        try:
            import pytz
            tzinfo = pytz.timezone(session_timezone)
        except ImportError:
            # Fallback if pytz not installed yet
            from datetime import timezone as dt_timezone
            tzinfo = dt_timezone.utc
            logger.warning(f"pytz not installed, using UTC instead of '{session_timezone}'")
        except Exception as e:
            # Fallback for invalid timezone
            import pytz
            tzinfo = pytz.UTC
            logger.warning(f"Invalid timezone '{session_timezone}': {e}, using UTC")
        samples = self._collect_samples(user_id, plan_id)

        if not samples:
            default_snapshot = PlanBehaviorSnapshot(
                user_id=user_id,
                plan_id=plan_id,
                timezone=timezone_name,
                prime_window_start_minute=None,
                prime_window_end_minute=None,
                confidence=0.0,
                weekday_pattern={},
                metadata={'sample_size': 0, 'timezone': timezone_name, 'last_recomputed_at': datetime.utcnow().isoformat()}
            )
            self._persist_snapshot(default_snapshot)
            return default_snapshot

        minute_offsets = []
        weekday_counter: Dict[str, int] = {}
        for dt_value in samples:
            localized = dt_value.astimezone(tzinfo)
            minute_offset = localized.hour * 60 + localized.minute
            minute_offsets.append(minute_offset)
            weekday_name = localized.strftime('%A')
            weekday_counter[weekday_name] = weekday_counter.get(weekday_name, 0) + 1

        minute_offsets.sort()
        central_minute = int(median(minute_offsets))
        if len(minute_offsets) >= 2:
            std_dev = pstdev(minute_offsets) if len(minute_offsets) > 1 else 0
        else:
            std_dev = 0

        spread = max(30, int(std_dev * 1.5))
        window_start = max(0, central_minute - spread)
        window_end = min(1439, central_minute + spread)
        confidence = self._calculate_confidence(len(minute_offsets), std_dev)

        snapshot = PlanBehaviorSnapshot(
            user_id=user_id,
            plan_id=plan_id,
            timezone=timezone_name,
            prime_window_start_minute=window_start,
            prime_window_end_minute=window_end,
            confidence=confidence,
            weekday_pattern=weekday_counter,
            metadata={
                'sample_size': len(minute_offsets),
                'std_dev_minutes': std_dev,
                'central_minute': central_minute,
                'timezone': timezone_name,
                'last_recomputed_at': datetime.utcnow().isoformat()
            }
        )
        self._persist_snapshot(snapshot)
        return snapshot

    def _collect_samples(self, user_id: str, plan_id: int) -> List[datetime]:
        """Collect recent session start timestamps for cadence learning."""
        samples: List[datetime] = []

        try:
            plan_sessions_resp = self.admin_client.table('plan_sessions').select(
                'id, completed_date, completion_status'
            ).eq('user_coaching_plan_id', plan_id).eq('completion_status', 'completed').order(
                'completed_date', desc=True
            ).limit(10).execute()
            for row in plan_sessions_resp.data or []:
                completed_date = row.get('completed_date')
                if completed_date:
                    try:
                        samples.append(parser.isoparse(completed_date))
                    except Exception:
                        continue
        except Exception as exc:
            logger.error(f"Failed to fetch completed plan sessions for plan {plan_id}: {exc}")

        try:
            ruck_resp = self.admin_client.table('ruck_session').select(
                'id, started_at, completed_at'
            ).eq('user_id', user_id).eq('status', 'completed').order('completed_at', desc=True).limit(20).execute()
            for row in ruck_resp.data or []:
                dt_value = row.get('started_at') or row.get('completed_at')
                if dt_value:
                    try:
                        samples.append(parser.isoparse(dt_value))
                    except Exception:
                        continue
        except Exception as exc:
            logger.error(f"Failed to fetch ruck sessions for cadence analysis: {exc}")

        # Deduplicate by timestamp to reduce overweighting
        deduped = []
        seen = set()
        for dt_value in samples:
            key = dt_value.replace(second=0, microsecond=0).isoformat()
            if key not in seen:
                seen.add(key)
                deduped.append(dt_value)
        return deduped[:30]

    def _calculate_confidence(self, sample_size: int, std_dev: float) -> float:
        if sample_size < MIN_HISTORY_FOR_CONFIDENCE:
            return 0.3 if sample_size >= 3 else 0.1
        spread_factor = min(std_dev / 120.0, 1.0)  # std dev relative to 2 hours
        confidence = max(0.0, 1.0 - spread_factor)
        return round(confidence, 2)

    def _persist_snapshot(self, snapshot: PlanBehaviorSnapshot) -> None:
        try:
            payload = {
                'user_id': snapshot.user_id,
                'user_coaching_plan_id': snapshot.plan_id,
                'prime_window_start_minute': snapshot.prime_window_start_minute,
                'prime_window_end_minute': snapshot.prime_window_end_minute,
                'confidence_score': snapshot.confidence,
                'weekday_pattern': snapshot.weekday_pattern,
                'metadata': snapshot.metadata,
                'last_recomputed_at': snapshot.metadata.get('last_recomputed_at')
            }
            self.admin_client.table('user_plan_behavior').upsert(
                payload,
                on_conflict='user_coaching_plan_id,user_id'
            ).execute()
        except Exception as exc:
            logger.error(f"Failed to persist plan behavior snapshot: {exc}")


class PlanNotificationContentFactory:
    """Generates tone-aware notification titles and bodies."""

    def __init__(self):
        pass

    def build_evening_brief(self, tone: str, session_context: Dict[str, Any]) -> Tuple[str, str]:
        weather_phrase = self._build_weather_phrase(session_context.get('weather_summary'))
        distance = session_context.get('distance_label', 'tomorrow\'s ruck')
        start_time = session_context.get('start_time_label', 'early')

        templates = {
            'drill_sergeant': (
                'Prep for Tomorrow\'s Ruck',
                f"Gear staged and lights out early. {distance} kicks off {start_time}. {weather_phrase}No excuses—show up mission-ready."
            ),
            'supportive_friend': (
                'Pack Up for Tomorrow',
                f"Lay your gear out tonight so {distance} feels effortless {start_time}. {weather_phrase}Rest up—you\'re building something awesome!"
            ),
            'data_nerd': (
                'Tomorrow\'s Session Brief',
                f"Scheduled start {start_time}. {distance} with target load {session_context.get('target_load', 'planned load')}. {weather_phrase}Optimize sleep window so HRV rebounds."
            ),
            'minimalist': (
                'Prep Tonight',
                f"{distance} starts {start_time}. {weather_phrase}Pack. Sleep. Execute."
            )
        }
        return templates.get(tone, templates['supportive_friend'])

    def build_morning_hype(self, tone: str, session_context: Dict[str, Any]) -> Tuple[str, str]:
        focus = session_context.get('session_focus', 'today\'s work')
        templates = {
            'drill_sergeant': (
                'Move Out',
                f"Alarm. Gear. Door. Hit {focus} and own the morning. Mission on."
            ),
            'supportive_friend': (
                'Good Morning, Rockstar',
                f"Quick sip, quick warmup—then let\'s crush {focus}. You always feel better after the first 5 minutes."
            ),
            'data_nerd': (
                'Session Window Open',
                f"Prime window underway. Track splits, stay inside target RPE {session_context.get('target_rpe', 'moderate')}."
            ),
            'minimalist': (
                'It\'s Go Time',
                f"{focus}."
            )
        }
        return templates.get(tone, templates['supportive_friend'])

    def build_completion_celebration(self, tone: str, session_context: Dict[str, Any]) -> Tuple[str, str]:
        distance = session_context.get('distance_label', 'session')
        next_tip = session_context.get('next_tip')
        templates = {
            'drill_sergeant': (
                'Session Secure',
                f"{distance.capitalize()} complete. {next_tip or 'Hydrate and refuel—next objective on deck.'} Keep the pressure on."
            ),
            'supportive_friend': (
                'You Did It!',
                f"{distance.capitalize()} locked in! {next_tip or 'Take a minute to savor it—you earned this.'}"
            ),
            'data_nerd': (
                'Metrics Logged',
                f"Session recorded. Pace {session_context.get('pace')} · Load {session_context.get('load_label')}. {next_tip or 'Update readiness journal for tomorrow.'}"
            ),
            'minimalist': (
                'Done + Dusted',
                f"{distance.capitalize()} complete. {next_tip or 'Nice work.'}"
            )
        }
        return templates.get(tone, templates['supportive_friend'])

    def build_missed_followup(self, tone: str, session_context: Dict[str, Any]) -> Tuple[str, str]:
        makeup = session_context.get('makeup_tip', 'Slot it in tomorrow or swap to a recovery walk.')
        templates = {
            'drill_sergeant': (
                'Session Missed',
                f"Window closed without a ruck. Reset tonight, reschedule, and execute that makeup session."
            ),
            'supportive_friend': (
                'Let\'s Bounce Back',
                f"Today went sideways—that happens. {makeup} I\'m in your corner."
            ),
            'data_nerd': (
                'Adherence Dip',
                f"Planned session not executed; adherence -1. {makeup} Update plan to stay on curve."
            ),
            'minimalist': (
                'Missed',
                f"No session logged. {makeup}"
            )
        }
        return templates.get(tone, templates['supportive_friend'])

    def build_weekly_digest(self, tone: str, summary: Dict[str, Any]) -> Tuple[str, str]:
        adherence = summary.get('adherence_percent', 0)
        completed = summary.get('completed_sessions', 0)
        planned = summary.get('planned_sessions', 0)
        next_focus = summary.get('upcoming_focus', 'steady volume')
        templates = {
            'drill_sergeant': (
                'Weekly Debrief',
                f"Executed {completed}/{planned} ({adherence:.0f}% adherence). Next focus: {next_focus}. Carry momentum forward."
            ),
            'supportive_friend': (
                'Weekly High-Five',
                f"{completed} of {planned} sessions done ({adherence:.0f}%!). Next week dial in {next_focus}. I love the consistency."
            ),
            'data_nerd': (
                'Weekly Metrics',
                f"Sessions {completed}/{planned}, adherence {adherence:.0f}%. Upcoming block: {next_focus}. Trending: {summary.get('trend', 'steady')}"
            ),
            'minimalist': (
                'Weekly Snapshot',
                f"{completed}/{planned}. Next: {next_focus}."
            )
        }
        return templates.get(tone, templates['supportive_friend'])

    def _build_weather_phrase(self, weather_summary: Optional[str]) -> str:
        if not weather_summary:
            return ''
        return f"Forecast: {weather_summary}. "


class PlanNotificationService:
    """Coordinates scheduling, sending, and auditing of plan notifications."""

    def __init__(self, admin_client=None):
        self.admin_client = admin_client or get_supabase_admin_client()
        self.cadence_analyzer = PlanCadenceAnalyzer(self.admin_client)
        self.content_factory = PlanNotificationContentFactory()
        self.weather_api_key = os.getenv('OPENWEATHER_API_KEY')
        self.weather_base_url = "https://api.openweathermap.org/data/2.5"

    # ------------------------------------------------------------------
    # Public orchestration APIs
    # ------------------------------------------------------------------
    def seed_plan_schedule(self, user_id: str, plan_id: int) -> None:
        """Schedule baseline notifications right after plan creation."""
        plan = self._fetch_plan(user_id, plan_id)
        if not plan:
            logger.warning(f"Cannot seed notifications; plan {plan_id} not found for user {user_id}")
            return

        timezone_name = plan.get('plan_notification_timezone') or plan.get('timezone') or 'UTC'
        logger.info(f"Seeding notifications for plan {plan_id} with timezone {timezone_name}")

        behavior = self.cadence_analyzer.ensure_behavior_snapshot(user_id, plan_id, timezone_name)
        prefs = self._get_user_preferences(user_id)
        # Fetch all sessions for the plan to schedule notifications for the entire duration
        upcoming_sessions = self._fetch_upcoming_sessions(plan_id, limit=100)

        logger.info(f"Found {len(upcoming_sessions)} upcoming sessions to schedule notifications for")

        for session in upcoming_sessions:
            self._schedule_session_notifications(user_id, plan_id, session, timezone_name, behavior, prefs)

        logger.info(f"Completed notification scheduling for plan {plan_id}")

    def handle_session_completed(self, user_id: str, plan_id: int, plan_session_id: int, session_payload: Dict[str, Any]) -> None:
        """Send completion celebration and update future queues."""
        plan = self._fetch_plan(user_id, plan_id)
        if not plan:
            return
        timezone_name = plan.get('plan_notification_timezone') or plan.get('timezone') or 'UTC'
        prefs = self._get_user_preferences(user_id)
        behavior = self.cadence_analyzer.ensure_behavior_snapshot(user_id, plan_id, timezone_name)

        tone = prefs.get('coaching_tone') or plan.get('coaching_personality') or 'supportive_friend'
        session_context = self._build_session_context(
            plan,
            None,
            behavior,
            prefs,
            notification_type='plan_completion_celebration',
            session_payload=session_payload,
            user_id=user_id
        )

        ai_content = notification_manager.generate_ai_plan_notification(
            user_id=user_id,
            notification_type='plan_completion_celebration',
            tone=tone,
            context=session_context
        )

        if ai_content:
            title = ai_content.get('title', '').strip() or 'Session complete'
            body = ai_content.get('body', '').strip() or 'Great work on that ruck!' 
        else:
            title, body = self.content_factory.build_completion_celebration(tone, session_context)

        notification_manager.send_notification(
            recipients=[user_id],
            notification_type='plan_completion_celebration',
            title=title,
            body=body,
            data={
                'plan_id': plan_id,
                'plan_session_id': plan_session_id,
                'type': 'plan_completion_celebration',
                'session_context': session_context,
                'session_payload': session_payload
            }
        )

        self._mark_audit_entries(plan_session_id, ['plan_evening_brief', 'plan_morning_hype', 'plan_missed_followup'], status='cancelled')
        self._schedule_followup_if_needed(user_id, plan_id, plan_session_id, session_payload, prefs, timezone_name)

        upcoming_sessions = self._fetch_upcoming_sessions(plan_id, limit=5)
        for session in upcoming_sessions:
            if session['id'] != plan_session_id:
                self._schedule_session_notifications(user_id, plan_id, session, timezone_name, behavior, prefs)

    def process_scheduled_notifications(self) -> int:
        """Send notifications whose scheduled time has arrived."""
        now = datetime.utcnow()
        try:
            due_resp = self.admin_client.table('plan_notification_audit').select('*').eq(
                'status', 'scheduled'
            ).lte('scheduled_for', now.isoformat()).limit(200).execute()
        except Exception as exc:
            logger.error(f"Failed to fetch due plan notifications: {exc}")
            return 0

        processed = 0
        for row in due_resp.data or []:
            try:
                self._send_from_audit_row(row)
                processed += 1
            except Exception as exc:
                logger.error(f"Error sending plan notification {row.get('id')}: {exc}")
        return processed

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------
    def _fetch_plan(self, user_id: str, plan_id: int) -> Optional[Dict[str, Any]]:
        try:
            resp = self.admin_client.table('user_coaching_plans').select(
                'id, user_id, coaching_personality, plan_modifications, plan_notification_timezone, start_date'
            ).eq('id', plan_id).eq('user_id', user_id).limit(1).execute()
            if resp.data:
                plan = resp.data[0]
                if plan.get('plan_modifications') is None:
                    plan['plan_modifications'] = {}
                plan_name = plan.get('plan_modifications', {}).get('personalization', {}).get('plan_name')
                if not plan_name:
                    plan_name = plan.get('plan_modifications', {}).get('plan_type')
                plan['plan_name'] = plan_name or 'Coaching plan'
                return plan
        except Exception as exc:
            logger.error(f"Failed to fetch plan {plan_id}: {exc}")
        return None

    def _fetch_upcoming_sessions(self, plan_id: int, limit: int = 10) -> List[Dict[str, Any]]:
        try:
            resp = self.admin_client.table('plan_sessions').select(
                'id, planned_week, planned_session_type, scheduled_date, scheduled_start_time, scheduled_timezone, completion_status'
            ).eq('user_coaching_plan_id', plan_id).eq('completion_status', 'planned').order(
                'scheduled_date'
            ).order('id').limit(limit).execute()
            return resp.data or []
        except Exception as exc:
            logger.error(f"Failed to fetch upcoming sessions for plan {plan_id}: {exc}")
            return []

    def _schedule_session_notifications(self,
                                         user_id: str,
                                         plan_id: int,
                                         session: Dict[str, Any],
                                         timezone_name: str,
                                         behavior: PlanBehaviorSnapshot,
                                         prefs: Dict[str, Any]) -> None:
        session_id = session['id']
        scheduled_date = session.get('scheduled_date')
        if not scheduled_date:
            return

        # Check if first ruck notifications are disabled
        if prefs.get('first_ruck_notifications_disabled', False):
            logger.info(f"Skipping first ruck notifications for user {user_id} - disabled in preferences")
            return

        # Get timezone from session or fall back to plan timezone
        session_timezone = session.get('scheduled_timezone') or timezone_name

        # Use pytz for proper timezone handling
        try:
            import pytz
            tzinfo = pytz.timezone(session_timezone)
        except ImportError:
            # Fallback if pytz not installed yet
            from datetime import timezone as dt_timezone
            tzinfo = dt_timezone.utc
            logger.warning(f"pytz not installed, using UTC instead of '{session_timezone}'")
        except Exception as e:
            # Fallback for invalid timezone
            import pytz
            tzinfo = pytz.UTC
            logger.warning(f"Invalid timezone '{session_timezone}': {e}, using UTC")
        start_time = self._resolve_session_start_time(session, behavior, prefs)
        session_start_dt = datetime.combine(
            datetime.fromisoformat(scheduled_date).date(),
            start_time
        ).replace(tzinfo=tzinfo)

        evening_offset = prefs.get('evening_brief_offset_minutes', DEFAULT_EVENING_OFFSET_MINUTES)
        evening_dt = session_start_dt - timedelta(minutes=evening_offset)
        morning_dt = session_start_dt - timedelta(minutes=MORNING_HYPE_OFFSET_MINUTES)

        now = datetime.now(tzinfo)
        if evening_dt > now:
            self._upsert_audit_entry(
                user_id=user_id,
                plan_id=plan_id,
                session_id=session_id,
                notification_type='plan_evening_brief',
                scheduled_at=evening_dt.astimezone(timezone.utc)
            )
            self._update_session_next_notification(session_id, evening_dt.astimezone(timezone.utc))

        if morning_dt > now:
            self._upsert_audit_entry(
                user_id=user_id,
                plan_id=plan_id,
                session_id=session_id,
                notification_type='plan_morning_hype',
                scheduled_at=morning_dt.astimezone(timezone.utc)
            )

        missed_dt = session_start_dt + timedelta(minutes=MISSED_FOLLOWUP_GRACE_MINUTES)
        self._upsert_audit_entry(
            user_id=user_id,
            plan_id=plan_id,
            session_id=session_id,
            notification_type='plan_missed_followup',
            scheduled_at=missed_dt.astimezone(timezone.utc)
        )

    def _resolve_session_start_time(self,
                                    session: Dict[str, Any],
                                    behavior: PlanBehaviorSnapshot,
                                    prefs: Dict[str, Any]) -> time:
        start_time_value = session.get('scheduled_start_time')
        if start_time_value:
            try:
                if isinstance(start_time_value, str):
                    return datetime.strptime(start_time_value, '%H:%M:%S').time()
            except ValueError:
                try:
                    return datetime.strptime(start_time_value, '%H:%M').time()
                except ValueError:
                    pass

        if behavior.is_confident():
            minute_of_day = behavior.prime_window_start_minute or 360
        else:
            minute_of_day = prefs.get('default_start_minute', 360)

        hour = minute_of_day // 60
        minute = minute_of_day % 60
        return time(hour=hour % 24, minute=minute)

    def _update_session_next_notification(self, session_id: int, next_dt_utc: Optional[datetime]) -> None:
        try:
            payload = {'next_notification_at': next_dt_utc.isoformat()} if next_dt_utc else {'next_notification_at': None}
            self.admin_client.table('plan_sessions').update(payload).eq('id', session_id).execute()
        except Exception as exc:
            logger.error(f"Failed to update plan_sessions.next_notification_at for {session_id}: {exc}")

    def _upsert_audit_entry(self,
                             user_id: str,
                             plan_id: int,
                             session_id: Optional[int],
                             notification_type: str,
                             scheduled_at: datetime) -> None:
        try:
            query = self.admin_client.table('plan_notification_audit').select('id').eq(
                'user_id', user_id
            ).eq('user_coaching_plan_id', plan_id).eq(
                'notification_type', notification_type
            ).eq('status', 'scheduled')

            if session_id is None:
                query = query.is_('plan_session_id', 'null')
            else:
                query = query.eq('plan_session_id', session_id)

            existing = query.limit(1).execute()

            if existing.data:
                audit_id = existing.data[0]['id']
                self.admin_client.table('plan_notification_audit').update({
                    'scheduled_for': scheduled_at.isoformat()
                }).eq('id', audit_id).execute()
            else:
                self.admin_client.table('plan_notification_audit').insert({
                    'user_id': user_id,
                    'user_coaching_plan_id': plan_id,
                    'plan_session_id': session_id,
                    'notification_type': notification_type,
                    'scheduled_for': scheduled_at.isoformat(),
                    'status': 'scheduled'
                }).execute()
        except Exception as exc:
            logger.error(f"Failed to upsert plan notification audit for session {session_id}: {exc}")

    def _send_from_audit_row(self, row: Dict[str, Any]) -> None:
        user_id = row['user_id']
        plan_id = row.get('user_coaching_plan_id')
        session_id = row.get('plan_session_id')
        notification_type = row['notification_type']

        plan = self._fetch_plan(user_id, plan_id) if plan_id else None
        prefs = self._get_user_preferences(user_id)
        tone = prefs.get('coaching_tone') or (plan.get('coaching_personality') if plan else 'supportive_friend')
        timezone_name = plan.get('plan_notification_timezone') if plan else prefs.get('timezone', 'UTC')
        behavior = self.cadence_analyzer.ensure_behavior_snapshot(user_id, plan_id, timezone_name)
        session = None
        if session_id:
            session_list = self._fetch_upcoming_sessions(plan_id, limit=20)
            for entry in session_list:
                if entry['id'] == session_id:
                    session = entry
                    break

        session_context = self._build_session_context(
            plan,
            session,
            behavior,
            prefs,
            notification_type=notification_type,
            user_id=user_id
        )

        ai_content = notification_manager.generate_ai_plan_notification(
            user_id=user_id,
            notification_type=notification_type,
            tone=tone,
            context=session_context
        )

        if ai_content:
            title = ai_content.get('title', '').strip() or 'Ruck update'
            body = ai_content.get('body', '').strip() or 'Stay on track with your plan.'
        else:
            if notification_type == 'plan_evening_brief':
                title, body = self.content_factory.build_evening_brief(tone, session_context)
            elif notification_type == 'plan_morning_hype':
                title, body = self.content_factory.build_morning_hype(tone, session_context)
            elif notification_type == 'plan_missed_followup':
                title, body = self.content_factory.build_missed_followup(tone, session_context)
            elif notification_type == 'plan_weekly_digest':
                title, body = self.content_factory.build_weekly_digest(tone, session_context)
            else:
                logger.warning(f"Unknown plan notification type {notification_type}")
                self._mark_audit_entry(row['id'], status='failed')
                return

        notification_manager.send_notification(
            recipients=[user_id],
            notification_type=notification_type,
            title=title,
            body=body,
            data={
                'type': notification_type,
                'plan_id': plan_id,
                'plan_session_id': session_id,
                'context': session_context
            }
        )

        self._mark_audit_entry(row['id'], status='sent')
        if session_id and notification_type != 'plan_missed_followup':
            self._update_session_next_notification(session_id, None)

    def _mark_audit_entry(self, audit_id: int, status: str) -> None:
        try:
            payload = {
                'status': status,
                'sent_at': datetime.utcnow().isoformat() if status == 'sent' else None
            }
            self.admin_client.table('plan_notification_audit').update(payload).eq('id', audit_id).execute()
        except Exception as exc:
            logger.error(f"Failed to mark plan_notification_audit {audit_id} as {status}: {exc}")

    def _mark_audit_entries(self, session_id: int, types: List[str], status: str) -> None:
        try:
            self.admin_client.table('plan_notification_audit').update({
                'status': status,
                'sent_at': datetime.utcnow().isoformat() if status == 'sent' else None
            }).eq('plan_session_id', session_id).in_('notification_type', types).eq('status', 'scheduled').execute()
        except Exception as exc:
            logger.error(f"Failed bulk update of plan_notification_audit for session {session_id}: {exc}")

    def _schedule_followup_if_needed(self,
                                     user_id: str,
                                     plan_id: int,
                                     session_id: int,
                                     session_payload: Dict[str, Any],
                                     prefs: Dict[str, Any],
                                     timezone_name: str) -> None:
        weekday = datetime.utcnow().strftime('%A')
        summary_needed = prefs.get('weekly_digest_day')
        if summary_needed and weekday == summary_needed:
            tzinfo = timezone.utc(timezone_name) or timezone.utc
            now_local = datetime.now(tzinfo)
            digest_local = now_local.replace(hour=19, minute=0, second=0, microsecond=0)
            if digest_local <= now_local:
                digest_local += timedelta(days=1)
            self._upsert_audit_entry(
                user_id=user_id,
                plan_id=plan_id,
                session_id=None,
                notification_type='plan_weekly_digest',
                scheduled_at=digest_local.astimezone(timezone.utc)
            )

    def _build_session_context(self,
                               plan: Optional[Dict[str, Any]],
                               session: Optional[Dict[str, Any]],
                               behavior: PlanBehaviorSnapshot,
                               prefs: Dict[str, Any],
                               notification_type: Optional[str] = None,
                               session_payload: Optional[Dict[str, Any]] = None,
                               user_id: Optional[str] = None) -> Dict[str, Any]:
        ctx: Dict[str, Any] = {}

        timezone_name = prefs.get('timezone', 'UTC')
        ctx['timezone'] = timezone_name

        if plan:
            plan_name = plan.get('plan_name') or plan.get('plan_modifications', {}).get('plan_type') or 'Coaching plan'
            ctx['plan_name'] = plan_name
            ctx['plan_id'] = plan.get('id')

        if behavior:
            ctx['behavior_confidence'] = behavior.confidence

        if session:
            ctx['session_id'] = session['id']
            ctx['plan_session_id'] = session['id']
            ctx['session_focus'] = session.get('planned_session_type', 'the session')
            scheduled_date = session.get('scheduled_date')
            scheduled_time = session.get('scheduled_start_time')
            if session.get('scheduled_timezone'):
                ctx['timezone'] = session['scheduled_timezone']
            if scheduled_date:
                try:
                    date_obj = datetime.fromisoformat(scheduled_date)
                    ctx['scheduled_date_label'] = date_obj.strftime('%A')
                except ValueError:
                    ctx['scheduled_date_label'] = scheduled_date
            if scheduled_time and isinstance(scheduled_time, str):
                ctx['start_time_label'] = scheduled_time[:5]
        elif session_payload and session_payload.get('scheduled_date'):
            try:
                date_obj = datetime.fromisoformat(session_payload['scheduled_date'])
                ctx['scheduled_date_label'] = date_obj.strftime('%A')
            except ValueError:
                ctx['scheduled_date_label'] = session_payload['scheduled_date']

        if session_payload and session_payload.get('session_focus') and not ctx.get('session_focus'):
            ctx['session_focus'] = session_payload['session_focus']
        if session_payload and session_payload.get('scheduled_timezone') and not session_payload.get('scheduled_timezone') == ctx.get('timezone'):
            ctx['timezone'] = session_payload.get('scheduled_timezone') or ctx.get('timezone')
        if session_payload and session_payload.get('scheduled_start_time') and not ctx.get('start_time_label'):
            scheduled_start = session_payload['scheduled_start_time']
            if isinstance(scheduled_start, str):
                ctx['start_time_label'] = scheduled_start[:5]

        ctx['target_load'] = prefs.get('target_load_label')
        ctx['target_rpe'] = prefs.get('target_rpe')
        ctx['distance_label'] = prefs.get('distance_label')
        ctx['makeup_tip'] = prefs.get('makeup_tip')

        # Fetch weather forecast for the session time
        weather_summary = self._get_session_weather(session, session_payload, prefs, user_id)
        if weather_summary:
            ctx['weather_summary'] = weather_summary
        else:
            ctx['weather_summary'] = prefs.get('weather_summary')

        if session_payload:
            if session_payload.get('distance_km') is not None:
                ctx['distance_label'] = f"{session_payload['distance_km']:.1f} km"
            if session_payload.get('duration_minutes') is not None:
                ctx['duration_minutes'] = session_payload['duration_minutes']
            if session_payload.get('ruck_weight_kg') is not None:
                ctx['load_label'] = f"{session_payload['ruck_weight_kg']:.1f} kg"
            if session_payload.get('adherence_score') is not None:
                ctx['adherence_percent'] = round(float(session_payload['adherence_score']) * 100)
            if session_payload.get('next_tip'):
                ctx['next_tip'] = session_payload['next_tip']
            if session_payload.get('makeup_tip'):
                ctx['makeup_tip'] = session_payload['makeup_tip']

        if not ctx.get('start_time_label'):
            minute_of_day = None
            if session and session.get('scheduled_start_time'):
                try:
                    parsed_time = datetime.strptime(session['scheduled_start_time'], '%H:%M:%S').time()
                    minute_of_day = parsed_time.hour * 60 + parsed_time.minute
                except ValueError:
                    pass
            if minute_of_day is None and behavior and behavior.prime_window_start_minute is not None:
                minute_of_day = behavior.prime_window_start_minute
            if minute_of_day is None:
                minute_of_day = prefs.get('default_start_minute', 360)

            hour = (minute_of_day // 60) % 24
            minute = minute_of_day % 60
            ctx['start_time_label'] = f"{hour:02d}:{minute:02d}"

        if behavior and behavior.prime_window_start_minute is not None and behavior.prime_window_end_minute is not None:
            start_hour = behavior.prime_window_start_minute // 60
            start_min = behavior.prime_window_start_minute % 60
            end_hour = behavior.prime_window_end_minute // 60
            end_min = behavior.prime_window_end_minute % 60
            ctx['prime_window_label'] = f"{start_hour:02d}:{start_min:02d}-{end_hour:02d}:{end_min:02d}"

        if notification_type == 'plan_weekly_digest' and plan:
            summary = self._build_weekly_summary(plan['id'])
            ctx.update(summary)
        if notification_type == 'plan_missed_followup' and not ctx.get('makeup_tip'):
            ctx['makeup_tip'] = 'Slide the session to tomorrow or log a short recovery walk today.'
        if notification_type == 'plan_completion_celebration' and not ctx.get('next_tip'):
            ctx['next_tip'] = 'Hydrate, refuel, and glance at the next session details tonight.'

        return ctx

    def _build_weekly_summary(self, plan_id: int) -> Dict[str, Any]:
        try:
            today = datetime.utcnow().date()
            window_start = today - timedelta(days=6)
            resp = self.admin_client.table('plan_sessions').select(
                'completion_status, scheduled_date, planned_session_type'
            ).eq('user_coaching_plan_id', plan_id).gte(
                'scheduled_date', window_start.isoformat()
            ).lte('scheduled_date', today.isoformat()).execute()

            rows = resp.data or []
            planned = len(rows)
            completed = len([r for r in rows if r.get('completion_status') == 'completed'])
            adherence = round((completed / planned) * 100, 1) if planned else 0.0
            trend = 'climbing' if adherence >= 80 else ('rebuilding' if adherence < 50 else 'steady')

            upcoming_sessions = self._fetch_upcoming_sessions(plan_id, limit=1)
            upcoming_focus = None
            if upcoming_sessions:
                upcoming_focus = upcoming_sessions[0].get('planned_session_type')

            return {
                'completed_sessions': completed,
                'planned_sessions': planned,
                'adherence_percent': adherence,
                'upcoming_focus': upcoming_focus or 'Stay consistent',
                'trend': trend
            }
        except Exception as exc:
            logger.error(f"Failed to build weekly summary for plan {plan_id}: {exc}")
            return {}

    def _get_user_preferences(self, user_id: str) -> Dict[str, Any]:
        def build_preferences(row: Dict[str, Any]) -> Dict[str, Any]:
            prefs = row.get('plan_notification_prefs') or {}
            prefs.setdefault('coaching_tone', row.get('coaching_tone') or 'supportive_friend')
            prefs['evening_brief_offset_minutes'] = row.get('plan_evening_brief_offset_minutes') or DEFAULT_EVENING_OFFSET_MINUTES
            prefs['quiet_hours'] = {
                'start': row.get('plan_quiet_hours_start'),
                'end': row.get('plan_quiet_hours_end')
            }
            prefs['timezone'] = row.get('plan_notification_timezone') or 'UTC'
            prefs.setdefault('default_start_minute', 360)
            prefs.setdefault('weekly_digest_day', 'Sunday')

            # Check for first ruck notification preference
            # notification_first_ruck = False means notifications are disabled
            prefs['first_ruck_notifications_disabled'] = not row.get('notification_first_ruck', True)

            return prefs

        try:
            resp = None
            try:
                resp = self.admin_client.table('user_profiles').select(
                    'coaching_tone, plan_notification_prefs, plan_quiet_hours_start, plan_quiet_hours_end, plan_evening_brief_offset_minutes, plan_notification_timezone, notification_first_ruck'
                ).eq('user_id', user_id).limit(1).execute()
            except Exception as profile_err:
                logger.debug(f"user_profiles lookup failed for {user_id}: {profile_err}")

            if resp and resp.data:
                return build_preferences(resp.data[0])

            users_resp = self.admin_client.table('user').select(
                'plan_notification_prefs, plan_quiet_hours_start, plan_quiet_hours_end, plan_evening_brief_offset_minutes, plan_notification_timezone, coaching_tone, notification_first_ruck'
            ).eq('id', user_id).limit(1).execute()
            if users_resp.data:
                return build_preferences(users_resp.data[0])

        except Exception as exc:
            logger.error(f"Failed to fetch plan notification prefs for {user_id}: {exc}")
        return {
            'coaching_tone': 'supportive_friend',
            'evening_brief_offset_minutes': DEFAULT_EVENING_OFFSET_MINUTES,
            'quiet_hours': {'start': None, 'end': None},
            'timezone': 'UTC',
            'default_start_minute': 360,
            'weekly_digest_day': 'Sunday'
        }

    def _get_session_weather(self, session: Optional[Dict[str, Any]], session_payload: Optional[Dict[str, Any]], prefs: Dict[str, Any], user_id: Optional[str] = None) -> Optional[str]:
        """Get weather forecast for a scheduled session."""
        try:
            # Get user_id from context if not provided
            if not user_id:
                return None

            # Get user's last known location from their recent sessions
            location = self._get_user_location(user_id)
            if not location:
                return None

            # Determine session datetime
            session_datetime = None

            if session and session.get('scheduled_date'):
                scheduled_date = session['scheduled_date']
                scheduled_time = session.get('scheduled_start_time', '06:00:00')
                timezone_name = session.get('scheduled_timezone') or prefs.get('timezone', 'UTC')

                try:
                    # Parse date and time
                    date_str = scheduled_date if isinstance(scheduled_date, str) else scheduled_date.isoformat()
                    time_str = scheduled_time if isinstance(scheduled_time, str) else '06:00:00'

                    # Combine date and time
                    datetime_str = f"{date_str} {time_str}"
                    session_datetime = datetime.fromisoformat(datetime_str)

                    # Apply timezone
                    tz_obj = timezone.utc(timezone_name)
                    if tz_obj:
                        session_datetime = session_datetime.replace(tzinfo=tz_obj)
                except Exception as e:
                    logger.warning(f"Failed to parse session datetime: {e}")
                    return None

            elif session_payload and session_payload.get('scheduled_date'):
                # Use session payload if available
                try:
                    scheduled_date = session_payload['scheduled_date']
                    scheduled_time = session_payload.get('scheduled_start_time', '06:00:00')
                    timezone_name = session_payload.get('scheduled_timezone') or prefs.get('timezone', 'UTC')

                    date_str = scheduled_date if isinstance(scheduled_date, str) else scheduled_date.isoformat()
                    time_str = scheduled_time if isinstance(scheduled_time, str) else '06:00:00'
                    datetime_str = f"{date_str} {time_str}"
                    session_datetime = datetime.fromisoformat(datetime_str)

                    tz_obj = timezone.utc(timezone_name)
                    if tz_obj:
                        session_datetime = session_datetime.replace(tzinfo=tz_obj)
                except Exception as e:
                    logger.warning(f"Failed to parse session payload datetime: {e}")
                    return None

            if not session_datetime:
                # Default to tomorrow morning if no date specified
                session_datetime = datetime.now() + timedelta(days=1)
                session_datetime = session_datetime.replace(hour=6, minute=0, second=0)

            # Fetch weather forecast
            weather_data = self._fetch_weather_forecast(
                location['latitude'],
                location['longitude'],
                session_datetime
            )

            if not weather_data:
                return None

            # Format the weather summary based on user preferences
            prefer_metric = prefs.get('prefer_metric', True)
            return self._format_weather_summary(weather_data, prefer_metric)

        except Exception as e:
            logger.error(f"Failed to get session weather: {e}")
            return None

    def _get_user_location(self, user_id: str) -> Optional[Dict[str, float]]:
        """Get user's location from their recent session or profile."""
        try:
            # Try to get from recent ruck sessions
            recent_session = self.admin_client.table('ruck_session').select(
                'start_latitude, start_longitude'
            ).eq('user_id', user_id).not_.is_('start_latitude', 'null').order(
                'created_at', desc=True
            ).limit(1).execute()

            if recent_session.data and recent_session.data[0].get('start_latitude'):
                return {
                    'latitude': recent_session.data[0]['start_latitude'],
                    'longitude': recent_session.data[0]['start_longitude']
                }

            # Fallback to user profile location if available
            user_profile = self.admin_client.table('user').select(
                'latitude, longitude'
            ).eq('id', user_id).limit(1).execute()

            if user_profile.data and user_profile.data[0].get('latitude'):
                return {
                    'latitude': user_profile.data[0]['latitude'],
                    'longitude': user_profile.data[0]['longitude']
                }

            logger.warning(f"No location found for user {user_id}")
            return None

        except Exception as e:
            logger.error(f"Failed to get user location: {e}")
            return None

    def _fetch_weather_forecast(self, latitude: float, longitude: float, target_datetime: datetime) -> Optional[Dict[str, Any]]:
        """Fetch weather forecast for a specific location and time."""
        if not self.weather_api_key:
            logger.warning("Weather API key not configured")
            return None

        try:
            # Use 5-day forecast API which gives 3-hour intervals
            url = f"{self.weather_base_url}/forecast"
            params = {
                'lat': latitude,
                'lon': longitude,
                'appid': self.weather_api_key,
                'units': 'metric'  # Celsius, m/s for wind
            }

            response = requests.get(url, params=params, timeout=10)
            if response.status_code != 200:
                logger.warning(f"Weather API returned {response.status_code}")
                return None

            data = response.json()
            forecasts = data.get('list', [])

            # Find the forecast closest to our target time
            target_timestamp = target_datetime.timestamp()
            closest_forecast = None
            min_time_diff = float('inf')

            for forecast in forecasts:
                forecast_time = forecast.get('dt', 0)
                time_diff = abs(forecast_time - target_timestamp)
                if time_diff < min_time_diff:
                    min_time_diff = time_diff
                    closest_forecast = forecast

            if not closest_forecast:
                return None

            # Extract relevant weather info
            weather = closest_forecast.get('weather', [{}])[0]
            main = closest_forecast.get('main', {})
            wind = closest_forecast.get('wind', {})

            return {
                'temperature': main.get('temp'),  # Celsius
                'feels_like': main.get('feels_like'),
                'description': weather.get('description', ''),
                'main': weather.get('main', ''),
                'wind_speed': wind.get('speed'),  # m/s
                'humidity': main.get('humidity'),
                'precipitation': closest_forecast.get('pop', 0) * 100,  # Convert to percentage
            }

        except Exception as e:
            logger.error(f"Failed to fetch weather forecast: {e}")
            return None

    def _format_weather_summary(self, weather_data: Optional[Dict[str, Any]], prefer_metric: bool = True) -> str:
        """Format weather data into a human-readable summary."""
        if not weather_data:
            return ""

        temp = weather_data.get('temperature')
        if temp is None:
            return ""

        # Convert temperature if needed
        if prefer_metric:
            temp_str = f"{round(temp)}°C"
        else:
            temp_f = (temp * 9/5) + 32
            temp_str = f"{round(temp_f)}°F"

        description = weather_data.get('description', '').lower()
        precip = weather_data.get('precipitation', 0)

        # Build summary based on conditions
        if precip > 60:
            summary = f"{temp_str} with likely rain ({round(precip)}% chance)"
        elif precip > 30:
            summary = f"{temp_str} with possible rain ({round(precip)}% chance)"
        elif 'rain' in description or 'storm' in description:
            summary = f"{temp_str} and {description}"
        elif 'snow' in description:
            summary = f"{temp_str} with snow"
        elif 'clear' in description or 'sun' in description:
            summary = f"{temp_str} and clear"
        elif 'cloud' in description:
            summary = f"{temp_str} and {description}"
        else:
            summary = f"{temp_str}"

        # Add wind warning if significant
        wind_speed = weather_data.get('wind_speed', 0)
        if wind_speed > 10:  # m/s, roughly 22 mph
            if prefer_metric:
                summary += f", windy ({round(wind_speed)} m/s)"
            else:
                mph = wind_speed * 2.237
                summary += f", windy ({round(mph)} mph)"

        return summary


# Singleton instance for reuse
plan_notification_service = PlanNotificationService()
