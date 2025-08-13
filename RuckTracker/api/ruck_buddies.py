from flask import Blueprint, request, jsonify, g, make_response
from flask_jwt_extended import jwt_required
import os
import math
import gzip
import json
from datetime import datetime, timedelta

from RuckTracker.supabase_client import get_supabase_client
from RuckTracker.api.auth import auth_required, get_user_id
from RuckTracker.services.redis_cache_service import cache_get, cache_set, cache_delete_pattern

ruck_buddies_bp = Blueprint('ruck_buddies', __name__)

def haversine_distance(lat1, lon1, lat2, lon2):
    """
    Calculate the great circle distance between two points 
    on the earth (specified in decimal degrees).
    Returns distance in meters.
    """
    # Convert decimal degrees to radians
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    
    # Haversine formula
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
    c = 2 * math.asin(math.sqrt(a))
    
    # Radius of earth in meters
    r = 6371000
    return c * r

def clip_route_for_privacy(location_points):
    """
    Clips the first and last ~200m (1/8 mile) of a route for privacy
    
    Args:
        location_points: List of dictionaries with 'latitude' and 'longitude' keys
    
    Returns:
        List of clipped location points
    """
    if not location_points or len(location_points) < 3:
        # Not enough points to meaningfully clip; return as-is
        return location_points
    
    # Privacy clipping distance (200m or ~1/8 mile)
    PRIVACY_DISTANCE_METERS = 200.0
    
    # Sort points by timestamp to ensure correct order (if timestamps exist)
    sorted_points = sorted(location_points, key=lambda p: p.get('timestamp', ''))
    
    if len(sorted_points) < 3:
        return sorted_points

    # Find the start clipping index (skip first ~200m)
    start_idx = 0
    cumulative_distance = 0
    for i in range(1, len(sorted_points)):
        prev_point = sorted_points[i-1]
        curr_point = sorted_points[i]
        
        if prev_point.get('latitude') and prev_point.get('longitude') and \
           curr_point.get('latitude') and curr_point.get('longitude'):
            distance = haversine_distance(
                float(prev_point['latitude']), float(prev_point['longitude']),
                float(curr_point['latitude']), float(curr_point['longitude'])
            )
            cumulative_distance += distance
            
            if cumulative_distance >= PRIVACY_DISTANCE_METERS:
                start_idx = i
                break
    
    # Find the end clipping index (skip last ~200m)
    end_idx = len(sorted_points)
    cumulative_distance = 0
    for i in range(len(sorted_points) - 2, -1, -1):
        curr_point = sorted_points[i]
        next_point = sorted_points[i+1]
        
        if curr_point.get('latitude') and curr_point.get('longitude') and \
           next_point.get('latitude') and next_point.get('longitude'):
            distance = haversine_distance(
                float(curr_point['latitude']), float(curr_point['longitude']),
                float(next_point['latitude']), float(next_point['longitude'])
            )
            cumulative_distance += distance
            
            if cumulative_distance >= PRIVACY_DISTANCE_METERS:
                end_idx = i + 1
                break

    # Safety check: ensure we have valid indices and some points
    if start_idx >= end_idx or start_idx >= len(sorted_points) or end_idx <= 0:
        # Fallback: return middle 50% if distance clipping fails
        total = len(sorted_points)
        start_idx = total // 4
        end_idx = 3 * total // 4
        if end_idx <= start_idx:
            # Last resort: return all points
            return sorted_points

    clipped_points = sorted_points[start_idx:end_idx]
    
    # Final safety: never return empty list
    if not clipped_points:
        return sorted_points
    return clipped_points


