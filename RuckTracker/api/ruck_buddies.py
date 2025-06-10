from flask import Blueprint, request, jsonify, g
from flask_jwt_extended import jwt_required
import os
from datetime import datetime, timedelta

from RuckTracker.supabase_client import get_supabase_client
from RuckTracker.api.auth import auth_required, get_user_id

ruck_buddies_bp = Blueprint('ruck_buddies', __name__)

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
            ' user:user_id(id,username,allow_ruck_sharing,gender),'
            ' location_points:location_point!location_point_session_id_fkey(id,latitude,longitude,altitude,timestamp),'
            ' likes:ruck_likes!ruck_likes_session_id_fkey(id,user_id),'
            ' comments:ruck_comment!ruck_comment_session_id_fkey(id,user_id,content,created_at)'
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
        
        # Add computed fields to session data
        session['like_count'] = like_count
        session['is_liked_by_current_user'] = is_liked_by_current_user
        session['comment_count'] = comment_count
        
        # Remove the raw likes/comments arrays to keep response clean
        session.pop('likes', None)
        session.pop('comments', None)
        
        processed_sessions.append(session)
    
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
