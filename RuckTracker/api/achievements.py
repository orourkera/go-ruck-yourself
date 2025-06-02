"""
Achievements API endpoints for RuckingApp
Handles achievement management, progress tracking, and award calculations
"""
import logging
from flask import Blueprint, request, jsonify, g
from flask_restful import Resource, Api
from RuckTracker.supabase_client import get_supabase_client
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any

logger = logging.getLogger(__name__)

class AchievementsResource(Resource):
    """Get all available achievements"""
    
    def get(self):
        try:
            supabase = get_supabase_client()
            
            # Get all active achievements
            response = supabase.table('achievements').select('*').eq('is_active', True).execute()
            
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
            supabase = get_supabase_client()
            
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
            supabase = get_supabase_client()
            
            # Get user's earned achievements with achievement details
            response = supabase.table('user_achievements').select(
                '*, achievements(*)'
            ).eq('user_id', user_id).order('earned_at', desc=True).execute()
            
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
            supabase = get_supabase_client()
            
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
            supabase = get_supabase_client()
            
            # Get session details
            session_response = supabase.table('ruck_session').select('*').eq('id', session_id).single().execute()
            
            if not session_response.data:
                return {'error': 'Session not found'}, 404
                
            session = session_response.data
            user_id = session['user_id']
            
            # Get all achievements
            achievements_response = supabase.table('achievements').select('*').eq('is_active', True).execute()
            achievements = achievements_response.data or []
            
            # Check for new achievements
            new_achievements = []
            
            for achievement in achievements:
                # Check if user already has this achievement
                existing = supabase.table('user_achievements').select('id').eq(
                    'user_id', user_id
                ).eq('achievement_id', achievement['id']).execute()
                
                if existing.data:
                    continue  # User already has this achievement
                
                # Check if user meets criteria for this achievement
                if self._check_achievement_criteria(supabase, user_id, session, achievement):
                    # Award the achievement
                    award_data = {
                        'user_id': user_id,
                        'achievement_id': achievement['id'],
                        'session_id': session_id,
                        'earned_at': datetime.utcnow().isoformat(),
                        'metadata': {'triggered_by_session': session_id}
                    }
                    
                    supabase.table('user_achievements').insert(award_data).execute()
                    new_achievements.append(achievement)
                    
                    logger.info(f"Awarded achievement {achievement['name']} to user {user_id}")
            
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
                target = criteria.get('target', 0)
                return session.get('power_points', 0) >= target
            
            elif criteria_type == 'elevation_gain':
                target = criteria.get('target', 0)
                return session.get('elevation_gain_m', 0) >= target
            
            elif criteria_type == 'session_duration':
                target = criteria.get('target', 0)
                return session.get('duration_seconds', 0) >= target
            
            elif criteria_type == 'pace_faster_than':
                target = criteria.get('target', 999999)
                pace = session.get('pace_seconds_per_km', 999999)
                return pace <= target
            
            elif criteria_type == 'pace_slower_than':
                target = criteria.get('target', 0)
                pace = session.get('pace_seconds_per_km', 0)
                return pace >= target
            
            elif criteria_type == 'cumulative_distance':
                # Get user's total distance
                response = supabase.rpc('get_user_total_distance', {'p_user_id': user_id}).execute()
                total_distance = response.data or 0
                target = criteria.get('target', 0)
                return total_distance >= target
            
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
                        count_response = supabase.rpc('count_sessions_before_hour', {
                            'p_user_id': user_id,
                            'p_hour': before_hour
                        }).execute()
                        count = count_response.data or 0
                        return count >= target_count
                    
                    elif 'after_hour' in criteria:
                        target_count = criteria.get('target', 1)
                        after_hour = criteria.get('after_hour')
                        
                        # Count sessions starting after this hour
                        count_response = supabase.rpc('count_sessions_after_hour', {
                            'p_user_id': user_id,
                            'p_hour': after_hour
                        }).execute()
                        count = count_response.data or 0
                        return count >= target_count
            
            # More complex criteria would be handled here (streaks, consistency, etc.)
            logger.warning(f"Unhandled achievement criteria type: {criteria_type}")
            return False
            
        except Exception as e:
            logger.error(f"Error checking achievement criteria: {str(e)}")
            return False


class AchievementStatsResource(Resource):
    """Get achievement statistics for a user"""
    
    def get(self, user_id):
        try:
            supabase = get_supabase_client()
            
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
            
            # Get total available achievements
            total_response = supabase.table('achievements').select('id').eq('is_active', True).execute()
            total_available = len(total_response.data or [])
            
            # Calculate total power points from all user's completed sessions
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
            supabase = get_supabase_client()
            
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
