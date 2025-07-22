from flask import Blueprint, request, jsonify, g
from RuckTracker.utils.api_response import api_response, api_error
from RuckTracker.supabase_client import get_supabase_client
from RuckTracker.services.push_notification_service import PushNotificationService, get_user_device_tokens
from RuckTracker.services.redis_cache_service import cache_get, cache_set
import logging

logger = logging.getLogger(__name__)

# Initialize push notification service
push_service = PushNotificationService()

users_bp = Blueprint('users', __name__)

@users_bp.route('/<uuid:user_id>/profile', methods=['GET'])
def get_public_profile(user_id):
    import time
    start_time = time.time()
    try:
        current_user_id = g.user.id if hasattr(g, 'user') and g.user else None
        logger.info(f"[PROFILE_PERF] get_public_profile: Started for user {user_id}, current_user: {current_user_id}")
        # Fetch basic profile fields. Some older databases may not yet have avatar_url or is_profile_private columns
        try:
            user_res = get_supabase_client().table('user').select('id, username, avatar_url, created_at, prefer_metric, is_profile_private, gender').eq('id', str(user_id)).single().execute()
        except Exception as fetch_err:
            # If the requested columns do not exist (e.g. column does not exist error), retry with a reduced column list
            err_msg = str(fetch_err)
            if '42703' in err_msg or 'column' in err_msg and ('avatar_url' in err_msg or 'is_profile_private' in err_msg):
                user_res = get_supabase_client().table('user').select('id, username, created_at').eq('id', str(user_id)).single().execute()
            else:
                raise

        if not user_res.data:
            return api_error('User not found', status_code=404)
        user = user_res.data
        is_own_profile = str(current_user_id) == str(user_id)
        is_private = user.get('is_profile_private', False) and not is_own_profile
        is_following = False
        is_followed_by = False
        followers_count = 0
        following_count = 0
        
        # Optimized: Batch all follow-related queries with PostgreSQL count()
        follow_start = time.time()
        supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
        
        try:
            # Use Supabase SELECT count() - only select id column for maximum efficiency
            followers_count_res = supabase.table('user_follows').select('id', count='exact').eq('followed_id', str(user_id)).execute()
            followers_count = followers_count_res.count or 0
            
            following_count_res = supabase.table('user_follows').select('id', count='exact').eq('follower_id', str(user_id)).execute()
            following_count = following_count_res.count or 0
            
        except Exception as e:
            logger.warning(f"[PROFILE_PERF] Count queries failed: {e}")
            followers_count = 0
            following_count = 0
        
        # Check follow relationships only if user is logged in
        if current_user_id:
            try:
                follow_res = supabase.table('user_follows').select('id').eq('follower_id', str(current_user_id)).eq('followed_id', str(user_id)).execute()
                is_following = bool(follow_res.data)
                
                followed_by_res = supabase.table('user_follows').select('id').eq('follower_id', str(user_id)).eq('followed_id', str(current_user_id)).execute()
                is_followed_by = bool(followed_by_res.data)
            except Exception:
                is_following = False
                is_followed_by = False
        
        follow_time = time.time() - follow_start
        logger.info(f"[PROFILE_PERF] All follow queries took {follow_time*1000:.2f}ms (followers: {followers_count}, following: {following_count})")
        response = {
            'user': {
                'id': user['id'],
                'username': user['username'],
                'avatarUrl': user.get('avatar_url'),
                'createdAt': user['created_at'],
                'preferMetric': user.get('prefer_metric', True),
                'isFollowing': is_following,
                'isFollowedBy': is_followed_by,
                'isOwnProfile': is_own_profile,
                'isPrivateProfile': user.get('is_profile_private', False),
                'gender': user.get('gender')
            },
            'stats': {},
            'clubs': None,
            'recentRucks': None
        }
        if not is_private:

            # Calculate stats directly from ruck_session table instead of user_profile_stats
            try:
                cache_key = f"user_lifetime_stats:{user_id}"
                cached_stats = cache_get(cache_key)
                if cached_stats:
                    total_rucks = cached_stats['total_rucks']
                    total_distance_km = cached_stats['total_distance_km']
                    total_duration_seconds = cached_stats['total_duration_seconds']
                    total_elevation_gain_m = cached_stats['total_elevation_gain_m']
                    total_calories_burned = cached_stats['total_calories_burned']
                    logger.info(f"[PROFILE_PERF] Using cached stats for user {user_id}")
                else:
                    sessions_start = time.time()
                    # Get completed sessions for this user
                    sessions_res = (
                        get_supabase_client()
                        .table('ruck_session')
                        .select('distance_km, duration_seconds, calories_burned, elevation_gain_m, power_points')
                        .eq('user_id', str(user_id))
                        .eq('status', 'completed')
                        .execute()
                    )
                    
                    sessions = sessions_res.data or []
                    sessions_time = time.time() - sessions_start
                    logger.info(f"[PROFILE_PERF] Sessions query took {sessions_time*1000:.2f}ms, found {len(sessions)} sessions")
                    
                    # Calculate aggregated stats from sessions
                    total_rucks = len(sessions)
                    total_distance_km = sum(s.get('distance_km', 0) or 0 for s in sessions)
                    total_duration_seconds = sum(s.get('duration_seconds', 0) or 0 for s in sessions)
                    total_elevation_gain_m = sum(s.get('elevation_gain_m', 0) or 0 for s in sessions)
                    total_calories_burned = sum(s.get('calories_burned', 0) or 0 for s in sessions)
                    
                    # Get duel stats
                    duels_won = 0
                    duels_lost = 0
                    try:
                        duel_stats_res = (
                            get_supabase_client()
                            .table('user_duel_stats')
                            .select('duels_won, duels_lost')
                            .eq('user_id', str(user_id))
                            .execute()
                        )
                        if duel_stats_res.data:
                            duels_won = duel_stats_res.data[0].get('duels_won', 0)
                            duels_lost = duel_stats_res.data[0].get('duels_lost', 0)
                    except Exception:
                        pass
                    
                    # Convert to camelCase for frontend
                    stats = {
                        'totalRucks': total_rucks,
                        'totalDistanceKm': total_distance_km,
                        'totalDurationSeconds': total_duration_seconds,
                        'totalElevationGainM': total_elevation_gain_m,
                        'totalCaloriesBurned': total_calories_burned,
                        'duelsWon': duels_won,
                        'duelsLost': duels_lost,
                        'eventsCompleted': 0,  # TODO: Implement when events are added
                        'followersCount': followers_count,
                        'followingCount': following_count,
                    }
                    
                    # Provide distance in miles if user prefers imperial
                    prefer_metric = user.get('prefer_metric', True)
                    if not prefer_metric and stats.get('totalDistanceKm') is not None:
                        stats['totalDistanceMi'] = round(stats['totalDistanceKm'] * 0.621371, 2)
                    
                    response['stats'] = stats
                    cache_set(cache_key, {
                        'total_rucks': total_rucks,
                        'total_distance_km': total_distance_km,
                        'total_duration_seconds': total_duration_seconds,
                        'total_elevation_gain_m': total_elevation_gain_m,
                        'total_calories_burned': total_calories_burned
                    }, 3600)
            except Exception as e:
                print(f"[ERROR] Failed to calculate stats for user {user_id}: {e}")
                response['stats'] = {
                    'totalRucks': 0,
                    'totalDistanceKm': 0,
                    'totalDurationSeconds': 0,
                    'totalElevationGainM': 0,
                    'totalCaloriesBurned': 0,
                    'duelsWon': 0,
                    'duelsLost': 0,
                    'eventsCompleted': 0,
                    'followersCount': followers_count,
                    'followingCount': following_count,
                }

            # Fetch clubs the user belongs to.
            # Prefer the correct 'club_memberships' table. If the table or relationship is missing
            # simply return an empty list instead of falling back to the legacy name that is now
            # known to cause "could not find relationship" (PGRST200) errors.
            try:
                admin_client = get_supabase_client()
                # Now that duplicate foreign key is removed, we can use simple syntax
                clubs_res = admin_client.from_('club_memberships').select('clubs(*)').eq('user_id', str(user_id)).execute()
                response['clubs'] = [row['clubs'] for row in clubs_res.data] if clubs_res.data else []
                # Add clubsCount into stats dict
                response['stats']['clubsCount'] = len(response['clubs'])
            except Exception as clubs_err:
                # Log but do not fail the entire profile request – just return no clubs.
                print(f"[WARN] get_public_profile: failed to fetch clubs for user {user_id}: {clubs_err}")
                response['clubs'] = []
                response['stats']['clubsCount'] = 0
            try:
                cache_key = f"user_recent_rucks:{user_id}"
                cached_recent = cache_get(cache_key)
                if cached_recent:
                    response['recentRucks'] = cached_recent
                    logger.info(f"[PROFILE_PERF] Using cached recent rucks for user {user_id}")
                else:
                    rucks_res = (
                        get_supabase_client()
                        .table('ruck_session')
                        .select('*')
                        .eq('user_id', str(user_id))
                        .eq('status', 'completed')
                        .order('completed_at', desc=True)
                        .limit(5)
                        .execute()
                    )
                    response['recentRucks'] = rucks_res.data or []
                    cache_set(cache_key, response['recentRucks'], 3600)
            except Exception as e:
                print(f"[ERROR] Failed to fetch recent rucks for user {user_id}: {e}")
                response['recentRucks'] = []
        total_time = time.time() - start_time
        logger.info(f"[PROFILE_PERF] get_public_profile: Completed in {total_time*1000:.2f}ms total")
        return api_response(response)
    except Exception as e:
        error_time = time.time() - start_time
        logger.error(f"[PROFILE_PERF] get_public_profile: ERROR after {error_time*1000:.2f}ms: {str(e)}")
        return api_error(str(e), status_code=500)

