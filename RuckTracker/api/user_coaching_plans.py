"""
User Coaching Plans API
Handles plan instantiation, progress tracking, and plan management
"""

import logging
import json
from datetime import datetime, timedelta
from typing import Any, Dict, Optional
from flask import request, g
from flask_restful import Resource
from ..supabase_client import get_supabase_client, get_supabase_admin_client
from ..utils.auth_helper import get_current_user_id
from ..utils.api_response import check_auth_and_respond
from RuckTracker.services.plan_notification_service import plan_notification_service

logger = logging.getLogger(__name__)

def _add_seconds_to_pace(pace_str, seconds):
    """Add seconds to a pace string (e.g., '7:30' + 30 = '8:00')"""
    try:
        parts = pace_str.split(':')
        minutes = int(parts[0])
        secs = int(parts[1]) if len(parts) > 1 else 0

        total_seconds = minutes * 60 + secs + seconds
        new_minutes = total_seconds // 60
        new_seconds = total_seconds % 60

        return f"{new_minutes}:{new_seconds:02d}"
    except:
        return pace_str

class UserCoachingPlansResource(Resource):
    """Manage user's active coaching plans"""
    
    def get(self):
        """Get user's active coaching plan with progress"""
        try:
            user_id = get_current_user_id()
            auth_response = check_auth_and_respond(user_id)
            if auth_response:
                return auth_response
            
            # Get active plan using admin client for reliable access
            client = get_supabase_admin_client()
            logger.info(f"Querying for active plan for user_id: {user_id}")
            try:
                plan_resp = client.table('user_coaching_plans').select(
                    '*'
                ).eq('user_id', user_id).eq('current_status', 'active').limit(1).execute()
                logger.info(f"Query successful, plans found: {len(plan_resp.data or [])}")
                active_plans = plan_resp.data or []
            except Exception as e:
                logger.error(f"Supabase admin query failed: {e}")
                return {"active_plan": None}, 200
            
            if not active_plans:
                logger.info(f"No active coaching plan found for user {user_id}")
                return {"active_plan": None}, 200

            plan = active_plans[0]
            logger.info(f"Found active plan for user {user_id}: plan_id={plan['id']}, coaching_plan_id={plan['coaching_plan_id']}, status={plan['current_status']}")
            
            # Get template data separately
            template_data = None
            try:
                template_resp = client.table('coaching_plan_templates').select(
                    'id, plan_id, name, duration_weeks'
                ).eq('id', plan['coaching_plan_id']).limit(1).execute()
                if template_resp.data:
                    template_data = template_resp.data[0]
            except Exception as e:
                logger.warning(f"Failed to fetch template for plan {plan['id']}: {e}")
            
            # Get ALL plan sessions with coaching points for complete plan view first
            sessions_resp = client.table('plan_sessions').select(
                'id, user_coaching_plan_id, session_id, planned_week, planned_session_type, completion_status, plan_adherence_score, notes, scheduled_date, completed_date, scheduled_start_time, scheduled_timezone, coaching_points'
            ).eq('user_coaching_plan_id', plan['id']).order('planned_week', desc=False).order('id', desc=False).execute()

            sessions = sessions_resp.data or []

            # Calculate real plan duration from sessions data
            if template_data and template_data.get('duration_weeks'):
                total_weeks = template_data['duration_weeks']
            elif sessions:
                # Calculate from actual sessions
                total_weeks = max(session['planned_week'] for session in sessions) if sessions else 1
            else:
                total_weeks = 1

            # Calculate plan progress
            weeks_elapsed = _calculate_weeks_elapsed(plan['start_date'])
            progress_percent = min(weeks_elapsed / total_weeks * 100, 100) if total_weeks > 0 else 0

            # Calculate adherence metrics
            adherence_stats = _calculate_adherence_stats(sessions)

            # Build weekly structure from plan sessions
            weekly_template = _build_weekly_template_from_sessions(sessions)

            # Get next session recommendation
            next_session = _get_next_session_recommendation_simple(plan, sessions)

            # Build complete template data with weekly structure
            complete_template = template_data or {
                "name": "Custom Plan",
                "duration_weeks": total_weeks,
                "plan_id": plan.get('coaching_plan_id', 'unknown')
            }

            # Add weekly structure to template
            if weekly_template:
                complete_template["base_structure"] = {
                    "weekly_template": weekly_template
                }

            return {
                "active_plan": {
                    "id": plan['id'],
                    "template": complete_template,
                    "plan_name": complete_template.get("name", "Custom Plan"),
                    "name": complete_template.get("name", "Custom Plan"),
                    "duration_weeks": total_weeks,
                    "personality": plan['coaching_personality'],
                    "coaching_personality": plan['coaching_personality'],
                    "start_date": plan['start_date'],
                    "current_week": plan['current_week'],
                    "weeks_elapsed": weeks_elapsed,
                    "progress_percent": progress_percent,
                    "adherence_percentage": adherence_stats['overall_adherence'],
                    "modifications": plan['plan_modifications'],
                    "adherence_stats": adherence_stats,
                    "plan_sessions": sessions,  # Complete sessions list
                    "recent_sessions": sessions[-10:],  # Last 10 sessions
                    "next_session": next_session
                }
            }, 200
            
        except Exception as e:
            logger.error(f"GET /user-coaching-plans failed: {e}")
            return {"error": "Failed to get coaching plan"}, 500
    
    def post(self):
        """DEPRECATED - Use /api/coaching-plans POST instead for personalized plan creation"""
        return {"error": "This endpoint is deprecated. Use POST /api/coaching-plans for creating personalized coaching plans"}, 410

    def delete(self):
        """Delete/cancel user's active coaching plan"""
        try:
            user_id = get_current_user_id()
            auth_response = check_auth_and_respond(user_id)
            if auth_response:
                return auth_response

            # Find active plan
            client = get_supabase_client()
            plan_resp = client.table('user_coaching_plans').select('id').eq(
                'user_id', user_id
            ).eq('current_status', 'active').limit(1).execute()

            if not plan_resp.data:
                return {"error": "No active coaching plan found"}, 404

            plan_id = plan_resp.data[0]['id']

            # Use admin client for both operations
            admin_client = get_supabase_admin_client()

            # Delete or update associated plan sessions
            # Option 1: Delete only future/planned sessions, keep completed ones for history
            try:
                # Delete only planned sessions (not completed ones)
                sessions_resp = admin_client.table('plan_sessions').delete().eq(
                    'user_coaching_plan_id', plan_id
                ).eq('completion_status', 'planned').execute()

                logger.info(f"Deleted {len(sessions_resp.data)} planned sessions for plan {plan_id}")

                # Update completed sessions to mark them as from a cancelled plan (optional)
                # This preserves history while indicating the plan was cancelled
                admin_client.table('plan_sessions').update({
                    'plan_cancelled': True
                }).eq('user_coaching_plan_id', plan_id).neq('completion_status', 'planned').execute()

            except Exception as session_error:
                logger.warning(f"Error handling plan sessions during deletion: {session_error}")
                # Continue with plan deletion even if session cleanup fails

            # Update plan status to cancelled
            update_resp = admin_client.table('user_coaching_plans').update({
                'current_status': 'cancelled',
                'cancelled_date': datetime.now().isoformat()
            }).eq('id', plan_id).execute()

            if update_resp.data:
                logger.info(f"Cancelled coaching plan {plan_id} for user {user_id}")
                return {"message": "Coaching plan cancelled successfully"}, 200
            else:
                return {"error": "Failed to cancel coaching plan"}, 500

        except Exception as e:
            logger.error(f"DELETE /user-coaching-plans failed: {e}")
            return {"error": "Failed to cancel coaching plan"}, 500

    def post_deprecated(self):
        """[DEPRECATED] Create new coaching plan from template - kept for reference only"""
        try:
            user_id = get_current_user_id()
            auth_response = check_auth_and_respond(user_id)
            if auth_response:
                return auth_response
            body = request.get_json() or {}
            
            template_id = body.get('template_id')
            personality = body.get('personality', 'supportive_friend')
            start_date = body.get('start_date')  # Optional, defaults to today
            
            logger.info(f"Creating coaching plan with template_id={template_id}, personality={personality}")
            
            if not template_id:
                return {"error": "template_id required"}, 400
                
            # Validate template exists (query by template_id which could be the primary key)
            client = get_supabase_client()
            template_resp = client.table('coaching_plan_templates').select(
                'id, plan_id, name, duration_weeks, base_structure'
            ).eq('id', template_id).limit(1).execute()
            
            if not template_resp.data:
                return {"error": "Template not found"}, 404
                
            template = template_resp.data[0]
            
            # Check if user already has active plan
            existing_resp = client.table('user_coaching_plans').select('id').eq(
                'user_id', user_id
            ).eq('current_status', 'active').limit(1).execute()
            
            if existing_resp.data:
                return {"error": "User already has an active coaching plan"}, 409
                
            # Parse start date or use today
            if start_date:
                try:
                    start_date_parsed = datetime.fromisoformat(start_date.replace('Z', '+00:00')).date()
                except:
                    return {"error": "Invalid start_date format"}, 400
            else:
                # Use user's timezone for "today"
                import pytz
                try:
                    user_tz = pytz.timezone(user_timezone)
                    start_date_parsed = datetime.now(user_tz).date()
                except:
                    # Fallback to UTC if timezone fails
                    start_date_parsed = datetime.now().date()
                
            # Create user coaching plan using admin client to bypass RLS
            admin_client = get_supabase_admin_client()
            plan_data = {
                'user_id': user_id,
                'coaching_plan_id': template_id,
                'coaching_personality': personality,
                'start_date': start_date_parsed.isoformat(),
                'current_week': 1,
                'current_status': 'active',
                'plan_modifications': {}
            }
            
            plan_resp = admin_client.table('user_coaching_plans').insert(plan_data).execute()
            created_plan = plan_resp.data[0]

            # Generate initial plan sessions with personalization data
            plan_metadata = {
                **template,  # Include all template fields
                'user_timezone': user_timezone,
                'preferred_notification_time': personalization_data.get('preferred_notification_time') if personalization_data else None,
                'enable_notifications': personalization_data.get('enable_notifications', True) if personalization_data else True,
            }
            _generate_plan_sessions(created_plan['id'], plan_metadata, start_date_parsed, user_id)
            
            logger.info(f"Created coaching plan {created_plan['id']} for user {user_id}")
            
            return {
                "plan_id": created_plan['id'],
                "message": f"Started {template['name']} coaching plan!",
                "start_date": start_date_parsed.isoformat(),
                "duration_weeks": template['duration_weeks']
            }, 201
            
        except Exception as e:
            logger.error(f"POST /user-coaching-plans failed: {e}")
            # Return more detailed error for debugging
            return {"error": f"Failed to create coaching plan: {str(e)}"}, 500


