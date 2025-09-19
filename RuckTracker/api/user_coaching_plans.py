"""
User Coaching Plans API
Handles plan instantiation, progress tracking, and plan management
"""

import logging
from datetime import datetime, timedelta
from flask import request, g
from flask_restful import Resource
from ..supabase_client import get_supabase_client, get_supabase_admin_client
from ..utils.auth_helper import get_current_user_id
from ..utils.api_response import check_auth_and_respond

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
                
            # Get user's active plan
            client = get_supabase_client()
            plan_resp = client.table('user_coaching_plans').select('id').eq(
                'user_id', user_id
            ).eq('current_status', 'active').maybe_single().execute()
            
            if not plan_resp.data:
                return {"error": "No active coaching plan found"}, 404
                
            plan_id = plan_resp.data['id']
            
            # Find the plan session to mark as completed
            current_week = _calculate_weeks_elapsed_from_plan(plan_resp.data)
            
            # Get next uncompleted session in current or previous week
            plan_session_resp = client.table('plan_sessions').select('id, planned_week, planned_session_type').eq(
                'user_coaching_plan_id', plan_id
            ).eq('completion_status', 'planned').lte('planned_week', current_week).order('planned_week').limit(1).execute()
            
            if not plan_session_resp.data:
                # No more planned sessions, create ad-hoc tracking
                logger.info(f"No planned session found, creating ad-hoc session tracking for session {session_id}")
                return {"message": "Session completed outside of plan"}, 200
                
            plan_session = plan_session_resp.data[0]
            
            # Calculate adherence score based on session performance
            adherence_score = _calculate_session_adherence(session_id, plan_session['planned_session_type'])
            
            # Update plan session
            update_data = {
                'session_id': session_id,
                'completion_status': 'completed',
                'completed_date': datetime.now().date().isoformat(),
                'plan_adherence_score': adherence_score
            }
            
            client.table('plan_sessions').update(update_data).eq('id', plan_session['id']).execute()
            
            # Update user plan current week if necessary
            if plan_session['planned_week'] > current_week:
                client.table('user_coaching_plans').update({
                    'current_week': plan_session['planned_week']
                }).eq('id', plan_id).execute()
            
            return {"message": "Session tracked against plan", "adherence_score": adherence_score}, 200
            
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


def _generate_plan_sessions(user_plan_id, template, start_date):
    """Generate plan sessions based on template structure"""
    try:
        client = get_supabase_admin_client()  # Use admin client to bypass RLS
        plan_structure = template['base_structure']  # Fixed field name
        duration_weeks = template['duration_weeks']
        
        sessions_to_create = []
        
        for week_num in range(1, duration_weeks + 1):
            week_start = start_date + timedelta(weeks=week_num-1)
            
            # Get week structure from template (default to 3 sessions if not specified)
            week_sessions = plan_structure.get(f'week_{week_num}', {
                'sessions': ['base_aerobic', 'recovery', 'base_aerobic']
            }).get('sessions', [])
            
            # Schedule sessions across the week (Mon, Wed, Fri pattern)
            session_days = [0, 2, 4]  # Monday, Wednesday, Friday
            
            for i, session_type in enumerate(week_sessions[:3]):  # Max 3 sessions per week
                if i < len(session_days):
                    session_date = week_start + timedelta(days=session_days[i])
                    
                    sessions_to_create.append({
                        'user_coaching_plan_id': user_plan_id,
                        'planned_week': week_num,
                        'planned_session_type': session_type,
                        'scheduled_date': session_date.isoformat(),
                        'completion_status': 'planned'
                    })
        
        # Batch insert sessions
        if sessions_to_create:
            client.table('plan_sessions').insert(sessions_to_create).execute()
            logger.info(f"Generated {len(sessions_to_create)} plan sessions for user plan {user_plan_id}")
            
    except Exception as e:
        logger.error(f"Failed to generate plan sessions: {e}")


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
