from flask import request, g
from flask_restful import Resource
from datetime import datetime, timedelta
import uuid
import logging
import math
import os
from dateutil import tz

from RuckTracker.supabase_client import get_supabase_client
from RuckTracker.services.redis_cache_service import cache_delete_pattern, cache_get, cache_set
from RuckTracker.utils.auth_helper import get_current_user_id
from RuckTracker.utils.api_response import check_auth_and_respond

logger = logging.getLogger(__name__)

def validate_ruck_id(ruck_id):
    """Convert string ruck_id to integer for database operations"""
    try:
        return int(ruck_id)
    except (ValueError, TypeError):
        logger.error(f"Invalid ruck_id format: {ruck_id}")
        return None

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
    Clips the first and last ~100m of a route for privacy
    
    Args:
        location_points: List of dictionaries with 'lat' and 'lng' keys
    
    Returns:
        List of clipped location points
    """
    if not location_points or len(location_points) < 3:
        return location_points
    
    # Privacy clipping distance (2fix 00m)
    PRIVACY_DISTANCE_METERS = 200.0
    
    # Convert to consistent format
    normalized_points = []
    for point in location_points:
        if isinstance(point, dict):
            if 'lat' in point and 'lng' in point:
                normalized_points.append({
                    'lat': float(point['lat']),
                    'lng': float(point['lng'])
                })
            elif 'latitude' in point and 'longitude' in point:
                normalized_points.append({
                    'lat': float(point['latitude']),
                    'lng': float(point['longitude'])
                })
    
    if len(normalized_points) < 3:
        return location_points
    
    # Find start clipping index (skip first ~100m)
    start_idx = 0
    cumulative_distance = 0
    for i in range(1, len(normalized_points)):
        prev_point = normalized_points[i-1]
        curr_point = normalized_points[i]
        
        distance = haversine_distance(
            prev_point['lat'], prev_point['lng'],
            curr_point['lat'], curr_point['lng']
        )
        cumulative_distance += distance
        
        if cumulative_distance >= PRIVACY_DISTANCE_METERS:
            start_idx = i
            break
    
    # Find end clipping index (skip last ~100m)
    end_idx = len(normalized_points)
    cumulative_distance = 0
    for i in range(len(normalized_points) - 2, -1, -1):
        curr_point = normalized_points[i]
        next_point = normalized_points[i+1]
        
        distance = haversine_distance(
            curr_point['lat'], curr_point['lng'],
            next_point['lat'], next_point['lng']
        )
        cumulative_distance += distance
        
        if cumulative_distance >= PRIVACY_DISTANCE_METERS:
            end_idx = i + 1
            break
    
    # Safety check: ensure we have valid indices and some points
    if start_idx >= end_idx or start_idx >= len(normalized_points) or end_idx <= 0:
        # Fallback: return middle 50% if distance clipping fails
        total = len(normalized_points)
        start_idx = total // 4
        end_idx = 3 * total // 4
        if end_idx <= start_idx:
            # Last resort: return all points
            return normalized_points
    
    # Extract the visible portion
    clipped_points = normalized_points[start_idx:end_idx]
    
    # Final safety: never return empty list
    if not clipped_points:
        return normalized_points
        
    return clipped_points

class RuckSessionListResource(Resource):
    def get(self):
        """Get all ruck sessions for the current user"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
                
            limit = request.args.get('limit', 20, type=int)  # Default to 20 sessions
            
            # Build cache key based on user and limit
            cache_key = f"ruck_session:{g.user.id}:list:{limit}"
            
            # Try to get cached response first
            cached_response = cache_get(cache_key)
            if cached_response:
                logger.info(f"[CACHE HIT] Returning cached session list for user {g.user.id}")
                return cached_response, 200
            
            logger.info(f"[CACHE MISS] Fetching session list from database for user {g.user.id}")
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            response_query = supabase.table('ruck_session') \
                .select('*') \
                .eq('user_id', g.user.id) \
                .eq('status', 'completed') \
                .order('completed_at', desc=True) \
                .limit(min(limit, 50))  # Cap at 50 sessions max
            
            response = response_query.execute()
            sessions = response.data
            if sessions is None:
                sessions = []
            
            # Get all session IDs for batch queries
            session_ids = [session['id'] for session in sessions]
            
            if not session_ids:
                cache_set(cache_key, sessions, 300)  # Cache for 5 minutes
                return sessions, 200
            
            # Fetch route data with intelligent sampling (preserve full route shape)
            locations_by_session = {}
            for session_id in session_ids:
                cache_key = f"session_points:{session_id}"
                cached_points = cache_get(cache_key)
                if cached_points:
                    locations_by_session[session_id] = cached_points
                    logger.info(f"[ROUTE_DEBUG] Session {session_id}: Cache hit with {len(cached_points)} points")
                else:
                    try:
                        points_resp = supabase.rpc('get_simplified_route', {'p_session_id': int(session_id), 'p_tolerance': 0.0001}).execute()
                        if points_resp.data:
                            processed_points = [{'lat': float(p['lat']), 'lng': float(p['lng'])} for p in points_resp.data]
                            locations_by_session[session_id] = processed_points
                            cache_set(cache_key, processed_points, 3600)
                            logger.info(f"[ROUTE_DEBUG] Session {session_id}: Fetched and cached {len(processed_points)} simplified points")
                        else:
                            locations_by_session[session_id] = []
                    except Exception as e:
                        logger.error(f"[ROUTE_DEBUG] RPC failed for {session_id}: {e}")
                        locations_by_session[session_id] = []

            # Batch fetch splits for all sessions (splits are small, safe to fetch)
            splits_by_session = {}
            try:
                all_splits_resp = supabase.table('session_splits') \
                    .select('session_id,split_number,split_distance_km,split_duration_seconds') \
                    .in_('session_id', session_ids) \
                    .order('session_id,split_number') \
                    .execute()
                
                if all_splits_resp.data:
                    for split in all_splits_resp.data:
                        session_id = split['session_id']
                        if session_id not in splits_by_session:
                            splits_by_session[session_id] = []
                        splits_by_session[session_id].append({
                            'split_number': split['split_number'],
                            'split_distance_km': split['split_distance_km'],
                            'split_duration_seconds': split['split_duration_seconds'],
                            'calories_burned': split.get('calories_burned', 0.0),
                            'elevation_gain_m': split.get('elevation_gain_m', 0.0),
                            'timestamp': split.get('split_timestamp')
                        })
            except Exception as e:
                logger.error(f"ERROR: Failed to fetch splits: {e}")
                splits_by_session = {}
            
            # Batch fetch photos for all sessions
            photos_by_session = {}
            try:
                all_photos_resp = supabase.table('ruck_photos') \
                    .select('ruck_id,id,filename,size,url,thumbnail_url,created_at') \
                    .in_('ruck_id', session_ids) \
                    .order('ruck_id,created_at') \
                    .execute()
                
                if all_photos_resp.data:
                    for photo in all_photos_resp.data:
                        session_id = photo['ruck_id']
                        if session_id not in photos_by_session:
                            photos_by_session[session_id] = []
                        photos_by_session[session_id].append({
                            'id': photo['id'],
                            'file_name': photo['filename'],
                            'file_size': photo['size'],
                            'url': photo['url'],
                            'thumbnail_url': photo['thumbnail_url'],
                            'uploaded_at': photo['created_at']
                        })
            except Exception as e:
                logger.error(f"ERROR: Failed to fetch photos: {e}")
                photos_by_session = {}
            
            # Enrich sessions with location and splits data
            for session in sessions:
                session_id = session['id']
                logger.info(f"[ROUTE_DEBUG] Enriching session {session_id}")
                
                # Add location points WITHOUT privacy clipping for now
                if session_id in locations_by_session:
                    route_data = locations_by_session[session_id]
                    logger.info(f"[ROUTE_DEBUG] Session {session_id}: Found {len(route_data)} route points")
                    session['route'] = route_data
                    session['location_points'] = route_data  # For compatibility
                else:
                    logger.warning(f"[ROUTE_DEBUG] Session {session_id}: No location data found")
                    session['route'] = []
                    session['location_points'] = []
                
                # Add splits if available
                if session_id in splits_by_session:
                    session['splits'] = splits_by_session[session_id]
                    logger.info(f"[ROUTE_DEBUG] Session {session_id}: Added {len(session['splits'])} splits")
                else:
                    session['splits'] = []
                    logger.info(f"[ROUTE_DEBUG] Session {session_id}: No splits data found")
                
                # Add photos if available
                if session_id in photos_by_session:
                    session['photos'] = photos_by_session[session_id]
                    logger.info(f"[ROUTE_DEBUG] Session {session_id}: Added {len(session['photos'])} photos")
                else:
                    session['photos'] = []
                    logger.info(f"[ROUTE_DEBUG] Session {session_id}: No photos found")
            
            # Cache the enriched result for 5 minutes
            cache_set(cache_key, sessions, 300)
            
            # Log final summary
            sessions_with_routes = sum(1 for s in sessions if s.get('location_points') and len(s['location_points']) > 0)
            total_route_points = sum(len(s.get('location_points', [])) for s in sessions)
            logger.info(f"[ROUTE_DEBUG] FINAL SUMMARY: Returning {len(sessions)} sessions, {sessions_with_routes} with routes, {total_route_points} total route points")
            
            logger.info(f"Returning {len(sessions)} sessions for user {g.user.id}")
            return sessions, 200
            
        except Exception as e:
            logger.error(f"Error fetching ruck sessions: {e}")
            return {'message': f"Error fetching sessions: {str(e)}"}, 500

    def post(self):
        """Create a new ruck session for the current user"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            data = request.get_json()
            if not data:
                return {'message': 'Missing required data for session creation'}, 400
            
            # Log incoming request data for debugging
            logger.info(f"Session creation request data: {data}")
            logger.info(f"Request contains event_id: {'event_id' in data}")
            if 'event_id' in data:
                logger.info(f"Event ID value: {data.get('event_id')} (type: {type(data.get('event_id'))})")
                
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))

            # Deduplication: Check for any active (in_progress) session for the current user
            active_sessions = supabase.table('ruck_session') \
                .select('id,status') \
                .eq('user_id', g.user.id) \
                .eq('status', 'in_progress') \
                .execute()
            if active_sessions.data and len(active_sessions.data) > 0:
                logger.info(f"Reusing active session {active_sessions.data[0]['id']}")
                return active_sessions.data[0], 200

            session_data = {
                'user_id': g.user.id,
                'status': 'in_progress',
                'started_at': datetime.now(tz.tzutc()).isoformat()
            }
            
            # Handle ruck weight (multiple possible keys)
            if 'ruck_weight_kg' in data and data.get('ruck_weight_kg') is not None:
                session_data['ruck_weight_kg'] = data.get('ruck_weight_kg')
            
            # Handle user weight (multiple possible keys)
            if 'user_weight_kg' in data and data.get('user_weight_kg') is not None:
                session_data['weight_kg'] = data.get('user_weight_kg')  # Map user_weight_kg to weight_kg
            elif 'weight_kg' in data and data.get('weight_kg') is not None:
                session_data['weight_kg'] = data.get('weight_kg')
            
            # Handle custom session ID if provided
            if 'id' in data and data.get('id') is not None:
                session_id_raw = data.get('id')
                
                # Handle manual sessions - these should get database auto-generated ID
                if isinstance(session_id_raw, str) and session_id_raw.startswith('manual_'):
                    logger.info(f"Manual session detected, letting database auto-generate ID instead of: {session_id_raw}")
                    # Don't set id for manual sessions - let database auto-generate
                else:
                    # For regular sessions, use the provided ID
                    try:
                        session_id = int(session_id_raw)
                        session_data['id'] = session_id
                        logger.info(f"Using provided session ID: {session_id}")
                    except (ValueError, TypeError):
                        logger.warning(f"Invalid session ID format: {session_id_raw}, letting database auto-generate")
            
            # Handle notes if provided
            if 'notes' in data and data.get('notes') is not None:
                session_data['notes'] = data.get('notes')
            
            # Handle custom start time if provided (for crash recovery)
            if 'start_time' in data and data.get('start_time') is not None:
                try:
                    # Parse and use the provided start time (frontend sends start_time, backend uses started_at)
                    start_time = datetime.fromisoformat(data['start_time'].replace('Z', '+00:00'))
                    session_data['started_at'] = start_time.isoformat()
                except (ValueError, TypeError) as e:
                    logger.warning(f"Invalid start_time format, using current time: {e}")
                    # Fall back to current time if parsing fails
            
            # Add event_id if provided (for event-associated ruck sessions)
            if 'event_id' in data and data.get('event_id') is not None:
                event_id_raw = data.get('event_id')
                
                # Handle manual ruck sessions - these shouldn't have an event_id
                if isinstance(event_id_raw, str) and event_id_raw.startswith('manual_'):
                    logger.info(f"Manual ruck session detected, ignoring event_id: {event_id_raw}")
                    # Don't set event_id for manual sessions
                else:
                    # For actual events, ensure event_id is an integer
                    try:
                        event_id = int(event_id_raw)
                        session_data['event_id'] = event_id
                        logger.info(f"Creating session for event {event_id}")
                    except (ValueError, TypeError):
                        logger.warning(f"Invalid event_id format: {event_id_raw}, ignoring")
            else:
                logger.info("No event_id provided - creating regular session")
            
            logger.info(f"Final session_data before insert: {session_data}")
            
            insert_resp = supabase.table('ruck_session') \
                .insert(session_data) \
                .execute()
            if not insert_resp.data:
                logger.error(f"Failed to create session: {insert_resp.error}")
                return {'message': 'Failed to create session'}, 500
            # Invalidate user's session cache and ruck buddies cache (new session may appear in feed)
            cache_delete_pattern(f"ruck_session:{g.user.id}:*")
            cache_delete_pattern("ruck_buddies:*")
            return insert_resp.data[0], 201
        except Exception as e:
            logger.error(f"Error creating ruck session: {e}")
            return {'message': f"Error creating ruck session: {str(e)}"}, 500

class RuckSessionResource(Resource):
    def get(self, ruck_id):
        try:
            ruck_id = validate_ruck_id(ruck_id)
            if ruck_id is None:
                return {'message': 'Invalid ruck session ID format'}, 400
            
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # First try to get the session for the current user (full access)
            response = supabase.table('ruck_session') \
                .select('*') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            
            is_own_session = bool(response.data and len(response.data) > 0)
            
            if not is_own_session:
                # If not the user's own session, check if it's a public session
                response = supabase.table('ruck_session') \
                    .select('*') \
                    .eq('id', ruck_id) \
                    .eq('is_public', True) \
                    .execute()
                
                if not response.data or len(response.data) == 0:
                    return {'message': 'Session not found'}, 404
                    
                session = response.data[0]
            else:
                session = response.data[0]
            
            # Fetch location points with intelligent sampling
            cache_key = f"session_points:{ruck_id}"
            cached_points = cache_get(cache_key)
            if cached_points:
                location_points = cached_points
                logger.info(f"[SESSION_DETAIL] Cache hit for {ruck_id}: {len(location_points)} points")
            else:
                try:
                    if is_own_session:
                        points_resp = supabase.rpc('get_simplified_route', {'p_session_id': int(ruck_id), 'p_tolerance': 0.0001}).execute()
                    else:
                        points_resp = supabase.rpc('get_clipped_simplified_route', {'p_session_id': int(ruck_id), 'p_privacy_distance': 200.0, 'p_max_points': 500}).execute()
                    if points_resp.data:
                        location_points = [{'lat': float(p['lat']), 'lng': float(p['lng']), 'timestamp': p['timestamp']} for p in points_resp.data]
                        if is_own_session:  # Cache unclipped for own sessions
                            cache_set(cache_key, location_points, 3600)
                        logger.info(f"[SESSION_DETAIL] Fetched {len(location_points)} points via RPC for {ruck_id}")
                    else:
                        location_points = []
                except Exception as e:
                    logger.error(f"[SESSION_DETAIL] RPC failed for {ruck_id}: {e}")
                    location_points = []  # Fallback: use old query logic here if needed

            if location_points and not is_own_session:
                original_count = len(location_points)
                location_points = clip_route_for_privacy(location_points)
                logger.debug(f"[PRIVACY_DEBUG] Clipped from {original_count} to {len(location_points)}")

            session['route'] = location_points
            session['location_points'] = location_points

            # Fetch splits data (for all sessions - public sessions should also show splits)
            try:
                splits_resp = supabase.table('session_splits') \
                    .select('*') \
                    .eq('session_id', ruck_id) \
                    .order('split_number') \
                    .execute()
                
                if splits_resp.data:
                    session['splits'] = splits_resp.data
                    logger.info(f"[SPLITS_DEBUG] Included {len(splits_resp.data)} splits in detail response for session {ruck_id}")
                else:
                    session['splits'] = []
                    logger.info(f"[SPLITS_DEBUG] No splits found for session {ruck_id}")
            except Exception as splits_fetch_error:
                logger.error(f"Error fetching splits for session {ruck_id}: {splits_fetch_error}")
                session['splits'] = []  # Ensure splits field exists even if fetch fails
            
            # Fetch photos data (only for the session owner for now)
            if is_own_session:
                logger.info(f"[PHOTO_DEBUG] Fetching photos for session {ruck_id} owned by user {g.user.id}")
                photos_resp = supabase.table('ruck_photos') \
                    .select('id,filename,size,url,thumbnail_url,created_at') \
                    .eq('ruck_id', ruck_id) \
                    .order('created_at') \
                    .execute()
                
                if photos_resp.data:
                    logger.info(f"[PHOTO_DEBUG] Found {len(photos_resp.data)} photos for session {ruck_id}")
                    # Transform photo data to match frontend expectations
                    session['photos'] = [{
                        'id': photo['id'],
                        'file_name': photo['filename'],
                        'file_size': photo['size'],
                        'url': photo['url'],
                        'thumbnail_url': photo['thumbnail_url'],
                        'uploaded_at': photo['created_at']
                    } for photo in photos_resp.data]
                    logger.info(f"[PHOTO_DEBUG] Transformed photos for session {ruck_id}: {[p['file_name'] for p in session['photos']]}")
                else:
                    logger.info(f"[PHOTO_DEBUG] No photos found for session {ruck_id}")
                    session['photos'] = []
            else:
                session['photos'] = []
            
            # Clean up user data before returning
            if 'user' in session:
                del session['user']
            
            return session, 200
        except Exception as e:
            logger.error(f"Error fetching ruck session {ruck_id}: {e}")
            return {'message': f"Error fetching ruck session: {str(e)}"}, 500

    def patch(self, ruck_id):
        """Allow updating notes, rating, perceived_exertion, and tags on any session."""
        try:
            ruck_id = validate_ruck_id(ruck_id)
            if ruck_id is None:
                return {'message': 'Invalid ruck session ID format'}, 400
            
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            data = request.get_json()
            if not data:
                return {'message': 'No data provided'}, 400

            allowed_fields = ['notes', 'rating', 'perceived_exertion', 'tags', 'elevation_gain_m', 'elevation_loss_m', 'distance_km', 'distance_meters', 'calories_burned', 'is_public', 'splits']
            update_data = {k: v for k, v in data.items() if k in allowed_fields}

            if not update_data:
                return {'message': 'No valid fields to update'}, 400

            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Handle splits separately since they need to be inserted into session_splits table
            splits_data = update_data.pop('splits', None)
            
            # Update the main session data
            update_resp = supabase.table('ruck_session') \
                .update(update_data) \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()

            if not update_resp.data or len(update_resp.data) == 0:
                return {'message': 'Failed to update session'}, 500

            # Handle splits data if provided
            if splits_data is not None:
                # First, delete existing splits for this session
                delete_resp = supabase.table('session_splits') \
                    .delete() \
                    .eq('session_id', ruck_id) \
                    .execute()
                
                # Insert new splits
                if splits_data and len(splits_data) > 0:
                    splits_to_insert = []
                    for split in splits_data:
                        split_record = {
                            'session_id': int(ruck_id),
                            'split_number': split.get('split_number') or split.get('splitNumber'),  # Handle both formats
                            'split_distance_km': split.get('split_distance', 1.0) or (split.get('distance', 0) / 1000.0 if split.get('distance') else 1.0),
                            'split_duration_seconds': split.get('split_duration_seconds') or (split.get('duration', {}).get('inSeconds') if isinstance(split.get('duration'), dict) else split.get('duration')),
                            'total_distance_km': split.get('total_distance', 0),
                            'total_duration_seconds': split.get('total_duration_seconds', 0),
                            'calories_burned': split.get('calories_burned', 0.0),
                            'elevation_gain_m': split.get('elevation_gain_m', 0.0),
                            'split_timestamp': split.get('timestamp') or datetime.now(tz.tzutc()).isoformat()
                        }
                        splits_to_insert.append(split_record)
                    
                    if splits_to_insert:
                        insert_resp = supabase.table('session_splits') \
                            .insert(splits_to_insert) \
                            .execute()
                        
                        if not insert_resp.data:
                            logger.warning(f"Failed to insert splits for session {ruck_id}")

            return update_resp.data[0], 200
        except Exception as e:
            logger.error(f"Error updating ruck session {ruck_id}: {e}")
            return {'message': f"Error updating ruck session: {str(e)}"}, 500

    def delete(self, ruck_id):
        """Hard delete a ruck session and all associated location_point records for the authenticated user."""
        try:
            ruck_id = validate_ruck_id(ruck_id)
            if ruck_id is None:
                return {'message': 'Invalid ruck session ID format'}, 400
            
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            # First, delete all associated location_point records
            loc_del_resp = supabase.table('location_point') \
                .delete() \
                .eq('session_id', ruck_id) \
                .execute()
            # Then, delete the ruck_session itself
            session_del_resp = supabase.table('ruck_session') \
                .delete() \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            if not session_del_resp.data or len(session_del_resp.data) == 0:
                return {'message': 'Session not found or failed to delete'}, 404
            cache_delete_pattern(f"ruck_session:{g.user.id}:*")
            return {'message': 'Session deleted successfully'}, 200
        except Exception as e:
            logger.error(f"Error deleting ruck session {ruck_id}: {e}")
            return {'message': f"Error deleting ruck session: {str(e)}"}, 500

class RuckSessionStartResource(Resource):
    def post(self, ruck_id):
        try:
            ruck_id = validate_ruck_id(ruck_id)
            if ruck_id is None:
                return {'message': 'Invalid ruck session ID format'}, 400
            
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            # Check if session already exists
            check = supabase.table('ruck_session') \
                .select('id,status') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            if not check.data or len(check.data) == 0:
                return {'message': 'Session not found'}, 404
            if check.data[0]['status'] != 'created':
                # Instead of error, return the existing session with 200
                return check.data[0], 200
            # Update status to in_progress
            update_resp = supabase.table('ruck_session') \
                .update({'status': 'in_progress', 'started_at': datetime.now(tz.tzutc()).isoformat()}) \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            if not update_resp.data or len(update_resp.data) == 0:
                logger.error(f"Failed to start session {ruck_id}: {update_resp.error}")
                return {'message': 'Failed to start session'}, 500
            cache_delete_pattern(f"ruck_session:{g.user.id}:*")
            return update_resp.data[0], 200
        except Exception as e:
            logger.error(f"Error starting ruck session {ruck_id}: {e}")
            return {'message': f"Error starting ruck session: {str(e)}"}, 500

class RuckSessionPauseResource(Resource):
    def post(self, ruck_id):
        try:
            ruck_id = validate_ruck_id(ruck_id)
            if ruck_id is None:
                return {'message': 'Invalid ruck session ID format'}, 400
            
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            # Check if session exists and is in_progress
            check = supabase.table('ruck_session') \
                .select('id,status') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            if not check.data or len(check.data) == 0:
                return {'message': 'Session not found'}, 404
            if check.data[0]['status'] != 'in_progress':
                return {'message': 'Session not in progress'}, 400
            # Update status to paused
            update_resp = supabase.table('ruck_session') \
                .update({'status': 'paused'}) \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            if not update_resp.data or len(update_resp.data) == 0:
                logger.error(f"Failed to pause session {ruck_id}: {update_resp.error}")
                return {'message': 'Failed to pause session'}, 500
            cache_delete_pattern(f"ruck_session:{g.user.id}:*")
            return update_resp.data[0], 200
        except Exception as e:
            logger.error(f"Error pausing ruck session {ruck_id}: {e}")
            return {'message': f"Error pausing ruck session: {str(e)}"}, 500

class RuckSessionResumeResource(Resource):
    def post(self, ruck_id):
        try:
            ruck_id = validate_ruck_id(ruck_id)
            if ruck_id is None:
                return {'message': 'Invalid ruck session ID format'}, 400
            
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            # Check if session exists and is paused
            check = supabase.table('ruck_session') \
                .select('id,status') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            if not check.data or len(check.data) == 0:
                return {'message': 'Session not found'}, 404
            if check.data[0]['status'] != 'paused':
                return {'message': 'Session not paused'}, 400
            # Update status to in_progress
            update_resp = supabase.table('ruck_session') \
                .update({'status': 'in_progress'}) \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            if not update_resp.data or len(update_resp.data) == 0:
                logger.error(f"Failed to resume session {ruck_id}: {update_resp.error}")
                return {'message': 'Failed to resume session'}, 500
            cache_delete_pattern(f"ruck_session:{g.user.id}:*")
            return update_resp.data[0], 200
        except Exception as e:
            logger.error(f"Error resuming ruck session {ruck_id}: {e}")
            return {'message': f"Error resuming ruck session: {str(e)}"}, 500

class RuckSessionCompleteResource(Resource):
    def post(self, ruck_id):
        """Complete a ruck session"""
        try:
            # Convert string ruck_id to integer for database operations
            ruck_id = validate_ruck_id(ruck_id)
            if ruck_id is None:
                return {'message': 'Invalid ruck session ID format'}, 400
            
            # Check authentication (use same pattern as location endpoint)
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            
            user_id = g.user.id
            data = request.get_json()
            if not data:
                return {'message': 'No data provided'}, 400
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            # Check if session exists
            session_check = supabase.table('ruck_session') \
                .select('id,status,started_at') \
                .eq('id', ruck_id) \
                .eq('user_id', user_id) \
                .execute()
            if not session_check.data or len(session_check.data) == 0:
                return {'message': 'Session not found'}, 404
            current_status = session_check.data[0]['status']
            started_at_str = session_check.data[0].get('started_at')
            if current_status not in ['in_progress', 'paused']:
                logger.warning(f"Session {ruck_id} completion failed: status is '{current_status}', expected 'in_progress' or 'paused'")
                if current_status == 'completed':
                    # Session already completed, return success to avoid client errors
                    return {
                        'message': 'Session already completed',
                        'session_id': ruck_id,
                        'status': 'already_completed'
                    }, 200
                else:
                    return {'message': f'Session not in progress or paused (current status: {current_status})'}, 400
            
            # Fetch user's allow_ruck_sharing preference to set default for is_public
            user_resp = supabase.table('user') \
                .select('allow_ruck_sharing') \
                .eq('id', user_id) \
                .single() \
                .execute()
        
            user_allows_sharing = user_resp.data.get('allow_ruck_sharing', False) if user_resp.data else False
        
            # Calculate duration
            if started_at_str:
                try:
                    started_at = datetime.fromisoformat(started_at_str.replace('Z', '+00:00'))
                    ended_at = datetime.now(tz.tzutc())
                    duration_seconds = int((ended_at - started_at).total_seconds())
                except Exception as e:
                    logger.error(f"Error calculating duration for session {ruck_id}: {e}")
                    duration_seconds = 0
            else:
                duration_seconds = 0
            # Calculate pace if possible
            distance_km = None
            if 'distance_km' in data and data['distance_km']:
                distance_km = data['distance_km']
        
            # Pace will be calculated later using processed distance, not client-sent distance

            # Update session status to completed with end data
            update_data = {
                'status': 'completed',
                'duration_seconds': duration_seconds
            }
        
            # Set is_public based on user preference or explicit override from client
            if 'is_public' in data:
                # Client explicitly set sharing preference for this session
                update_data['is_public'] = data['is_public']
            else:
                # Default based on user's global preference
                update_data['is_public'] = user_allows_sharing
            
            # Add all relevant fields if provided
            if 'distance_km' in data:
                update_data['distance_km'] = data['distance_km']
            if 'weight_kg' in data:
                update_data['weight_kg'] = data['weight_kg']
            if 'ruck_weight_kg' in data:
                update_data['ruck_weight_kg'] = data['ruck_weight_kg']
            if 'calories_burned' in data:
                update_data['calories_burned'] = data['calories_burned']
            if 'elevation_gain_m' in data:
                update_data['elevation_gain_m'] = data['elevation_gain_m']
            if 'elevation_loss_m' in data:
                update_data['elevation_loss_m'] = data['elevation_loss_m']
            # Always set completed_at to now (UTC) when completing session
            update_data['completed_at'] = datetime.now(tz.tzutc()).isoformat()

            # Pace will be calculated later using processed distance

            if 'start_time' in data:
                update_data['started_at'] = data['start_time']
            if 'end_time' in data: # Keep this for now, though completed_at should be primary
                update_data['completed_at'] = data['end_time']
            if 'final_average_pace' in data: # Client-sent pace (legacy key), overrides server calc
                update_data['average_pace'] = data['final_average_pace']
            if 'average_pace' in data:     # Client-sent pace (current key), overrides server calc / legacy key
                update_data['average_pace'] = data['average_pace']
            if 'rating' in data:
                update_data['rating'] = data['rating']
            if 'perceived_exertion' in data:
                update_data['perceived_exertion'] = data['perceived_exertion']
            if 'notes' in data:
                update_data['notes'] = data['notes']
            if 'tags' in data:
                update_data['tags'] = data['tags']
            if 'planned_duration_minutes' in data:
                update_data['planned_duration_minutes'] = data['planned_duration_minutes']
            
            # Log the sharing decision for debugging
            logger.info(f"Session {ruck_id} completion: user_allows_sharing={user_allows_sharing}, is_public={update_data['is_public']}")
        
            # SERVER-SIDE METRIC CALCULATION FALLBACK
            # If key metrics are missing or zero, calculate them from GPS data
            needs_calculation = (
                not update_data.get('distance_km') or update_data.get('distance_km', 0) == 0 or
                not update_data.get('calories_burned') or update_data.get('calories_burned', 0) == 0 or
                not update_data.get('elevation_gain_m') or update_data.get('elevation_gain_m', 0) == 0 or
                not update_data.get('average_pace') or update_data.get('average_pace', 0) == 0
            )
        
            if needs_calculation:
                logger.info(f"Session {ruck_id}: Missing metrics detected, calculating from GPS data...")
                try:
                    # Fetch GPS location points for this session
                    location_resp = supabase.table('location_point') \
                        .select('latitude,longitude,altitude,timestamp') \
                        .eq('session_id', ruck_id) \
                        .order('timestamp') \
                        .execute()
                
                    if location_resp.data and len(location_resp.data) >= 2:
                        points = location_resp.data
                        logger.info(f"Found {len(points)} GPS points for calculation")
                    
                        # Calculate distance using haversine formula
                        total_distance_km = 0
                        elevation_gain_m = 0
                        previous_altitude = None
                    
                        for i in range(1, len(points)):
                            prev_point = points[i-1]
                            curr_point = points[i]
                        
                            # Calculate distance between consecutive points
                            lat1, lon1 = float(prev_point['latitude']), float(prev_point['longitude']) 
                            lat2, lon2 = float(curr_point['latitude']), float(curr_point['longitude'])
                        
                            # Haversine formula
                            R = 6371  # Earth's radius in km
                            dlat = math.radians(lat2 - lat1)
                            dlon = math.radians(lon2 - lon1)
                            a = (math.sin(dlat/2) * math.sin(dlat/2) + 
                                 math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * 
                                 math.sin(dlon/2) * math.sin(dlon/2))
                            c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
                            distance_km = R * c
                            total_distance_km += distance_km
                        
                            # Calculate elevation gain
                            if curr_point.get('altitude') is not None and prev_point.get('altitude') is not None:
                                alt_diff = float(curr_point['altitude']) - float(prev_point['altitude'])
                                if alt_diff > 0:  # Only count positive elevation changes
                                    elevation_gain_m += alt_diff
                    
                        # Calculate missing metrics - use threshold to avoid overwriting small but valid distances
                        if not update_data.get('distance_km') or update_data.get('distance_km', 0) <= 0.001:  # Only override if truly zero or negligible
                            update_data['distance_km'] = round(total_distance_km, 3)
                            logger.info(f"[DISTANCE_DEBUG] Overriding client distance with GPS calculation: {total_distance_km:.3f} km")
                        else:
                            logger.info(f"[DISTANCE_DEBUG] Using client-provided distance: {update_data.get('distance_km')} km")
                    
                        if not update_data.get('elevation_gain_m') or update_data.get('elevation_gain_m', 0) == 0:
                            update_data['elevation_gain_m'] = round(elevation_gain_m, 1)
                            logger.info(f"Calculated elevation gain: {elevation_gain_m:.1f} m")
                    
                        # Calculate average pace if we have distance and duration
                        final_distance = update_data.get('distance_km', 0)
                        logger.info(f"[PACE_DEBUG] Backend pace calculation inputs: duration_seconds={duration_seconds}, final_distance={final_distance}km")
                        if final_distance > 0 and duration_seconds > 0:
                            if not update_data.get('average_pace') or update_data.get('average_pace', 0) == 0:
                                calculated_pace = duration_seconds / final_distance  # seconds per km
                                update_data['average_pace'] = calculated_pace  # Store with full precision like Session 1088
                                logger.info(f"[PACE_DEBUG] Calculated pace: {duration_seconds}s ÷ {final_distance}km = {calculated_pace} sec/km")
                    
                        # Calculate calories if missing (basic estimation)
                        if not update_data.get('calories_burned') or update_data.get('calories_burned', 0) == 0:
                            # Basic calorie estimation: assume 80kg user, ~400 cal/hour base + elevation
                            weight_kg = update_data.get('weight_kg', 80)  # Default 80kg if not provided
                            ruck_weight_kg = update_data.get('ruck_weight_kg', 0)
                            total_weight_kg = weight_kg + ruck_weight_kg
                        
                            # Base metabolic rate (calories per hour)
                            base_cal_per_hour = 4.5 * total_weight_kg  # METs calculation for rucking
                            duration_hours = duration_seconds / 3600
                            base_calories = base_cal_per_hour * duration_hours
                        
                            # Add elevation bonus (1 cal per 10m elevation gain per kg body weight)
                            elevation_calories = (elevation_gain_m / 10) * weight_kg
                        
                            estimated_calories = round(base_calories + elevation_calories)
                            update_data['calories_burned'] = estimated_calories
                            logger.info(f"Estimated calories: {estimated_calories} (base: {base_calories:.0f}, elevation: {elevation_calories:.0f})")
                    
                        logger.info(f"Server-calculated metrics for session {ruck_id}: distance={update_data.get('distance_km')}km, pace={update_data.get('average_pace')}s/km, calories={update_data.get('calories_burned')}, elevation={update_data.get('elevation_gain_m')}m")
                    
                    else:
                        logger.warning(f"Session {ruck_id}: Insufficient GPS data for metric calculation ({len(location_resp.data) if location_resp.data else 0} points)")
                    
                except Exception as calc_error:
                    logger.error(f"Error calculating server-side metrics for session {ruck_id}: {calc_error}")
                    # Continue with original data - don't fail the completion
    
            # Continue with update as before
            update_resp = supabase.table('ruck_session') \
                .update(update_data) \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            if not update_resp.data or len(update_resp.data) == 0:
                logger.error(f"Failed to end session {ruck_id}: {update_resp.error}")
                return {'message': 'Failed to end session'}, 500
        
            completed_session = update_resp.data[0]
        
            # Handle splits data if provided
            if 'splits' in data and data['splits']:
                splits_data = data['splits']
                logger.info(f"Processing {len(splits_data)} splits for session {ruck_id}")
                
                # Get session location points for elevation calculation
                session_location_points = completed_session.get('location_points', [])
                logger.info(f"Found {len(session_location_points)} location points for elevation calculation")
                
                try:
                    # First, delete existing splits for this session
                    delete_resp = supabase.table('session_splits') \
                        .delete() \
                        .eq('session_id', ruck_id) \
                        .execute()
                    
                    # Insert new splits
                    if splits_data and len(splits_data) > 0:
                        splits_to_insert = []
                        for split in splits_data:
                            # Use elevation gain data from frontend instead of recalculating
                            # The frontend now properly calculates elevation gains for splits
                            split_elevation_gain = split.get('elevation_gain_m', 0.0)
                            
                            logger.debug(f"Split {split.get('split_number')}: using frontend elevation gain: {split_elevation_gain:.1f}m")
                            
                            # Handle the split data format from the Flutter app
                            split_record = {
                                'session_id': int(ruck_id),
                                'split_number': split.get('split_number'),
                                'split_distance_km': split.get('split_distance', 1.0),  # Always 1.0 (1km or 1mi)
                                'split_duration_seconds': split.get('split_duration_seconds'),
                                'total_distance_km': split.get('total_distance', 0),
                                'total_duration_seconds': split.get('total_duration_seconds', 0),
                                'calories_burned': split.get('calories_burned', 0.0),
                                'elevation_gain_m': split_elevation_gain,  # Use calculated elevation gain
                                'split_timestamp': split.get('timestamp') if split.get('timestamp') else datetime.now(tz.tzutc()).isoformat()
                            }
                            splits_to_insert.append(split_record)
                        
                        if splits_to_insert:
                            insert_resp = supabase.table('session_splits') \
                                .insert(splits_to_insert) \
                                .execute()
                            
                            if insert_resp.data:
                                logger.info(f"Successfully inserted {len(insert_resp.data)} splits for session {ruck_id}")
                            else:
                                logger.warning(f"Failed to insert splits for session {ruck_id}: {insert_resp.error}")
                except Exception as splits_error:
                    logger.error(f"Error handling splits for session {ruck_id}: {splits_error}")
                    # Don't fail the session completion if splits insertion fails
        
            # Check if this session is associated with an event and update progress
            if completed_session.get('event_id'):
                try:
                    event_id = completed_session['event_id']
                    logger.info(f"Updating event progress for session {ruck_id} in event {event_id}")
                
                    # Update event participant progress
                    progress_update = {
                        'ruck_session_id': int(ruck_id),  # Convert to int to match database type
                        'distance_km': completed_session.get('distance_km', 0),
                        'duration_minutes': int(duration_seconds / 60) if duration_seconds else 0,
                        'calories_burned': completed_session.get('calories_burned', 0),
                        'elevation_gain_m': completed_session.get('elevation_gain_m', 0),
                        'average_pace_min_per_km': completed_session.get('average_pace', 0) / 60 if completed_session.get('average_pace') else None,
                        'status': 'completed',
                        'completed_at': completed_session['completed_at']
                    }
                
                    # Update the event progress entry
                    progress_resp = supabase.table('event_participant_progress') \
                        .update(progress_update) \
                        .eq('event_id', event_id) \
                        .eq('user_id', g.user.id) \
                        .execute()
                
                    if progress_resp.data:
                        logger.info(f"Successfully updated event progress for user {g.user.id} in event {event_id}")
                    else:
                        logger.warning(f"Failed to update event progress for user {g.user.id} in event {event_id}")
                    
                except Exception as event_error:
                    logger.error(f"Error updating event progress for session {ruck_id}: {event_error}")
                    # Don't fail the session completion if event progress update fails
        
            # Check if this user is in any active duels and update progress automatically
            try:
                logger.info(f"Checking for active duels for user {g.user.id} after completing session {ruck_id}")
                
                # Find active duel participants for this user
                duel_participants_resp = supabase.table('duel_participants') \
                    .select('id, duel_id, current_value') \
                    .eq('user_id', g.user.id) \
                    .eq('status', 'accepted') \
                    .execute()
                
                if duel_participants_resp.data:
                    # For each active duel participation, check if the duel is still active
                    for participant in duel_participants_resp.data:
                        participant_id = participant['id']
                        duel_id = participant['duel_id']
                        
                        # Get duel details
                        duel_resp = supabase.table('duels') \
                            .select('id, status, challenge_type, target_value, ends_at') \
                            .eq('id', duel_id) \
                            .single() \
                            .execute()
                        
                        if not duel_resp.data or duel_resp.data['status'] != 'active':
                            continue
                            
                        duel = duel_resp.data
                        
                        # Check if duel has ended
                        if duel['ends_at']:
                            duel_end_time = datetime.fromisoformat(duel['ends_at'])
                            current_time = datetime.now(duel_end_time.tzinfo) if duel_end_time.tzinfo else datetime.utcnow()
                            if current_time > duel_end_time:
                                continue
                            
                        # Check if session was already counted for this duel
                        existing_session_resp = supabase.table('duel_sessions') \
                            .select('id') \
                            .eq('duel_id', duel_id) \
                            .eq('participant_id', participant_id) \
                            .eq('session_id', ruck_id) \
                            .execute()
                        
                        if existing_session_resp.data:
                            logger.info(f"Session {ruck_id} already counted for duel {duel_id}")
                            continue
                            
                        # Calculate contribution based on challenge type
                        contribution = 0
                        if duel['challenge_type'] == 'distance':
                            contribution = completed_session.get('distance_km', 0)
                        elif duel['challenge_type'] == 'duration':
                            contribution = int(duration_seconds / 60) if duration_seconds else 0
                        elif duel['challenge_type'] == 'time':  # Handle 'time' alias for duration
                            contribution = int(duration_seconds / 60) if duration_seconds else 0
                        elif duel['challenge_type'] == 'elevation':
                            contribution = completed_session.get('elevation_gain_m', 0)
                        elif duel['challenge_type'] == 'power_points':
                            # Power points are automatically calculated by the database computed column
                            # We need to re-fetch the session to get the computed power_points value
                            session_with_power_points = supabase.table('ruck_session') \
                                .select('power_points') \
                                .eq('id', ruck_id) \
                                .single() \
                                .execute()
                            if session_with_power_points.data and session_with_power_points.data.get('power_points'):
                                contribution = float(session_with_power_points.data['power_points'])
                            else:
                                contribution = 0
                        
                        if contribution > 0:
                            # Update participant progress
                            new_value = participant['current_value'] + contribution
                            now = datetime.utcnow()
                            
                            supabase.table('duel_participants').update({
                                'current_value': new_value,
                                'updated_at': now.isoformat()
                            }).eq('id', participant_id).execute()
                            
                            # Record the session contribution
                            supabase.table('duel_sessions').insert([{
                                'duel_id': duel_id,
                                'participant_id': participant_id,
                                'session_id': ruck_id,
                                'contribution_value': contribution,
                                'created_at': now.isoformat()
                            }]).execute()
                            
                            # Notification handled by database trigger
                            # try:
                            #     from api.duel_comments import create_duel_progress_notification
                            #     user_resp = supabase.table('users').select('username').eq('id', g.user.id).single().execute()
                            #     user_name = user_resp.data.get('username', 'Unknown User') if user_resp.data else 'Unknown User'
                            #     create_duel_progress_notification(duel_id, g.user.id, user_name, ruck_id)
                            # except Exception as notif_error:
                            #     logger.error(f"Failed to create duel progress notification: {notif_error}")
                            
                            logger.info(f"Updated duel {duel_id} progress for user {g.user.id}: +{contribution} ({duel['challenge_type']}) = {new_value}")
                            
                            # Check if participant reached target
                            if new_value >= duel['target_value']:
                                supabase.table('duel_participants').update({
                                    'target_reached_at': now.isoformat()
                                }).eq('id', participant_id).execute()
                                logger.info(f"User {g.user.id} reached target in duel {duel_id}")
                        
            except Exception as duel_error:
                logger.error(f"Error updating duel progress for session {ruck_id}: {duel_error}")
                # Don't fail the session completion if duel progress update fails
        
            logger.info(f"Session {ruck_id} completion - achievement checking moved to frontend post-navigation")
            completed_session['new_achievements'] = []  # Empty for now, populated by separate API call
        
            cache_delete_pattern(f"ruck_session:{user_id}:*")
            cache_delete_pattern("ruck_buddies:*")
            cache_delete_pattern(f"weekly_stats:{user_id}:*")
            cache_delete_pattern(f"monthly_stats:{user_id}:*")
            cache_delete_pattern(f"yearly_stats:{user_id}:*")
            cache_delete_pattern(f"user_lifetime_stats:{user_id}")
            cache_delete_pattern(f"user_recent_rucks:{user_id}")
            cache_delete_pattern(f'user_profile:{user_id}:*')

            # Fetch and include splits data in the response
            try:
                splits_resp = supabase.table('session_splits') \
                    .select('*') \
                    .eq('session_id', ruck_id) \
                    .order('split_number') \
                    .execute()
                
                if splits_resp.data:
                    completed_session['splits'] = splits_resp.data
                    logger.info(f"Included {len(splits_resp.data)} splits in completion response for session {ruck_id}")
                else:
                    completed_session['splits'] = []
                    logger.info(f"No splits found for session {ruck_id}")
            except Exception as splits_fetch_error:
                logger.error(f"Error fetching splits for completed session {ruck_id}: {splits_fetch_error}")
                completed_session['splits'] = []  # Ensure splits field exists even if fetch fails
            
            return completed_session, 200
        except Exception as e:
            logger.error(f"Error ending ruck session {ruck_id}: {e}")
            return {'message': f"Error ending ruck session: {str(e)}"}, 500

class RuckSessionLocationResource(Resource):
    def post(self, ruck_id):
        """Upload location points to an active ruck session (POST /api/rucks/<ruck_id>/location)"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            
            data = request.get_json()
            
            # Support both single point and batch of points (like heart rate)
            if 'points' in data:
                # Batch mode - array of location points
                if not isinstance(data['points'], list):
                    return {'message': 'Missing or invalid points'}, 400
                location_points = data['points']
            else:
                # Legacy mode - single point (backwards compatibility)
                if 'latitude' not in data or 'longitude' not in data:
                    return {'message': 'Missing location data'}, 400
                location_points = [data]  # Convert to array format
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Check if session exists and belongs to user (like heart rate)
            session_resp = supabase.table('ruck_session') \
                .select('id,status') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            
            if not session_resp.data:
                logger.warning(f"Session {ruck_id} not found or not accessible for user {g.user.id}")
                return {'message': 'Session not found or access denied'}, 404
            
            session_data = session_resp.data[0]
            if session_data['status'] != 'in_progress':
                logger.warning(f"Session {ruck_id} status is '{session_data['status']}', not 'in_progress'")
                return {'message': f"Session not in progress (status: {session_data['status']})"}, 400
            
            # Insert location points (like heart rate samples)
            location_rows = []
            for point in location_points:
                if 'latitude' not in point or 'longitude' not in point:
                    continue  # Skip invalid points
                location_rows.append({
                    'session_id': ruck_id,
                    'latitude': float(point['latitude']),
                    'longitude': float(point['longitude']),
                    'altitude': point.get('elevation') or point.get('elevation_meters'),
                    'timestamp': point.get('timestamp', datetime.now(tz.tzutc()).isoformat())
                })
            
            if not location_rows:
                return {'message': 'No valid location points'}, 400
                
            insert_resp = supabase.table('location_point').insert(location_rows).execute()
            if not insert_resp.data:
                return {'message': 'Failed to insert location points'}, 500
                
            # Note: No need to invalidate session cache for location points
            # Session data (distance, duration, etc.) is calculated separately
            return {'status': 'ok', 'inserted': len(insert_resp.data)}, 201
            
        except Exception as e:
            logger.error(f"Error adding location points for ruck session {ruck_id}: {e}")
            return {'message': f'Error uploading location points: {str(e)}'}, 500