class UserCoachingPlanProgressResource(Resource):
    """Get detailed progress for user's active coaching plan"""
    
    def get(self, plan_id=None):
        """Get detailed progress and next recommendations"""
        try:
            user_id = get_current_user_id()
            auth_response = check_auth_and_respond(user_id)
            if auth_response:
                return auth_response
            
            # Get active plan without relying on joined template (avoid missing-row issues)
            client = get_supabase_client()
            plan_query = client.table('user_coaching_plans').select(
                'id, coaching_plan_id, start_date, current_week, plan_modifications'
            ).eq('user_id', user_id).eq('current_status', 'active')

            # Only filter by plan_id if it's provided and not 'null' string
            if plan_id and plan_id != 'null':
                plan_query = plan_query.eq('id', plan_id)

            plan_resp = plan_query.limit(1).execute()

            if not plan_resp.data:
                return {"error": "No active coaching plan found"}, 404

            plan = plan_resp.data[0]
            template = None

            # Try to load template metadata (non-fatal if missing)
            base_plan_id = plan.get('coaching_plan_id')
            if base_plan_id:
                try:
                    template_resp = client.table('coaching_plan_templates').select(
                        'plan_id, name, duration_weeks, base_structure, retests'
                    ).eq('id', base_plan_id).maybe_single().execute()
                    template = template_resp.data
                except Exception as template_err:
                    logger.warning(f"Unable to load template metadata for plan {plan['id']}: {template_err}")

            if not template:
                try:
                    modifications = plan.get('plan_modifications')
                    if isinstance(modifications, str):
                        import json
                        modifications = json.loads(modifications)
                    if isinstance(modifications, dict):
                        structure = modifications.get('plan_structure') or {}
                        template = {
                            'plan_id': modifications.get('plan_type'),
                            'name': modifications.get('plan_name') or 'Coaching Plan',
                            'duration_weeks': structure.get('duration_weeks') or 12,
                            'base_structure': structure,
                            'retests': structure.get('retests') if isinstance(structure, dict) else {}
                        }
                except Exception as fallback_err:
                    logger.warning(f"Failed to parse plan_modifications for plan {plan['id']}: {fallback_err}")

            if not template:
                template = {
                    'plan_id': None,
                    'name': 'Coaching Plan',
                    'duration_weeks': 12,
                    'base_structure': {},
                    'retests': {}
                }

            # Get all plan sessions with coaching points
            sessions_resp = client.table('plan_sessions').select(
                'id, planned_week, planned_session_type, completion_status, plan_adherence_score, '
                'scheduled_date, completed_date, session_id, coaching_points'
            ).eq('user_coaching_plan_id', plan['id']).order('planned_week').execute()
            
            sessions = sessions_resp.data or []
            
            # Calculate comprehensive progress
            progress_data = _calculate_comprehensive_progress(plan, template, sessions)
            
            # Get next session recommendation
            next_session = _get_next_session_recommendation(plan, sessions)
            
            return {
                "plan_info": {
                    "id": plan['id'],
                    "name": template['name'],
                    "current_week": plan['current_week'],
                    "total_weeks": template['duration_weeks'],
                    "start_date": plan['start_date']
                },
                "progress": progress_data,
                "next_session": next_session,
                "weekly_schedule": _get_current_week_schedule(plan, sessions)
            }, 200
            
        except Exception as e:
            logger.error(f"GET /user-coaching-plan-progress failed: {e}")
            return {"error": "Failed to get plan progress"}, 500