@users_bp.route('/<uuid:user_id>/followers', methods=['GET'])
def get_followers(user_id):
    try:
        current_user_id = g.user.id if hasattr(g, 'user') and g.user else None
        page = int(request.args.get('page', 1))
        per_page = 20
        offset = (page - 1) * per_page
        followers_res = get_supabase_client().table('user_follows').select('follower_id, created_at, user:follower_id(username, avatar_url)').eq('followed_id', user_id).order('created_at', desc=True).range(offset, offset + per_page - 1).execute()
        followers = []
        for f in followers_res.data or []:
            is_following_back = False
            if current_user_id:
                check_res = get_supabase_client().table('user_follows').select('id').eq('follower_id', current_user_id).eq('followed_id', f['follower_id']).execute()
                is_following_back = bool(check_res.data)
            followers.append({
                'id': f['follower_id'],
                'username': f['user']['username'],
                'avatarUrl': f['user']['avatar_url'],
                'isFollowing': is_following_back,
                'followedAt': f['created_at']
            })
        has_more = len(followers) == per_page
        return api_response({'followers': followers, 'pagination': {'page': page, 'hasMore': has_more}})
    except Exception as e:
        return api_error(str(e), status_code=500)

@users_bp.route('/<uuid:user_id>/following', methods=['GET'])
def get_following(user_id):
    try:
        current_user_id = g.user.id if hasattr(g, 'user') and g.user else None
        page = int(request.args.get('page', 1))
        per_page = 20
        offset = (page - 1) * per_page
        following_res = get_supabase_client().table('user_follows').select('followed_id, created_at, user:followed_id(username, avatar_url)').eq('follower_id', user_id).order('created_at', desc=True).range(offset, offset + per_page - 1).execute()
        following = []
        for f in following_res.data or []:
            # For the "following" list, we need to check if the current user is following this person
            # If viewing own following list, isFollowing should be true (since they're in the following list)
            # If viewing someone else's following list, check if current user follows this person
            is_following = False
            if current_user_id:
                if str(current_user_id) == str(user_id):
                    # Viewing own following list - by definition, we're following all these people
                    is_following = True
                else:
                    # Viewing someone else's following list - check if current user follows this person
                    check_res = get_supabase_client().table('user_follows').select('id').eq('follower_id', current_user_id).eq('followed_id', f['followed_id']).execute()
                    is_following = bool(check_res.data)
            
            following.append({
                'id': f['followed_id'],
                'username': f['user']['username'],
                'avatarUrl': f['user']['avatar_url'],
                'isFollowing': is_following,
                'followedAt': f['created_at']
            })
        has_more = len(following) == per_page
        return api_response({'following': following, 'pagination': {'page': page, 'hasMore': has_more}})
    except Exception as e:
        return api_error(str(e), status_code=500)