class RuckSessionEditResource(Resource):
    def put(self, ruck_id):
        """Edit a ruck session - trim/crop session by removing data after new end time"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            
            data = request.get_json()
            if not data:
                return {'message': 'No data provided'}, 400
            
            # Validate required fields
            required_fields = ['end_time', 'duration_seconds', 'distance_km', 'elevation_gain_m', 'elevation_loss_m']
            for field in required_fields:
                if field not in data:
                    return {'message': f'Missing required field: {field}'}, 400
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Verify session exists and belongs to user
            session_resp = supabase.table('ruck_session') \
                .select('id,user_id,status,started_at') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            
            if not session_resp.data:
                logger.warning(f"Session {ruck_id} not found or not accessible for user {g.user.id}")
                return {'message': 'Session not found or access denied'}, 404
            
            session_data = session_resp.data[0]
            
            # Parse the new end time
            try:
                new_end_time = datetime.fromisoformat(data['end_time'].replace('Z', '+00:00'))
            except ValueError as e:
                return {'message': f'Invalid end_time format: {str(e)}'}, 400
            
            # Validate end time is after start time
            start_time = datetime.fromisoformat(session_data['started_at'].replace('Z', '+00:00'))
            if new_end_time <= start_time:
                return {'message': 'End time must be after start time'}, 400
            
            logger.info(f"Editing session {ruck_id} - new end time: {new_end_time}")
            
            # Update session with new metrics
            session_updates = {
                'completed_at': data['end_time'],
                'duration_seconds': data['duration_seconds'],
                'distance_km': data['distance_km'],
                'elevation_gain_m': data['elevation_gain_m'],
                'elevation_loss_m': data['elevation_loss_m'],
                'calories_burned': data.get('calories_burned'),
                'average_pace': data.get('average_pace_min_per_km'),
                'avg_heart_rate': data.get('avg_heart_rate'),
                'max_heart_rate': data.get('max_heart_rate'),
                'min_heart_rate': data.get('min_heart_rate')
            }
            
            # Update the session
            update_resp = supabase.table('ruck_session') \
                .update(session_updates) \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            
            if not update_resp.data:
                return {'message': 'Failed to update session'}, 500
            
            # Delete location points after the new end time
            delete_locations_resp = supabase.table('location_point') \
                .delete() \
                .eq('session_id', ruck_id) \
                .gte('timestamp', data['end_time']) \
                .execute()
            
            logger.info(f"Deleted location points after {data['end_time']} for session {ruck_id}: {len(delete_locations_resp.data) if delete_locations_resp.data else 'unknown'} points deleted")
            
            # Delete heart rate samples after the new end time
            delete_hr_resp = supabase.table('heart_rate_sample') \
                .delete() \
                .eq('session_id', ruck_id) \
                .gte('timestamp', data['end_time']) \
                .execute()
            
            logger.info(f"Deleted heart rate samples after {data['end_time']} for session {ruck_id}")
            
            # Delete splits after the new end time
            delete_splits_resp = supabase.table('session_splits') \
                .delete() \
                .eq('session_id', ruck_id) \
                .gte('split_timestamp', data['end_time']) \
                .execute()
            
            logger.info(f"Deleted splits after {data['end_time']} for session {ruck_id}")
            
            # Clear cache for this user's sessions and location data
            cache_delete_pattern(f"ruck_session:{g.user.id}:*")
            cache_delete_pattern(f"location_points:{ruck_id}:*")
            cache_delete_pattern(f"session_details:{ruck_id}:*")
            
            logger.info(f"Successfully edited session {ruck_id}")
            
            return {
                'message': 'Session updated successfully',
                'session_id': ruck_id,
                'updated_at': (update_resp.data[0].get('updated_at') if update_resp and update_resp.data else None)
            }, 200
            
        except Exception as e:
            logger.error(f"Error editing session {ruck_id}: {e}")
            return {'message': f'Error editing session: {str(e)}'}, 500


class HeartRateSampleUploadResource(Resource):
    def get(self, ruck_id):
        """Get heart rate samples for a ruck session (GET /api/rucks/<ruck_id>/heart_rate)"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
                
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Check if session exists and belongs to user
            session_resp = supabase.table('ruck_session') \
                .select('id,user_id') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
                
            if not session_resp.data:
                logger.warning(f"Session {ruck_id} not found or not accessible for user {g.user.id}")
                return {'message': 'Session not found or access denied'}, 404
            
            session_data = session_resp.data[0]
            
            # Get heart rate samples for this session with intelligent downsampling
            # First get count to determine if we need downsampling
            count_response = supabase.table('heart_rate_sample') \
                .select('id', count='exact') \
                .eq('session_id', ruck_id) \
                .execute()
                
            total_samples = count_response.count or 0
            logger.info(f"Total heart rate samples for session {ruck_id}: {total_samples}")
            
            # Smart downsampling pattern (same as location points)
            MAX_HR_SAMPLES = 400  # Target number of samples for chart performance
            
            if total_samples <= MAX_HR_SAMPLES:
                # For reasonable sample counts, return all data
                response = supabase.table('heart_rate_sample') \
                    .select('*') \
                    .eq('session_id', ruck_id) \
                    .order('timestamp') \
                    .execute()
            else:
                # For large datasets, use database-level downsampling
                interval = max(1, total_samples // MAX_HR_SAMPLES)
                logger.info(f"Downsampling heart rate data: interval={interval}, target={MAX_HR_SAMPLES} samples")
                
                # Try RPC function for efficient database-level sampling
                try:
                    response = supabase.rpc('get_sampled_heart_rate', {
                        'p_session_id': int(ruck_id),
                        'p_interval': interval,
                        'p_max_samples': MAX_HR_SAMPLES
                    }).execute()
                    
                    # If RPC worked and returned data, use it
                    if response.data:
                        logger.info(f"Successfully used RPC function for heart rate downsampling")
                    else:
                        response = None
                except Exception as rpc_error:
                    logger.info(f"RPC function not available: {rpc_error}")
                    response = None
                
                # Fallback to Python-based downsampling if RPC doesn't exist or failed
                if not response or not response.data:
                    logger.info("RPC function not available, using Python-based downsampling")
                    all_samples_response = supabase.table('heart_rate_sample') \
                        .select('*') \
                        .eq('session_id', ruck_id) \
                        .order('timestamp') \
                        .limit(50000) \
                        .execute()
                    
                    if all_samples_response.data:
                        downsampled = all_samples_response.data[::interval]
                        # Ensure we always include the last sample for accurate end time
                        if len(all_samples_response.data) > 0 and all_samples_response.data[-1] not in downsampled:
                            downsampled.append(all_samples_response.data[-1])
                        
                        # Create a mock response object
                        class MockResponse:
                            def __init__(self, data):
                                self.data = data
                        
                        response = MockResponse(downsampled)
                    else:
                        response = all_samples_response
            
            logger.info(f"Retrieved {len(response.data)} heart rate samples for session {ruck_id} (downsampled from {total_samples})")
            return response.data, 200
            
        except Exception as e:
            logger.error(f"Error fetching heart rate samples for session {ruck_id}: {e}")
            return {'message': f"Error fetching heart rate samples: {str(e)}"}, 500

    def post(self, ruck_id):
        """Upload heart rate samples to a ruck session (POST /api/rucks/<ruck_id>/heart_rate)"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            data = request.get_json()
            if not data or 'samples' not in data or not isinstance(data['samples'], list):
                return {'message': 'Missing or invalid samples'}, 400
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            # Check if session exists and belongs to user
            session_resp = supabase.table('ruck_session') \
                .select('id,status') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            
            if not session_resp.data:
                logger.warning(f"Session {ruck_id} not found or not accessible for user {g.user.id}")
                return {'message': 'Session not found or access denied'}, 404
            
            session_data = session_resp.data[0]
            if session_data['status'] != 'in_progress':
                logger.warning(f"Session {ruck_id} status is '{session_data['status']}', not 'in_progress'")
                return {'message': f"Session not in progress (status: {session_data['status']})"}, 400
            
            # Insert heart rate samples
            heart_rate_rows = []
            for sample in data['samples']:
                if 'timestamp' not in sample or 'bpm' not in sample:
                    continue
                heart_rate_rows.append({
                    'session_id': ruck_id,
                    'timestamp': sample['timestamp'],
                    'bpm': sample['bpm']
                })
            if not heart_rate_rows:
                return {'message': 'No valid heart rate samples'}, 400
            insert_resp = supabase.table('heart_rate_sample').insert(heart_rate_rows).execute()
            if not insert_resp.data:
                return {'message': 'Failed to insert heart rate samples'}, 500
            cache_delete_pattern(f"ruck_session:{g.user.id}:*")
            return {'status': 'ok', 'inserted': len(insert_resp.data)}, 201
        except Exception as e:
            return {'message': f'Error uploading heart rate samples: {str(e)}'}, 500


class RuckSessionRouteChunkResource(Resource):
    def post(self, ruck_id):
        """Upload route data chunk for completed session (POST /api/rucks/<ruck_id>/route-chunk)"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            
            data = request.get_json()
            if not data or 'route_points' not in data or not isinstance(data['route_points'], list):
                return {'message': 'Missing or invalid route_points'}, 400
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Check if session exists, belongs to user, and is completed
            session_resp = supabase.table('ruck_session') \
                .select('id,status') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            
            if not session_resp.data:
                logger.warning(f"Session {ruck_id} not found or not accessible for user {g.user.id}")
                return {'message': 'Session not found or access denied'}, 404
            
            session_data = session_resp.data[0]
            if session_data['status'] != 'completed':
                logger.warning(f"Session {ruck_id} status is '{session_data['status']}', not 'completed'")
                return {'message': f"Session not completed (status: {session_data['status']}). Route chunks can only be uploaded to completed sessions."}, 400
            
            # Insert location points
            location_rows = []
            for point in data['route_points']:
                if 'timestamp' not in point or 'lat' not in point or 'lng' not in point:
                    continue
                location_rows.append({
                    'session_id': ruck_id,
                    'timestamp': point['timestamp'],
                    'latitude': point['lat'],
                    'longitude': point['lng'],
                    'altitude': point.get('altitude'),
                    'accuracy': point.get('accuracy'),
                    'speed': point.get('speed'),
                    'heading': point.get('heading')
                })
            
            if not location_rows:
                return {'message': 'No valid location points in chunk'}, 400
            
            insert_resp = supabase.table('location_point').insert(location_rows).execute()
            if not insert_resp.data:
                return {'message': 'Failed to insert location points'}, 500
            
            # Clear cache for this user's sessions
            cache_delete_pattern(f"ruck_session:{g.user.id}:*")
            
            logger.info(f"Successfully uploaded route chunk for session {ruck_id}: {len(insert_resp.data)} points")
            return {'status': 'ok', 'inserted': len(insert_resp.data)}, 201
            
        except Exception as e:
            logger.error(f"Error uploading route chunk for session {ruck_id}: {e}")
            return {'message': f'Error uploading route chunk: {str(e)}'}, 500


class RuckSessionHeartRateChunkResource(Resource):
    def post(self, ruck_id):
        """Upload heart rate data chunk for completed session (POST /api/rucks/<ruck_id>/heart-rate-chunk)"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            
            data = request.get_json()
            if not data or 'heart_rate_samples' not in data or not isinstance(data['heart_rate_samples'], list):
                return {'message': 'Missing or invalid heart_rate_samples'}, 400
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Check if session exists, belongs to user, and is completed
            session_resp = supabase.table('ruck_session') \
                .select('id,status') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            
            if not session_resp.data:
                logger.warning(f"Session {ruck_id} not found or not accessible for user {g.user.id}")
                return {'message': 'Session not found or access denied'}, 404
            
            session_data = session_resp.data[0]
            if session_data['status'] != 'completed':
                logger.warning(f"Session {ruck_id} status is '{session_data['status']}', not 'completed'")
                return {'message': f"Session not completed (status: {session_data['status']}). Heart rate chunks can only be uploaded to completed sessions."}, 400
            
            # Insert heart rate samples
            heart_rate_rows = []
            for sample in data['heart_rate_samples']:
                if 'timestamp' not in sample or 'bpm' not in sample:
                    continue
                heart_rate_rows.append({
                    'session_id': ruck_id,
                    'timestamp': sample['timestamp'],
                    'bpm': sample['bpm']
                })
            
            if not heart_rate_rows:
                return {'message': 'No valid heart rate samples in chunk'}, 400
            
            insert_resp = supabase.table('heart_rate_sample').insert(heart_rate_rows).execute()
            if not insert_resp.data:
                return {'message': 'Failed to insert heart rate samples'}, 500
            
            # Clear cache for this user's sessions
            cache_delete_pattern(f"ruck_session:{g.user.id}:*")
            
            logger.info(f"Successfully uploaded heart rate chunk for session {ruck_id}: {len(insert_resp.data)} samples")
            return {'status': 'ok', 'inserted': len(insert_resp.data)}, 201
            
        except Exception as e:
            logger.error(f"Error uploading heart rate chunk for session {ruck_id}: {e}")
            return {'message': f'Error uploading heart rate chunk: {str(e)}'}, 500