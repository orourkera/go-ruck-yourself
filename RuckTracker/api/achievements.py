"""
Achievements API endpoints for RuckingApp
Handles achievement management, progress tracking, and award calculations
"""
import logging
from flask import Blueprint, request, jsonify, g
from flask_restful import Resource, Api
from RuckTracker.supabase_client import get_supabase_client, get_supabase_admin_client
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
from ..services.push_notification_service import PushNotificationService, get_user_device_tokens

logger = logging.getLogger(__name__)

class AchievementsResource(Resource):
    """Get all available achievements"""
    
    def get(self):
        try:
            # Use admin client since achievements are public data
            supabase = get_supabase_admin_client()
            
            # Get unit preference from query parameters
            unit_preference = request.args.get('unit_preference', 'metric')  # default to metric
            
            # Base query for active achievements
            query = supabase.table('achievements').select('*').eq('is_active', True)
            
            # Filter by unit preference: include universal (null) achievements and user's preferred unit
            if unit_preference in ['metric', 'standard']:
                # Get achievements that are either universal (unit_preference is null) 
                # or match the user's preference
                response = query.or_(f'unit_preference.is.null,unit_preference.eq.{unit_preference}').execute()
            else:
                # If no valid preference provided, get all achievements
                response = query.execute()
            
            if response.data:
                return {
                    'status': 'success',
                    'achievements': response.data
                }, 200
            else:
                return {
                    'status': 'success',
                    'achievements': []
                }, 200
                
        except Exception as e:
            logger.error(f"Error fetching achievements: {str(e)}")
            return {'error': 'Failed to fetch achievements'}, 500


class AchievementCategoriesResource(Resource):
    """Get achievement categories"""
    
    def get(self):
        try:
            # Get the user's JWT token from the request context
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Get distinct categories
            response = supabase.table('achievements').select('category').eq('is_active', True).execute()
            
            if response.data:
                categories = list(set([item['category'] for item in response.data]))
                return {
                    'status': 'success',
                    'categories': categories
                }, 200
            else:
                return {
                    'status': 'success',
                    'categories': []
                }, 200
                
        except Exception as e:
            logger.error(f"Error fetching achievement categories: {str(e)}")
            return {'error': 'Failed to fetch achievement categories'}, 500


class UserAchievementsResource(Resource):
    """Get user's earned achievements"""
    
    def get(self, user_id):
        try:
            logger.info(f"Fetching achievements for user_id: {user_id}")
            # Get the user's JWT token from the request context
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            response = supabase.table('user_achievements').select(
                '*, achievements(*)'
            ).eq('user_id', user_id).order('earned_at', desc=True).execute()
            
            logger.info(f"Supabase response for user {user_id}: {response.data}")
            logger.info(f"Number of achievements found: {len(response.data) if response.data else 0}")
            
            if response.data:
                return {
                    'status': 'success',
                    'user_achievements': response.data
                }, 200
            else:
                return {
                    'status': 'success',
                    'user_achievements': []
                }, 200
        
        except Exception as e:
            logger.error(f"Error fetching user achievements: {str(e)}")
            return {'error': 'Failed to fetch user achievements'}, 500


class UserAchievementsProgressResource(Resource):
    """Get user's progress toward unearned achievements"""
    
    def get(self, user_id):
        try:
            # Get the user's JWT token from the request context
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Get user's progress with achievement details
            response = supabase.table('achievement_progress').select(
                '*, achievements(*)'
            ).eq('user_id', user_id).execute()
            
            if response.data:
                return {
                    'status': 'success',
                    'achievement_progress': response.data
                }, 200
            else:
                return {
                    'status': 'success',
                    'achievement_progress': []
                }, 200
                
        except Exception as e:
            logger.error(f"Error fetching achievement progress: {str(e)}")
            return {'error': 'Failed to fetch achievement progress'}, 500


