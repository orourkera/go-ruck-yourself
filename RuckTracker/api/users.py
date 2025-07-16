from flask import Blueprint, request, jsonify, g
from RuckTracker.utils.api_response import api_response, api_error
from RuckTracker.supabase_client import get_supabase_client

users_bp = Blueprint('users', __name__)

@users_bp.route('/<uuid:user_id>/profile', methods=['GET'])
def get_public_profile(user_id):
    try:
        current_user_id = g.current_user['id'] if 'current_user' in g else None
        # Fetch basic profile fields. Some older databases may not yet have avatar_url or is_profile_private columns
        try:
            user_res = get_supabase_client().table('user').select('id, username, avatar_url, created_at, is_profile_private').eq('id', user_id).single().execute()
        except Exception as fetch_err:
            # If the requested columns do not exist (e.g. column does not exist error), retry with a reduced column list
            err_msg = str(fetch_err)
            if '42703' in err_msg or 'column' in err_msg and ('avatar_url' in err_msg or 'is_profile_private' in err_msg):
                user_res = get_supabase_client().table('user').select('id, username, created_at').eq('id', user_id).single().execute()
            else:
                raise

        if not user_res.data:
            return api_error('User not found', status_code=404)
        user = user_res.data
        is_own_profile = current_user_id == user_id
        is_private = user['is_profile_private'] and not is_own_profile
        is_following = False
        is_followed_by = False
        if current_user_id:
            follow_res = get_supabase_client().table('user_follows').select('id').eq('follower_id', current_user_id).eq('followed_id', user_id).execute()
            is_following = bool(follow_res.data)
            followed_by_res = get_supabase_client().table('user_follows').select('id').eq('follower_id', user_id).eq('followed_id', current_user_id).execute()
            is_followed_by = bool(followed_by_res.data)
        response = {
            'user': {
                'id': user['id'],
                'username': user['username'],
                'avatarUrl': user.get('avatar_url'),
                'createdAt': user['created_at'],
                'isFollowing': is_following,
                'isFollowedBy': is_followed_by,
                'isPrivateProfile': user.get('is_profile_private', False)
            },
            'stats': None,
            'clubs': None,
            'recentRucks': None
        }
        if not is_private:
            stats_res = get_supabase_client().table('user_profile_stats').select('*').eq('user_id', user_id).execute()
            response['stats'] = stats_res.data[0] if stats_res.data else {}
            clubs_res = get_supabase_client().from_('club_members').select('clubs(*)').eq('user_id', user_id).execute()
            response['clubs'] = [cm['clubs'] for cm in clubs_res.data] if clubs_res.data else []
            rucks_res = get_supabase_client().table('ruck_sessions').select('*').eq('user_id', user_id).order('end_time', desc=True).limit(5).execute()
            response['recentRucks'] = rucks_res.data or []
        return api_response(response)
    except Exception as e:
        return api_error(str(e), status_code=500)

@users_bp.route('/<uuid:user_id>/followers', methods=['GET'])
def get_followers(user_id):
    try:
        current_user_id = g.current_user['id'] if 'current_user' in g else None
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
        current_user_id = g.current_user['id'] if 'current_user' in g else None
        page = int(request.args.get('page', 1))
        per_page = 20
        offset = (page - 1) * per_page
        following_res = get_supabase_client().table('user_follows').select('followed_id, created_at, user:followed_id(username, avatar_url)').eq('follower_id', user_id).order('created_at', desc=True).range(offset, offset + per_page - 1).execute()
        following = []
        for f in following_res.data or []:
            is_following_back = False
            if current_user_id:
                check_res = get_supabase_client().table('user_follows').select('id').eq('follower_id', f['followed_id']).eq('followed_id', current_user_id).execute()
                is_following_back = bool(check_res.data)
            following.append({
                'id': f['followed_id'],
                'username': f['user']['username'],
                'avatarUrl': f['user']['avatar_url'],
                'isFollowing': is_following_back,
                'followedAt': f['created_at']
            })
        has_more = len(following) == per_page
        return api_response({'following': following, 'pagination': {'page': page, 'hasMore': has_more}})
    except Exception as e:
        return api_error(str(e), status_code=500)

@users_bp.route('/<uuid:user_id>/follow', methods=['POST'])
def follow_user(user_id):
    try:
        current_user_id = g.current_user['id']
        insert_res = get_supabase_client().table('user_follows').insert({'follower_id': current_user_id, 'followed_id': user_id}).execute()
        if insert_res.data:
            count_res = get_supabase_client().table('user_follows').select('count(*)').eq('followed_id', user_id).execute()
            followers_count = count_res.data[0]['count'] if count_res.data else 0
            return api_response({'success': True, 'isFollowing': True, 'followersCount': followers_count})
        return api_error('Failed to follow', status_code=400)
    except Exception as e:
        return api_error(str(e), status_code=500)

@users_bp.route('/<uuid:user_id>/follow', methods=['DELETE'])
def unfollow_user(user_id):
    try:
        current_user_id = g.current_user['id']
        delete_res = get_supabase_client().table('user_follows').delete().eq('follower_id', current_user_id).eq('followed_id', user_id).execute()
        count_res = get_supabase_client().table('user_follows').select('count(*)').eq('followed_id', user_id).execute()
        followers_count = count_res.data[0]['count'] if count_res.data else 0
        return api_response({'success': True, 'isFollowing': False, 'followersCount': followers_count})
    except Exception as e:
        return api_error(str(e), status_code=500)

@users_bp.route('/social/following-feed', methods=['GET'])
def get_following_feed():
    try:
        current_user_id = g.current_user['id']
        page = int(request.args.get('page', 1))
        per_page = 20
        offset = (page - 1) * per_page
        # Get followed users
        followed_res = get_supabase_client().table('user_follows').select('followed_id').eq('follower_id', current_user_id).execute()
        followed_ids = [f['followed_id'] for f in followed_res.data] if followed_res.data else []
        if not followed_ids: return api_response({'rucks': [], 'pagination': {'page': page, 'hasMore': False}})
        # Get recent rucks from followed users
        rucks_res = get_supabase_client().table('ruck_sessions').select('*').in_('user_id', followed_ids).order('end_time', desc=True).range(offset, offset + per_page - 1).execute()
        has_more = len(rucks_res.data or []) == per_page
        return api_response({'rucks': rucks_res.data or [], 'pagination': {'page': page, 'hasMore': has_more}})
    except Exception as e:
        return api_error(str(e), status_code=500)

@users_bp.route('/me/privacy', methods=['PATCH'])
def update_privacy():
    try:
        data = request.get_json()
        if not isinstance(data, dict) or 'isPrivateProfile' not in data:
            return api_error('Invalid request: missing isPrivateProfile', status_code=400)
        is_private = data['isPrivateProfile']
        if not isinstance(is_private, bool):
            return api_error('isPrivateProfile must be boolean', status_code=400)
        current_user_id = g.current_user['id']
        update_res = get_supabase_client().table('user').update({'is_profile_private': is_private}).eq('id', current_user_id).execute()
        if update_res.data:
            return api_response({'success': True, 'isPrivateProfile': is_private})
        return api_error('Failed to update privacy', status_code=400)
    except Exception as e:
        return api_error(str(e), status_code=500)             else:
                raise
        if update_res.data:
            return api_response({'success': True, 'isPrivateProfile': is_private})
        return api_error('Failed to update privacy', status_code=400)
    except Exception as e:
        return api_error(str(e), status_code=500) 