def sample_route_points(location_points, target_distance_between_points_m=75):
    """
    Sample route points to reduce data size while maintaining consistent route detail.
    Uses distance-based sampling instead of fixed point count.
    
    Args:
        location_points: List of location points
        target_distance_between_points_m: Target distance between sampled points in meters
    
    Returns:
        Sampled list of location points
    """
    if not location_points or len(location_points) <= 2:
        return location_points
    
    # Always include first point
    sampled = [location_points[0]]
    
    # Track cumulative distance to determine when to include next point
    cumulative_distance = 0
    last_included_idx = 0
    
    for i in range(1, len(location_points)):
        prev_point = location_points[i-1]
        curr_point = location_points[i]
        
        if prev_point.get('latitude') and prev_point.get('longitude') and \
           curr_point.get('latitude') and curr_point.get('longitude'):
            
            # Calculate distance from previous point
            distance = haversine_distance(
                prev_point['latitude'], prev_point['longitude'],
                curr_point['latitude'], curr_point['longitude']
            )
            cumulative_distance += distance
            
            # Include point if we've traveled enough distance since last included point
            if cumulative_distance >= target_distance_between_points_m:
                sampled.append(curr_point)
                cumulative_distance = 0  # Reset distance counter
                last_included_idx = i
    
    # Always include last point if it wasn't already included
    if last_included_idx < len(location_points) - 1:
        sampled.append(location_points[-1])
    
    # Cap at reasonable maximum to prevent huge payloads (e.g., 500 points max)
    if len(sampled) > 500:
        # If still too many points, use traditional sampling
        interval = len(sampled) / 500
        final_sampled = [sampled[0]]
        for i in range(1, 499):
            index = int(i * interval)
            if index < len(sampled):
                final_sampled.append(sampled[index])
        final_sampled.append(sampled[-1])
        return final_sampled
    
    return sampled


