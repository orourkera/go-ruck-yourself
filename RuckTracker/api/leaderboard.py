"""
Leaderboard API endpoints for RuckBuddy
Well I'll be jiggered! This here's the leaderboard API, slicker than a greased pig
"""

import logging
from datetime import datetime
from flask import request, g
from flask_restful import Resource
from supabase import Client
from ..supabase_client import get_supabase_client
from ..services.redis_cache_service import get_cache_service

logger = logging.getLogger(__name__)

class LeaderboardResource(Resource):
    """
    Main leaderboard endpoint that shows public ruck statistics
    Respects user privacy by filtering out users who disabled ruck sharing
    """
    
    def get(self):
        """Get leaderboard data with sorting, pagination, and search"""
        try:
            # Get authenticated user
            if not hasattr(g, 'user') or g.user is None:
                return {'error': 'Authentication required'}, 401
            
            # Parse query parameters
            sort_by = request.args.get('sortBy', 'powerPoints')
            ascending = request.args.get('ascending', 'false').lower() == 'true'
            limit = min(int(request.args.get('limit', 50)), 100)  # Cap at 100
            offset = int(request.args.get('offset', 0))
            search = request.args.get('search', '').strip()
            
            # Validate sort_by parameter
            valid_sorts = ['powerPoints', 'rucks', 'distance', 'elevation', 'calories']
            if sort_by not in valid_sorts:
                sort_by = 'powerPoints'
            
            # Build cache key
            cache_key = f"leaderboard:{sort_by}:{ascending}:{limit}:{offset}:{search}"
            cache_service = get_cache_service()
            
            # Try to get from cache first (cache for 5 minutes)
            cached_result = cache_service.get(cache_key)
            if cached_result:
                logger.info(f"Returning cached leaderboard data for key: {cache_key}")
                return cached_result
            
            # Get Supabase client
            supabase: Client = get_supabase_client()
            
            # Build the query - this is where the magic happens!
            # CRITICAL: Filter out users who disabled public ruck sharing
            query = supabase.table('users').select('''
                id,
                username,
                avatar_url,
                created_at,
                public,
                ruck_sessions!inner(
                    id,
                    distance_km,
                    elevation_gain_meters,
                    calories_burned,
                    power_points,
                    completed_at,
                    waypoints
                )
            ''').eq('public.Allow_Ruck_Sharing', True)  # PRIVACY FILTER - CRITICAL!
            
            # Add search filter if provided
            if search:
                query = query.ilike('username', f'%{search}%')
            
            # Execute the query
            response = query.execute()
            
            if not response.data:
                return {'users': [], 'total': 0}
            
            # Process and aggregate user data
            user_stats = {}
            
            for user_data in response.data:
                user_id = user_data['id']
                
                if user_id not in user_stats:
                    # Get the user's most recent location from their latest ruck
                    latest_ruck = None
                    if user_data['ruck_sessions']:
                        latest_ruck = max(user_data['ruck_sessions'], 
                                        key=lambda x: x['completed_at'] if x['completed_at'] else '1900-01-01')
                    
                    location = "Unknown Location"
                    if latest_ruck and latest_ruck.get('waypoints'):
                        # Get the last waypoint for location
                        waypoints = latest_ruck['waypoints']
                        if waypoints and len(waypoints) > 0:
                            last_waypoint = waypoints[-1]
                            if 'location_name' in last_waypoint:
                                location = last_waypoint['location_name']
                            elif 'latitude' in last_waypoint and 'longitude' in last_waypoint:
                                # Could implement reverse geocoding here if needed
                                location = f"{last_waypoint['latitude']:.3f}, {last_waypoint['longitude']:.3f}"
                    
                    user_stats[user_id] = {
                        'id': user_id,
                        'username': user_data['username'],
                        'avatarUrl': user_data.get('avatar_url'),
                        'location': location,
                        'isRucking': False,  # TODO: Implement real-time status
                        'stats': {
                            'rucks': 0,
                            'distanceKm': 0.0,
                            'elevationGainMeters': 0.0,
                            'caloriesBurned': 0,
                            'powerPoints': 0.0
                        }
                    }
                
                # Aggregate completed ruck sessions only
                for ruck in user_data['ruck_sessions']:
                    if ruck.get('completed_at'):  # Only count completed rucks
                        stats = user_stats[user_id]['stats']
                        stats['rucks'] += 1
                        stats['distanceKm'] += ruck.get('distance_km', 0.0)
                        stats['elevationGainMeters'] += ruck.get('elevation_gain_meters', 0.0)
                        stats['caloriesBurned'] += ruck.get('calories_burned', 0)
                        stats['powerPoints'] += ruck.get('power_points', 0.0)
            
            # Convert to list and sort
            users_list = list(user_stats.values())
            
            # Sort the results
            sort_key_map = {
                'powerPoints': lambda x: x['stats']['powerPoints'],
                'rucks': lambda x: x['stats']['rucks'],
                'distance': lambda x: x['stats']['distanceKm'],
                'elevation': lambda x: x['stats']['elevationGainMeters'],
                'calories': lambda x: x['stats']['caloriesBurned']
            }
            
            users_list.sort(key=sort_key_map[sort_by], reverse=not ascending)
            
            # Add rank to each user
            for i, user in enumerate(users_list):
                user['rank'] = i + 1
            
            # Apply pagination
            total_users = len(users_list)
            paginated_users = users_list[offset:offset + limit]
            
            result = {
                'users': paginated_users,
                'total': total_users,
                'hasMore': offset + limit < total_users
            }
            
            # Cache the result for 5 minutes
            cache_service.set(cache_key, result, expire=300)
            
            logger.info(f"Leaderboard query successful: {len(paginated_users)} users returned")
            return result
            
        except Exception as e:
            logger.error(f"Error fetching leaderboard: {str(e)}", exc_info=True)
            return {'error': 'Failed to fetch leaderboard data'}, 500


