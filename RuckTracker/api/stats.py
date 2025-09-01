import logging
import time
from flask import g, jsonify
from flask_restful import Resource
from datetime import datetime, timedelta, timezone

from ..supabase_client import get_supabase_client
from ..services.redis_cache_service import cache_get, cache_set, cache_delete_pattern

logger = logging.getLogger(__name__)

def get_week_range(date):
    """Calculates the start (Monday) and end (Sunday) of the week for a given date."""
    start_of_week = date - timedelta(days=date.weekday())
    end_of_week = start_of_week + timedelta(days=6)
    start_dt = datetime(start_of_week.year, start_of_week.month, start_of_week.day, tzinfo=timezone.utc)
    end_dt = datetime(end_of_week.year, end_of_week.month, end_of_week.day, 23, 59, 59, 999999, tzinfo=timezone.utc)
    return start_dt, end_dt

def get_month_range(date):
    """Calculates the start and end of the month for a given date."""
    start_of_month = datetime(date.year, date.month, 1, tzinfo=timezone.utc)
    if date.month == 12:
        end_of_month = datetime(date.year + 1, 1, 1, tzinfo=timezone.utc) - timedelta(microseconds=1)
    else:
        end_of_month = datetime(date.year, date.month + 1, 1, tzinfo=timezone.utc) - timedelta(microseconds=1)
    return start_of_month, end_of_month
    
def get_year_range(date):
    """Calculates the start and end of the year for a given date."""
    start_of_year = datetime(date.year, 1, 1, tzinfo=timezone.utc)
    end_of_year = datetime(date.year + 1, 1, 1, tzinfo=timezone.utc) - timedelta(microseconds=1)
    return start_of_year, end_of_year

def calculate_aggregates(sessions):
    """Calculates aggregates from a list of session dictionaries."""
    if not sessions:
        return {
            'total_sessions': 0,
            'total_distance_km': 0.0,
            'total_duration_seconds': 0,
            'total_calories': 0,
            'total_power_points': 0,
            'performance': { # Nest performance metrics
                 'avg_pace_seconds_per_km': 0.0,
                 'avg_distance_km': 0.0,
                 'avg_duration_seconds': 0,
             }
        }

    total_sessions = len(sessions)
    total_distance_km = sum(s.get('distance_km', 0) or 0 for s in sessions)
    total_duration_seconds = sum(s.get('duration_seconds', 0) or 0 for s in sessions)
    total_calories = sum(s.get('calories_burned', 0) or 0 for s in sessions)
    total_power_points = sum(s.get('power_points', 0) or 0 for s in sessions)

    avg_distance_km = total_distance_km / total_sessions if total_sessions > 0 else 0.0
    avg_duration_seconds = total_duration_seconds / total_sessions if total_sessions > 0 else 0
    
    # Calculate overall pace as total_duration / total_distance (correct approach)
    # This gives the true average pace across all sessions, weighted by distance
    avg_pace_seconds_per_km = total_duration_seconds / total_distance_km if total_distance_km > 0 else 0.0

    return {
        'total_sessions': total_sessions,
        'total_distance_km': float(total_distance_km),
        'total_duration_seconds': int(total_duration_seconds),
        'total_calories': int(total_calories),
        'total_power_points': int(total_power_points),
        'performance': {
             'avg_pace_seconds_per_km': float(avg_pace_seconds_per_km),
             'avg_distance_km': float(avg_distance_km),
             'avg_duration_seconds': int(avg_duration_seconds),
        }
    }
    