class PlanSessionTrackingResource(Resource):
    """Track session completion against plan"""
    
    def post(self):
        """Mark session as completed against plan"""
        try:
            user_id = get_current_user_id()
            auth_response = check_auth_and_respond(user_id)
            if auth_response:
                return auth_response
            body = request.get_json() or {}
            
            session_id = body.get('session_id')
            if not session_id:
                return {"error": "session_id required"}, 400

            try:
                session_id = int(session_id)
            except (TypeError, ValueError):
                return {"error": "session_id must be an integer"}, 400
                
            tracking_result = _record_session_against_plan(
                user_id=user_id,
                session_id=session_id,
                user_jwt=getattr(g, 'access_token', None)
            )

            status = tracking_result.get('status')

            if status == 'tracked':
                return {
                    "message": "Session tracked against plan",
                    "adherence_score": tracking_result.get('adherence_score'),
                    "plan_session": tracking_result.get('plan_session')
                }, 200

            if status == 'no_active_plan':
                return {"error": "No active coaching plan found"}, 404

            if status == 'no_matching_session':
                return {"message": "Session completed outside of plan"}, 200

            if status == 'error':
                return {"error": "Failed to track session against plan"}, 500

            return {"message": "No plan update required", "status": status}, 200
            
        except Exception as e:
            logger.error(f"POST /plan-session-tracking failed: {e}")
            return {"error": "Failed to track session against plan"}, 500