class CheckSessionAchievementsResource(Resource):
    """Check and award achievements for a completed session"""
    
    def post(self, session_id):
        try:
            # Get the user's JWT token from the request context
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Get session details
            session_response = supabase.table('ruck_session').select('*').eq('id', session_id).single().execute()
            
            if not session_response.data:
                logger.error(f"Session {session_id} not found")
                return {'error': 'Session not found'}, 404
                
            session = session_response.data
            user_id = session['user_id']
            
            logger.info(f"Checking achievements for session {session_id}, user {user_id}")
            logger.info(f"Session data: {session}")
            
            # Validate session data - skip achievement checking for sessions with invalid/extreme values
            distance_km = session.get('distance_km', 0)
            duration_seconds = session.get('duration_seconds', 0)
            
            # Skip if distance is extremely small (likely invalid data) or duration is 0
            if distance_km < 0.001 or duration_seconds <= 0:  # Less than 1 meter or no duration
                logger.warning(f"Skipping achievement check for session {session_id} - invalid data: distance={distance_km}km, duration={duration_seconds}s")
                return {
                    'status': 'success', 
                    'new_achievements': [],
                    'session_id': session_id,
                    'message': 'Session has invalid data - skipped achievement check'
                }, 200
            
            # Get all achievements
            achievements_response = supabase.table('achievements').select('*').eq('is_active', True).execute()
            achievements = achievements_response.data or []
            
            logger.info(f"Found {len(achievements)} active achievements to check")
            
            # Check for new achievements
            new_achievements = []
            
            for achievement in achievements:
                logger.debug(f"Checking achievement: {achievement['name']} (ID: {achievement['id']})")
                
                # Check if user already has this achievement
                existing = supabase.table('user_achievements').select('id').eq(
                    'user_id', user_id
                ).eq('achievement_id', achievement['id']).execute()
                
                if existing.data:
                    logger.debug(f"User already has achievement: {achievement['name']}")
                    continue  # User already has this achievement
                
                # Check if user meets criteria for this achievement
                criteria_met = self._check_achievement_criteria(supabase, user_id, session, achievement)
                logger.debug(f"Achievement {achievement['name']} criteria met: {criteria_met}")
                
                if criteria_met:
                    # Award the achievement
                    award_data = {
                        'user_id': user_id,
                        'achievement_id': achievement['id'],
                        'session_id': session_id,
                        'earned_at': datetime.utcnow().isoformat(),
                        'metadata': {'triggered_by_session': session_id}
                    }
                    
                    try:
                        insert_result = supabase.table('user_achievements').insert(award_data).execute()
                        logger.info(f"Successfully awarded achievement {achievement['name']} to user {user_id}")
                        logger.debug(f"Insert result: {insert_result.data}")
                        new_achievements.append(achievement)
                    except Exception as insert_error:
                        logger.error(f"Failed to insert achievement {achievement['name']}: {str(insert_error)}")
            
            # Send push notification
            if new_achievements:
                device_tokens = get_user_device_tokens([user_id])
                if device_tokens:
                    push_service = PushNotificationService()
                    achievement_names = [achievement['name'] for achievement in new_achievements]
                    push_service.send_achievement_notification(
                        device_tokens=device_tokens,
                        achievement_names=achievement_names,
                        session_id=session_id
                    )
            
            logger.info(f"Achievement check complete. New achievements: {len(new_achievements)}")
            if new_achievements:
                logger.info(f"New achievements awarded: {[a['name'] for a in new_achievements]}")
        
            return {
                'status': 'success',
                'new_achievements': new_achievements,
                'session_id': session_id
            }, 200
            
        except Exception as e:
            logger.error(f"Error checking session achievements: {str(e)}")
            return {'error': 'Failed to check session achievements'}, 500
    
    def _check_achievement_criteria(self, supabase, user_id: str, session: Dict, achievement: Dict) -> bool:
        """Check if user meets criteria for a specific achievement"""
        try:
            criteria = achievement['criteria']
            criteria_type = criteria.get('type')
            
            if criteria_type == 'first_ruck':
                return True  # If we're checking, this must be their first completed ruck
            
            elif criteria_type == 'single_session_distance':
                target = criteria.get('target', 0)
                return session.get('distance_km', 0) >= target
            
            elif criteria_type == 'session_weight':
                target = criteria.get('target', 0)
                return session.get('ruck_weight_kg', 0) >= target
            
            elif criteria_type == 'power_points':
                # Power points are always cumulative across all sessions
                try:
                    response = supabase.rpc('calculate_user_power_points', {
                        'user_id_param': user_id
                    }).execute()
                    total_power_points = response.data or 0
                except Exception as rpc_error:
                    # Fallback to manual calculation if RPC doesn't exist
                    logger.warning(f"RPC calculate_user_power_points not available, using fallback: {str(rpc_error)}")
                    power_response = supabase.table('ruck_session').select(
                        'power_points'
                    ).eq('user_id', user_id).eq('status', 'completed').execute()
                    
                    total_power_points = 0
                    if power_response.data:
                        for sess in power_response.data:
                            power_points = sess.get('power_points')
                            if power_points is not None:
                                try:
                                    total_power_points += float(power_points)
                                except (ValueError, TypeError):
                                    continue
                
                target = criteria.get('target', 0)
                return total_power_points >= target
            
            elif criteria_type == 'elevation_gain':
                target = criteria.get('target', 0)
                return session.get('elevation_gain_m', 0) >= target
            
            elif criteria_type == 'session_duration':
                target = criteria.get('target', 0)
                return session.get('duration_seconds', 0) >= target
            
            elif criteria_type == 'pace_faster_than':
                target = criteria.get('target', 999999)
                pace = session.get('average_pace', 999999)
                logger.debug(f"Pace faster than check: {pace} <= {target} = {pace <= target}")
                return pace <= target
            
            elif criteria_type == 'pace_slower_than':
                target = criteria.get('target', 0)
                pace = session.get('average_pace', 0)
                logger.debug(f"Pace slower than check: {pace} >= {target} = {pace >= target}")
                return pace >= target
            
            elif criteria_type == 'cumulative_distance':
                # Get user's total distance with error handling
                try:
                    response = supabase.rpc('get_user_total_distance', {'p_user_id': user_id}).execute()
                    total_distance = response.data or 0
                    target = criteria.get('target', 0)
                    return total_distance >= target
                except Exception as e:
                    logger.error(f"Error getting user total distance: {str(e)}")
                    return False
            
            elif criteria_type == 'time_of_day':
                # Check early bird / night owl achievements
                start_time = session.get('start_time')
                if start_time:
                    dt = datetime.fromisoformat(start_time.replace('Z', '+00:00'))
                    hour = dt.hour
                    
                    if 'before_hour' in criteria:
                        target_count = criteria.get('target', 1)
                        before_hour = criteria.get('before_hour')
                        
                        # Count sessions starting before this hour
                        try:
                            count_response = supabase.rpc('count_sessions_before_hour', {
                                'p_user_id': user_id,
                                'p_hour': before_hour
                            }).execute()
                            count = count_response.data or 0
                            return count >= target_count
                        except Exception as e:
                            logger.error(f"Error counting sessions before hour: {str(e)}")
                            return False
                    
                    elif 'after_hour' in criteria:
                        target_count = criteria.get('target', 1)
                        after_hour = criteria.get('after_hour')
                        
                        # Count sessions starting after this hour
                        try:
                            count_response = supabase.rpc('count_sessions_after_hour', {
                                'p_user_id': user_id,
                                'p_hour': after_hour
                            }).execute()
                            count = count_response.data or 0
                            return count >= target_count
                        except Exception as e:
                            logger.error(f"Error counting sessions after hour: {str(e)}")
                            return False
            
            elif criteria_type == 'daily_streak':
                # Check for consecutive daily rucks
                target = criteria.get('target', 7)
                current_streak = self._calculate_daily_streak(supabase, user_id)
                return current_streak >= target
        
            elif criteria_type == 'weekly_streak':
                # Check for consecutive weekly rucks
                target = criteria.get('target', 8)
                current_streak = self._calculate_weekly_streak(supabase, user_id)
                return current_streak >= target
        
            elif criteria_type == 'weekend_streak':
                # Check for consecutive weekend rucks
                target = criteria.get('target', 4)
                current_streak = self._calculate_weekend_streak(supabase, user_id)
                return current_streak >= target
        
            elif criteria_type == 'monthly_consistency':
                # Check for consistent monthly activity
                target = criteria.get('target', 3)  # months
                min_rucks = criteria.get('min_rucks', 4)  # per month
                return self._check_monthly_consistency(supabase, user_id, target, min_rucks)
        
            elif criteria_type == 'negative_split':
                # Check if this session had a negative split
                return self._check_negative_split(session)
        
            elif criteria_type == 'pace_consistency':
                # Check pace consistency across multiple sessions
                target = criteria.get('target', 0.1)  # variance threshold
                return self._check_pace_consistency(supabase, user_id, target)
        
            elif criteria_type == 'photo_uploads':
                # Check total photo uploads
                target = criteria.get('target', 10)
                total_photos = self._count_user_photos(supabase, user_id)
                return total_photos >= target
        
            elif criteria_type == 'weather_variety':
                # Check variety of weather conditions
                target = criteria.get('target', 3)
                weather_types = self._count_weather_variety(supabase, user_id)
                return weather_types >= target
        
            elif criteria_type == 'total_likes_given':
                # Check total likes given by user
                target = criteria.get('target', 100)
                total_likes = self._count_likes_given(supabase, user_id)
                return total_likes >= target
        
            elif criteria_type == 'total_likes_received':
                # Check total likes received by user
                target = criteria.get('target', 50)
                total_likes = self._count_likes_received(supabase, user_id)
                return total_likes >= target
        
            elif criteria_type == 'monthly_distance':
                # Check monthly distance achievement
                target = criteria.get('target', 50)
                current_year = datetime.utcnow().year
                current_month = datetime.utcnow().month
                
                try:
                    monthly_distance_response = supabase.rpc('get_user_monthly_distance', {
                        'p_user_id': user_id,
                        'p_year': current_year,
                        'p_month': current_month
                    }).execute()
                    
                    monthly_distance = monthly_distance_response.data or 0
                    logger.debug(f"Monthly distance check: {monthly_distance} >= {target} = {monthly_distance >= target}")
                    return monthly_distance >= target
                except Exception as e:
                    logger.error(f"Error getting user monthly distance: {str(e)}")
                    return False
        
            elif criteria_type == 'quarterly_distance':
                # Check quarterly distance achievement
                target = criteria.get('target', 200)
                current_year = datetime.utcnow().year
                current_quarter = (datetime.utcnow().month - 1) // 3 + 1
                
                try:
                    quarterly_distance_response = supabase.rpc('get_user_quarterly_distance', {
                        'p_user_id': user_id,
                        'p_year': current_year,
                        'p_quarter': current_quarter
                    }).execute()
                    
                    quarterly_distance = quarterly_distance_response.data or 0
                    logger.debug(f"Quarterly distance check: {quarterly_distance} >= {target} = {quarterly_distance >= target}")
                    return quarterly_distance >= target
                except Exception as e:
                    logger.error(f"Error getting user quarterly distance: {str(e)}")
                    return False
        
            # More complex criteria would be handled here
            logger.warning(f"Unhandled achievement criteria type: {criteria_type}")
            return False
            
        except Exception as e:
            logger.error(f"Error checking achievement criteria: {str(e)}")
            return False
    
    def _calculate_daily_streak(self, supabase, user_id: str) -> int:
        """Calculate current daily streak"""
        try:
            # Get sessions ordered by date
            response = supabase.table('ruck_session').select(
                'start_time'
            ).eq('user_id', user_id).eq('status', 'completed').order('start_time', desc=True).execute()
            
            if not response.data:
                return 0
            
            streak = 0
            current_date = datetime.utcnow().date()
            
            for session in response.data:
                session_date = datetime.fromisoformat(session['start_time'].replace('Z', '+00:00')).date()
                if session_date == current_date:
                    streak += 1
                    current_date -= timedelta(days=1)
                else:
                    break
            
            return streak
        except Exception as e:
            logger.error(f"Error calculating daily streak: {str(e)}")
            return 0
    
    def _calculate_weekly_streak(self, supabase, user_id: str) -> int:
        """Calculate current weekly streak"""
        try:
            # Get sessions grouped by week
            response = supabase.table('ruck_session').select(
                'start_time'
            ).eq('user_id', user_id).eq('status', 'completed').order('start_time', desc=True).execute()
            
            if not response.data:
                return 0
            
            # Group by week
            weeks_with_rucks = set()
            for session in response.data:
                session_date = datetime.fromisoformat(session['start_time'].replace('Z', '+00:00')).date()
                week_start = session_date - timedelta(days=session_date.weekday())
                weeks_with_rucks.add(week_start)
            
            # Count consecutive weeks from current week backwards
            streak = 0
            current_week_start = datetime.utcnow().date() - timedelta(days=datetime.utcnow().weekday())
            
            while current_week_start in weeks_with_rucks:
                streak += 1
                current_week_start -= timedelta(days=7)
            
            return streak
        except Exception as e:
            logger.error(f"Error calculating weekly streak: {str(e)}")
            return 0
    
    def _calculate_weekend_streak(self, supabase, user_id: str) -> int:
        """Calculate current weekend streak"""
        try:
            # Get weekend sessions (Saturday = 5, Sunday = 6)
            response = supabase.table('ruck_session').select(
                'start_time'
            ).eq('user_id', user_id).eq('status', 'completed').order('start_time', desc=True).execute()
            
            if not response.data:
                return 0
            
            weekends_with_rucks = set()
            for session in response.data:
                session_date = datetime.fromisoformat(session['start_time'].replace('Z', '+00:00')).date()
                if session_date.weekday() >= 5:  # Saturday or Sunday
                    # Get the Saturday of this weekend
                    weekend_start = session_date - timedelta(days=session_date.weekday() - 5)
                    weekends_with_rucks.add(weekend_start)
            
            # Count consecutive weekends
            streak = 0
            current_weekend = datetime.utcnow().date()
            current_weekend -= timedelta(days=current_weekend.weekday() - 5 if current_weekend.weekday() >= 5 else current_weekend.weekday() + 2)
            
            while current_weekend in weekends_with_rucks:
                streak += 1
                current_weekend -= timedelta(days=7)
            
            return streak
        except Exception as e:
            logger.error(f"Error calculating weekend streak: {str(e)}")
            return 0
    
    def _check_monthly_consistency(self, supabase, user_id: str, target_months: int, min_rucks_per_month: int) -> bool:
        """Check monthly consistency"""
        try:
            # Get sessions from last target_months
            months_ago = datetime.utcnow().replace(day=1) - timedelta(days=target_months * 31)
            
            response = supabase.table('ruck_session').select(
                'start_time'
            ).eq('user_id', user_id).eq('status', 'completed').gte('start_time', months_ago.isoformat()).execute()
            
            if not response.data:
                return False
            
            # Group by month
            month_counts = {}
            for session in response.data:
                session_date = datetime.fromisoformat(session['start_time'].replace('Z', '+00:00')).date()
                month_key = (session_date.year, session_date.month)
                month_counts[month_key] = month_counts.get(month_key, 0) + 1
            
            # Check if we have enough consecutive months with min_rucks
            consecutive_months = 0
            current_month = datetime.utcnow().replace(day=1)
            
            for _ in range(target_months):
                month_key = (current_month.year, current_month.month)
                if month_counts.get(month_key, 0) >= min_rucks_per_month:
                    consecutive_months += 1
                else:
                    break
                current_month -= timedelta(days=32)
                current_month = current_month.replace(day=1)
            
            return consecutive_months >= target_months
        except Exception as e:
            logger.error(f"Error checking monthly consistency: {str(e)}")
            return False
    
    def _check_negative_split(self, session: Dict) -> bool:
        """Check if session had negative split"""
        try:
            # This would require split data - for now return False
            # TODO: Implement when split data is available in session
            return False
        except Exception as e:
            logger.error(f"Error checking negative split: {str(e)}")
            return False
    
    def _check_pace_consistency(self, supabase, user_id: str, variance_threshold: float) -> bool:
        """Check pace consistency across sessions"""
        try:
            # Get recent sessions
            response = supabase.table('ruck_session').select(
                'pace_seconds_per_km'
            ).eq('user_id', user_id).eq('status', 'completed').limit(10).execute()
            
            if not response.data or len(response.data) < 3:
                return False
            
            paces = [s['pace_seconds_per_km'] for s in response.data if s.get('pace_seconds_per_km')]
            if len(paces) < 3:
                return False
            
            # Calculate coefficient of variation
            mean_pace = sum(paces) / len(paces)
            variance = sum((p - mean_pace) ** 2 for p in paces) / len(paces)
            std_dev = variance ** 0.5
            cv = std_dev / mean_pace if mean_pace > 0 else 1
            
            return cv <= variance_threshold
        except Exception as e:
            logger.error(f"Error checking pace consistency: {str(e)}")
            return False
    
    def _count_user_photos(self, supabase, user_id: str) -> int:
        """Count total photos uploaded by user"""
        try:
            response = supabase.rpc('count', {
                'table_name': 'ruck_photos',
                'conditions': f"user_id = '{user_id}'"
            }).execute()
            return response.data or 0
        except Exception as e:
            logger.error(f"Error counting user photos: {str(e)}")
            return 0
    
    def _count_weather_variety(self, supabase, user_id: str) -> int:
        """Count distinct weather conditions"""
        try:
            # This would require weather data in sessions
            # TODO: Implement when weather data is available
            return 0
        except Exception as e:
            logger.error(f"Error counting weather variety: {str(e)}")
            return 0
    
    def _count_likes_given(self, supabase, user_id: str) -> int:
        """Count total likes given by user"""
        try:
            # This would require likes table
            # TODO: Implement when likes system is available
            return 0
        except Exception as e:
            logger.error(f"Error counting likes given: {str(e)}")
            return 0
    
    def _count_likes_received(self, supabase, user_id: str) -> int:
        """Count total likes received by user"""
        try:
            # This would require likes table
            # TODO: Implement when likes system is available
            return 0
        except Exception as e:
            logger.error(f"Error counting likes received: {str(e)}")
            return 0


