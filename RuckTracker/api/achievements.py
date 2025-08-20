"""
Achievements API endpoints for RuckingApp
Handles achievement management, progress tracking, and award calculations
"""
import logging
from flask import Blueprint, request, jsonify, g
from flask_restful import Resource, Api
from RuckTracker.supabase_client import get_supabase_client, get_supabase_admin_client
from RuckTracker.services.redis_cache_service import cache_get, cache_set
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
from ..services.push_notification_service import PushNotificationService, get_user_device_tokens

logger = logging.getLogger(__name__)

class AchievementsResource(Resource):
    """Get all available achievements"""
    
    def get(self):
        try:
            # Get unit preference from query parameters
            unit_preference = request.args.get('unit_preference', 'metric')  # default to metric
            
            # Check cache first
            cache_key = f"achievements:all:{unit_preference}"
            cached_response = cache_get(cache_key)
            if cached_response:
                return {
                    'status': 'success',
                    'achievements': cached_response
                }, 200
            
            # Use admin client since achievements are public data
            supabase = get_supabase_admin_client()
            
            # Base query for active achievements - only select fields needed by frontend
            query = supabase.table('achievements').select(
                'id, achievement_key, name, description, category, tier, criteria, icon_name, is_active, created_at, updated_at, unit_preference'
            ).eq('is_active', True)
            
            # Filter by unit preference: include universal (null) achievements and user's preferred unit
            if unit_preference in ['metric', 'standard']:
                # Get achievements that are either universal (unit_preference is null) 
                # or match the user's preference
                response = query.or_(f'unit_preference.is.null,unit_preference.eq.{unit_preference}').execute()
            else:
                # If no valid preference provided, get all achievements
                response = query.execute()
            
            if response.data:
                # Cache for 30 minutes since achievements don't change often
                cache_set(cache_key, response.data, 1800)
                return {
                    'status': 'success',
                    'achievements': response.data
                }, 200
            else:
                # Cache empty result for shorter time
                cache_set(cache_key, [], 300)
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
            
            # Select only necessary columns to reduce payload size
            response = supabase.table('user_achievements').select(
                'id, achievement_id, session_id, earned_at, progress_value, metadata, '
                'achievements(name, description, tier, category, icon_name, achievement_key)'
            ).eq('user_id', user_id).order('earned_at', desc=True).execute()
            
            # Log count only to avoid large memory usage in logs
            logger.info(
                f"Fetched achievements for user {user_id}: count={len(response.data) if response.data else 0}"
            )
            
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
                '*, achievements(name, tier, category, icon_name, achievement_key)'
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
            
            # Global min requirements
            if not self._validateSessionForAchievements(session):
                return {
                    'status': 'success', 
                    'new_achievements': [],
                    'session_id': session_id,
                    'message': 'Session does not meet minimum requirements for achievements'
                }, 200
        
            # BATCH APPROACH: Get all data in fewer queries
            logger.info("Starting batch achievement check...")
            
            # Single query: Get user data + existing achievements + user stats
            user_data_response = supabase.table('user').select('prefer_metric').eq('id', user_id).single().execute()
            prefer_metric = user_data_response.data.get('prefer_metric', True) if user_data_response.data else True
            unit_preference = 'metric' if prefer_metric else 'standard'
            
            # Batch query: Get all user's existing achievements in one call
            existing_achievements_response = supabase.table('user_achievements').select('achievement_id').eq('user_id', user_id).execute()
            existing_achievement_ids = {a['achievement_id'] for a in existing_achievements_response.data or []}
            
            # Batch query: Get filtered achievements (pre-filtered by unit preference)
            achievements_query = supabase.table('achievements').select('*').eq('is_active', True)
            achievements_response = achievements_query.or_(f'unit_preference.is.null,unit_preference.eq.{unit_preference}').execute()
            all_achievements = achievements_response.data or []
            
            # Pre-filter: Remove achievements user already has (in memory, no DB calls)
            achievements = [a for a in all_achievements if a['id'] not in existing_achievement_ids]
            
            # Batch query: Get user stats that are commonly needed for criteria checking
            user_stats = {}
            try:
                # Get total distance, power points, and session counts in one query
                stats_response = supabase.rpc('get_user_achievement_stats', {'user_id': user_id}).execute()
                user_stats = stats_response.data or {}
            except Exception as e:
                # Fallback: Get stats individually if RPC doesn't exist
                logger.warning(f"RPC get_user_achievement_stats not available, using fallback: {str(e)}")
                try:
                    distance_response = supabase.rpc('get_user_total_distance', {'p_user_id': user_id}).execute()
                    user_stats['total_distance'] = distance_response.data or 0
                except:
                    user_stats['total_distance'] = 0
            
                try:
                    power_response = supabase.rpc('calculate_user_power_points', {'user_id_param': user_id}).execute()
                    user_stats['total_power_points'] = power_response.data or 0
                except:
                    user_stats['total_power_points'] = 0
        
            logger.info(f"Batch optimized: User={unit_preference}, Total achievements={len(all_achievements)}, Already earned={len(existing_achievement_ids)}, To check={len(achievements)}, Stats loaded={len(user_stats)}")
            
            # Check for new achievements
            new_achievements = []
            
            for achievement in achievements:
                achievement_unit = achievement.get('unit_preference')
                logger.info(f"Checking achievement: {achievement['name']} (ID: {achievement['id']}) - Unit: {achievement_unit or 'universal'}")
                logger.debug(f"Achievement criteria: {achievement.get('criteria', {})}")
                
                # Double-check unit compatibility (safety check - should be redundant now)
                if achievement_unit is not None and achievement_unit != unit_preference:
                    logger.warning(f"Skipping achievement {achievement['name']} - unit mismatch: user={unit_preference}, achievement={achievement_unit}")
                    continue
                
                # Skip redundant existing check - already pre-filtered in batch approach
                # This eliminates N database queries per session!
                
                # Check if user meets criteria for this achievement (with pre-loaded stats)
                criteria_met = self._check_achievement_criteria(supabase, user_id, session, achievement, user_stats)
                logger.info(f"Achievement {achievement['name']} criteria met: {criteria_met}")
                
                # Log specific details for suspicious achievements
                if criteria_met and ('62' in achievement['name'] or 'mile' in achievement['name'] or 'pacer' in achievement['name'] or 'rucker' in achievement['name'] or 'mover' in achievement['name']):
                    logger.warning(f"SUSPICIOUS ACHIEVEMENT AWARDED: {achievement['name']} for session with distance={session.get('distance_km')}km, duration={session.get('duration_seconds')}s, pace={session.get('average_pace')}")
                
                if criteria_met:
                    # Safety check: prevent mass awarding more than 5 achievements per session
                    if len(new_achievements) >= 5:
                        logger.warning(f"SAFETY LIMIT: Already awarded {len(new_achievements)} achievements for session {session_id}. Skipping {achievement['name']} to prevent mass awarding.")
                        continue
                    
                    # Final validation: double-check if achievement already exists (race condition protection)
                    final_check = supabase.table('user_achievements').select('id').eq(
                        'user_id', user_id
                    ).eq('achievement_id', achievement['id']).execute()
                    
                    if final_check.data:
                        logger.warning(f"Race condition detected: Achievement {achievement['name']} already exists for user {user_id}")
                        continue
                    
                    # Award the achievement
                    award_data = {
                        'user_id': user_id,
                        'achievement_id': achievement['id'],
                        'session_id': session_id,
                        'earned_at': datetime.utcnow().isoformat(),
                        'metadata': {
                            'triggered_by_session': session_id,
                            'unit_preference': unit_preference,
                            'session_distance_km': session.get('distance_km'),
                            'session_duration_s': session.get('duration_seconds')
                        }
                    }
                    
                    try:
                        insert_result = supabase.table('user_achievements').insert(award_data).execute()
                        logger.info(f"✅ AWARDED: {achievement['name']} to user {user_id} (unit: {unit_preference})")
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
    
    def _validateSessionForAchievements(self, session: Dict) -> bool:
        distance_km = session.get('distance_km', 0) or 0
        duration_seconds = session.get('duration_seconds', 0) or 0
        
        # Handle None values that could come from database
        if distance_km is None:
            distance_km = 0
        if duration_seconds is None:
            duration_seconds = 0
        
        # CRITICAL: Ensure values are numeric before comparison
        try:
            distance_km = float(distance_km) if distance_km is not None else 0.0
            duration_seconds = int(duration_seconds) if duration_seconds is not None else 0
        except (ValueError, TypeError):
            logger.warning(f"Invalid session data types: distance={distance_km}, duration={duration_seconds}")
            return False
            
        is_valid = duration_seconds >= 300 and distance_km >= 0.5
        logger.info(f"Session validation: duration={duration_seconds}s, distance={distance_km}km, valid={is_valid}")
        return is_valid

    def _check_achievement_criteria(self, supabase, user_id: str, session: Dict, achievement: Dict, user_stats: Dict = None) -> bool:
        """Check if user meets criteria for a specific achievement"""
        try:
            # CRITICAL: Check minimum session requirements first
            session_distance = session.get('distance_km', 0)
            session_duration = session.get('duration_seconds', 0)
            
            # Ensure numeric values for comparison
            try:
                session_distance = float(session_distance) if session_distance is not None else 0.0
                session_duration = int(session_duration) if session_duration is not None else 0
            except (ValueError, TypeError):
                logger.warning(f"Invalid criteria check data types: distance={session_distance}, duration={session_duration}")
                return False
            
            # Minimum session requirements: at least 5 minutes AND 500 meters
            if session_duration < 300 or session_distance < 0.5:
                logger.info(f"Session too short for achievements: {session_duration}s, {session_distance}km")
                return False
            
            criteria = achievement['criteria']
            criteria_type = criteria.get('type')
            
            unit_pref = achievement.get('unit_preference')
            
            if criteria_type == 'first_ruck':
                return True  # If we're checking, this must be their first completed ruck
            
            elif criteria_type == 'single_session_distance':
                target = criteria.get('target', 0)
                distance = session.get('distance_km', 0)
                # Convert target to km if achievement is in standard (miles)
                target_km = target if unit_pref in [None, 'metric'] else target * 1.60934
                result = distance >= target_km
                logger.info(f"DISTANCE CHECK: distance={distance}km, target={target_km}km (orig={target} {'miles' if unit_pref=='standard' else 'km'}), result={result}")
                return result
            
            elif criteria_type == 'session_duration':
                target = criteria.get('target', 0)
                duration = session.get('duration_seconds', 0)
                result = duration >= target
                logger.info(f"DURATION CHECK: duration={duration}s, target={target}s, result={result}")
                return result
            
            elif criteria_type == 'session_weight':
                target = criteria.get('target', 0)
                # Convert target to kg if achievement is in standard (lbs)
                target_kg = target if unit_pref in [None, 'metric'] else target * 0.45359237
                result = session.get('ruck_weight_kg', 0) >= target_kg
                logger.info(f"WEIGHT CHECK: weight_kg={session.get('ruck_weight_kg', 0)}, target_kg={target_kg} (orig={target} {'lb' if unit_pref=='standard' else 'kg'}), result={result}")
                return result
            
            elif criteria_type == 'power_points':
                # Use pre-loaded stats if available, otherwise fall back to individual queries
                if user_stats and 'total_power_points' in user_stats:
                    total_power_points = user_stats['total_power_points']
                else:
                    # Fallback: individual database call (slower)
                    try:
                        response = supabase.rpc('calculate_user_power_points', {
                            'user_id_param': user_id
                        }).execute()
                        total_power_points = response.data or 0
                    except Exception as rpc_error:
                        logger.warning(f"RPC calculate_user_power_points not available, using manual calculation: {str(rpc_error)}")
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
                # Convert target to meters if achievement is in standard (feet)
                target_m = target if unit_pref in [None, 'metric'] else target * 0.3048
                result = session.get('elevation_gain_m', 0) >= target_m
                logger.info(f"ELEVATION CHECK: elevation_m={session.get('elevation_gain_m', 0)}, target_m={target_m} (orig={target} {'ft' if unit_pref=='standard' else 'm'}), result={result}")
                return result
            

            
            elif criteria_type == 'pace_faster_than':
                target = criteria.get('target', 999999)
                pace = session.get('average_pace')
                
                # Check if pace is None or invalid
                if pace is None:
                    logger.info(f"PACE CHECK FAILED: pace is None")
                    return False
                
                # Convert target to seconds/km if achievement is in standard (seconds/mile)
                target_s_per_km = target if unit_pref in [None, 'metric'] else (target / 1.60934)
                
                # CRITICAL: Pace achievements must also meet minimum distance requirements
                achievement_name = achievement.get('name', '').lower()
                required_distance = 0
                
                if '80' in achievement_name and 'km' in achievement_name:
                    required_distance = 80
                elif '50' in achievement_name and 'km' in achievement_name:
                    required_distance = 50
                elif '42' in achievement_name and 'km' in achievement_name:
                    required_distance = 42.195  # Marathon
                elif '20' in achievement_name and 'km' in achievement_name:
                    required_distance = 20
                elif '10' in achievement_name and 'km' in achievement_name:
                    required_distance = 10
                elif '5' in achievement_name and 'km' in achievement_name:
                    required_distance = 5
                elif 'mile' in achievement_name:
                    if '26' in achievement_name:
                        required_distance = 26.2 * 1.609  # Marathon in km
                    elif '13' in achievement_name:
                        required_distance = 13.1 * 1.609  # Half marathon in km
                    elif '10' in achievement_name:
                        required_distance = 10 * 1.609
                    elif '6' in achievement_name:
                        required_distance = 6 * 1.609
                    elif '3' in achievement_name:
                        required_distance = 3 * 1.609
                
                session_distance = session.get('distance_km', 0)
                
                # If this is a distance-specific pace achievement, check distance requirement
                if required_distance > 0 and not (required_distance * 0.95 <= session_distance <= required_distance * 1.05):
                    logger.info(f"PACE CHECK FAILED: Distance {session_distance}km not within tolerance of {required_distance}km")
                    return False
                
                logger.info(f"PACE FASTER THAN CHECK: pace_s_per_km={pace}, target_s_per_km={target_s_per_km} (orig_target={target} {'s/mile' if unit_pref=='standard' else 's/km'}), result={pace <= target_s_per_km}")
                logger.info(f"Session data: distance={session_distance}km, duration={session.get('duration_seconds')}s, required_distance={required_distance}km")
                return pace <= target_s_per_km
        
            elif criteria_type == 'pace_slower_than':
                target = criteria.get('target', 0)
                pace = session.get('average_pace')
                
                # Check if pace is None or invalid
                if pace is None:
                    logger.info(f"PACE CHECK FAILED: pace is None")
                    return False
                
                # Convert target to seconds/km if achievement is in standard (seconds/mile)
                target_s_per_km = target if unit_pref in [None, 'metric'] else (target / 1.60934)
                logger.info(f"PACE SLOWER THAN CHECK: pace_s_per_km={pace}, target_s_per_km={target_s_per_km} (orig_target={target} {'s/mile' if unit_pref=='standard' else 's/km'}), result={pace >= target_s_per_km}")
                logger.info(f"Session data: distance={session.get('distance_km')}km, duration={session.get('duration_seconds')}s")
                return pace >= target_s_per_km
        
            elif criteria_type == 'cumulative_distance':
                # Use pre-loaded stats if available, otherwise fall back to individual queries
                if user_stats and 'total_distance' in user_stats:
                    total_distance = user_stats['total_distance']
                else:
                    # Fallback: individual database call (slower)
                    try:
                        response = supabase.rpc('get_user_total_distance', {'p_user_id': user_id}).execute()
                        total_distance = response.data or 0
                    except Exception as e:
                        logger.error(f"Error getting user total distance: {str(e)}")
                        return False
            
                target = criteria.get('target', 0)
                # Convert target to km if achievement is in standard (miles)
                target_km = target if unit_pref in [None, 'metric'] else target * 1.60934
                result = total_distance >= target_km
                logger.debug(f"CUMULATIVE DISTANCE CHECK: total={total_distance}km, target_km={target_km} (orig={target} {'miles' if unit_pref=='standard' else 'km'}), result={result}")
                return result
        
            elif criteria_type == 'time_of_day':
                # Check early bird / night owl achievements
                started_at = session.get('started_at')
                if started_at:
                    dt = datetime.fromisoformat(started_at.replace('Z', '+00:00'))
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
                    # Convert target to km if achievement is in standard (miles)
                    target_km = target if unit_pref in [None, 'metric'] else target * 1.60934
                    logger.debug(f"Monthly distance check: {monthly_distance}km >= {target_km}km (orig={target} {'miles' if unit_pref=='standard' else 'km'}) = {monthly_distance >= target_km}")
                    return monthly_distance >= target_km
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
                    # Convert target to km if achievement is in standard (miles)
                    target_km = target if unit_pref in [None, 'metric'] else target * 1.60934
                    logger.debug(f"Quarterly distance check: {quarterly_distance}km >= {target_km}km (orig={target} {'miles' if unit_pref=='standard' else 'km'}) = {quarterly_distance >= target_km}")
                    return quarterly_distance >= target_km
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
                'started_at'
            ).eq('user_id', user_id).eq('status', 'completed').order('started_at', desc=True).execute()
            
            if not response.data:
                return 0
            
            streak = 0
            current_date = datetime.utcnow().date()
            session_dates = sorted(set(datetime.fromisoformat(s['started_at'].replace('Z', '+00:00')).date() for s in response.data), reverse=True)
            for session_date in session_dates:
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
                'started_at'
            ).eq('user_id', user_id).eq('status', 'completed').order('started_at', desc=True).execute()
            
            if not response.data:
                return 0
            
            # Group by week
            weeks_with_rucks = set()
            for session in response.data:
                session_date = datetime.fromisoformat(session['started_at'].replace('Z', '+00:00')).date()
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
                'started_at'
            ).eq('user_id', user_id).eq('status', 'completed').order('started_at', desc=True).execute()
            
            if not response.data:
                return 0
            
            weekends_with_rucks = set()
            for session in response.data:
                session_date = datetime.fromisoformat(session['started_at'].replace('Z', '+00:00')).date()
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
                'started_at'
            ).eq('user_id', user_id).eq('status', 'completed').gte('started_at', months_ago.isoformat()).execute()
            
            if not response.data:
                return False
            
            # Group by month
            month_counts = {}
            for session in response.data:
                session_date = datetime.fromisoformat(session['started_at'].replace('Z', '+00:00')).date()
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
            # Get recent sessions with duration and distance to calculate pace
            response = supabase.table('ruck_session').select(
                'duration_seconds, distance_km'
            ).eq('user_id', user_id).eq('status', 'completed').limit(10).execute()
            
            if not response.data or len(response.data) < 3:
                return False
            
            paces = []
            for session in response.data:
                duration = session.get('duration_seconds')
                distance = session.get('distance_km')
                if duration and distance:
                    pace = duration / distance
                    paces.append(pace)
            
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
            # Use direct table query instead of missing RPC function
            response = supabase.table('ruck_photos').select('id', count='exact').eq('user_id', user_id).execute()
            return response.count or 0
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
            # Get recent achievements from the last 7 days
            since_date = (datetime.utcnow() - timedelta(days=7)).isoformat()
            
            # Check cache first - cache by date to ensure fresh data
            cache_key = f"achievements:recent:{since_date[:10]}"  # Cache by date (YYYY-MM-DD)
            cached_response = cache_get(cache_key)
            if cached_response:
                return {
                    'status': 'success',
                    'recent_achievements': cached_response
                }, 200
            
            # Get the user's JWT token from the request context
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            response = supabase.table('user_achievements').select(
                'earned_at, metadata, user_id, achievements(name, description, tier, category, icon_name, achievement_key)'
            ).gte('earned_at', since_date).order('earned_at', desc=True).limit(50).execute()
            
            if response.data:
                # Cache for 10 minutes since recent achievements change frequently
                cache_set(cache_key, response.data, 600)
                return {
                    'status': 'success',
                    'recent_achievements': response.data
                }, 200
            else:
                # Cache empty result for shorter time
                cache_set(cache_key, [], 300)
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
