from flask import Blueprint, jsonify, g, request
from flask_jwt_extended import jwt_required
import os
from datetime import datetime, timedelta

from ..config import supabase
from ..auth.auth import auth_required, get_user_id

ruck_buddies_bp = Blueprint('ruck_buddies', __name__)

@ruck_buddies_bp.route('/api/ruck-buddies', methods=['GET'])
@auth_required
def get_ruck_buddies():
    """
    Get public ruck sessions from other users.
    Filters by is_public = true and user.allow_ruck_sharing = true.
    
    Query params:
    - limit: Number of sessions to return (default: 20)
    - offset: Pagination offset (default: 0)
    - filter: 'recent' (default), 'popular', 'distance' (longest), 'duration' (longest)
    """
    limit = request.args.get('limit', 20, type=int)
    offset = request.args.get('offset', 0, type=int)
    filter_type = request.args.get('filter', 'recent')
    
    # Define ordering based on filter type
    if filter_type == 'popular':
        order_by = "likes_count.desc()"
    elif filter_type == 'distance':
        order_by = "distance_km.desc()"
    elif filter_type == 'duration':
        order_by = "duration_seconds.desc()"
    else:  # 'recent' is default
        order_by = "completed_at.desc()"
    
    # Base query getting public ruck sessions that aren't from the current user
    # Also join with users table to get user display info and check allow_ruck_sharing
    query = supabase.table('ruck_session') \
        .select('''
            id,
            user_id,
            ruck_weight_kg,
            duration_seconds,
            distance_km,
            calories_burned,
            elevation_gain_m,
            elevation_loss_m,
            started_at,
            completed_at,
            created_at,
            avg_heart_rate,
            users:user_id (
                username,
                display_name,
                avatar_url
            )
        ''') \
        .eq('is_public', True) \
        .neq('user_id', g.user.id) \
        .order(order_by) \
        .limit(limit) \
        .offset(offset)

    # Execute the query
    response = query.execute()
    
    if hasattr(response, 'error') and response.error:
        return jsonify({'error': response.error}), 500
    
    # Return the data
    return jsonify({
        'ruck_sessions': response.data,
        'meta': {
            'count': len(response.data),
            'limit': limit,
            'offset': offset,
            'filter': filter_type
        }
    }), 200