def get_daily_breakdown(sessions, start_date, end_date, date_field='completed_at'):
    """Calculates daily breakdown for weekly view."""
    daily_data = {i: {
        'sessions_count': 0, 
        'distance_km': 0.0,
        'duration_seconds': 0,
        'calories': 0,
        'power_points': 0
    } for i in range(7)}
    day_names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
    
    for s in sessions:
        session_time_str = s.get(date_field)
        if session_time_str:
            try:
                session_time_dt = datetime.fromisoformat(session_time_str.replace('Z', '+00:00')).astimezone(timezone.utc)
                if start_date <= session_time_dt <= end_date:
                    day_index = session_time_dt.weekday()
                    daily_data[day_index]['sessions_count'] += 1
                    daily_data[day_index]['distance_km'] += float(s.get('distance_km', 0) or 0)
                    daily_data[day_index]['duration_seconds'] += int(s.get('duration_seconds', 0) or 0)
                    daily_data[day_index]['calories'] += int(s.get('calories_burned', 0) or 0)
                    daily_data[day_index]['power_points'] += int(s.get('power_points', 0) or 0)
            except (ValueError, TypeError) as e:
                logger.warning(f"Error parsing timestamp for daily breakdown: {e}")
    
    # Convert to array format for frontend
    result = []
    for i in range(7):
        # Calculate the actual date for this day of the week
        day_date = start_date + timedelta(days=i)
        result.append({
            'period': day_names[i][:3],  # Mon, Tue, Wed for chart labels
            'date': day_date.strftime('%Y-%m-%d'),
            'sessions_count': daily_data[i]['sessions_count'],
            'distance_km': daily_data[i]['distance_km'],
            'duration_seconds': daily_data[i]['duration_seconds'],
            'calories': daily_data[i]['calories'],
            'power_points': daily_data[i]['power_points']
        })
    
    return result

def get_weekly_breakdown(sessions, start_date, end_date, date_field='completed_at'):
    """Calculates weekly breakdown for monthly view."""
    # Get the first Monday of the month for week calculation
    first_day_of_month = start_date.replace(day=1)
    first_monday = first_day_of_month - timedelta(days=first_day_of_month.weekday())
    
    weekly_data = {}
    
    for s in sessions:
        session_time_str = s.get(date_field)
        if session_time_str:
            try:
                session_time_dt = datetime.fromisoformat(session_time_str.replace('Z', '+00:00')).astimezone(timezone.utc)
                if start_date <= session_time_dt <= end_date:
                    # Calculate which week this session belongs to
                    days_since_first_monday = (session_time_dt - first_monday).days
                    week_index = days_since_first_monday // 7
                    
                    if week_index not in weekly_data:
                        weekly_data[week_index] = {
                            'sessions_count': 0,
                            'distance_km': 0.0,
                            'duration_seconds': 0,
                            'calories': 0,
                            'power_points': 0
                        }
                    
                    weekly_data[week_index]['sessions_count'] += 1
                    weekly_data[week_index]['distance_km'] += float(s.get('distance_km', 0) or 0)
                    weekly_data[week_index]['duration_seconds'] += int(s.get('duration_seconds', 0) or 0)
                    weekly_data[week_index]['calories'] += int(s.get('calories_burned', 0) or 0)
                    weekly_data[week_index]['power_points'] += int(s.get('power_points', 0) or 0)
            except (ValueError, TypeError) as e:
                logger.warning(f"Error parsing timestamp for weekly breakdown: {e}")
    
    # Convert to array format for frontend
    result = []
    max_weeks = 6  # Max weeks in a month view
    for week_index in range(max_weeks):
        week_start = first_monday + timedelta(weeks=week_index)
        if week_start > end_date + timedelta(days=7):
            break
            
        data = weekly_data.get(week_index, {
            'sessions_count': 0,
            'distance_km': 0.0,
            'duration_seconds': 0,
            'calories': 0,
            'power_points': 0
        })
        
        result.append({
            'period': f'W{week_index + 1}',
            'date': week_start.strftime('%Y-%m-%d'),
            **data
        })
    
    return result

def get_monthly_breakdown(sessions, start_date, end_date, date_field='completed_at'):
    """Calculates monthly breakdown for yearly view."""
    monthly_data = {}
    month_names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                   'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
    
    for s in sessions:
        session_time_str = s.get(date_field)
        if session_time_str:
            try:
                session_time_dt = datetime.fromisoformat(session_time_str.replace('Z', '+00:00')).astimezone(timezone.utc)
                if start_date <= session_time_dt <= end_date:
                    month_key = session_time_dt.month - 1  # 0-based index
                    
                    if month_key not in monthly_data:
                        monthly_data[month_key] = {
                            'sessions_count': 0,
                            'distance_km': 0.0,
                            'duration_seconds': 0,
                            'calories': 0,
                            'power_points': 0
                        }
                    
                    monthly_data[month_key]['sessions_count'] += 1
                    monthly_data[month_key]['distance_km'] += float(s.get('distance_km', 0) or 0)
                    monthly_data[month_key]['duration_seconds'] += int(s.get('duration_seconds', 0) or 0)
                    monthly_data[month_key]['calories'] += int(s.get('calories_burned', 0) or 0)
                    monthly_data[month_key]['power_points'] += int(s.get('power_points', 0) or 0)
            except (ValueError, TypeError) as e:
                logger.warning(f"Error parsing timestamp for monthly breakdown: {e}")
    
    # Convert to array format for frontend
    result = []
    for month_index in range(12):
        month_start = datetime(start_date.year, month_index + 1, 1, tzinfo=timezone.utc)
        
        data = monthly_data.get(month_index, {
            'sessions_count': 0,
            'distance_km': 0.0,
            'duration_seconds': 0,
            'calories': 0,
            'power_points': 0
        })
        
        result.append({
            'period': month_names[month_index],
            'date': month_start.strftime('%Y-%m-%d'),
            **data
        })
    
    return result

