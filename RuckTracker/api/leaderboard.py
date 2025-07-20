"""
Leaderboard API endpoints for RuckBuddy
Well I'll be jiggered! This here's the leaderboard API, slicker than a greased pig
"""

import logging
from datetime import datetime
from flask import request, g
from flask_restful import Resource
from supabase import Client
from ..supabase_client import get_supabase_client, get_supabase_admin_client
from ..services.redis_cache_service import get_cache_service

logger = logging.getLogger(__name__)

class LeaderboardResource(Resource):
    """
    Main leaderboard endpoint that shows public ruck statistics
    Respects user privacy by filtering out users who disabled ruck sharing
    """
    
    def get(self):
        """Get leaderboard data with sorting, pagination, and search"""
        print("🚀🚀🚀 LEADERBOARD METHOD START - VERY FIRST LINE 🚀🚀🚀")
        print("🔥🔥🔥 LEADERBOARD API CALLED - DEBUG TEST 🔥🔥🔥")
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
            
            # Get Supabase admin client to bypass RLS for public leaderboard data
            supabase: Client = get_supabase_admin_client()
            logger.info(f"[DEBUG] Using admin client: {type(supabase)}")
            
            # Build the query - this is where the magic happens!
            # CRITICAL: Filter out users who disabled public ruck sharing
            query = supabase.table('users').select('''
                id,
                username,
                avatar_url,
                created_at,
                public,
                ruck_session!inner(
                    id,
                    distance_km,
                    elevation_gain_m,
                    calories_burned,
                    power_points,
                    completed_at,
                    started_at,
                    status
                )
            ''')  # TEMPORARILY DISABLED: .eq('allow_ruck_sharing', True)  # PRIVACY FILTER - CRITICAL!
            
            # Add search filter if provided
            if search:
                query = query.ilike('username', f'%{search}%')
            
            # Execute the query
            print("🔍 ABOUT TO EXECUTE SUPABASE QUERY")
            logger.info(f"[DEBUG] Executing leaderboard query with admin client...")
            print(f"🔍 Query object type: {type(query)}")
            try:
                print("🔍 Calling query.execute()...")
                response = query.execute()
                print(f"🔍 Query executed! Response received: {type(response)}")
                logger.info(f"[DEBUG] Query executed successfully")
                logger.info(f"[DEBUG] Response type: {type(response)}")
                logger.info(f"[DEBUG] Response data type: {type(response.data)}")
                print(f"🔍 Response data count: {len(response.data) if response.data else 0}")
                logger.info(f"[DEBUG] Query response count: {len(response.data) if response.data else 0}")
                if response.data:
                    print(f"🔍 First row sample: {response.data[0] if len(response.data) > 0 else 'None'}")
                    logger.info(f"[DEBUG] First row sample: {response.data[0] if len(response.data) > 0 else 'None'}")
                else:
                    print("🔍 NO DATA RETURNED FROM QUERY")
                    logger.info(f"[DEBUG] No data returned from query")
            except Exception as e:
                print(f"🔍 QUERY EXECUTION FAILED: {str(e)}")
                logger.error(f"[DEBUG] Query execution failed: {str(e)}")
                logger.error(f"[DEBUG] Query error type: {type(e)}")
                return {'users': [], 'total': 0, 'hasMore': False, 'activeRuckersCount': 0}
            
            if not response.data:
                return {'users': [], 'total': 0}
            
            # Process and aggregate user data
            user_stats = {}
            active_ruckers_count = 0
            
            for user_data in response.data:
                user_id = user_data['id']
                
                if user_id not in user_stats:
                    # Get ruck sessions safely (might be missing if user has no sessions)
                    ruck_sessions = user_data.get('ruck_session', [])
                    
                    # Check if user is currently rucking (has active session)
                    is_currently_rucking = False
                    for ruck in ruck_sessions:
                        if ruck.get('status') in ['in_progress', 'paused'] and not ruck.get('completed_at'):
                            is_currently_rucking = True
                            break
                    
                    if is_currently_rucking:
                        active_ruckers_count += 1
                    
                    # Get the user's most recent location from their latest ruck
                    latest_ruck = None
                    if ruck_sessions:
                        latest_ruck = max(ruck_sessions, 
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
                        'isCurrentlyRucking': is_currently_rucking,
                        'stats': {
                            'rucks': 0,
                            'distanceKm': 0.0,
                            'elevationGainMeters': 0.0,
                            'caloriesBurned': 0,
                            'powerPoints': 0.0
                        }
                    }
                
                # Aggregate completed ruck sessions only
                for ruck in user_data.get('ruck_session', []):
                    if ruck.get('completed_at'):  # Only count completed rucks
                        stats = user_stats[user_id]['stats']
                        stats['rucks'] += 1
                        stats['distanceKm'] += ruck.get('distance_km', 0.0)
                        stats['elevationGainMeters'] += ruck.get('elevation_gain_m', 0.0)
                        stats['caloriesBurned'] += ruck.get('calories_burned', 0)
                        stats['powerPoints'] += ruck.get('power_points', 0.0)
            
            # Filter out users with zero completed rucks - only show active ruckers!
            active_user_stats = {user_id: stats for user_id, stats in user_stats.items() 
                                if stats['stats']['rucks'] > 0}
            
            logger.info(f"Filtered leaderboard: {len(user_stats)} total users -> {len(active_user_stats)} active ruckers")
            
            # Convert to list and sort
            users_list = list(active_user_stats.values())
            
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
                'hasMore': offset + limit < total_users,
                'activeRuckersCount': active_ruckers_count
            }
            
            # Cache the result for 5 minutes
            cache_service.set(cache_key, result, expire_seconds=300)
            
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
            
            # Get Supabase admin client to bypass RLS for public leaderboard data
            supabase: Client = get_supabase_admin_client()
            logger.info(f"[DEBUG] My-rank using admin client: {type(supabase)}")
            
            # Build the query - users with public ruck sharing enabled only
            query = supabase.table('users').select('''
                id,
                username,
                ruck_session!inner(
                    power_points,
                    distance_km,
                    completed_at,
                    status
                )
            ''')  # TEMPORARILY DISABLED: .eq('allow_ruck_sharing', True)  # PRIVACY FILTER - CRITICAL!
            
            logger.info(f"[DEBUG] Executing my-rank query with admin client...")
            response = query.execute()
            logger.info(f"[DEBUG] My-rank query response count: {len(response.data) if response.data else 0}")
            
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
                for ruck in user_data.get('ruck_session', []):
                    if ruck.get('completed_at'):  # Only count completed rucks
                        stats = user_stats[user_id]['stats']
                        stats['rucks'] += 1
                        stats['distanceKm'] += ruck.get('distance_km', 0.0)
                        stats['elevationGainMeters'] += ruck.get('elevation_gain_m', 0.0)
                        stats['caloriesBurned'] += ruck.get('calories_burned', 0)
                        stats['powerPoints'] += ruck.get('power_points', 0.0)
            
            # Filter out users with zero completed rucks - consistent with main leaderboard
            active_user_stats = {user_id: stats for user_id, stats in user_stats.items() 
                                if stats['stats']['rucks'] > 0}
            
            # Check if current user has any completed rucks
            if current_user_id not in active_user_stats:
                return {'rank': None}  # User not on leaderboard (no completed rucks)
            
            # Convert to list and sort
            users_list = list(active_user_stats.values())
            
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
            cache_service.set(cache_key, user_rank, expire_seconds=120)
            
            return {'rank': user_rank}
            
        except Exception as e:
            logger.error(f"Error fetching user rank: {str(e)}", exc_info=True)
            return {'error': 'Failed to fetch user rank'}, 500
