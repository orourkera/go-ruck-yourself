"""
Leaderboard API endpoints for RuckBuddy
Well I'll be jiggered! This here's the leaderboard API, slicker than a greased pig
"""

import logging
from datetime import datetime, timedelta, timezone
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
        try:
            # Get authenticated user (optional for browse mode)
            current_user_id = g.user.id if hasattr(g, 'user') and g.user else None

            # Parse query parameters - match frontend default
            sort_by = request.args.get('sortBy', 'distance')
            ascending = request.args.get('ascending', 'false').lower() == 'true'
            # Always enforce pagination to prevent memory issues
            _limit_param = request.args.get('limit')
            limit = min(int(_limit_param), 100) if _limit_param is not None else 100  # Default to 100
            offset = int(request.args.get('offset', 0))
            search = request.args.get('search', '').strip()
            time_period = request.args.get('timePeriod', 'all_time')

            # Validate sort_by parameter
            valid_sorts = ['powerPoints', 'rucks', 'distance', 'elevation', 'calories']
            if sort_by not in valid_sorts:
                sort_by = 'powerPoints'

            # Build cache key with enforced pagination
            cache_key = f"leaderboard:{sort_by}:{ascending}:{limit}:{offset}:{search}:{time_period}:browse"
            cache_service = get_cache_service()

            # ALWAYS fetch active ruckers count using admin client (don't cache this, it changes frequently)
            # Use admin client to bypass RLS and see ALL active sessions
            active_ruckers_count = 0
            try:
                from datetime import datetime, timezone, timedelta
                admin_client = get_supabase_admin_client()

                # Query for all sessions that are in_progress or paused
                # Also get started_at to filter out stale sessions
                active_sessions_response = admin_client.table('ruck_session') \
                    .select('id, user_id, started_at, status') \
                    .in_('status', ['in_progress', 'paused']) \
                    .execute()

                if active_sessions_response.data:
                    # Count unique users with active sessions that started within last 24 hours
                    # (to avoid counting stale sessions that auto-complete job hasn't cleaned up yet)
                    active_user_ids = set()
                    cutoff_time = datetime.now(timezone.utc) - timedelta(hours=24)

                    for session in active_sessions_response.data:
                        if session.get('user_id') and session.get('started_at'):
                            try:
                                started_at_str = session['started_at']
                                if started_at_str.endswith('Z'):
                                    started_at = datetime.fromisoformat(started_at_str.replace('Z', '+00:00'))
                                elif '+' in started_at_str:
                                    started_at = datetime.fromisoformat(started_at_str)
                                else:
                                    started_at = datetime.fromisoformat(started_at_str + '+00:00')

                                # Only count if session started within last 24 hours
                                if started_at > cutoff_time:
                                    active_user_ids.add(session['user_id'])
                            except (ValueError, AttributeError) as e:
                                logger.warning(f"[LEADERBOARD] Failed to parse started_at for session {session.get('id')}: {e}")
                                continue

                    active_ruckers_count = len(active_user_ids)
                    logger.info(f"[LEADERBOARD] Found {active_ruckers_count} active ruckers across entire system (started within 24h)")
            except Exception as e:
                logger.error(f"[LEADERBOARD] Failed to count active ruckers: {e}")
                active_ruckers_count = 0

            # Use admin client for browse mode, authenticated for logged-in users (for leaderboard data)
            if current_user_id:
                supabase: Client = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            else:
                supabase: Client = get_supabase_admin_client()
            logger.debug(f"Using authenticated client with RLS for leaderboard data: {type(supabase)}")

            # Try to get leaderboard data from cache first (cache for 5 minutes)
            cached_result = cache_service.get(cache_key)
            if cached_result:
                logger.debug(f"Returning cached leaderboard data for key: {cache_key}")
                # Update the cached result with fresh active ruckers count
                cached_result['activeRuckersCount'] = active_ruckers_count
                return cached_result

            # Build the query - different approach for rucking_now vs other time periods
            if time_period == 'rucking_now':
                # For rucking_now, query active sessions and join users
                # This ensures we only get users who are currently rucking
                from datetime import datetime, timezone, timedelta

                # Get active sessions from last 24 hours
                cutoff = (datetime.now(timezone.utc) - timedelta(hours=24)).isoformat()

                # Query sessions that are in_progress/paused and started within 24h
                sessions_query = supabase.table('ruck_session') \
                    .select('*, user:user_id(id, username, avatar_url, gender, allow_ruck_sharing)') \
                    .in_('status', ['in_progress', 'paused']) \
                    .gte('started_at', cutoff)

                if search:
                    # For search, we need to filter on the joined user table - not directly supported
                    # So we'll filter after fetching
                    pass

                response = sessions_query.execute()

                logger.info(f"[LEADERBOARD] rucking_now query returned {len(response.data) if response.data else 0} sessions")

                # Filter out users who disabled sharing and apply search
                filtered_data = []
                for session in response.data if response.data else []:
                    logger.debug(f"[LEADERBOARD] Processing session {session.get('id')}, user data: {session.get('user')}")
                    user_data = session.get('user')
                    if user_data and user_data.get('allow_ruck_sharing'):
                        if search and search.lower() not in user_data.get('username', '').lower():
                            continue
                        # Transform to match expected format
                        user_id = user_data['id']
                        # Check if we already have this user
                        existing = next((u for u in filtered_data if u['id'] == user_id), None)
                        if not existing:
                            filtered_data.append({
                                'id': user_id,
                                'username': user_data['username'],
                                'avatar_url': user_data.get('avatar_url'),
                                'gender': user_data.get('gender'),
                                'ruck_session': [session]
                            })
                        else:
                            existing['ruck_session'].append(session)

                response.data = filtered_data
            else:
                # For other time periods, use the original query approach
                query = (
                    supabase.table('user').select(
                        '''
                        id,
                        username,
                        avatar_url,
                        gender,
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
            
            # Execute the query (skip for rucking_now since we already executed it)
            if time_period != 'rucking_now':
                logger.debug("Executing leaderboard query with admin client...")
                logger.debug(f"Query object type: {type(query)}")
                try:
                    response = query.execute()
                    logger.debug(f"Query executed successfully, response type: {type(response)}")

                    # Check if embed worked
                    has_ruck_session_data = False
                    if response.data and len(response.data) > 0:
                        first_user = response.data[0]
                        has_ruck_session_data = 'ruck_session' in first_user and first_user['ruck_session'] is not None

                    # If embed failed, fall back to manual approach (and clear any partial embed data)
                    if not has_ruck_session_data:
                        # Clear any partial embedded data to prevent double counting
                        for user in response.data:
                            user['ruck_session'] = []
                        logger.debug("Embed failed, using manual approach")
                    
                    # Get user IDs for manual session query
                    user_ids = [user['id'] for user in response.data]
                    
                    # Query ruck sessions in chunks with per-user limits to prevent memory explosion  
                    sessions_data = []
                    for user_id_chunk in [user_ids[i:i+50] for i in range(0, len(user_ids), 50)]:
                        sessions_query = supabase.table('ruck_session').select(
                            'id, user_id, distance_km, elevation_gain_m, calories_burned, '
                            'power_points, completed_at, started_at, status'
                        ).in_('user_id', user_id_chunk)
                        
                        # Apply time period filter
                        if time_period == 'last_7_days':
                            cutoff_date = (datetime.now(timezone.utc) - timedelta(days=7)).isoformat()
                            sessions_query = sessions_query.gte('completed_at', cutoff_date)
                        elif time_period == 'last_30_days':
                            cutoff_date = (datetime.now(timezone.utc) - timedelta(days=30)).isoformat()
                            sessions_query = sessions_query.gte('completed_at', cutoff_date)
                        elif time_period == 'rucking_now':
                            sessions_query = sessions_query.in_('status', ['in_progress', 'paused']).is_('completed_at', None)
                        
                        # Limit sessions per user to max 100 recent sessions
                        sessions_query = sessions_query.order('completed_at', desc=True).limit(min(len(user_id_chunk) * 100, 1000))
                        
                        chunk_response = sessions_query.execute()
                        sessions_data.extend(chunk_response.data)
                    
                    # Create combined response object
                    sessions_response = type('Response', (), {'data': sessions_data})()
                    logger.debug(f"Chunked sessions query returned: {len(sessions_data)} sessions")
                    
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
                    
                    logger.debug("Manual approach complete - users now have ruck_session data")
                
                    logger.debug(f"Response data count: {len(response.data) if response.data else 0}")
                except Exception as e:
                    logger.error(f"Query execution failed: {str(e)}")
                    logger.error(f"Query error type: {type(e)}")
                    return {'users': [], 'total': 0, 'hasMore': False, 'activeRuckersCount': 0}
            
            if not response.data:
                return {'users': [], 'total': 0, 'activeRuckersCount': active_ruckers_count}

            # Process and aggregate user data for the current page
            # (active_ruckers_count already fetched above before cache check)
            user_stats = {}

            for user_data in response.data:
                user_id = user_data['id']
                
                if user_id not in user_stats:
                    # Get ruck sessions safely (might be missing if user has no sessions)
                    ruck_sessions = user_data.get('ruck_session', [])

                    # Check if THIS user is currently rucking (for display purposes)
                    is_currently_rucking = False
                    for ruck in ruck_sessions:
                        if ruck.get('status') in ['in_progress', 'paused']:
                            is_currently_rucking = True
                            break

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
                        'gender': user_data.get('gender'),
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
                
                # Process ruck sessions based on time period
                for ruck in user_data.get('ruck_session', []):
                    include_ruck = False
                    
                    # Handle rucking_now filter - only count active sessions
                    if time_period == 'rucking_now':
                        if ruck.get('status') in ['in_progress', 'paused'] and not ruck.get('completed_at'):
                            include_ruck = True
                    else:
                        # For other filters, only process completed rucks
                        if ruck.get('completed_at'):
                            include_ruck = True
                            if time_period != 'all_time':
                                completed_at = ruck.get('completed_at')
                                if completed_at:
                                    try:
                                        # Parse completion date
                                        if completed_at.endswith('Z'):
                                            completion_time = datetime.fromisoformat(completed_at.replace('Z', '+00:00'))
                                        elif '+' in completed_at:
                                            completion_time = datetime.fromisoformat(completed_at)
                                        else:
                                            completion_time = datetime.fromisoformat(completed_at + '+00:00')
                                        
                                        # Check if within time period
                                        if time_period == 'last_7_days':
                                            cutoff_date = datetime.now(timezone.utc) - timedelta(days=7)
                                            include_ruck = completion_time >= cutoff_date
                                        elif time_period == 'last_30_days':
                                            cutoff_date = datetime.now(timezone.utc) - timedelta(days=30)
                                            include_ruck = completion_time >= cutoff_date
                                    except (ValueError, AttributeError):
                                        # If we can't parse the date, exclude it to be safe
                                        include_ruck = False
                    
                    if include_ruck:
                        stats = user_stats[user_id]['stats']
                        # For rucking_now filter, only count if there's actual progress
                        if time_period == 'rucking_now':
                            # For active sessions, show current progress
                            stats['rucks'] += 1
                            # Active sessions should have current progress data
                            stats['distanceKm'] += ruck.get('distance_km') or 0.0
                            stats['elevationGainMeters'] += ruck.get('elevation_gain_m') or 0.0
                            stats['caloriesBurned'] += ruck.get('calories_burned') or 0
                            stats['powerPoints'] += ruck.get('power_points') or 0.0
                        else:
                            # For completed rucks, add all stats
                            stats['rucks'] += 1
                            stats['distanceKm'] += ruck.get('distance_km') or 0.0
                            stats['elevationGainMeters'] += ruck.get('elevation_gain_m') or 0.0
                            stats['caloriesBurned'] += ruck.get('calories_burned') or 0
                            stats['powerPoints'] += ruck.get('power_points') or 0.0
            
            # Filter out users with no meaningful stats - consistent across all time periods
            # Require either completed rucks OR currently active with progress
            active_user_stats = {}
            for user_id, stats in user_stats.items():
                user_has_meaningful_data = False
                
                if time_period == 'rucking_now':
                    # For live view: show users currently rucking with some progress OR completed sessions
                    if (stats['isCurrentlyRucking'] and 
                        (stats['stats']['distanceKm'] > 0.01 or stats['stats']['powerPoints'] > 0)) or \
                       stats['stats']['rucks'] > 0:
                        user_has_meaningful_data = True
                else:
                    # For historical views: require completed sessions with meaningful stats
                    if (stats['stats']['rucks'] > 0 and 
                        (stats['stats']['distanceKm'] > 0.01 or 
                         stats['stats']['powerPoints'] > 0 or 
                         stats['stats']['elevationGainMeters'] > 1)):
                        user_has_meaningful_data = True
                
                if user_has_meaningful_data:
                    active_user_stats[user_id] = stats
            
            logger.debug(f"Filtered leaderboard: {len(user_stats)} total users -> {len(active_user_stats)} active ruckers")
            
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
            
            # Add rank to each user BEFORE pagination
            for i, user in enumerate(users_list):
                user['rank'] = i + 1
            
            # Apply pagination after ranking
            total_users = len(users_list)
            start = max(offset, 0)
            end = max(start + limit, 0)
            paged_users = users_list[start:end]
            has_more = end < total_users

            result = {
                'users': paged_users,
                'total': total_users,
                'hasMore': has_more,
                'activeRuckersCount': active_ruckers_count
            }
            
            # Cache the result for 60 seconds to align with frontend refresh timing
            cache_service.set(cache_key, result, expire_seconds=60)
            
            logger.debug(f"Leaderboard query successful: {len(users_list)} users returned")
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
            sort_by = request.args.get('sortBy', 'distance')
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
            
            # Use authenticated client with proper RLS for security  
            supabase: Client = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            logger.debug(f"My-rank using authenticated client with RLS: {type(supabase)}")
            
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
            
            logger.debug(f"Executing my-rank query with admin client...")
            response = query.execute()
            logger.debug(f"My-rank query response count: {len(response.data) if response.data else 0}")
            
            if not response.data:
                return {'rank': None}
            
            # Check if embed worked for my-rank query too
            has_ruck_session_data = False
            if response.data and len(response.data) > 0:
                first_user = response.data[0]
                has_ruck_session_data = 'ruck_session' in first_user and first_user['ruck_session'] is not None
                logger.debug(f"My-rank first user has ruck_session data: {has_ruck_session_data}")
            
            # If embed failed, fall back to manual approach for my-rank too (clear partial data)
            if not has_ruck_session_data:
                # Clear any partial embedded data to prevent double counting
                for user in response.data:
                    user['ruck_session'] = []
                logger.debug("My-rank embed failed, using manual approach")
                
                # Get user IDs for manual session query
                user_ids = [user['id'] for user in response.data]

                if not user_ids:
                    logger.debug('My-rank manual fallback has no user IDs; returning empty rank')
                    return {'rank': None}

                # Query ruck sessions separately in manageable chunks to avoid PostgREST limits
                sessions_data = []
                chunk_size = 50
                for i in range(0, len(user_ids), chunk_size):
                    user_id_chunk = user_ids[i:i + chunk_size]

                    sessions_query = supabase.table('ruck_session').select(
                        'id, user_id, power_points, distance_km, completed_at, '
                        'elevation_gain_m, calories_burned, status, started_at, created_at'
                    ).in_('user_id', user_id_chunk)

                    try:
                        chunk_response = sessions_query.execute()
                        if chunk_response.data:
                            sessions_data.extend(chunk_response.data)
                        logger.debug(
                            "My-rank manual sessions chunk: %s users -> %s sessions",
                            len(user_id_chunk),
                            len(chunk_response.data) if chunk_response.data else 0,
                        )
                    except Exception as chunk_error:
                        logger.error(
                            "My-rank sessions chunk query failed for %s users: %s",
                            len(user_id_chunk),
                            chunk_error,
                        )

                sessions_response = type('Response', (), {'data': sessions_data})()
                logger.debug(
                    "My-rank manual sessions query returned: %s sessions",
                    len(sessions_response.data),
                )
                
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
                
                logger.debug(f"My-rank manual approach complete - users now have ruck_session data")
            
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
            
            # Cache the result for 60 seconds to align with leaderboard cache
            cache_service.set(cache_key, user_rank, expire_seconds=60)
            
            return {'rank': user_rank}
            
        except Exception as e:
            logger.error(f"Error fetching user rank: {str(e)}", exc_info=True)
            return {'error': 'Failed to fetch user rank'}, 500