def _calculate_weeks_elapsed(start_date_str):
    """Calculate how many weeks have elapsed since plan start"""
    start_date = datetime.fromisoformat(start_date_str).date()
    today = datetime.now().date()
    days_elapsed = (today - start_date).days
    return max(1, (days_elapsed // 7) + 1)  # Week 1, 2, 3, etc.


def _calculate_weeks_elapsed_from_plan(plan):
    """Calculate weeks elapsed from plan data"""
    return _calculate_weeks_elapsed(plan['start_date'])


def _calculate_adherence_stats(sessions):
    """Calculate adherence statistics from plan sessions"""
    if not sessions:
        return {"overall_adherence": 0, "weekly_consistency": 0, "completed_sessions": 0}
        
    total_sessions = len(sessions)
    completed_sessions = len([s for s in sessions if s['completion_status'] == 'completed'])
    modified_sessions = len([s for s in sessions if s['completion_status'] == 'modified'])
    
    # Count modified sessions as partial adherence
    adherence_score = (completed_sessions + (modified_sessions * 0.5)) / total_sessions if total_sessions > 0 else 0
    
    # Calculate weekly consistency (sessions per week)
    weeks_with_sessions = len(set(s['planned_week'] for s in sessions if s['completion_status'] in ['completed', 'modified']))
    total_weeks = max(s['planned_week'] for s in sessions) if sessions else 1
    weekly_consistency = weeks_with_sessions / total_weeks if total_weeks > 0 else 0
    
    return {
        "overall_adherence": round(adherence_score * 100, 1),
        "weekly_consistency": round(weekly_consistency * 100, 1),
        "completed_sessions": completed_sessions,
        "total_sessions": total_sessions
    }


def _generate_plan_sessions(user_plan_id, plan_metadata, start_date, user_id=None):
    """Generate plan sessions based on personalized plan metadata."""
    try:
        logger.info(f"Starting session generation for plan {user_plan_id}")
        logger.info(f"Plan metadata keys: {list(plan_metadata.keys())}")
        client = get_supabase_admin_client()  # Use admin client to bypass RLS

        # Extract timezone and notification preferences from metadata
        user_timezone = plan_metadata.get('user_timezone', 'UTC')
        preferred_notification_time = plan_metadata.get('preferred_notification_time')
        enable_notifications = plan_metadata.get('enable_notifications', True)

        # If user_id not provided, try to get it from the plan
        if not user_id:
            try:
                plan_resp = client.table('user_coaching_plans').select('user_id').eq('id', user_plan_id).single().execute()
                if plan_resp.data:
                    user_id = plan_resp.data['user_id']
            except Exception:
                pass

        # Try multiple sources for plan structure
        plan_structure = plan_metadata.get('plan_structure')
        if isinstance(plan_structure, str):
            try:
                plan_structure = json.loads(plan_structure)
            except json.JSONDecodeError:
                plan_structure = None

        if not plan_structure and 'base_structure' in plan_metadata:
            plan_structure = plan_metadata['base_structure']
            if isinstance(plan_structure, str):
                try:
                    plan_structure = json.loads(plan_structure)
                except json.JSONDecodeError:
                    plan_structure = None

        if not isinstance(plan_structure, dict):
            plan_structure = {}

        # Look for weekly template in multiple places
        weekly_template = None

        # First check plan_structure
        if plan_structure.get('weekly_template'):
            weekly_template = plan_structure['weekly_template']
        # Then check base_structure directly
        elif plan_metadata.get('base_structure', {}).get('weekly_template'):
            weekly_template = plan_metadata['base_structure']['weekly_template']
        # Then check root of metadata
        elif plan_metadata.get('weekly_template'):
            weekly_template = plan_metadata['weekly_template']

        # Also check for training_schedule as fallback
        training_schedule = plan_metadata.get('training_schedule', [])

        # If still no weekly_template but we have training_schedule, use that
        if not weekly_template and training_schedule:
            weekly_template = training_schedule

        logger.info(f"Weekly template found: {weekly_template is not None}, length: {len(weekly_template) if weekly_template else 0}")
        logger.info(f"Training schedule found: {len(training_schedule) if training_schedule else 0}")

        duration_weeks = plan_metadata.get('duration_weeks') or plan_structure.get('duration_weeks')
        if not duration_weeks:
            duration_weeks = plan_metadata.get('weeks')

        logger.info(f"Duration weeks: {duration_weeks}")

        if not duration_weeks:
            logger.error(f"Cannot generate sessions for plan {user_plan_id}: duration_weeks missing from metadata keys: {plan_metadata.keys()}")
            return

        if not weekly_template:
            logger.error(f"No weekly template found for plan {user_plan_id}, cannot generate sessions")
            return

        logger.info(f"Generating sessions for {duration_weeks} weeks with {len(weekly_template)} sessions per week")
        sessions_to_create = []

        base_weekday = start_date.weekday()

        def day_to_offset(day_name: str) -> int:
            mapping = {
                'monday': 0,
                'tuesday': 1,
                'wednesday': 2,
                'thursday': 3,
                'friday': 4,
                'saturday': 5,
                'sunday': 6
            }
            desired = mapping.get(day_name.lower())
            if desired is None:
                return 0
            return (desired - base_weekday) % 7

        def generate_coaching_points(session_type: str, week_num: int) -> Dict[str, Any]:
            """Generate coaching points based on session type and week number."""
            # Try to get user-specific metrics for personalized coaching
            user_metrics = {}
            try:
                # Get user_id from the plan
                plan_resp = client.table('user_coaching_plans').select('user_id').eq('id', user_plan_id).single().execute()
                if plan_resp.data:
                    user_id = plan_resp.data['user_id']
                    # Get user baseline metrics
                    baseline = _get_user_performance_baseline(user_id)
                    if baseline['has_data']:
                        user_metrics = {
                            'avg_pace_s_per_km': baseline['avg_pace_s_per_km'],
                            'avg_distance_km': baseline['avg_distance_km'],
                            'last_weight_kg': baseline['last_weight_kg']
                        }
            except Exception as e:
                logger.warning(f"Could not fetch user metrics for coaching points: {e}")

            # Calculate personalized targets based on user data
            if user_metrics:
                pace_min = int(user_metrics['avg_pace_s_per_km'] // 60)
                pace_sec = int(user_metrics['avg_pace_s_per_km'] % 60)
                tempo_pace = f"{pace_min - 1}:{pace_sec:02d}"  # 1 min faster for tempo
                easy_pace = f"{pace_min + 1}:{pace_sec:02d}"  # 1 min slower for recovery

                # Personalized heart rate zones (could be enhanced with age/max HR data)
                target_hr_zone2_min = 120
                target_hr_zone2_max = 140
                target_hr_zone3_min = 141
                target_hr_zone3_max = 160
            else:
                # No user data available - return minimal structure
                # The personalized plan should provide all specifics
                return {
                    'session_goals': {
                        'primary': 'Complete as planned',
                        'focus_points': []
                    }
                }

            base_coaching_points = {
                'intervals': {
                    'intervals': [
                        {'type': 'warmup', 'duration_minutes': 5, 'instruction': 'Easy pace to warm up'},
                        {'type': 'work', 'duration_minutes': 2, 'instruction': 'Push hard! Increase your pace'},
                        {'type': 'recovery', 'duration_minutes': 2, 'instruction': 'Slow down and recover'},
                        {'type': 'work', 'duration_minutes': 2, 'instruction': 'Back to fast pace!'},
                        {'type': 'recovery', 'duration_minutes': 2, 'instruction': 'Easy recovery pace'},
                        {'type': 'work', 'duration_minutes': 2, 'instruction': 'Final push! Give it your all'},
                        {'type': 'recovery', 'duration_minutes': 2, 'instruction': 'Recover well'},
                        {'type': 'cooldown', 'duration_minutes': 5, 'instruction': 'Cool down with easy walking'}
                    ],
                    'session_goals': {
                        'primary': 'Complete high-intensity intervals with good form',
                        'secondary': 'Maintain consistent recovery pace',
                        'focus_points': ['breathing control', 'maintain posture during intervals', 'quick transitions']
                    }
                },
                'tempo': {
                    'intervals': [
                        {'type': 'warmup', 'duration_minutes': 10, 'instruction': f'Gradual warm up to {tempo_pace}/km pace'},
                        {'type': 'work', 'duration_minutes': 20 + week_num, 'instruction': f'Hold {tempo_pace}/km pace - comfortably hard'},
                        {'type': 'cooldown', 'duration_minutes': 10, 'instruction': f'Easy cool down at {easy_pace}/km'}
                    ],
                    'milestones': [
                        {'distance_km': 2, 'message': 'Settling into tempo pace nicely!'},
                        {'distance_km': 4, 'message': 'Halfway through tempo - stay strong!'},
                        {'distance_km': 6, 'message': 'Final push - maintain that pace!'}
                    ],
                    'heart_rate_zones': [
                        {'zone': 3, 'min_bpm': target_hr_zone3_min, 'max_bpm': target_hr_zone3_max, 'instruction': f'Target heart rate: {target_hr_zone3_min}-{target_hr_zone3_max} bpm'}
                    ],
                    'session_goals': {
                        'primary': f'Maintain {tempo_pace}/km pace throughout',
                        'secondary': 'Focus on consistent breathing',
                        'focus_points': ['steady rhythm', 'relaxed shoulders', 'consistent pace']
                    }
                },
                'base_aerobic': {
                    'time_triggers': [
                        {'elapsed_minutes': 15, 'message': f'Perfect {easy_pace}/km pace - stay conversational'},
                        {'elapsed_minutes': 30, 'message': 'Halfway point - perfect Zone 2 effort'},
                        {'elapsed_minutes': 45, 'message': 'Building that aerobic base beautifully'},
                        {'elapsed_minutes': 60, 'message': 'One hour strong! Excellent endurance work'}
                    ],
                    'heart_rate_zones': [
                        {'zone': 2, 'min_bpm': target_hr_zone2_min, 'max_bpm': target_hr_zone2_max, 'instruction': f'Stay in Zone 2 ({target_hr_zone2_min}-{target_hr_zone2_max} bpm)'}
                    ],
                    'milestones': [
                        {'distance_km': 3, 'message': '3K down - great consistent pacing!'},
                        {'distance_km': 5, 'message': '5K milestone - aerobic engine building nicely!'}
                    ],
                    'session_goals': {
                        'primary': f'Maintain easy {easy_pace}/km conversational pace',
                        'secondary': 'Build aerobic endurance in Zone 2',
                        'focus_points': ['relaxed breathing', 'efficient form', 'enjoy the movement']
                    }
                },
                'hill_work': {
                    'intervals': [
                        {'type': 'warmup', 'duration_minutes': 10, 'instruction': 'Easy pace to warm up'},
                        {'type': 'work', 'duration_minutes': 3, 'instruction': 'Power up the hill!'},
                        {'type': 'recovery', 'duration_minutes': 3, 'instruction': 'Easy recovery down'},
                        {'type': 'work', 'duration_minutes': 3, 'instruction': 'Attack the hill again!'},
                        {'type': 'recovery', 'duration_minutes': 3, 'instruction': 'Recover on the descent'},
                        {'type': 'work', 'duration_minutes': 3, 'instruction': 'One more strong effort!'},
                        {'type': 'cooldown', 'duration_minutes': 10, 'instruction': 'Easy cool down on flat'}
                    ],
                    'session_goals': {
                        'primary': 'Build power and strength on hills',
                        'secondary': 'Maintain form on inclines',
                        'focus_points': ['forward lean on hills', 'short powerful steps', 'use arms for momentum']
                    }
                },
                'long_slow': {
                    'milestones': [
                        {'distance_km': 5, 'message': 'First 5K done - great pacing!'},
                        {'distance_km': 10, 'message': '10K milestone - you\'re crushing it!'},
                        {'distance_km': 15, 'message': '15K! Outstanding endurance!'}
                    ],
                    'time_triggers': [
                        {'elapsed_minutes': 30, 'message': '30 minutes - settle into your rhythm'},
                        {'elapsed_minutes': 60, 'message': '1 hour strong! Stay hydrated'},
                        {'elapsed_minutes': 90, 'message': '90 minutes - incredible endurance!'}
                    ],
                    'session_goals': {
                        'primary': 'Build endurance with sustained effort',
                        'secondary': 'Practice fueling and hydration',
                        'focus_points': ['consistent pace', 'mental toughness', 'proper nutrition']
                    }
                },
                'recovery': {
                    'time_triggers': [
                        {'elapsed_minutes': 10, 'message': 'Perfect recovery pace - keep it easy'},
                        {'elapsed_minutes': 20, 'message': 'Great active recovery session'}
                    ],
                    'session_goals': {
                        'primary': 'Active recovery to promote healing',
                        'secondary': 'Maintain movement without stress',
                        'focus_points': ['very easy effort', 'focus on form', 'relaxation']
                    }
                }
            }

            # Return coaching points for the session type
            return base_coaching_points.get(session_type, {})

        def add_session(week_num: int, session_payload: Dict[str, Any]):
            day_name = session_payload.get('day', 'monday')
            session_type_raw = session_payload.get('session_type', 'planned_session')

            # Normalize session type for coaching points generation
            # Handle variations like "Base Ruck", "Interval Ruck", "Long Posture Ruck", etc.
            session_type = session_type_raw.lower().replace(' ', '_').replace('/', '_')

            # Map common plan session types to our coaching point types
            mapped_type = None
            if 'interval' in session_type:
                mapped_type = 'intervals'
            elif 'tempo' in session_type or 'speed' in session_type:
                mapped_type = 'tempo'
            elif 'recovery' in session_type or 'easy' in session_type:
                mapped_type = 'recovery'
            elif 'hill' in session_type:
                mapped_type = 'hill_work'
            elif 'long' in session_type:
                mapped_type = 'long_slow'
            elif 'base' in session_type or 'aerobic' in session_type:
                mapped_type = 'base_aerobic'
            elif 'balance' in session_type or 'mobility' in session_type:
                mapped_type = 'recovery'  # Use recovery for lighter sessions
            elif 'posture' in session_type:
                mapped_type = 'base_aerobic'  # Focus on form

            session_offset = day_to_offset(day_name)
            week_start = start_date + timedelta(weeks=week_num - 1)
            session_date = week_start + timedelta(days=session_offset)

            # Session date is already calculated correctly from timezone-aware start_date
            session_date_str = session_date.isoformat()

            # Get coaching points only if we could map the session type
            if mapped_type:
                coaching_points = generate_coaching_points(mapped_type, week_num)
            else:
                # For unmapped types, use minimal coaching points
                coaching_points = {}

            # Add any specific notes from the session payload to coaching points
            if 'notes' in session_payload:
                if 'session_goals' not in coaching_points:
                    coaching_points['session_goals'] = {}
                coaching_points['session_goals']['session_notes'] = session_payload['notes']

            # Add weight/duration specifics if provided
            if 'weight_kg' in session_payload:
                coaching_points['target_weight_kg'] = session_payload['weight_kg']
            if 'duration_minutes' in session_payload:
                coaching_points['target_duration_minutes'] = session_payload['duration_minutes']
            if 'target_distance_km' in session_payload:
                coaching_points['target_distance_km'] = session_payload['target_distance_km']
            if 'distance_km' in session_payload and 'target_distance_km' not in coaching_points:
                coaching_points['target_distance_km'] = session_payload['distance_km']

            # Create session with timezone information
            session_data = {
                'user_coaching_plan_id': user_plan_id,
                'planned_week': week_num,
                'planned_session_type': session_type_raw,  # Keep original name for display
                'scheduled_date': session_date_str,
                'scheduled_timezone': user_timezone,  # Store user's timezone
                'completion_status': 'planned',
                'coaching_points': coaching_points
            }

            # If user has preferred notification time and notifications enabled, set it
            if enable_notifications and preferred_notification_time:
                # Parse the preferred time (expected format: "HH:MM")
                try:
                    hour, minute = map(int, preferred_notification_time.split(':'))
                    # Combine date with preferred time
                    notification_time = session_date.replace(hour=hour, minute=minute)
                    session_data['scheduled_start_time'] = notification_time.time().isoformat()
                    # Calculate when to send notification (e.g., 1 hour before)
                    notification_datetime = notification_time.replace(hour=max(0, hour - 1))
                    session_data['next_notification_at'] = notification_datetime.isoformat()
                    session_data['notification_metadata'] = {
                        'enabled': True,
                        'type': 'reminder',
                        'time_before_minutes': 60
                    }
                except (ValueError, AttributeError) as e:
                    logger.warning(f"Could not parse preferred notification time '{preferred_notification_time}': {e}")

            sessions_to_create.append(session_data)

        for week_num in range(1, duration_weeks + 1):
            if weekly_template:
                logger.info(f"Adding sessions for week {week_num} from weekly_template")
                for session in weekly_template:
                    add_session(week_num, session)
            elif training_schedule:
                logger.info(f"Adding sessions for week {week_num} from training_schedule")
                for session in training_schedule:
                    add_session(week_num, session)
            # No fallback - all plans should have a template from personalization

        logger.info(f"Total sessions to create: {len(sessions_to_create)}")

        if sessions_to_create:
            logger.info(f"Inserting {len(sessions_to_create)} sessions into plan_sessions table")
            result = client.table('plan_sessions').insert(sessions_to_create).execute()
            logger.info(f"Insert result: {result.data[0] if result.data else 'no data returned'}")
            logger.info(f"Generated {len(sessions_to_create)} plan sessions with coaching points for user plan {user_plan_id}")
        else:
            logger.warning(f"No sessions to create for plan {user_plan_id}")

    except Exception as e:
        logger.error(f"Failed to generate plan sessions: {e}")
        logger.exception("Full traceback:")


def _record_session_against_plan(user_id: str, session_id: int, user_jwt: Optional[str] = None) -> Dict[str, Any]:
    """Attach a completed ruck session to the user's active coaching plan if applicable."""
    try:
        client = get_supabase_client(user_jwt=user_jwt)

        plan_resp = client.table('user_coaching_plans').select(
            'id, start_date, current_week'
        ).eq('user_id', user_id).eq('current_status', 'active').maybe_single().execute()

        # Handle case where plan_resp is None or has no data
        if not plan_resp or not plan_resp.data:
            return {'status': 'no_active_plan'}

        plan_data = plan_resp.data
        plan_id = plan_data['id']

        # Determine which plan week we should be checking against
        current_week = _calculate_weeks_elapsed_from_plan(plan_data)

        plan_session_resp = client.table('plan_sessions').select(
            'id, planned_week, planned_session_type, scheduled_date, scheduled_start_time, scheduled_timezone, coaching_points'
        ).eq('user_coaching_plan_id', plan_id).eq('completion_status', 'planned') \
         .lte('planned_week', current_week).order('planned_week').order('id').limit(1).execute()

        # Handle case where plan_session_resp is None or has no data
        if not plan_session_resp or not plan_session_resp.data:
            return {'status': 'no_matching_session', 'plan_id': plan_id}

        plan_session = plan_session_resp.data[0]

        adherence_score = _calculate_session_adherence(session_id, plan_session['planned_session_type'])

        update_payload = {
            'session_id': session_id,
            'completion_status': 'completed',
            'completed_date': datetime.utcnow().date().isoformat(),
            'plan_adherence_score': adherence_score
        }

        client.table('plan_sessions').update(update_payload).eq('id', plan_session['id']).execute()

        # Update the plan's current week if we've advanced beyond it
        plan_current_week = plan_data.get('current_week') or 1
        if plan_session['planned_week'] > plan_current_week:
            client.table('user_coaching_plans').update({
                'current_week': plan_session['planned_week']
            }).eq('id', plan_id).execute()

        tracked_session = {
            **plan_session,
            'session_id': session_id,
            'completion_status': 'completed',
            'completed_date': update_payload['completed_date'],
            'plan_adherence_score': adherence_score
        }

        session_payload = {
            'session_focus': plan_session.get('planned_session_type'),
            'scheduled_date': plan_session.get('scheduled_date'),
            'scheduled_start_time': plan_session.get('scheduled_start_time'),
            'scheduled_timezone': plan_session.get('scheduled_timezone'),
            'adherence_score': adherence_score
        }

        try:
            session_details_resp = client.table('ruck_session').select(
                'distance_km, duration_seconds, ruck_weight_kg, completed_at, avg_heart_rate'
            ).eq('id', session_id).maybe_single().execute()

            if session_details_resp.data:
                details = session_details_resp.data
                if details.get('distance_km') is not None:
                    session_payload['distance_km'] = float(details['distance_km'])
                if details.get('duration_seconds') is not None:
                    session_payload['duration_minutes'] = int(details['duration_seconds'] // 60)
                if details.get('ruck_weight_kg') is not None:
                    session_payload['ruck_weight_kg'] = float(details['ruck_weight_kg'])
                if details.get('completed_at'):
                    session_payload['completed_at'] = details['completed_at']
                if details.get('avg_heart_rate') is not None:
                    session_payload['avg_heart_rate'] = details['avg_heart_rate']
        except Exception as details_exc:
            logger.warning(f"Unable to fetch session metrics for {session_id}: {details_exc}")

        try:
            plan_notification_service.handle_session_completed(
                user_id=user_id,
                plan_id=plan_id,
                plan_session_id=plan_session['id'],
                session_payload=session_payload
            )
        except Exception as notify_exc:
            logger.error(f"Plan notification scheduling failed for session {session_id}: {notify_exc}")

        return {
            'status': 'tracked',
            'plan_id': plan_id,
            'plan_session_id': plan_session['id'],
            'adherence_score': adherence_score,
            'plan_session': tracked_session
        }

    except Exception as e:
        logger.error(f"Failed to record session {session_id} for user {user_id} against plan: {e}")
        return {'status': 'error', 'error': str(e)}


def _calculate_comprehensive_progress(plan, template, sessions):
    """Calculate comprehensive progress metrics"""
    weeks_elapsed = _calculate_weeks_elapsed(plan['start_date'])
    total_weeks = template['duration_weeks']
    
    # Time-based progress
    time_progress = min(weeks_elapsed / total_weeks * 100, 100)
    
    # Session-based progress
    adherence_stats = _calculate_adherence_stats(sessions)
    
    # Weekly breakdown
    weekly_breakdown = {}
    for week in range(1, weeks_elapsed + 1):
        week_sessions = [s for s in sessions if s['planned_week'] == week]
        completed = len([s for s in week_sessions if s['completion_status'] == 'completed'])
        total = len(week_sessions)
        weekly_breakdown[f'week_{week}'] = {
            'completed': completed,
            'total': total,
            'adherence': round(completed / total * 100, 1) if total > 0 else 0
        }
    
    return {
        "time_progress_percent": round(time_progress, 1),
        "overall_adherence": adherence_stats['overall_adherence'],
        "weekly_consistency": adherence_stats['weekly_consistency'],
        "total_sessions_completed": adherence_stats['completed_sessions'],
        "weekly_breakdown": weekly_breakdown,
        "current_streak": _calculate_current_streak(sessions),
        "next_milestone": _get_next_milestone(weeks_elapsed, total_weeks)
    }


def _get_user_performance_baseline(user_id):
    """Get user's recent performance metrics from user_insights"""
    try:
        client = get_supabase_admin_client()

        # Get user insights
        result = client.table('user_insights').select('facts').eq('user_id', user_id).single().execute()

        if result.data and 'facts' in result.data:
            facts = result.data['facts']

            # Calculate averages from 30-day data
            sessions_30d = facts.get('totals_30d', {}).get('sessions', 0)
            distance_30d = facts.get('totals_30d', {}).get('distance_km', 0)
            duration_30d = facts.get('totals_30d', {}).get('duration_s', 0)

            # Get last session data
            last_weight = facts.get('recency', {}).get('last_ruck_weight_kg', 0)
            last_distance = facts.get('recency', {}).get('last_ruck_distance_km', 0)

            # Get pace data from splits
            splits_data = facts.get('splits', {})
            pace_by_idx = splits_data.get('avg_pace_s_per_km_by_idx_1_10', [])

            # Calculate average pace from first few splits
            avg_pace_s_per_km = 510  # Default 8:30 per km
            if pace_by_idx and len(pace_by_idx) > 0:
                # Average the pace of first 3 splits for a good baseline
                first_splits = pace_by_idx[:3]
                if first_splits:
                    total_pace = sum(s.get('avg', 510) for s in first_splits)
                    avg_pace_s_per_km = total_pace / len(first_splits)
            elif duration_30d > 0 and distance_30d > 0:
                # Fallback: calculate from totals
                avg_pace_s_per_km = duration_30d / distance_30d

            # Calculate averages
            avg_distance_km = distance_30d / sessions_30d if sessions_30d > 0 else 0

            # Check if they're getting faster (negative splits)
            is_improving = splits_data.get('negative_split_frequency', 0) > 0.5

            return {
                'has_data': sessions_30d > 0,
                'avg_distance_km': avg_distance_km if avg_distance_km > 0 else 5.0,
                'avg_pace_s_per_km': avg_pace_s_per_km,
                'last_weight_kg': last_weight if last_weight > 0 else 9.0,
                'last_distance_km': last_distance,
                'sessions_30d': sessions_30d,
                'is_improving': is_improving
            }
    except Exception as e:
        logger.error(f"Failed to get user performance baseline: {e}")

    # Return defaults if no data
    return {
        'has_data': False,
        'avg_distance_km': 5.0,
        'avg_pace_s_per_km': 510,  # 8:30 per km
        'last_weight_kg': 9.0,
        'last_distance_km': 0,
        'sessions_30d': 0,
        'is_improving': False
    }


def _get_next_session_recommendation(plan, sessions):
    """Get recommendation for next session with specific targets based on user's actual performance"""
    current_week = _calculate_weeks_elapsed(plan['start_date'])

    # Find next planned session with coaching points
    next_planned = None
    for session in sessions:
        if session['completion_status'] == 'planned' and session['planned_week'] <= current_week:
            next_planned = session
            break

    if not next_planned:
        return {"message": "No upcoming sessions in current week"}

    week_number = next_planned['planned_week']

    # Get user's actual baseline from user_insights
    user_id = plan.get('user_id')
    user_baseline = _get_user_performance_baseline(user_id)

    # Use actual data or smart defaults
    if user_baseline['has_data']:
        # Use their actual recent performance with progressive overload
        avg_distance_km = user_baseline['avg_distance_km']
        avg_pace_s_per_km = user_baseline['avg_pace_s_per_km']
        last_weight_kg = user_baseline['last_weight_kg']

        # Progressive overload based on their actual baseline
        # Week 1: Match their average
        # Each week: Add 5-10% distance, 2-3% weight
        progress_factor = 1.0 + (week_number * 0.05)  # 5% per week
        weight_factor = 1.0 + (week_number * 0.02)   # 2% per week

        base_distance_km = avg_distance_km * progress_factor
        base_weight_kg = last_weight_kg * weight_factor if last_weight_kg > 0 else 9.0

        # Calculate duration from distance and pace
        base_duration_min = (base_distance_km * avg_pace_s_per_km) / 60

        # Format pace for display (e.g., "7:30")
        base_pace_min = int(avg_pace_s_per_km // 60)
        base_pace_sec = int(avg_pace_s_per_km % 60)
        user_pace_str = f"{base_pace_min}:{base_pace_sec:02d}"

    else:
        # No history - use conservative defaults
        base_distance_km = 3.0 + (week_number * 0.3)  # More conservative progression
        base_duration_min = 30 + (week_number * 5)
        base_weight_kg = 9 + (week_number * 0.5)
        user_pace_str = "8:30"  # Conservative default pace

    # Generate recommendation based on session type with SPECIFIC personalized targets
    recommendations = {
        'base_aerobic': {
            'description': 'Easy aerobic base building',
            'duration': f'{int(base_duration_min)}-{int(base_duration_min + 15)} minutes',
            'duration_minutes': int(base_duration_min),
            'distance_km': round(base_distance_km * 1.2, 1),  # Longer distance for base
            'intensity': 'Conversational pace (Zone 2)',
            'pace_per_km': f'{user_pace_str}-{_add_seconds_to_pace(user_pace_str, 60)} min/km' if user_baseline['has_data'] else '8:00-9:00 min/km',
            'load': f'{round(base_weight_kg, 1)} kg',
            'weight_kg': base_weight_kg,
            'notes': 'Focus on maintaining steady breathing and good posture throughout',
            'personalized': user_baseline['has_data']
        },
        'recovery': {
            'description': 'Active recovery session',
            'duration': '20-30 minutes',
            'duration_minutes': 25,
            'distance_km': round(base_distance_km * 0.6, 1),  # Shorter for recovery
            'intensity': 'Very easy pace',
            'pace_per_km': '9:00-10:00 min/km',
            'load': f'{round(base_weight_kg * 0.5, 1)} kg or bodyweight',
            'weight_kg': base_weight_kg * 0.5,
            'notes': 'This should feel easy - prioritize movement quality over speed'
        },
        'tempo': {
            'description': 'Controlled tempo effort',
            'duration': f'{int(base_duration_min)}-{int(base_duration_min + 10)} minutes',
            'duration_minutes': int(base_duration_min),
            'distance_km': round(base_distance_km, 1),
            'intensity': 'Comfortably hard pace',
            'pace_per_km': f'{_add_seconds_to_pace(user_pace_str, -30)}-{user_pace_str} min/km' if user_baseline['has_data'] else '7:00-7:30 min/km',
            'load': f'{round(base_weight_kg * 1.2, 1)} kg',
            'weight_kg': base_weight_kg * 1.2,
            'notes': 'Push yourself but maintain consistent pace - no heroics',
            'personalized': user_baseline['has_data']
        },
        'hill_work': {
            'description': 'Hill power development',
            'duration': f'{base_duration_min - 5}-{base_duration_min + 5} minutes',
            'duration_minutes': base_duration_min,
            'distance_km': round(base_distance_km * 0.8, 1),  # Less distance due to hills
            'intensity': 'Varied based on terrain',
            'pace_per_km': 'N/A - focus on effort',
            'load': f'{round(base_weight_kg * 0.8, 1)} kg',
            'weight_kg': base_weight_kg * 0.8,
            'notes': 'Find hills with 4-6% grade, power walk up, recover on the way down'
        },
        'long_slow': {
            'description': 'Long slow distance ruck',
            'duration': f'{base_duration_min * 2}-{base_duration_min * 2 + 30} minutes',
            'duration_minutes': base_duration_min * 2,
            'distance_km': round(base_distance_km * 2.5, 1),
            'intensity': 'Easy sustainable pace',
            'pace_per_km': '9:00-10:00 min/km',
            'load': f'{round(base_weight_kg * 0.8, 1)} kg',
            'weight_kg': base_weight_kg * 0.8,
            'notes': 'Build endurance - take breaks if needed, focus on completing the distance'
        },
        'intervals': {
            'description': 'Speed interval training',
            'duration': f'{base_duration_min} minutes total',
            'duration_minutes': base_duration_min,
            'distance_km': round(base_distance_km * 0.9, 1),
            'intensity': 'Alternating hard/easy',
            'pace_per_km': '6:30 hard / 8:30 easy',
            'load': f'{round(base_weight_kg * 0.7, 1)} kg',
            'weight_kg': base_weight_kg * 0.7,
            'notes': '5min warmup, then 8x (2min hard/2min easy), 5min cooldown'
        }
    }

    session_type = next_planned['planned_session_type']
    recommendation = recommendations.get(session_type, recommendations['base_aerobic'])

    # Add personalized message if using their data
    personalized_message = None
    if user_baseline['has_data']:
        if user_baseline['is_improving']:
            personalized_message = f"Based on your recent {user_baseline['sessions_30d']} sessions averaging {user_baseline['avg_distance_km']:.1f}km at {user_pace_str}/km pace. You're getting faster - keep it up!"
        else:
            personalized_message = f"Based on your recent {user_baseline['sessions_30d']} sessions averaging {user_baseline['avg_distance_km']:.1f}km. Today's targets will push you just beyond your comfort zone."

    # Include coaching points in the recommendation
    coaching_points = next_planned.get('coaching_points', {})

    return {
        "session_type": session_type,
        "type": session_type.replace('_', ' ').title(),
        "scheduled_date": next_planned['scheduled_date'],
        "week": next_planned['planned_week'],
        "recommendation": recommendation,
        # Include top-level for easier access
        "distance_km": recommendation['distance_km'],
        "duration_minutes": recommendation['duration_minutes'],
        "weight_kg": recommendation['weight_kg'],
        "notes": recommendation['notes'],
        "personalized": user_baseline['has_data'],
        "personalized_message": personalized_message,
        "coaching_points": coaching_points  # This is critical for AI cheerleader
    }


def _get_current_week_schedule(plan, sessions):
    """Get current week's session schedule"""
    current_week = _calculate_weeks_elapsed(plan['start_date'])
    
    week_sessions = [s for s in sessions if s['planned_week'] == current_week]
    
    return {
        "week_number": current_week,
        "sessions": [
            {
                "type": s['planned_session_type'],
                "scheduled_date": s['scheduled_date'],
                "status": s['completion_status'],
                "completed_date": s.get('completed_date'),
                "adherence_score": s.get('plan_adherence_score')
            }
            for s in week_sessions
        ]
    }


def _calculate_session_adherence(session_id, planned_session_type):
    """Calculate how well a session matched the plan"""
    try:
        # Get session data
        client = get_supabase_client()
        session_resp = client.table('ruck_session').select(
            'duration_s, distance_km, ruck_weight_kg, heart_rate_avg'
        ).eq('id', session_id).single().execute()
        
        if not session_resp.data:
            return 0.5  # Default partial adherence
            
        session = session_resp.data
        
        # Simple adherence scoring based on session type
        # This can be enhanced with more sophisticated logic
        duration_minutes = (session.get('duration_s') or 0) / 60
        distance_km = session.get('distance_km') or 0
        
        if planned_session_type == 'recovery':
            # Recovery sessions should be shorter and easier
            if duration_minutes >= 20 and duration_minutes <= 40:
                return 1.0
            elif duration_minutes >= 15:
                return 0.7
            else:
                return 0.3
                
        elif planned_session_type == 'base_aerobic':
            # Base sessions should be moderate duration
            if duration_minutes >= 40 and duration_minutes <= 70:
                return 1.0
            elif duration_minutes >= 30:
                return 0.8
            else:
                return 0.5
                
        elif planned_session_type == 'tempo':
            # Tempo sessions should be focused and moderately long
            if duration_minutes >= 35 and duration_minutes <= 60:
                return 1.0
            else:
                return 0.7
                
        else:
            # Default adherence for unknown session types
            return 0.8
            
    except Exception as e:
        logger.error(f"Failed to calculate session adherence: {e}")
        return 0.5


def _calculate_current_streak(sessions):
    """Calculate current consecutive session completion streak"""
    if not sessions:
        return 0
        
    # Sort by planned week and check for consecutive completions
    completed_sessions = [s for s in sessions if s['completion_status'] == 'completed']
    if not completed_sessions:
        return 0
        
    # Simple streak calculation - consecutive completed sessions
    streak = 0
    for session in reversed(completed_sessions):
        if session['completion_status'] == 'completed':
            streak += 1
        else:
            break
            
    return streak


def _get_next_milestone(weeks_elapsed, total_weeks):
    """Get next milestone in the plan"""
    milestones = [
        (2, "2 weeks - Habit formation"),
        (4, "1 month - Consistency building"),
        (8, "2 months - Routine established"),
        (12, "3 months - Lifestyle integration")
    ]

    for week, description in milestones:
        if weeks_elapsed < week:
            return {"week": week, "description": description}

    if weeks_elapsed < total_weeks:
        return {"week": total_weeks, "description": "Plan completion"}

    return {"message": "All milestones achieved!"}


def _build_weekly_template_from_sessions(sessions):
    """Build weekly template structure from plan sessions"""
    if not sessions:
        return []

    # Group sessions by week to find the weekly pattern
    weekly_sessions = {}
    for session in sessions:
        week = session['planned_week']
        if week not in weekly_sessions:
            weekly_sessions[week] = []
        weekly_sessions[week].append(session)

    # Use the first week as the template pattern
    first_week = min(weekly_sessions.keys()) if weekly_sessions else 1
    first_week_sessions = weekly_sessions.get(first_week, [])

    # Convert to day-based template format
    day_mapping = {
        'monday': 'mon',
        'tuesday': 'tue',
        'wednesday': 'wed',
        'thursday': 'thu',
        'friday': 'fri',
        'saturday': 'sat',
        'sunday': 'sun'
    }

    # Build weekly template from scheduled dates and session types
    weekly_template = []
    for session in first_week_sessions:
        try:
            # Parse the scheduled date to determine day of week
            scheduled_date = session.get('scheduled_date')
            if scheduled_date:
                from datetime import datetime
                date_obj = datetime.fromisoformat(scheduled_date.replace('Z', '+00:00'))
                day_name = date_obj.strftime('%A').lower()
                day_key = day_mapping.get(day_name, 'monday')

                # Extract coaching points for session details (handle JSON string)
                coaching_points = {}
                coaching_points_raw = session.get('coaching_points')
                if coaching_points_raw:
                    try:
                        import json
                        coaching_points = json.loads(coaching_points_raw) if isinstance(coaching_points_raw, str) else coaching_points_raw
                    except (json.JSONDecodeError, TypeError):
                        coaching_points = {}

                session_data = {
                    'day': day_key,
                    'session_type': session['planned_session_type'],
                    'type': session['planned_session_type']
                }

                # Add duration and distance if available in coaching points
                if 'target_duration_minutes' in coaching_points:
                    session_data['duration'] = coaching_points['target_duration_minutes']
                if 'target_weight_kg' in coaching_points:
                    session_data['weight_kg'] = coaching_points['target_weight_kg']

                weekly_template.append(session_data)
        except Exception as e:
            logger.warning(f"Failed to parse session date {session.get('scheduled_date')}: {e}")
            continue

    return weekly_template


def _get_next_session_recommendation_simple(plan, sessions):
    """Simple next session recommendation"""
    current_week = plan.get('current_week', 1)

    # Find next planned session
    next_planned = None
    for session in sessions:
        if session['completion_status'] == 'planned' and session['planned_week'] >= current_week:
            next_planned = session
            break

    if not next_planned:
        return None

    # Extract coaching points data if available (handle JSON string)
    coaching_points = {}
    coaching_points_raw = next_planned.get('coaching_points')
    if coaching_points_raw:
        try:
            import json
            coaching_points = json.loads(coaching_points_raw) if isinstance(coaching_points_raw, str) else coaching_points_raw
        except (json.JSONDecodeError, TypeError):
            coaching_points = {}

    return {
        "session_type": next_planned['planned_session_type'],
        "type": next_planned['planned_session_type'].replace('_', ' ').title(),
        "scheduled_date": next_planned['scheduled_date'],
        "week": next_planned['planned_week'],
        "duration_minutes": coaching_points.get('target_duration_minutes'),
        "weight_kg": coaching_points.get('target_weight_kg'),
        "distance_km": coaching_points.get('distance_km'),
        "notes": coaching_points.get('session_goals', {}).get('session_notes', ''),
        "description": next_planned['planned_session_type'].replace('_', ' ').title()
    }