@users_bp.route('/<uuid:user_id>/follow', methods=['POST'])
def follow_user(user_id):
    try:
        current_user_id = g.user.id
        
        # Check if user is trying to follow themselves
        if str(current_user_id) == str(user_id):
            return api_error('Cannot follow yourself', status_code=400)
        
        # Check if target user exists and if their profile is private
        # Handle both column names in case of migration timing issues
        try:
            user_res = get_supabase_client().table('user').select('id, is_profile_private').eq('id', str(user_id)).single().execute()
        except Exception as e:
            # If is_profile_private column doesn't exist, try the old column name
            if 'column' in str(e).lower() and 'is_profile_private' in str(e):
                try:
                    user_res = get_supabase_client().table('user').select('id, is_private_profile').eq('id', str(user_id)).single().execute()
                    # Map old column name to new one for consistency
                    if user_res.data:
                        user_res.data['is_profile_private'] = user_res.data.get('is_private_profile', False)
                except Exception:
                    # If both column names fail, assume user exists but privacy column is missing (default to public)
                    user_res = get_supabase_client().table('user').select('id').eq('id', str(user_id)).single().execute()
                    if user_res.data:
                        user_res.data['is_profile_private'] = False
            else:
                raise e
        
        if not user_res.data:
            return api_error('User not found', status_code=404)
        
        target_user = user_res.data
        if target_user.get('is_profile_private', False):
            return api_error('Cannot follow private profiles', status_code=403)
        
        # Check if already following
        supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
        existing_follow = supabase.table('user_follows').select('id').eq('follower_id', str(current_user_id)).eq('followed_id', str(user_id)).execute()
        if existing_follow.data:
            return api_error('Already following this user', status_code=400)
        
        # Insert the follow relationship
        try:
            # Use authenticated client to respect RLS policies
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            insert_res = supabase.table('user_follows').insert({'follower_id': str(current_user_id), 'followed_id': str(user_id)}).execute()
            if insert_res.data:
                # Send push notification to the followed user
                try:
                    logger.info(f"🔔 PUSH NOTIFICATION: Starting new follower push notification for user {user_id}")
                    
                    # Get follower's username
                    follower_response = supabase.table('user').select('username').eq('id', str(current_user_id)).execute()
                    follower_name = follower_response.data[0]['username'] if follower_response.data else 'Someone'
                    
                    logger.info(f"🔔 PUSH NOTIFICATION: Sending to followed user {user_id}, from follower {follower_name}")
                    
                    # Get device tokens for the followed user
                    device_tokens = get_user_device_tokens([str(user_id)])
                    logger.info(f"🔔 PUSH NOTIFICATION: Retrieved {len(device_tokens)} device tokens: {device_tokens}")
                    
                    if device_tokens:
                        logger.info(f"🔔 PUSH NOTIFICATION: Calling send_new_follower_notification...")
                        result = push_service.send_new_follower_notification(
                            device_tokens=device_tokens,
                            follower_name=follower_name,
                            follower_id=str(current_user_id)
                        )
                        logger.info(f"🔔 PUSH NOTIFICATION: New follower notification sent successfully, result: {result}")
                    else:
                        logger.warning(f"🔔 PUSH NOTIFICATION: No device tokens found for user {user_id}")
                        
                except Exception as e:
                    logger.error(f"🔔 PUSH NOTIFICATION: Failed to send new follower notification: {e}", exc_info=True)
                    # Don't fail the follow if notification fails
                
                count_res = get_supabase_client().table('user_follows').select('id').eq('followed_id', str(user_id)).execute()
                followers_count = len(count_res.data) if count_res.data else 0
                return jsonify({'success': True, 'isFollowing': True, 'followersCount': followers_count})
            return api_error('Failed to follow', status_code=400)
        except Exception as insert_error:
            # Log the exact error for debugging
            print(f"[ERROR] Follow insert failed: {str(insert_error)}")
            # Check if it's an RLS policy error
            if 'policy' in str(insert_error).lower() or 'permission' in str(insert_error).lower():
                return api_error('Permission denied - this may be due to profile privacy settings', status_code=403)
            raise insert_error
    except Exception as e:
        print(f"[ERROR] Follow endpoint error: {str(e)}")
        return api_error(str(e), status_code=500)