class LeaderboardMyRankResource(Resource):
    """
    Get the current user's rank on the leaderboard
    """
    
    def get(self):
        """Get current user's rank"""
        try:
            # Get authenticated user
            if not hasattr(g, 'user') or g.user is None:
                return {'error': 'Authentication required'}, 401
            
            current_user_id = g.user.id
            
            # Parse sort parameters (same as main leaderboard)
            sort_by = request.args.get('sortBy', 'powerPoints')
            ascending = request.args.get('ascending', 'false').lower() == 'true'
            
            # Validate sort_by parameter
            valid_sorts = ['powerPoints', 'rucks', 'distance', 'elevation', 'calories']
            if sort_by not in valid_sorts:
                sort_by = 'powerPoints'
            
            # Build cache key
            cache_key = f"user_rank:{current_user_id}:{sort_by}:{ascending}"
            cache_service = get_cache_service()
            
            # Try cache first (cache for 2 minutes)
            cached_rank = cache_service.get(cache_key)
            if cached_rank is not None:
                return {'rank': cached_rank}
            
            # Get Supabase client
            supabase: Client = get_supabase_client()
            
            # Get all users with their aggregated stats (same logic as main leaderboard)
            response = supabase.table('users').select('''
                id,
                ruck_sessions!inner(
                    distance_km,
                    elevation_gain_meters,
                    calories_burned,
                    power_points,
                    completed_at
                )
            ''').eq('public.Allow_Ruck_Sharing', True).execute()  # PRIVACY FILTER
            
            if not response.data:
                return {'rank': None}
            
            # Aggregate stats for all users
            user_stats = {}
            
            for user_data in response.data:
                user_id = user_data['id']
                
                if user_id not in user_stats:
                    user_stats[user_id] = {
                        'id': user_id,
                        'stats': {
                            'rucks': 0,
                            'distanceKm': 0.0,
                            'elevationGainMeters': 0.0,
                            'caloriesBurned': 0,
                            'powerPoints': 0.0
                        }
                    }
                
                # Aggregate completed ruck sessions only
                for ruck in user_data['ruck_sessions']:
                    if ruck.get('completed_at'):  # Only count completed rucks
                        stats = user_stats[user_id]['stats']
                        stats['rucks'] += 1
                        stats['distanceKm'] += ruck.get('distance_km', 0.0)
                        stats['elevationGainMeters'] += ruck.get('elevation_gain_meters', 0.0)
                        stats['caloriesBurned'] += ruck.get('calories_burned', 0)
                        stats['powerPoints'] += ruck.get('power_points', 0.0)
            
            # Check if current user has any stats
            if current_user_id not in user_stats:
                return {'rank': None}  # User not on leaderboard
            
            # Convert to list and sort
            users_list = list(user_stats.values())
            
            # Sort the results
            sort_key_map = {
                'powerPoints': lambda x: x['stats']['powerPoints'],
                'rucks': lambda x: x['stats']['rucks'],
                'distance': lambda x: x['stats']['distanceKm'],
                'elevation': lambda x: x['stats']['elevationGainMeters'],
                'calories': lambda x: x['stats']['caloriesBurned']
            }
            
            users_list.sort(key=sort_key_map[sort_by], reverse=not ascending)
            
            # Find current user's rank
            user_rank = None
            for i, user in enumerate(users_list):
                if user['id'] == current_user_id:
                    user_rank = i + 1
                    break
            
            # Cache the result for 2 minutes
            cache_service.set(cache_key, user_rank, expire=120)
            
            return {'rank': user_rank}
            
        except Exception as e:
            logger.error(f"Error fetching user rank: {str(e)}", exc_info=True)
            return {'error': 'Failed to fetch user rank'}, 500