class WeeklyStatsResource(Resource):
    def get(self):
        """Get aggregated stats for the current week."""
        logger.info(f"[STATS_PERF] WeeklyStatsResource.get called for user_id={g.user.id if hasattr(g, 'user') else 'unknown'}")
        
        if not hasattr(g, 'user') or g.user is None:
            logger.warning("[STATS_PERF] WeeklyStatsResource: User not authenticated")
            return {'message': 'User not authenticated'}, 401

        try:
            logger.info("[STATS_PERF] WeeklyStatsResource: Starting date calculations")
            today = datetime.now(timezone.utc)
            start_dt, end_dt = get_week_range(today)
            date_range_str = f"{start_dt.strftime('%b %d')} - {end_dt.strftime('%b %d, %Y')}"
            start_iso = start_dt.isoformat()
            end_iso = end_dt.isoformat()
            logger.info(f"[STATS_PERF] WeeklyStatsResource: Date range calculated: {date_range_str}")

            cache_key = f"weekly_stats:{g.user.id}:{start_iso}:{end_iso}"
            logger.info(f"[STATS_PERF] WeeklyStatsResource: Checking cache with key: {cache_key}")
            cached_response = cache_get(cache_key)
            if cached_response:
                logger.info("[STATS_PERF] WeeklyStatsResource: Returning cached response")
                return {'data': cached_response}, 200

            # Use the authenticated user's JWT for RLS
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            logger.info(f"[STATS_PERF] WeeklyStatsResource: Executing query for user {g.user.id} from {start_iso} to {end_iso}")
            response = supabase.table('ruck_session') \
                .select('distance_km, duration_seconds, calories_burned, power_points, completed_at') \
                .eq('user_id', g.user.id) \
                .gte('completed_at', start_iso) \
                .lte('completed_at', end_iso) \
                .eq('status', 'completed') \
                .execute()
            logger.info(f"[STATS_PERF] WeeklyStatsResource: Query completed, got {len(response.data) if response.data else 0} sessions")

            if response.data is None:
                 logger.error(f"Supabase query error for weekly stats: {getattr(response, 'error', 'Unknown error')}")
                 error_detail = getattr(response, 'error', None)
                 if not error_detail and hasattr(response, 'message'):
                      error_detail = getattr(response, 'message', 'Failed to fetch data')
                 return {'message': f'Error fetching weekly sessions: {error_detail}'}, 500
            
            sessions = response.data
            stats = calculate_aggregates(sessions)
            stats['date_range'] = date_range_str
            stats['time_series'] = get_daily_breakdown(sessions, start_dt, end_dt, date_field='completed_at')

            cache_set(cache_key, stats)
            return {'data': stats}, 200

        except Exception as e:
            logger.error(f"Error calculating weekly stats: {str(e)}", exc_info=True)
            return {'message': f'Error calculating weekly stats: {str(e)}'}, 500

