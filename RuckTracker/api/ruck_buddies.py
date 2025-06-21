from flask import Blueprint, request, jsonify, g
from flask_jwt_extended import jwt_required
import os
import math
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
        return location_points
    
    # Privacy clipping distance (200m or ~1/8 mile)
    PRIVACY_DISTANCE_METERS = 200.0
    
    # Sort points by timestamp to ensure correct order
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
                prev_point['latitude'], prev_point['longitude'],
                curr_point['latitude'], curr_point['longitude']
            )
            cumulative_distance += distance
            
            if cumulative_distance >= PRIVACY_DISTANCE_METERS:
                start_idx = i
                break
    
    # Find the end clipping index (skip last ~200m)
    end_idx = len(sorted_points) - 1
    cumulative_distance = 0
    for i in range(len(sorted_points) - 2, -1, -1):
        curr_point = sorted_points[i]
        next_point = sorted_points[i+1]
        
        if curr_point.get('latitude') and curr_point.get('longitude') and \
           next_point.get('latitude') and next_point.get('longitude'):
            distance = haversine_distance(
                curr_point['latitude'], curr_point['longitude'],
                next_point['latitude'], next_point['longitude']
            )
            cumulative_distance += distance
            
            if cumulative_distance >= PRIVACY_DISTANCE_METERS:
                end_idx = i
                break
    
    # Ensure we have at least some points left
    if start_idx >= end_idx:
        # If clipping would remove everything, return a minimal route (middle section)
        middle_start = max(0, len(sorted_points) // 4)
        middle_end = min(len(sorted_points), 3 * len(sorted_points) // 4)
        return sorted_points[middle_start:middle_end] if middle_end > middle_start else sorted_points[1:-1]
    
    return sorted_points[start_idx:end_idx + 1]

@ruck_buddies_bp.route('/api/ruck-buddies', methods=['GET'])
@auth_required
def get_ruck_buddies():
    """
    Get public ruck sessions from other users.
    Filters by is_public = true and user.allow_ruck_sharing = true.
    
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
    
    # Get latitude and longitude for proximity sorting
    latitude = request.args.get('latitude', type=float)
    longitude = request.args.get('longitude', type=float)
    
    # Build cache key based on query parameters (excluding current user for privacy)
    lat_lon_str = f"{latitude:.3f}_{longitude:.3f}" if latitude and longitude else "no_location"
    cache_key = f"ruck_buddies:{sort_by}:{page}:{per_page}:{lat_lon_str}"
    
    # Try to get cached response first
    cached_response = cache_get(cache_key)
    if cached_response:
        print(f"[CACHE HIT] Returning cached ruck buddies for key: {cache_key}")
        return jsonify(cached_response)
    
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
    # Also join with users table to get user display info and check allow_ruck_sharing
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
        .eq('user.allow_ruck_sharing', True) \
        .neq('user_id', g.user.id) \
        .order(order_by) \
        .limit(per_page) \
        .offset(offset)

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
        
        # Log privacy clipping for verification
        print(f"[PRIVACY_DEBUG] Session {session.get('id')}: Original points: {len(location_points)}, Clipped points: {len(clipped_location_points)}")
        
        # Add computed fields to session data
        session['like_count'] = like_count
        session['is_liked_by_current_user'] = is_liked_by_current_user
        session['comment_count'] = comment_count
        session['location_points'] = clipped_location_points
        
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
    return jsonify({
        'ruck_sessions': processed_sessions,
        'meta': {
            'count': len(response.data),
            'per_page': per_page,
            'page': page,
            'sort_by': sort_by
        }
    }), 200