@users_bp.route('/<uuid:user_id>/follow', methods=['DELETE'])
def unfollow_user(user_id):
    try:
        current_user_id = g.user.id
        # Use authenticated client to respect RLS policies
        supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
        delete_res = supabase.table('user_follows').delete().eq('follower_id', str(current_user_id)).eq('followed_id', str(user_id)).execute()
        count_res = get_supabase_client().table('user_follows').select('id').eq('followed_id', str(user_id)).execute()
        followers_count = len(count_res.data) if count_res.data else 0
        return jsonify({'success': True, 'isFollowing': False, 'followersCount': followers_count})
    except Exception as e:
        return api_error(str(e), status_code=500)

@users_bp.route('/social/following-feed', methods=['GET'])
def get_following_feed():
    try:
        current_user_id = g.user.id
        page = int(request.args.get('page', 1))
        per_page = 20
        offset = (page - 1) * per_page
        # Get followed users
        followed_res = get_supabase_client().table('user_follows').select('followed_id').eq('follower_id', current_user_id).execute()
        followed_ids = [f['followed_id'] for f in followed_res.data] if followed_res.data else []
        if not followed_ids: return api_response({'rucks': [], 'pagination': {'page': page, 'hasMore': False}})
        # Get recent rucks from followed users
        rucks_res = get_supabase_client().table('ruck_session').select('*').in_('user_id', followed_ids).order('end_time', desc=True).range(offset, offset + per_page - 1).execute()
        has_more = len(rucks_res.data or []) == per_page
        return api_response({'rucks': rucks_res.data or [], 'pagination': {'page': page, 'hasMore': has_more}})
    except Exception as e:
        return api_error(str(e), status_code=500)

