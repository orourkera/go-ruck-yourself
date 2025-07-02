from flask import request, g
from flask_restful import Resource
from datetime import datetime, timedelta
import uuid
import logging
import math
from dateutil import tz

from RuckTracker.supabase_client import get_supabase_client
from RuckTracker.services.redis_cache_service import cache_delete_pattern, cache_get, cache_set

logger = logging.getLogger(__name__)

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
                
            limit = request.args.get('limit', 50, type=int)  # Default to 50 sessions max
            
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
                .limit(min(limit, 100))  # Cap at 100 sessions max
            
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
            MAX_POINTS_PER_SESSION = 100  # Reduced for better performance
            
            logger.info(f"[ROUTE_DEBUG] Starting to fetch location points for {len(session_ids)} sessions")
            
            try:
                all_location_points = []
                
                for session_id in session_ids:
                    logger.info(f"[ROUTE_DEBUG] Processing session {session_id}")
                    
                    # Intelligent sampling using Postgres RPC to keep route quality while capping memory
                    count_resp = supabase.table('location_point') \
                        .select('id', count='exact') \
                        .eq('session_id', int(session_id)) \
                        .execute()

                    total_points = count_resp.count or 0
                    logger.info(f"[ROUTE_DEBUG] Session {session_id} has {total_points} location points in database")

                    if total_points <= MAX_POINTS_PER_SESSION:
                        # Small sessions – return all points
                        logger.info(f"[ROUTE_DEBUG] Session {session_id}: Using direct query (≤{MAX_POINTS_PER_SESSION} points)")
                        session_locations = supabase.table('location_point') \
                            .select('session_id,latitude,longitude,timestamp') \
                            .eq('session_id', int(session_id)) \
                            .order('timestamp') \
                            .execute()
                    else:
                        # Large sessions – sample via RPC
                        interval = max(1, total_points // MAX_POINTS_PER_SESSION)
                        logger.info(f"[ROUTE_DEBUG] Session {session_id}: Using RPC sampling (interval={interval}, target={MAX_POINTS_PER_SESSION} points)")
                        session_locations = supabase.rpc('get_sampled_route_points', {
                            'p_session_id': int(session_id),
                            'p_interval': interval,
                            'p_max_points': MAX_POINTS_PER_SESSION
                        }).execute()
                    
                    fetched_points = len(session_locations.data) if session_locations.data else 0
                    logger.info(f"[ROUTE_DEBUG] Session {session_id}: Fetched {fetched_points} location points from query")
                    
                    if session_locations.data:
                        all_location_points.extend(session_locations.data)
                        logger.info(f"[ROUTE_DEBUG] Session {session_id}: Added {fetched_points} points to all_location_points")
                    else:
                        logger.warning(f"[ROUTE_DEBUG] Session {session_id}: No location data returned from query")
                
                logger.info(f"[ROUTE_DEBUG] Total fetched: {len(all_location_points)} location points for {len(session_ids)} sessions")
                
                # Group location points by session_id
                for loc in all_location_points:
                    session_id = loc['session_id']
                    if session_id not in locations_by_session:
                        locations_by_session[session_id] = []
                    
                    # Ensure the location data contains latitude and longitude
                    if 'latitude' in loc and 'longitude' in loc:
                        try:
                            # Convert numeric values if needed
                            lat = float(loc['latitude']) if loc['latitude'] is not None else None
                            lng = float(loc['longitude']) if loc['longitude'] is not None else None
                            
                            if lat is not None and lng is not None:
                                locations_by_session[session_id].append({
                                    'lat': lat,
                                    'lng': lng
                                })
                        except (ValueError, TypeError):
                            logger.warning(f"[ROUTE_DEBUG] Invalid lat/lng in location point: {loc}")
                            continue
                    else:
                        logger.warning(f"[ROUTE_DEBUG] Location point missing lat/lng: {loc}")
                
                logger.info(f"[ROUTE_DEBUG] Grouped into {len(locations_by_session)} sessions with location data")
                for session_id, points in locations_by_session.items():
                    logger.info(f"[ROUTE_DEBUG] Session {session_id}: {len(points)} valid points after processing")
            
            except Exception as e:
                logger.error(f"[ROUTE_DEBUG] ERROR: Failed to fetch location points: {e}")
                locations_by_session = {}
            
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
            if 'ruck_weight_kg' in data and data.get('ruck_weight_kg') is not None:
                session_data['ruck_weight_kg'] = data.get('ruck_weight_kg')
            if 'weight_kg' in data and data.get('weight_kg') is not None:
                session_data['weight_kg'] = data.get('weight_kg')
            
            # Add event_id if provided (for event-associated ruck sessions)
            if 'event_id' in data and data.get('event_id') is not None:
                session_data['event_id'] = data.get('event_id')
                logger.info(f"Creating session for event {data.get('event_id')}")
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
                    .select('*, user:user_id(allow_ruck_sharing)') \
                    .eq('id', ruck_id) \
                    .eq('is_public', True) \
                    .execute()
                
                if not response.data or len(response.data) == 0:
                    return {'message': 'Session not found'}, 404
                    
                session = response.data[0]
                
                # Check if the session owner allows sharing
                user_data = session.get('user')
                if not user_data or not user_data.get('allow_ruck_sharing', False):
                    return {'message': 'Session not found'}, 404
            else:
                session = response.data[0]
            
            # Fetch location points with intelligent sampling
            MAX_POINTS_FOR_DETAIL = 500
            count_resp = supabase.table('location_point') \
                .select('id', count='exact') \
                .eq('session_id', ruck_id) \
                .execute()

            total_points = count_resp.count or 0

            if total_points <= MAX_POINTS_FOR_DETAIL:
                locations_resp = supabase.table('location_point') \
                    .select('latitude,longitude,timestamp') \
                    .eq('session_id', ruck_id) \
                    .order('timestamp') \
                    .execute()
            else:
                interval = max(1, total_points // MAX_POINTS_FOR_DETAIL)
                locations_resp = supabase.rpc('get_sampled_route_points', {
                    'p_session_id': int(ruck_id),
                    'p_interval': interval,
                    'p_max_points': MAX_POINTS_FOR_DETAIL
                }).execute()
            
            logger.debug(f"Location response data for session {ruck_id}: {len(locations_resp.data) if locations_resp.data else 0} points")
            
            if locations_resp.data:
                # Convert location points to the expected format
                # Accept both latitude/longitude or lat/lng keys (RPC may return either format)
                location_points = []
                for loc in locations_resp.data:
                    lat_val = loc.get('latitude', loc.get('lat'))
                    lng_val = loc.get('longitude', loc.get('lng'))
                    if lat_val is None or lng_val is None:
                        logger.debug(f"[ROUTE_PARSE] Skipping location with missing coords: {loc}")
                        continue
                    location_points.append({
                        'lat': float(lat_val),
                        'lng': float(lng_val),
                        'timestamp': loc.get('timestamp', loc.get('point_time', ''))
                    })
                
                # Apply privacy clipping if this is not the user's own session
                if not is_own_session:
                    original_count = len(location_points)
                    location_points = clip_route_for_privacy(location_points)
                    logger.debug(f"[PRIVACY_DEBUG] Session {ruck_id} viewed by user {g.user.id}: Original points: {original_count}, Clipped points: {len(location_points)}")
                else:
                    logger.debug(f"[PRIVACY_DEBUG] Session {ruck_id} viewed by owner {g.user.id}: No clipping applied")
                
                # Attach both 'route' (legacy) and 'location_points' (for frontend compatibility)
                session['route'] = location_points
                session['location_points'] = location_points
            else:
                session['route'] = []
                session['location_points'] = []
            
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
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            data = request.get_json()
            if not data:
                return {'message': 'No data provided'}, 400
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            # Check if session exists
            session_check = supabase.table('ruck_session') \
                .select('id,status,started_at') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            if not session_check.data or len(session_check.data) == 0:
                return {'message': 'Session not found'}, 404
            current_status = session_check.data[0]['status']
            started_at_str = session_check.data[0].get('started_at')
            if current_status not in ['in_progress', 'paused']:
                return {'message': 'Session not in progress or paused'}, 400
            
            # Fetch user's allow_ruck_sharing preference to set default for is_public
            user_resp = supabase.table('user') \
                .select('allow_ruck_sharing') \
                .eq('id', g.user.id) \
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
        
            server_calculated_pace = None
            if distance_km and distance_km > 0 and duration_seconds > 0:
                server_calculated_pace = duration_seconds / distance_km  # seconds per km

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

            # Store server-calculated pace first
            if server_calculated_pace is not None:
                update_data['average_pace'] = server_calculated_pace

            if 'start_time' in data:
                update_data['start_time'] = data['start_time']
            if 'end_time' in data: # Keep this for now, though completed_at should be primary
                update_data['end_time'] = data['end_time']
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
                            # Calculate elevation gain for this split
                            split_elevation_gain = 0.0
                            
                            if session_location_points:
                                try:
                                    # Calculate elevation gain for this split based on location points
                                    split_number = split.get('split_number', 1)
                                    total_distance_km = split.get('total_distance', 0)
                                    prev_total_distance_km = 0
                                    
                                    # Find previous split's total distance
                                    if split_number > 1:
                                        for prev_split in splits_data:
                                            if prev_split.get('split_number') == split_number - 1:
                                                prev_total_distance_km = prev_split.get('total_distance', 0)
                                                break
                                    
                                    # Find location points that fall within this split's distance range
                                    split_start_points = []
                                    split_end_points = []
                                    
                                    for point in session_location_points:
                                        if isinstance(point, dict) and 'cumulative_distance_km' in point and 'altitude' in point:
                                            point_distance = point['cumulative_distance_km']
                                            if prev_total_distance_km <= point_distance <= total_distance_km:
                                                if not split_start_points and point_distance >= prev_total_distance_km:
                                                    split_start_points.append(point)
                                                if point_distance >= total_distance_km * 0.9:  # Near end of split
                                                    split_end_points.append(point)
                                    
                                    # Calculate elevation gain
                                    if split_start_points and split_end_points:
                                        start_elevation = sum(p['altitude'] for p in split_start_points) / len(split_start_points)
                                        end_elevation = sum(p['altitude'] for p in split_end_points) / len(split_end_points)
                                        split_elevation_gain = max(0, end_elevation - start_elevation)  # Only positive gain
                                        
                                        logger.debug(f"Split {split_number}: elevation gain calculated as {split_elevation_gain:.1f}m (start: {start_elevation:.1f}m, end: {end_elevation:.1f}m)")
                                    
                                except Exception as elev_calc_error:
                                    logger.warning(f"Error calculating elevation for split {split.get('split_number')}: {elev_calc_error}")
                                    split_elevation_gain = 0.0
                            
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
        
            # Check for achievements after session completion
            try:
                logger.info(f"Checking achievements for completed session {ruck_id}")
                
                # Import achievement checking function
                from RuckTracker.api.achievements import CheckSessionAchievementsResource
                
                # Create instance and check achievements
                achievement_checker = CheckSessionAchievementsResource()
                new_achievements = []
                
                # Get all active achievements
                achievements_response = supabase.table('achievements').select('*').eq('is_active', True).execute()
                achievements = achievements_response.data or []
                
                # Check each achievement
                for achievement in achievements:
                    # Check if user already has this achievement
                    existing = supabase.table('user_achievements').select('id').eq(
                        'user_id', g.user.id
                    ).eq('achievement_id', achievement['id']).execute()
                    
                    if existing.data:
                        continue  # User already has this achievement
                    
                    # Check if user meets criteria for this achievement
                    if achievement_checker._check_achievement_criteria(supabase, g.user.id, completed_session, achievement):
                        # Award the achievement
                        award_data = {
                            'user_id': g.user.id,
                            'achievement_id': achievement['id'],
                            'session_id': ruck_id,
                            'earned_at': datetime.utcnow().isoformat(),
                            'metadata': {'triggered_by_session': ruck_id}
                        }
                        
                        supabase.table('user_achievements').insert(award_data).execute()
                        new_achievements.append(achievement)
                        
                        logger.info(f"Awarded achievement {achievement['name']} to user {g.user.id} for session {ruck_id}")
                
                # Add achievements to response for frontend display
                completed_session['new_achievements'] = new_achievements
                
                if new_achievements:
                    logger.info(f"User {g.user.id} earned {len(new_achievements)} new achievements in session {ruck_id}")
                    # Add achievements to response for frontend to display
                    completed_session['new_achievements'] = new_achievements
                else:
                    logger.info(f"No new achievements earned by user {g.user.id} in session {ruck_id}")
                    completed_session['new_achievements'] = []
                    
            except Exception as achievement_error:
                logger.error(f"Error checking achievements for session {ruck_id}: {achievement_error}")
                # Don't fail the session completion if achievement checking fails
                completed_session['new_achievements'] = []
        
            cache_delete_pattern(f"ruck_session:{g.user.id}:*")
            cache_delete_pattern("ruck_buddies:*")
            cache_delete_pattern(f"weekly_stats:{g.user.id}:*")
            cache_delete_pattern(f"monthly_stats:{g.user.id}:*")
            cache_delete_pattern(f"yearly_stats:{g.user.id}:*")
            
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
                
            cache_delete_pattern(f"ruck_session:{g.user.id}:*")
            return {'status': 'ok', 'inserted': len(insert_resp.data)}, 201
            
        except Exception as e:
            logger.error(f"Error adding location points for ruck session {ruck_id}: {e}")
            return {'message': f"Error uploading location points: {str(e)}"}, 500

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