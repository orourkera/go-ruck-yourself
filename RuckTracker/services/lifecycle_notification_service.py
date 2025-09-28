"""Lifecycle notification processor for onboarding and reactivation pushes."""
from __future__ import annotations

import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional

from ..supabase_client import get_supabase_admin_client
from .notification_manager import notification_manager

logger = logging.getLogger(__name__)


class LifecycleNotificationService:
    """Processes cohort-based lifecycle push notifications."""

    NEW_USER_WINDOW_HOURS = 72
    NEW_USER_PRIMARY_SEND = 24
    NEW_USER_SECONDARY_SEND = 72
    SINGLE_RUCK_LAPSE_DAYS = 7

    def __init__(self) -> None:
        self.admin_client = get_supabase_admin_client()

    # ------------------------------------------------------------------
    # Public entrypoints
    # ------------------------------------------------------------------
    def process_new_user_nudges(self) -> int:
        """Send activation pushes to new users who have not logged a ruck."""
        users = self._fetch_new_user_targets()
        sent = 0
        for target in users:
            try:
                if self._has_existing_notification(
                    target['id'], f"retention_new_user_day{target['cohort']}"
                ):
                    continue

                timezone = target.get('plan_notification_timezone') or 'UTC'
                prefer_metric = target.get('prefer_metric', True)

                notification_manager.send_new_user_activation_notification(
                    recipient_id=target['id'],
                    hours_since_signup=target['hours_since_signup'],
                    context={
                        'timezone': timezone,
                        'prefer_metric': prefer_metric,
                    },
                )
                sent += 1
            except Exception as exc:
                logger.error(
                    "Failed to send new-user activation push for %s: %s",
                    target['id'],
                    exc,
                    exc_info=True,
                )
        logger.info("Lifecycle: dispatched %s new-user activation pushes", sent)
        return sent

    def process_single_ruck_lapses(self) -> int:
        """Reach out to users who did one ruck but have lapsed for a week."""
        targets = self._fetch_single_ruck_lapsed_users()
        sent = 0
        for target in targets:
            try:
                if self._has_existing_notification(target['id'], 'retention_single_ruck_day7'):
                    continue

                context = {
                    'last_ruck': target.get('last_ruck'),
                    'current_weather': self._get_current_weather_for_user(target['id']),
                }
                notification_manager.send_single_ruck_reactivation_notification(
                    recipient_id=target['id'],
                    days_since_last=self.SINGLE_RUCK_LAPSE_DAYS,
                    context=context,
                )
                sent += 1
            except Exception as exc:
                logger.error(
                    "Failed to send single-ruck reactivation push for %s: %s",
                    target['id'],
                    exc,
                    exc_info=True,
                )
        logger.info("Lifecycle: dispatched %s single-ruck reactivation pushes", sent)
        return sent

    # ------------------------------------------------------------------
    # Query helpers
    # ------------------------------------------------------------------
    def _fetch_new_user_targets(self) -> List[Dict[str, any]]:
        """Return users created within the activation windows with zero rucks."""
        now = datetime.utcnow()
        window_start = now - timedelta(hours=self.NEW_USER_WINDOW_HOURS)

        response = (
            self.admin_client
            .table('user')
            .select('id, created_at, prefer_metric, plan_notification_timezone')
            .gte('created_at', window_start.isoformat())
            .lte('created_at', (now - timedelta(hours=12)).isoformat())
            .execute()
        )

        users: List[Dict[str, any]] = []
        for row in response.data or []:
            created_at = datetime.fromisoformat(row['created_at'].replace('Z', '+00:00'))
            hours_since_signup = int((now - created_at).total_seconds() // 3600)

            if hours_since_signup < self.NEW_USER_PRIMARY_SEND:
                continue
            if hours_since_signup > self.NEW_USER_WINDOW_HOURS:
                continue

            if self._user_has_completed_rucks(row['id']):
                continue

            cohort = 1 if hours_since_signup < self.NEW_USER_SECONDARY_SEND else 3

            users.append(
                {
                    'id': row['id'],
                    'hours_since_signup': hours_since_signup,
                    'cohort': cohort,
                    'prefer_metric': row.get('prefer_metric', True),
                    'plan_notification_timezone': row.get('plan_notification_timezone'),
                }
            )
        return users

    def _fetch_single_ruck_lapsed_users(self) -> List[Dict[str, any]]:
        """Return users with exactly one completed ruck whose last session is ~7 days ago."""
        now = datetime.utcnow()
        window_start = now - timedelta(days=self.SINGLE_RUCK_LAPSE_DAYS + 2)
        window_end = now - timedelta(days=self.SINGLE_RUCK_LAPSE_DAYS)

        response = (
            self.admin_client
            .table('ruck_session')
            .select('user_id, completed_at, distance_km, duration_seconds, location_name, weather_conditions')
            .eq('status', 'completed')
            .gte('completed_at', window_start.isoformat())
            .lte('completed_at', window_end.isoformat())
            .order('completed_at', desc=True)
            .execute()
        )

        candidates = {}
        for row in response.data or []:
            user_id = row['user_id']
            completed_at = datetime.fromisoformat(row['completed_at'].replace('Z', '+00:00'))
            candidates.setdefault(user_id, row)

        targets: List[Dict[str, any]] = []
        for user_id, last_ruck in candidates.items():
            if not self._user_has_exactly_one_completed_ruck(user_id):
                continue

            targets.append(
                {
                    'id': user_id,
                    'last_ruck': {
                        'completed_at': last_ruck['completed_at'],
                        'distance_km': last_ruck.get('distance_km'),
                        'duration_seconds': last_ruck.get('duration_seconds'),
                        'location_name': last_ruck.get('location_name'),
                        'weather_conditions': last_ruck.get('weather_conditions'),
                    },
                }
            )
        return targets

    def _user_has_exactly_one_completed_ruck(self, user_id: str) -> bool:
        response = (
            self.admin_client
            .table('ruck_session')
            .select('id', count='exact')
            .eq('user_id', user_id)
            .eq('status', 'completed')
            .execute()
        )
        count = getattr(response, 'count', None)
        if count is None:
            count = len(response.data or [])
        return count == 1

    # ------------------------------------------------------------------
    # Support utilities
    # ------------------------------------------------------------------
    def _has_existing_notification(self, user_id: str, notification_type: str) -> bool:
        response = (
            self.admin_client
            .table('notifications')
            .select('id')
            .eq('recipient_id', user_id)
            .eq('type', notification_type)
            .limit(1)
            .execute()
        )
        return bool(response.data)

    def _get_current_weather_for_user(self, user_id: str) -> Optional[Dict[str, any]]:
        try:
            return notification_manager._get_current_weather_for_user(user_id)  # pylint: disable=protected-access
        except Exception as exc:
            logger.debug('Weather lookup failed for %s: %s', user_id, exc)
            return None

    def _user_has_completed_rucks(self, user_id: str) -> bool:
        response = (
            self.admin_client
            .table('ruck_session')
            .select('id', count='exact')
            .eq('user_id', user_id)
            .eq('status', 'completed')
            .limit(1)
            .execute()
        )
        count = getattr(response, 'count', None)
        if count is None:
            count = len(response.data or [])
        return count > 0


def process_lifecycle_notifications() -> Dict[str, int]:
    """Convenience wrapper for scheduled jobs."""
    service = LifecycleNotificationService()
    return {
        'new_user_pushes': service.process_new_user_nudges(),
        'single_ruck_reactivations': service.process_single_ruck_lapses(),
    }


if __name__ == '__main__':
    stats = process_lifecycle_notifications()
    logger.info('Lifecycle push job completed: %s', stats)