class AchievementStatsResource(Resource):
    """Get achievement statistics for a user"""
    
    def get(self, user_id):
        try:
            # Get the user's JWT token from the request context
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Get user's earned achievements count by category and tier
            earned_response = supabase.table('user_achievements').select(
                'achievements(category, tier)'
            ).eq('user_id', user_id).execute()
            
            earned_data = earned_response.data or []
            
            # Count by category and tier
            category_counts = {}
            tier_counts = {}
            total_earned = len(earned_data)
            
            for item in earned_data:
                achievement = item.get('achievements', {})
                category = achievement.get('category')
                tier = achievement.get('tier')
                
                if category:
                    category_counts[category] = category_counts.get(category, 0) + 1
                if tier:
                    tier_counts[tier] = tier_counts.get(tier, 0) + 1
            
            # Get total available achievements using admin client for RLS bypass
            supabase_admin = get_supabase_admin_client()
            
            # Get unit preference from query parameters
            unit_preference = request.args.get('unit_preference', 'metric')  # default to metric
            
            # Filter total available achievements by unit preference
            total_query = supabase_admin.table('achievements').select('id').eq('is_active', True)
            
            if unit_preference in ['metric', 'standard']:
                # Get achievements that are either universal (unit_preference is null) 
                # or match the user's preference
                total_response = total_query.or_(f'unit_preference.is.null,unit_preference.eq.{unit_preference}').execute()
            else:
                # If no valid preference provided, get all achievements
                total_response = total_query.execute()
                
            total_available = len(total_response.data or [])
            
            # Calculate total power points using SQL aggregation for better performance
            try:
                # Use RPC to calculate sum directly in database
                power_points_result = supabase.rpc('calculate_user_power_points', {
                    'user_id_param': user_id
                }).execute()
                
                total_power_points = 0
                if power_points_result.data is not None:
                    total_power_points = float(power_points_result.data or 0)
                    
            except Exception as rpc_error:
                # Fallback to original method if RPC doesn't exist
                logger.warning(f"RPC calculate_user_power_points not available, using fallback: {str(rpc_error)}")
                power_points_response = supabase.table('ruck_session').select(
                    'power_points'
                ).eq('user_id', user_id).eq('status', 'completed').execute()
                
                total_power_points = 0
                if power_points_response.data:
                    for session in power_points_response.data:
                        power_points = session.get('power_points')
                        if power_points is not None:
                            try:
                                # Convert to float and add to total
                                total_power_points += float(power_points)
                            except (ValueError, TypeError):
                                # Skip invalid power_points values
                                continue
            
            return {
                'status': 'success',
                'stats': {
                    'total_earned': total_earned,
                    'total_available': total_available,
                    'completion_percentage': round((total_earned / total_available * 100) if total_available > 0 else 0, 1),
                    'power_points': int(round(total_power_points)),  # Round to nearest integer for display
                    'by_category': category_counts,
                    'by_tier': tier_counts
                }
            }, 200
            
        except Exception as e:
            logger.error(f"Error fetching achievement stats: {str(e)}")
            return {'error': 'Failed to fetch achievement stats'}, 500