@ruck_buddies_bp.route('/api/ruck-buddies', methods=['GET'])
@auth_required
def get_ruck_buddies():
    """
    Get public ruck sessions from other users.
    Filters by is_public = true. Individual sessions can be shared even when the user's global allow_ruck_sharing setting is false.
    
    Query params:
    - page: Page number (default: 1)
    - per_page: Number of sessions per page (default: 20)
    - sort_by: Sorting option - 'proximity_asc', 'calories_desc', 'distance_desc', 'duration_desc', 'elevation_gain_desc'
    - latitude, longitude: Required for proximity_asc sorting
    """
    # Ensure g.user is available from auth_required decorator
    if not hasattr(g, 'user') or not g.user:
        return jsonify({'error': 'Authentication required'}), 401

    # Get pagination parameters (convert from page-based to offset-based)
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 20, type=int)
    offset = (page - 1) * per_page
    
    # Get sort_by parameter (this matches what the frontend sends)
    sort_by = request.args.get('sort_by', 'proximity_asc')
    
    # Get following_only parameter for "My Buddies" filter
    following_only = request.args.get('following_only', 'false').lower() == 'true'
    
    # Get latitude and longitude for proximity sorting
    latitude = request.args.get('latitude', type=float)
    longitude = request.args.get('longitude', type=float)
    
    # Build cache key based on query parameters (excluding current user for privacy)
    lat_lon_str = f"{latitude:.3f}_{longitude:.3f}" if latitude and longitude else "no_location"
    following_str = "following" if following_only else "all"
    cache_key = f"ruck_buddies:{sort_by}:{page}:{per_page}:{lat_lon_str}:{following_str}"
    
    # Try to get cached response first
    cached_response = cache_get(cache_key)
    if cached_response:
        print(f"[CACHE HIT] Returning cached ruck buddies for key: {cache_key}")
        response = make_response(gzip.compress(json.dumps(cached_response).encode('utf-8')))
        response.headers['Content-Encoding'] = 'gzip'
        return response
    
    print(f"[CACHE MISS] Fetching ruck buddies from database for key: {cache_key}")
    
    # Define ordering based on sort_by parameter
    if sort_by == 'calories_desc':
        order_by = "calories_burned.desc"
    elif sort_by == 'distance_desc':
        order_by = "distance_km.desc"
    elif sort_by == 'duration_desc':
        order_by = "duration_seconds.desc"
    elif sort_by == 'elevation_gain_desc':
        order_by = "elevation_gain_m.desc"
    elif sort_by == 'proximity_asc':
        if latitude is not None and longitude is not None:
            # For proximity, we'll need to handle this separately
            # This is a placeholder - in a real implementation, we would use geospatial functions
            order_by = "completed_at.desc"  # Fallback ordering for now
        else:
            order_by = "completed_at.desc"  # Default if no coordinates
    else:
        order_by = "completed_at.desc"  # Default fallback

    # Get supabase client
    supabase = get_supabase_client(g.access_token if hasattr(g, 'access_token') else None)

    # Base query getting public ruck sessions that aren't from the current user
    # Also join with users table to get user display info
    # Include social data (likes, comments) to avoid separate API calls
    query = supabase.table('ruck_session') \
        .select(
            'id, user_id, ruck_weight_kg, duration_seconds, distance_km, calories_burned,'
            ' elevation_gain_m, elevation_loss_m, started_at, completed_at, created_at,'
            ' avg_heart_rate, '
            ' user:user_id(id,username,allow_ruck_sharing,gender,avatar_url),'
            ' location_points:location_point!location_point_session_id_fkey(id,latitude,longitude,altitude,timestamp),'
            ' likes:ruck_likes!ruck_likes_ruck_id_fkey(id,user_id),'
            ' comments:ruck_comments!ruck_comments_ruck_id_fkey(id,user_id,content,created_at)'
        ) \
        .eq('is_public', True) \
        .neq('user_id', g.user.id) \
        .gt('duration_seconds', 180) \
        .gte('distance_km', 0.5)
    
    # If following_only is true, filter to only show rucks from users the current user follows
    if following_only:
        # Get list of users the current user follows
        followed_users_res = supabase.table('user_follows').select('followed_id').eq('follower_id', g.user.id).execute()
        followed_user_ids = [f['followed_id'] for f in followed_users_res.data] if followed_users_res.data else []
        
        if not followed_user_ids:
            # If user isn't following anyone, return empty result
            return jsonify({
                'ruck_sessions': [],
                'meta': {
                    'count': 0,
                    'per_page': per_page,
                    'page': page,
                    'sort_by': sort_by
                }
            }), 200
        
        # Filter to only include rucks from followed users
        query = query.in_('user_id', followed_user_ids)  # Exclude rucks shorter than 3 minutes (180 seconds)
    
    # Apply sorting and pagination
    query = query.order(order_by).limit(per_page).offset(offset)

    # Execute the query
    response = query.execute()
    
    if hasattr(response, 'error') and response.error:
        return jsonify({'error': response.error}), 500
    
    # Process the response to add computed social data
    processed_sessions = []
    current_user_id = g.user.id
    
    for session in response.data:
        # Count likes and check if current user liked it
        likes = session.get('likes', [])
        like_count = len(likes)
        is_liked_by_current_user = any(like.get('user_id') == current_user_id for like in likes)
        
        # Count comments
        comments = session.get('comments', [])
        comment_count = len(comments)
        
        # Clip route for privacy
        location_points = session.get('location_points', [])
        clipped_location_points = clip_route_for_privacy(location_points)
        
        # Sample route points
        sampled_location_points = sample_route_points(clipped_location_points)
        
        # Add computed fields to session data
        session['like_count'] = like_count
        session['is_liked_by_current_user'] = is_liked_by_current_user
        session['comment_count'] = comment_count
        session['location_points'] = sampled_location_points
        
        # Remove the raw likes/comments arrays to keep response clean
        session.pop('likes', None)
        session.pop('comments', None)
        
        processed_sessions.append(session)
    
    # Cache the response for future requests
    cache_set(cache_key, {
        'ruck_sessions': processed_sessions,
        'meta': {
            'count': len(response.data),
            'per_page': per_page,
            'page': page,
            'sort_by': sort_by
        }
    })
    
    # Return the processed data
    response = make_response(gzip.compress(json.dumps({
        'ruck_sessions': processed_sessions,
        'meta': {
            'count': len(response.data),
            'per_page': per_page,
            'page': page,
            'sort_by': sort_by
        }
    }).encode('utf-8')))
    response.headers['Content-Encoding'] = 'gzip'
    response.headers['Content-Type'] = 'application/json'
    # Cache for 5 minutes for better performance
    response.headers['Cache-Control'] = 'public, max-age=300'
    return response, 200
