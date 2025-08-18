from flask import Blueprint, request, jsonify, g
from RuckTracker.utils.api_response import api_response, api_error
from RuckTracker.supabase_client import get_supabase_client
from RuckTracker.services.push_notification_service import PushNotificationService, get_user_device_tokens
from RuckTracker.services.redis_cache_service import cache_get, cache_set, cache_delete_pattern
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
        supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))

        cache_key = f'user_profile:{user_id}:{current_user_id or "anon"}'
        cached_profile = cache_get(cache_key)
        if cached_profile:
            logger.info(f"[PROFILE_PERF] Cache hit for profile {user_id}")
            return api_response(cached_profile)

        query_start = time.time()
        profile_resp = supabase.rpc('get_user_profile', {'p_user_id': str(user_id), 'p_current_user_id': str(current_user_id) if current_user_id else None}).execute()
        query_time = time.time() - query_start
        logger.info(f"[PROFILE_PERF] Profile RPC took {query_time*1000:.2f}ms")

        if not profile_resp.data:
            return api_error('User not found', status_code=404)

        profile_data = profile_resp.data[0]

        is_own_profile = current_user_id is not None and str(current_user_id) == str(profile_data['id'])
        is_private = profile_data.get('is_profile_private', False) and not is_own_profile

        response = {
            'user': {
                'id': profile_data['id'],
                'username': profile_data['username'],
                'avatarUrl': profile_data.get('avatar_url'),
                'createdAt': profile_data['created_at'],
                'preferMetric': profile_data.get('prefer_metric', True),
                'isFollowing': profile_data.get('is_following', False),
                'isFollowedBy': profile_data.get('is_followed_by', False),
                'isOwnProfile': is_own_profile,
                'isPrivateProfile': profile_data.get('is_profile_private', False),
                'gender': profile_data.get('gender')
            },
            'stats': {},
            'clubs': None,
            'recentRucks': None
        }

        if not is_private:
            stats = {
                'totalRucks': profile_data.get('total_rucks', 0),
                'totalDistanceKm': profile_data.get('total_distance_km', 0.0),
                'totalDurationSeconds': profile_data.get('total_duration_seconds', 0),
                'totalElevationGainM': profile_data.get('total_elevation_gain_m', 0.0),
                'totalCaloriesBurned': profile_data.get('total_calories_burned', 0),
                'duelsWon': profile_data.get('duels_won', 0),
                'duelsLost': profile_data.get('duels_lost', 0),
                'eventsCompleted': profile_data.get('events_completed', 0),
                'followersCount': profile_data.get('followers_count', 0),
                'followingCount': profile_data.get('following_count', 0),
                'clubsCount': len(profile_data.get('clubs', []))
            }

            prefer_metric = profile_data.get('prefer_metric', True)
            if not prefer_metric and stats.get('totalDistanceKm') is not None:
                stats['totalDistanceMi'] = round(stats['totalDistanceKm'] * 0.621371, 2)

            response['stats'] = stats
            response['clubs'] = profile_data.get('clubs', [])
            response['recentRucks'] = profile_data.get('recent_rucks', [])

        cache_set(cache_key, response, 3600)

        total_time = time.time() - start_time
        logger.info(f"[PROFILE_PERF] get_public_profile: Completed in {total_time*1000:.2f}ms total")
        return api_response(response)
    except Exception as e:
        error_time = time.time() - start_time
        logger.error(f"[PROFILE_PERF] get_public_profile: ERROR after {error_time*1000:.2f}ms: {str(e)}")
        return api_error(str(e))

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
        return api_error(str(e))

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
        return api_error(str(e))

@users_bp.route('/<uuid:user_id>/follow', methods=['POST'])
def follow_user(user_id):
    try:
        current_user_id = g.user.id
        
        # Check if user is trying to follow themselves
        if str(current_user_id) == str(user_id):
            return api_error('Cannot follow yourself')
        
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
            return api_error('Cannot follow private profiles')
        
        # Check if already following
        supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
        existing_follow = supabase.table('user_follows').select('id').eq('follower_id', str(current_user_id)).eq('followed_id', str(user_id)).execute()
        if existing_follow.data:
            return api_error('Already following this user')
        
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
            return api_error('Failed to follow')
        except Exception as insert_error:
            # Log the exact error for debugging
            print(f"[ERROR] Follow insert failed: {str(insert_error)}")
            # Check if it's an RLS policy error
            if 'policy' in str(insert_error).lower() or 'permission' in str(insert_error).lower():
                return api_error('Permission denied - this may be due to profile privacy settings')
            raise insert_error
    except Exception as e:
        print(f"[ERROR] Follow endpoint error: {str(e)}")
        return api_error(str(e))

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
        return api_error(str(e))

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
        return api_error(str(e))

@users_bp.route('/me/privacy', methods=['PATCH'])
def update_privacy():
    """Update the current user's profile privacy setting."""
    try:
        data = request.get_json()
        if not isinstance(data, dict) or 'isPrivateProfile' not in data:
            return api_error('Invalid request: missing isPrivateProfile')
        is_private = data['isPrivateProfile']
        if not isinstance(is_private, bool):
            return api_error('isPrivateProfile must be boolean')

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
        return api_error('Failed to update privacy')
    except Exception as e:
        return api_error(str(e)) 