@users_bp.route('/me/privacy', methods=['PATCH'])
def update_privacy():
    """Update the current user's profile privacy setting."""
    try:
        data = request.get_json()
        if not isinstance(data, dict) or 'isPrivateProfile' not in data:
            return api_error('Invalid request: missing isPrivateProfile', status_code=400)
        is_private = data['isPrivateProfile']
        if not isinstance(is_private, bool):
            return api_error('isPrivateProfile must be boolean', status_code=400)

        current_user_id = g.user.id

        # Try to update the correct column name first. If that fails because the
        # column does not exist (older DB), fall back to the legacy name.
        try:
            update_res = (
                get_supabase_client()
                .table('user')
                .update({'is_profile_private': is_private})
                .eq('id', current_user_id)
                .execute()
            )
        except Exception as upd_err:
            if '42703' in str(upd_err) or ('column' in str(upd_err) and 'is_profile_private' in str(upd_err)):
                update_res = (
                    get_supabase_client()
                    .table('user')
                    .update({'is_private_profile': is_private})
                    .eq('id', current_user_id)
                    .execute()
                )
            else:
                raise

        if update_res.data:
            return api_response({'success': True, 'isPrivateProfile': is_private})
        return api_error('Failed to update privacy', status_code=400)
    except Exception as e:
        return api_error(str(e), status_code=500) 