class MonthlyStatsResource(Resource):
    def get(self):
        """Get aggregated stats for the current month."""
        start_time = time.time()
        logger.info(f"[STATS_PERF] MonthlyStatsResource.get called for user_id={getattr(g.user, 'id', 'unknown') if hasattr(g, 'user') else 'unknown'}")
        
        if not hasattr(g, 'user') or g.user is None:
            logger.warning("[STATS_PERF] MonthlyStatsResource: User not authenticated")
            return {'message': 'User not authenticated'}, 401

        try:
            logger.info("[STATS_PERF] MonthlyStatsResource: Starting date calculations")
            today = datetime.now(timezone.utc)
            start_dt, end_dt = get_month_range(today)
            date_range_str = today.strftime('%B %Y')
            start_iso = start_dt.isoformat()
            end_iso = end_dt.isoformat()
            logger.info(f"[STATS_PERF] MonthlyStatsResource: Date range calculated: {date_range_str}")

            cache_key = f"monthly_stats:{g.user.id}:{start_iso}:{end_iso}"
            logger.info(f"[STATS_PERF] MonthlyStatsResource: Checking cache with key: {cache_key}")
            cached_response = cache_get(cache_key)
            if cached_response:
                logger.info("[STATS_PERF] MonthlyStatsResource: Returning cached response")
                return {'data': cached_response}, 200

            # Use the authenticated user's JWT for RLS
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            logger.info(f"[STATS_PERF] MonthlyStatsResource: Executing query for user {g.user.id} from {start_iso} to {end_iso}")
            response = supabase.table('ruck_session') \
                .select('distance_km, duration_seconds, calories_burned, power_points, completed_at') \
                .eq('user_id', g.user.id) \
                .gte('completed_at', start_iso) \
                .lte('completed_at', end_iso) \
                .eq('status', 'completed') \
                .execute()
            logger.info(f"[STATS_PERF] MonthlyStatsResource: Query completed, got {len(response.data) if response.data else 0} sessions")

            if response.data is None:
                 logger.error(f"Supabase query error for monthly stats: {getattr(response, 'error', 'Unknown error')}")
                 error_detail = getattr(response, 'error', None)
                 if not error_detail and hasattr(response, 'message'):
                      error_detail = getattr(response, 'message', 'Failed to fetch data')
                 return {'message': f'Error fetching monthly sessions: {error_detail}'}, 500

            sessions = response.data
            stats = calculate_aggregates(sessions)
            stats['date_range'] = date_range_str
            stats['time_series'] = get_weekly_breakdown(sessions, start_dt, end_dt, date_field='completed_at')

            cache_set(cache_key, stats)
            return {'data': stats}, 200

        except Exception as e:
            logger.error(f"Error calculating monthly stats: {str(e)}", exc_info=True)
            return {'message': f'Error calculating monthly stats: {str(e)}'}, 500

class YearlyStatsResource(Resource):
    def get(self):
        """Get aggregated stats for the current year."""
        if not hasattr(g, 'user') or g.user is None:
            return {'message': 'User not authenticated'}, 401

        try:
            today = datetime.now(timezone.utc)
            start_dt, end_dt = get_year_range(today)
            date_range_str = str(today.year)
            start_iso = start_dt.isoformat()
            end_iso = end_dt.isoformat()
            
            cache_key = f"yearly_stats:{g.user.id}:{start_iso}:{end_iso}"
            cached_response = cache_get(cache_key)
            if cached_response:
                return {'data': cached_response}, 200

            # Use the authenticated user's JWT for RLS
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            response = supabase.table('ruck_session') \
                .select('distance_km, duration_seconds, calories_burned, power_points, completed_at') \
                .eq('user_id', g.user.id) \
                .gte('completed_at', start_iso) \
                .lte('completed_at', end_iso) \
                .eq('status', 'completed') \
                .execute()

            if response.data is None:
                 logger.error(f"Supabase query error for yearly stats: {getattr(response, 'error', 'Unknown error')}")
                 error_detail = getattr(response, 'error', None)
                 if not error_detail and hasattr(response, 'message'):
                      error_detail = getattr(response, 'message', 'Failed to fetch data')
                 return {'message': f'Error fetching yearly sessions: {error_detail}'}, 500

            sessions = response.data
            stats = calculate_aggregates(sessions)
            stats['date_range'] = date_range_str
            stats['time_series'] = get_monthly_breakdown(sessions, start_dt, end_dt, date_field='completed_at')

            cache_set(cache_key, stats)
            return {'data': stats}, 200

        except Exception as e:
            logger.error(f"Error calculating yearly stats: {str(e)}", exc_info=True)
            return {'message': f'Error calculating yearly stats: {str(e)}'}, 500 
