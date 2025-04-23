import logging
from flask import g, jsonify
from flask_restful import Resource
from datetime import datetime, timedelta, timezone

from ..supabase_client import get_supabase_client

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

    avg_distance_km = total_distance_km / total_sessions if total_sessions > 0 else 0.0
    avg_duration_seconds = total_duration_seconds / total_sessions if total_sessions > 0 else 0
    
    total_pace_seconds_per_km = 0.0
    valid_pace_sessions = 0
    for s in sessions:
        dist = s.get('distance_km', 0) or 0
        dur = s.get('duration_seconds', 0) or 0
        if dist > 0 and dur > 0:
             pace = dur / dist 
             total_pace_seconds_per_km += pace
             valid_pace_sessions += 1
             
    avg_pace_seconds_per_km = total_pace_seconds_per_km / valid_pace_sessions if valid_pace_sessions > 0 else 0.0

    return {
        'total_sessions': total_sessions,
        'total_distance_km': float(total_distance_km),
        'total_duration_seconds': int(total_duration_seconds),
        'total_calories': int(total_calories),
        'performance': {
             'avg_pace_seconds_per_km': float(avg_pace_seconds_per_km),
             'avg_distance_km': float(avg_distance_km),
             'avg_duration_seconds': int(avg_duration_seconds),
        }
    }
    
def get_daily_breakdown(sessions, start_date, end_date):
    """Calculates daily breakdown for weekly view."""
    daily_data = {i: {'sessions_count': 0, 'distance_km': 0.0} for i in range(7)}
    day_names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
    
    for s in sessions:
        created_at_str = s.get('created_at')
        if created_at_str:
            try:
                created_at = datetime.fromisoformat(created_at_str.replace('Z', '+00:00')).astimezone(timezone.utc)
                if start_date <= created_at <= end_date:
                    day_index = created_at.weekday()
                    daily_data[day_index]['sessions_count'] += 1
                    daily_data[day_index]['distance_km'] += s.get('distance_km', 0) or 0
            except ValueError:
                logger.warning(f"Could not parse date for daily breakdown: {created_at_str}")
                
    return [
        {'day_name': day_names[i], **data} 
        for i, data in daily_data.items()
    ]

class WeeklyStatsResource(Resource):
    def get(self):
        """Get aggregated stats for the current week."""
        if not hasattr(g, 'user') or g.user is None:
            return {'message': 'User not authenticated'}, 401

        try:
            today = datetime.now(timezone.utc)
            start_dt, end_dt = get_week_range(today)
            date_range_str = f"{start_dt.strftime('%b %d')} - {end_dt.strftime('%b %d, %Y')}"
            start_iso = start_dt.isoformat()
            end_iso = end_dt.isoformat()

            supabase = get_supabase_client()
            response = supabase.table('ruck_sessions') \
                .select('distance_km, duration_seconds, calories_burned, created_at') \
                .eq('user_id', g.user.id) \
                .gte('created_at', start_iso) \
                .lte('created_at', end_iso) \
                .execute()

            if response.data is None:
                 logger.error(f"Supabase query error for weekly stats: {getattr(response, 'error', 'Unknown error')}")
                 error_detail = getattr(response, 'error', None)
                 if not error_detail and hasattr(response, 'message'):
                      error_detail = getattr(response, 'message', 'Failed to fetch data')
                 return {'message': f'Error fetching weekly sessions: {error_detail}'}, 500
            
            sessions = response.data
            stats = calculate_aggregates(sessions)
            stats['date_range'] = date_range_str
            stats['daily_breakdown'] = get_daily_breakdown(sessions, start_dt, end_dt)

            return {'data': stats}, 200

        except Exception as e:
            logger.error(f"Error calculating weekly stats: {str(e)}", exc_info=True)
            return {'message': f'Error calculating weekly stats: {str(e)}'}, 500

class MonthlyStatsResource(Resource):
     def get(self):
        """Get aggregated stats for the current month."""
        if not hasattr(g, 'user') or g.user is None:
            return {'message': 'User not authenticated'}, 401

        try:
            today = datetime.now(timezone.utc)
            start_dt, end_dt = get_month_range(today)
            date_range_str = today.strftime('%B %Y')
            start_iso = start_dt.isoformat()
            end_iso = end_dt.isoformat()

            supabase = get_supabase_client()
            response = supabase.table('ruck_sessions') \
                .select('distance_km, duration_seconds, calories_burned') \
                .eq('user_id', g.user.id) \
                .gte('created_at', start_iso) \
                .lte('created_at', end_iso) \
                .execute()

            if response.data is None:
                 logger.error(f"Supabase query error for monthly stats: {getattr(response, 'error', 'Unknown error')}")
                 error_detail = getattr(response, 'error', None)
                 if not error_detail and hasattr(response, 'message'):
                      error_detail = getattr(response, 'message', 'Failed to fetch data')
                 return {'message': f'Error fetching monthly sessions: {error_detail}'}, 500

            stats = calculate_aggregates(response.data)
            stats['date_range'] = date_range_str

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
            
            supabase = get_supabase_client()
            response = supabase.table('ruck_sessions') \
                .select('distance_km, duration_seconds, calories_burned') \
                .eq('user_id', g.user.id) \
                .gte('created_at', start_iso) \
                .lte('created_at', end_iso) \
                .execute()

            if response.data is None:
                 logger.error(f"Supabase query error for yearly stats: {getattr(response, 'error', 'Unknown error')}")
                 error_detail = getattr(response, 'error', None)
                 if not error_detail and hasattr(response, 'message'):
                      error_detail = getattr(response, 'message', 'Failed to fetch data')
                 return {'message': f'Error fetching yearly sessions: {error_detail}'}, 500

            stats = calculate_aggregates(response.data)
            stats['date_range'] = date_range_str

            return {'data': stats}, 200

        except Exception as e:
            logger.error(f"Error calculating yearly stats: {str(e)}", exc_info=True)
            return {'message': f'Error calculating yearly stats: {str(e)}'}, 500 