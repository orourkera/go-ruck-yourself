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
            query = (
                supabase.table('user').select(
                    '''
                    id,
                    username,
                    avatar_url,
                    created_at,
                    ruck_session(
                        id,
                        distance_km,
                        elevation_gain_m,
                        calories_burned,
                        power_points,
                        completed_at,
                        started_at,
                        status
                    )
                    '''
                )
                .eq('allow_ruck_sharing', True)  # Enforce privacy filter
            )
            
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
                
                # Check if embed worked
                has_ruck_session_data = False
                if response.data and len(response.data) > 0:
                    first_user = response.data[0]
                    has_ruck_session_data = 'ruck_session' in first_user
                    print(f"🔍 First user has ruck_session data: {has_ruck_session_data}")
                    if has_ruck_session_data:
                        print(f"🔍 First user ruck_session count: {len(first_user['ruck_session'])}")
                    else:
                        print(f"🔍 First user keys: {list(first_user.keys())}")
                
                # If embed failed, fall back to manual approach
                if not has_ruck_session_data:
                    print("🔍 EMBED FAILED - USING MANUAL QUERY APPROACH")
                    logger.info("[DEBUG] Embed failed, using manual approach")
                    
                    # Get user IDs for manual session query
                    user_ids = [user['id'] for user in response.data]
                    
                    # Query ruck sessions separately
                    sessions_query = supabase.table('ruck_session').select(
                        'id, user_id, distance_km, elevation_gain_m, calories_burned, '
                        'power_points, completed_at, started_at, status'
                    ).in_('user_id', user_ids)
                    
                    sessions_response = sessions_query.execute()
                    print(f"🔍 Manual sessions query returned: {len(sessions_response.data)} sessions")
                    
                    # Group sessions by user_id
                    sessions_by_user = {}
                    for session in sessions_response.data:
                        user_id = session['user_id']
                        if user_id not in sessions_by_user:
                            sessions_by_user[user_id] = []
                        sessions_by_user[user_id].append(session)
                    
                    # Attach sessions to users
                    for user in response.data:
                        user['ruck_session'] = sessions_by_user.get(user['id'], [])
                    
                    print(f"🔍 Manual approach complete - users now have ruck_session data")
                
                print(f"🔍 Response data count: {len(response.data) if response.data else 0}")
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
                    
                    # Location extraction removed – `waypoints` not selected anymore.
                    location = None
                    
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
                        stats['distanceKm'] += ruck.get('distance_km') or 0.0
                        stats['elevationGainMeters'] += ruck.get('elevation_gain_m') or 0.0
                        stats['caloriesBurned'] += ruck.get('calories_burned') or 0
                        stats['powerPoints'] += ruck.get('power_points') or 0.0
            
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
            
            # Return ALL users (no pagination)
            total_users = len(users_list)
            
            result = {
                'users': users_list,  # Return all users, not paginated
                'total': total_users,
                'hasMore': False,  # No more pages since we return everything
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
            query = (
                supabase.table('user').select(
                    '''
                    id,
                    username,
                    ruck_session(
                        power_points,
                        distance_km,
                        completed_at,
                        elevation_gain_m,
                        calories_burned
                    )
                    '''
                )
                .eq('allow_ruck_sharing', True)  # Enforce privacy filter
            )
            
            logger.info(f"[DEBUG] Executing my-rank query with admin client...")
            response = query.execute()
            logger.info(f"[DEBUG] My-rank query response count: {len(response.data) if response.data else 0}")
            
            if not response.data:
                return {'rank': None}
            
            # Check if embed worked for my-rank query too
            has_ruck_session_data = False
            if response.data and len(response.data) > 0:
                first_user = response.data[0]
                has_ruck_session_data = 'ruck_session' in first_user
                logger.info(f"[DEBUG] My-rank first user has ruck_session data: {has_ruck_session_data}")
            
            # If embed failed, fall back to manual approach for my-rank too
            if not has_ruck_session_data:
                logger.info("[DEBUG] My-rank embed failed, using manual approach")
                
                # Get user IDs for manual session query
                user_ids = [user['id'] for user in response.data]
                
                # Query ruck sessions separately
                sessions_query = supabase.table('ruck_session').select(
                    'id, user_id, power_points, distance_km, completed_at, '
                    'elevation_gain_m, calories_burned'
                ).in_('user_id', user_ids)
                
                sessions_response = sessions_query.execute()
                logger.info(f"[DEBUG] My-rank manual sessions query returned: {len(sessions_response.data)} sessions")
                
                # Group sessions by user_id
                sessions_by_user = {}
                for session in sessions_response.data:
                    user_id = session['user_id']
                    if user_id not in sessions_by_user:
                        sessions_by_user[user_id] = []
                    sessions_by_user[user_id].append(session)
                
                # Attach sessions to users
                for user in response.data:
                    user['ruck_session'] = sessions_by_user.get(user['id'], [])
                
                logger.info(f"[DEBUG] My-rank manual approach complete - users now have ruck_session data")
            
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
                        stats['distanceKm'] += ruck.get('distance_km') or 0.0
                        stats['elevationGainMeters'] += ruck.get('elevation_gain_m') or 0.0
                        stats['caloriesBurned'] += ruck.get('calories_burned') or 0
                        stats['powerPoints'] += ruck.get('power_points') or 0.0
            
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