class RecentAchievementsResource(Resource):
    """Get recently earned achievements across the platform"""
    
    def get(self):
        try:
            # Get the user's JWT token from the request context
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Get recent achievements from the last 7 days
            since_date = (datetime.utcnow() - timedelta(days=7)).isoformat()
            
            response = supabase.table('user_achievements').select(
                '*, achievements(*)'
            ).gte('earned_at', since_date).order('earned_at', desc=True).limit(50).execute()
            
            if response.data:
                return {
                    'status': 'success',
                    'recent_achievements': response.data
                }, 200
            else:
                return {
                    'status': 'success',
                    'recent_achievements': []
                }, 200
                
        except Exception as e:
            logger.error(f"Error fetching recent achievements: {str(e)}")
            return {'error': 'Failed to fetch recent achievements'}, 500


# Create Blueprint
achievements_bp = Blueprint('achievements', __name__)
achievements_api = Api(achievements_bp)

# Register resources
achievements_api.add_resource(AchievementsResource, '/achievements')
achievements_api.add_resource(AchievementCategoriesResource, '/achievements/categories')
achievements_api.add_resource(UserAchievementsResource, '/users/<string:user_id>/achievements')
achievements_api.add_resource(UserAchievementsProgressResource, '/users/<string:user_id>/achievements/progress')
achievements_api.add_resource(CheckSessionAchievementsResource, '/achievements/check/<int:session_id>')
achievements_api.add_resource(AchievementStatsResource, '/achievements/stats/<string:user_id>')
achievements_api.add_resource(RecentAchievementsResource, '/achievements/recent')
