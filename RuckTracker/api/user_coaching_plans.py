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
            
            # Get active plan with template info (with defensive error handling)
            client = get_supabase_client()
            try:
                plan_resp = client.table('user_coaching_plans').select(
                    'id, coaching_plan_id, coaching_personality, start_date, current_week, current_status, plan_modifications, created_at, '
                    'coaching_plan_templates!coaching_plan_id(id, plan_id, name, duration_weeks, base_structure, progression_rules, non_negotiables, retests, personalization_knobs, expert_tips, is_active)'
                ).eq('user_id', user_id).eq('current_status', 'active').limit(1).execute()
            except Exception as join_error:
                # Fallback to simple query without template join if foreign key fails
                logger.warning(f"GET /user-coaching-plans join failed for user {user_id}, falling back: {join_error}")
                try:
                    plan_resp = client.table('user_coaching_plans').select(
                        'id, coaching_plan_id, coaching_personality, start_date, current_week, current_status, plan_modifications, created_at'
                    ).eq('user_id', user_id).eq('current_status', 'active').limit(1).execute()
                except Exception as fallback_error:
                    logger.error(f"GET /user-coaching-plans fallback also failed for user {user_id}: {fallback_error}")
                    return {"error": "Failed to fetch coaching plan"}, 500
            
            if not plan_resp.data:
                return {"active_plan": None}, 200
                
            plan = plan_resp.data[0]
            
            # Calculate plan progress (with fallback if template missing)
            weeks_elapsed = _calculate_weeks_elapsed(plan['start_date'])
            template_data = plan.get('coaching_plan_templates')
            if template_data:
                total_weeks = template_data['duration_weeks']
                progress_percent = min(weeks_elapsed / total_weeks * 100, 100)
            else:
                # Fallback when template data is missing
                total_weeks = 8  # Default duration
                progress_percent = min(weeks_elapsed / total_weeks * 100, 100)
                logger.warning(f"GET /user-coaching-plans using fallback duration for user {user_id}")
            
            # Get recent plan sessions
            sessions_resp = client.table('plan_sessions').select(
                'id, planned_week, planned_session_type, completion_status, plan_adherence_score, scheduled_date, completed_date'
            ).eq('user_coaching_plan_id', plan['id']).order('planned_week', desc=False).limit(20).execute()
            
            # Calculate adherence metrics
            sessions = sessions_resp.data or []
            adherence_stats = _calculate_adherence_stats(sessions)
            
            return {
                "active_plan": {
                    "id": plan['id'],
                    "template": template_data or {
                        "name": "Default Plan",
                        "duration_weeks": total_weeks,
                        "plan_id": plan.get('coaching_plan_id', 'unknown')
                    },
                    "personality": plan['coaching_personality'],
                    "start_date": plan['start_date'],
                    "current_week": plan['current_week'],
                    "weeks_elapsed": weeks_elapsed,
                    "progress_percent": progress_percent,
                    "modifications": plan['plan_modifications'],
                    "adherence_stats": adherence_stats,
                    "recent_sessions": sessions[-10:]  # Last 10 sessions
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
            
            # Generate initial plan sessions
            _generate_plan_sessions(created_plan['id'], template, start_date_parsed)
            
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
            
            # Get active plan (fixed to match actual database schema)
            client = get_supabase_client()
            query = client.table('user_coaching_plans').select(
                'id, coaching_plan_id, start_date, current_week, '
                'coaching_plan_templates!coaching_plan_id(plan_id, name, duration_weeks, base_structure, retests)'
            ).eq('user_id', user_id).eq('current_status', 'active')
            
            # If plan_id is provided, filter by it as well
            if plan_id:
                query = query.eq('id', plan_id)
            
            plan_resp = query.limit(1).execute()
            
            if not plan_resp.data:
                return {"error": "No active coaching plan found"}, 404
                
            plan = plan_resp.data[0]
            template = plan['coaching_plan_templates']
            
            # Get all plan sessions
            sessions_resp = client.table('plan_sessions').select(
                'id, planned_week, planned_session_type, completion_status, plan_adherence_score, '
                'scheduled_date, completed_date, session_id'
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


def _generate_plan_sessions(user_plan_id, plan_metadata, start_date):
    """Generate plan sessions based on personalized plan metadata."""
    try:
        client = get_supabase_admin_client()  # Use admin client to bypass RLS
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

        weekly_template = plan_structure.get('weekly_template')
        if not weekly_template:
            weekly_template = plan_metadata.get('weekly_template', [])

        training_schedule = plan_metadata.get('training_schedule', [])

        duration_weeks = plan_metadata.get('duration_weeks') or plan_structure.get('duration_weeks')
        if not duration_weeks:
            duration_weeks = plan_metadata.get('weeks')

        if not duration_weeks:
            logger.warning(f"Cannot generate sessions for plan {user_plan_id}: duration_weeks missing")
            return

        sessions_to_create = []

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
            return mapping.get(day_name.lower(), 0)

        def add_session(week_num: int, session_payload: Dict[str, Any]):
            day_name = session_payload.get('day', 'monday')
            session_type = session_payload.get('session_type', 'planned_session')
            session_offset = day_to_offset(day_name)
            week_start = start_date + timedelta(weeks=week_num - 1)
            session_date = week_start + timedelta(days=session_offset)

            sessions_to_create.append({
                'user_coaching_plan_id': user_plan_id,
                'planned_week': week_num,
                'planned_session_type': session_type,
                'scheduled_date': session_date.isoformat(),
                'completion_status': 'planned'
            })

        for week_num in range(1, duration_weeks + 1):
            if weekly_template:
                for session in weekly_template:
                    add_session(week_num, session)
            elif training_schedule:
                for session in training_schedule:
                    add_session(week_num, session)
            else:
                # Fallback: create a generic ruck session 3 times per week
                default_sessions = [
                    {'day': 'monday', 'session_type': 'planned_ruck'},
                    {'day': 'wednesday', 'session_type': 'planned_ruck'},
                    {'day': 'friday', 'session_type': 'planned_ruck'}
                ]
                for session in default_sessions:
                    add_session(week_num, session)

        if sessions_to_create:
            client.table('plan_sessions').insert(sessions_to_create).execute()
            logger.info(f"Generated {len(sessions_to_create)} plan sessions for user plan {user_plan_id}")

    except Exception as e:
        logger.error(f"Failed to generate plan sessions: {e}")


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
            'id, planned_week, planned_session_type, scheduled_date, scheduled_start_time, scheduled_timezone'
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

    # Find next planned session
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
        "personalized_message": personalized_message
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
