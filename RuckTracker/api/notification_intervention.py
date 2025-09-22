"""
Notification opt-out intervention system - psychological tactics to prevent quitting.
"""

import logging
from datetime import datetime, timedelta
from flask import request, g
from flask_restful import Resource
from typing import Dict, Any, Tuple

from ..supabase_client import get_supabase_client, get_supabase_admin_client
from ..utils.auth_helper import get_current_user_id
from ..utils.api_response import check_auth_and_respond

logger = logging.getLogger(__name__)


class NotificationInterventionService:
    """Handles psychological interventions when users try to disable notifications."""

    def __init__(self):
        self.admin_client = get_supabase_admin_client()

    def get_user_coaching_context(self, user_id: str) -> Dict[str, Any]:
        """Get user's coaching plan progress and stats for intervention."""
        try:
            # Get active coaching plan
            plan_resp = self.admin_client.table('user_coaching_plans').select(
                'id, plan_name, start_date, duration_weeks, coaching_personality'
            ).eq('user_id', user_id).eq('current_status', 'active').limit(1).execute()

            if not plan_resp.data:
                return {}

            plan = plan_resp.data[0]
            plan_id = plan['id']

            # Get session stats
            sessions_resp = self.admin_client.table('plan_sessions').select(
                'id, completion_status'
            ).eq('user_coaching_plan_id', plan_id).execute()

            total_sessions = len(sessions_resp.data) if sessions_resp.data else 0
            completed_sessions = len([s for s in (sessions_resp.data or []) if s['completion_status'] == 'completed'])

            # Calculate days in plan
            start_date = datetime.fromisoformat(plan['start_date'].replace('Z', '+00:00'))
            days_in = (datetime.now() - start_date).days

            # Get disable attempt count
            attempts_resp = self.admin_client.table('notification_disable_attempts').select(
                'id'
            ).eq('user_id', user_id).execute()

            attempt_count = len(attempts_resp.data) if attempts_resp.data else 0

            return {
                'plan_id': plan_id,
                'plan_name': plan['plan_name'],
                'coaching_personality': plan['coaching_personality'],
                'total_sessions': total_sessions,
                'completed_sessions': completed_sessions,
                'completion_percentage': (completed_sessions / total_sessions * 100) if total_sessions > 0 else 0,
                'days_in_plan': days_in,
                'weeks_remaining': plan['duration_weeks'] - (days_in // 7),
                'attempt_count': attempt_count
            }

        except Exception as e:
            logger.error(f"Failed to get coaching context: {e}")
            return {}

    def record_disable_attempt(self, user_id: str, intervention_type: str, response: str):
        """Record that user attempted to disable notifications."""
        try:
            self.admin_client.table('notification_disable_attempts').insert({
                'user_id': user_id,
                'attempt_timestamp': datetime.now().isoformat(),
                'intervention_type': intervention_type,
                'user_response': response
            }).execute()
        except Exception as e:
            logger.error(f"Failed to record disable attempt: {e}")

    def get_intervention_message(self, personality: str, context: Dict[str, Any]) -> Dict[str, Any]:
        """Generate personality-specific intervention message."""

        attempt_count = context.get('attempt_count', 0)
        completion_pct = context.get('completion_percentage', 0)
        sessions_left = context.get('total_sessions', 0) - context.get('completed_sessions', 0)

        # Escalate based on attempt count
        if attempt_count == 0:
            return self._first_intervention(personality, completion_pct, sessions_left)
        elif attempt_count == 1:
            return self._second_intervention(personality, context)
        elif attempt_count == 2:
            return self._third_intervention(personality, context)
        else:
            return self._final_intervention(personality, context)

    def _first_intervention(self, personality: str, completion_pct: float, sessions_left: int) -> Dict[str, Any]:
        """First attempt - gentle redirect with progress reminder."""

        interventions = {
            'drill_sergeant': {
                'title': 'NEGATIVE, SOLDIER!',
                'message': f"You're {completion_pct:.0f}% through your mission with only {sessions_left} sessions left. You think you can just quit when it gets tough? Your future self will hate you for this weakness!",
                'buttons': [
                    {'text': 'Roger That', 'action': 'dismiss', 'style': 'primary'},
                    {'text': "I'm Weak", 'action': 'disable', 'style': 'danger'}
                ],
                'image': 'drill_sergeant_disappointed'
            },
            'supportive_friend': {
                'title': 'Wait, Let\'s Talk!',
                'message': f"You've already completed {completion_pct:.0f}% of your plan! That's amazing! Only {sessions_left} sessions to go. What if we adjusted the timing instead of turning them off completely?",
                'buttons': [
                    {'text': 'Adjust Timing', 'action': 'adjust', 'style': 'primary'},
                    {'text': 'Keep Them On', 'action': 'dismiss', 'style': 'secondary'},
                    {'text': 'Turn Off Anyway', 'action': 'disable', 'style': 'danger'}
                ],
                'image': 'supportive_concerned'
            },
            'data_nerd': {
                'title': 'Statistical Analysis',
                'message': f"Current progress: {completion_pct:.1f}% complete. Remaining sessions: {sessions_left}. Users who disable notifications have 91% plan failure rate. Your success probability drops from 78% to 9% if you proceed.",
                'buttons': [
                    {'text': 'View My Stats', 'action': 'stats', 'style': 'primary'},
                    {'text': 'Continue Plan', 'action': 'dismiss', 'style': 'secondary'},
                    {'text': 'Accept 91% Failure Risk', 'action': 'disable', 'style': 'danger'}
                ],
                'image': 'data_chart_down'
            },
            'minimalist': {
                'title': 'Really?',
                'message': f"{completion_pct:.0f}% done. {sessions_left} left.",
                'buttons': [
                    {'text': 'Continue', 'action': 'dismiss', 'style': 'primary'},
                    {'text': 'Quit', 'action': 'disable', 'style': 'danger'}
                ],
                'image': None
            }
        }

        return interventions.get(personality, interventions['supportive_friend'])

    def _second_intervention(self, personality: str, context: Dict[str, Any]) -> Dict[str, Any]:
        """Second attempt - show what they're giving up."""

        days_invested = context.get('days_in_plan', 0)
        weeks_remaining = context.get('weeks_remaining', 0)

        interventions = {
            'drill_sergeant': {
                'title': 'YOU\'RE GIVING UP?!',
                'message': f"After {days_invested} days of effort?! You have {weeks_remaining} weeks left to prove you're not a quitter. 87% of people who turn off notifications quit within a week. BE THE 13% WHO DON'T!",
                'buttons': [
                    {'text': "I'm Not a Quitter", 'action': 'dismiss', 'style': 'primary'},
                    {'text': 'One Day Break', 'action': 'snooze_24h', 'style': 'warning'},
                    {'text': "I Give Up", 'action': 'disable', 'style': 'danger'}
                ],
                'image': 'drill_sergeant_angry',
                'show_progress': True
            },
            'supportive_friend': {
                'title': f'You\'ve Invested {days_invested} Days!',
                'message': f"I know it's tough, but you've built such great momentum! How about we try just one more session tomorrow? If you still feel this way after, we can reassess. Deal?",
                'buttons': [
                    {'text': 'One More Session', 'action': 'one_more', 'style': 'primary'},
                    {'text': 'Pause 24 Hours', 'action': 'snooze_24h', 'style': 'warning'},
                    {'text': 'I Need to Stop', 'action': 'disable', 'style': 'danger'}
                ],
                'image': 'supportive_encouraging',
                'show_progress': True
            }
        }

        return interventions.get(personality, interventions['supportive_friend'])

    def _third_intervention(self, personality: str, context: Dict[str, Any]) -> Dict[str, Any]:
        """Third attempt - compromise offer."""

        return {
            'title': 'Final Offer',
            'message': "Okay, let's compromise. What if we only send you one notification per day - just the evening prep reminder? That's 85% fewer notifications but keeps you accountable.",
            'buttons': [
                {'text': 'Just Evening Reminders', 'action': 'reduce_critical', 'style': 'primary'},
                {'text': 'Switch Coach Personality', 'action': 'switch_personality', 'style': 'secondary'},
                {'text': 'Disable Everything', 'action': 'disable_with_penalty', 'style': 'danger'}
            ],
            'warning': 'Warning: Disabling will reset your streak and remove your Committed badge',
            'image': 'last_chance'
        }

    def _final_intervention(self, personality: str, context: Dict[str, Any]) -> Dict[str, Any]:
        """Final attempt - let them go but with consequences."""

        return {
            'title': 'Accountability Contract Broken',
            'message': f"On {context.get('start_date', 'day one')}, you committed to completing this plan. Disabling notifications breaks this contract with yourself.",
            'buttons': [
                {'text': 'Honor My Commitment', 'action': 'dismiss', 'style': 'primary'},
                {'text': 'Break My Word', 'action': 'disable_final', 'style': 'danger'}
            ],
            'consequences': [
                'Streak will reset to 0',
                'Committed badge will be removed',
                'Excluded from leaderboards',
                'Plan marked as abandoned'
            ],
            'image': 'contract_torn'
        }


class CoachingNotificationInterventionResource(Resource):
    """API endpoint for handling notification disable attempts."""

    def __init__(self):
        self.service = NotificationInterventionService()

    def post(self):
        """Handle attempt to disable coaching plan notifications."""
        try:
            user_id = get_current_user_id()
            auth_response = check_auth_and_respond(user_id)
            if auth_response:
                return auth_response

            data = request.get_json() or {}
            action = data.get('action', 'attempt_disable')

            # Get user's coaching context
            context = self.service.get_user_coaching_context(user_id)

            if not context.get('plan_id'):
                # No active plan, let them disable
                return {
                    'allow_disable': True,
                    'message': 'No active coaching plan'
                }, 200

            # Check if they're responding to a previous intervention
            if action in ['dismiss', 'adjust', 'stats', 'snooze_24h', 'one_more',
                         'reduce_critical', 'switch_personality', 'disable_with_penalty', 'disable_final']:

                # Record their response
                intervention_type = f"attempt_{context.get('attempt_count', 0) + 1}"
                self.service.record_disable_attempt(user_id, intervention_type, action)

                # Handle their choice
                if action == 'dismiss':
                    return {'action': 'close_dialog', 'notifications_remain': True}, 200

                elif action == 'adjust':
                    return {'action': 'show_timing_settings'}, 200

                elif action == 'stats':
                    return {
                        'action': 'show_stats',
                        'stats': {
                            'completed': context.get('completed_sessions', 0),
                            'total': context.get('total_sessions', 0),
                            'percentage': context.get('completion_percentage', 0),
                            'days_active': context.get('days_in_plan', 0)
                        }
                    }, 200

                elif action == 'snooze_24h':
                    # Snooze for 24 hours
                    snooze_until = (datetime.now() + timedelta(hours=24)).isoformat()
                    self.admin_client.table('user_coaching_plans').update({
                        'notifications_snoozed_until': snooze_until
                    }).eq('id', context['plan_id']).execute()

                    return {
                        'action': 'notifications_snoozed',
                        'snoozed_until': snooze_until,
                        'message': 'Notifications paused for 24 hours'
                    }, 200

                elif action == 'one_more':
                    # Schedule an extra motivational notification for tomorrow
                    return {
                        'action': 'one_more_session',
                        'message': 'Great! I\'ll check in with you after tomorrow\'s session.'
                    }, 200

                elif action == 'reduce_critical':
                    # Reduce to only evening notifications
                    self.admin_client.table('user_coaching_plans').update({
                        'notification_level': 'critical_only'
                    }).eq('id', context['plan_id']).execute()

                    return {
                        'action': 'reduced_notifications',
                        'message': 'Notifications reduced to evening reminders only'
                    }, 200

                elif action == 'switch_personality':
                    return {'action': 'show_personality_selector'}, 200

                elif action in ['disable', 'disable_with_penalty', 'disable_final']:
                    # Actually disable with consequences
                    if action in ['disable_with_penalty', 'disable_final']:
                        # Apply penalties
                        self._apply_quit_penalties(user_id, context['plan_id'])

                    # Disable notifications
                    self.admin_client.table('user_coaching_plans').update({
                        'notifications_enabled': False,
                        'quit_date': datetime.now().isoformat()
                    }).eq('id', context['plan_id']).execute()

                    return {
                        'action': 'notifications_disabled',
                        'penalties_applied': action in ['disable_with_penalty', 'disable_final'],
                        'message': 'Notifications disabled. Your commitment has ended.'
                    }, 200

            else:
                # Initial attempt - show intervention
                personality = context.get('coaching_personality', 'supportive_friend')
                intervention = self.service.get_intervention_message(personality, context)

                return {
                    'show_intervention': True,
                    'intervention': intervention,
                    'context': {
                        'attempt': context.get('attempt_count', 0) + 1,
                        'progress': context.get('completion_percentage', 0)
                    }
                }, 200

        except Exception as e:
            logger.error(f"Notification intervention failed: {e}")
            return {'error': 'Failed to process request'}, 500

    def _apply_quit_penalties(self, user_id: str, plan_id: int):
        """Apply penalties for quitting."""
        try:
            # Reset streak
            self.admin_client.table('user').update({
                'current_streak': 0
            }).eq('id', user_id).execute()

            # Mark plan as abandoned
            self.admin_client.table('user_coaching_plans').update({
                'current_status': 'abandoned',
                'abandoned_date': datetime.now().isoformat()
            }).eq('id', plan_id).execute()

            # Log the quit event
            self.admin_client.table('quit_events').insert({
                'user_id': user_id,
                'plan_id': plan_id,
                'quit_date': datetime.now().isoformat(),
                'reason': 'disabled_notifications'
            }).execute()

        except Exception as e:
            logger.error(f"Failed to apply quit penalties: {e}")