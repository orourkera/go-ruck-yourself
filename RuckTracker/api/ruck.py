from flask import request, g
from flask_restful import Resource
from datetime import datetime, timedelta
import uuid
import logging
from dateutil import tz

from RuckTracker.supabase_client import get_supabase_client

logger = logging.getLogger(__name__)

class RuckSessionListResource(Resource):
    def get(self):
        """Get all ruck sessions for the current user"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            limit = request.args.get('limit', type=int)
        # If limit is None, do not apply limit
            response_query = supabase.table('ruck_session') \
                .select('*') \
                .eq('user_id', g.user.id) \
                .eq('status', 'completed') \
                .order('completed_at', desc=True)
            if limit:
                response_query = response_query.limit(limit)
            response = response_query.execute()
            sessions = response.data
            if sessions is None:
                sessions = []
            
            # Get all session IDs for batch queries
            session_ids = [session['id'] for session in sessions]
            
            if not session_ids:
                return sessions, 200
            
            # Batch fetch all location points for all sessions with pagination
            try:
                all_location_points = []
                page_size = 1000  # Use Supabase's actual limit
                offset = 0
                
                while True:
                    logger.info(f"DEBUG: Fetching location points page: offset={offset}, limit={page_size}")
                    locations_page = supabase.table('location_point') \
                        .select('session_id,latitude,longitude') \
                        .in_('session_id', session_ids) \
                        .order('session_id,timestamp') \
                        .range(offset, offset + page_size - 1) \
                        .execute()
                    
                    if not locations_page.data:
                        logger.info(f"DEBUG: No more location points, stopping pagination")
                        break
                    
                    points_in_page = len(locations_page.data)
                    all_location_points.extend(locations_page.data)
                    logger.info(f"DEBUG: Got {points_in_page} points, total so far: {len(all_location_points)}")
                    
                    # If we got less than page_size, we're done
                    if points_in_page < page_size:
                        logger.info(f"DEBUG: Got partial page ({points_in_page} < {page_size}), stopping pagination")
                        break
                    
                    offset += page_size
                    
                    # Safety check to prevent infinite loops
                    if offset > 50000:
                        logger.warning(f"Location points query exceeded 50k limit, stopping pagination")
                        break
                
                # Create a mock response object for compatibility
                class MockResponse:
                    def __init__(self, data):
                        self.data = data
                
                all_locations_resp = MockResponse(all_location_points)
                
                logger.info(f"DEBUG: Fetching location points for session IDs: {session_ids}")
                logger.info(f"DEBUG: Location points query returned {len(all_location_points)} total points via pagination")
                
                if hasattr(all_locations_resp, 'count') and all_locations_resp.count:
                    logger.info(f"DEBUG: Query count metadata: {all_locations_resp.count}")
            except Exception as e:
                logger.error(f"ERROR: Failed to fetch location points: {e}")
                all_locations_resp = None
            
            # Batch fetch all splits for all sessions  
            all_splits_resp = supabase.table('session_splits') \
                .select('session_id,split_number,split_distance_km,split_duration_seconds') \
                .in_('session_id', session_ids) \
                .order('session_id,split_number') \
                .execute()
            
            # Group location points by session_id
            locations_by_session = {}
            if all_locations_resp and all_locations_resp.data:
                for loc in all_locations_resp.data:
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
                                locations_by_session[session_id].append({'lat': lat, 'lng': lng})
                        except (ValueError, TypeError) as e:
                            logger.warning(f"Invalid location data for session {session_id}: {e}")
            
            # Sample location points for display performance
            for session_id in locations_by_session:
                points = locations_by_session[session_id]
                if len(points) > 200:  # If more than 200 points, sample every nth point
                    step = len(points) // 150  # Keep roughly 150 points for smooth display
                    sampled_points = points[::step]
                    # Always include first and last points for complete route
                    if points[0] not in sampled_points:
                        sampled_points.insert(0, points[0])
                    if points[-1] not in sampled_points:
                        sampled_points.append(points[-1])
                    locations_by_session[session_id] = sampled_points
                    logger.info(f"DEBUG: Sampled session {session_id} from {len(points)} to {len(sampled_points)} points")
            
            # Debug: Log which sessions have location data
            sessions_with_locations = set(locations_by_session.keys())
            logger.info(f"DEBUG: Sessions with location data: {sessions_with_locations}")
            logger.info(f"DEBUG: Sessions without location data: {set(session_ids) - sessions_with_locations}")
            
            # Group splits by session_id
            splits_by_session = {}
            if all_splits_resp.data:
                for split in all_splits_resp.data:
                    session_id = split['session_id']
                    if session_id not in splits_by_session:
                        splits_by_session[session_id] = []
                    
                    distance_km = split['split_distance_km']
                    duration_seconds = split['split_duration_seconds']
                    
                    # Calculate pace (seconds per km)
                    pace_per_km = duration_seconds / distance_km if distance_km > 0 else 0
                    
                    splits_by_session[session_id].append({
                        'split_number': split['split_number'],
                        'distance_km': distance_km,
                        'duration_seconds': duration_seconds,
                        'pace_per_km': pace_per_km
                    })
            
            # Attach route and splits data to each session
            for session in sessions:
                session_id = session['id']
                
                # Attach location points
                location_points = locations_by_session.get(session_id, [])
                session['route'] = location_points  # legacy
                session['location_points'] = location_points
                
                # Debug: Log which sessions get empty location points
                logger.info(f"DEBUG: Session {session_id} gets {len(location_points)} location points")
                
                # Attach splits
                session['splits'] = splits_by_session.get(session_id, [])
            
            logger.info(f"Session data being returned to client (sample of up to 3 sessions):")
            for i, session in enumerate(sessions[:3]):
                logger.info(f"Session sample {i+1}: {{'id': {session['id']}, 'start_time': {session.get('start_time')}, 'created_at': {session.get('created_at')}, 'completed_at': {session.get('completed_at')}, 'end_time': {session.get('end_time')}, 'status': {session.get('status')}}}")
            if len(sessions) > 3:
                logger.info(f"...(and {len(sessions) - 3} more sessions)")
            
            return sessions, 200
        except Exception as e:
            logger.error(f"Error getting ruck sessions: {e}")
            return {'message': f"Error getting ruck sessions: {str(e)}"}, 500

    def post(self):
        """Create a new ruck session for the current user"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            data = request.get_json()
            if not data:
                return {'message': 'Missing required data for session creation'}, 400
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
                
            insert_resp = supabase.table('ruck_session') \
                .insert(session_data) \
                .execute()
            if not insert_resp.data:
                logger.error(f"Failed to create session: {insert_resp.error}")
                return {'message': 'Failed to create session'}, 500
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
            response = supabase.table('ruck_session') \
                .select('*') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            if not response.data or len(response.data) == 0:
                return {'message': 'Session not found'}, 404
            session = response.data[0]
            locations_resp = supabase.table('location_point') \
                .select('latitude,longitude') \
                .eq('session_id', ruck_id) \
                .order('timestamp', desc=True) \
                .execute()
            logger.debug(f"Location response data for session {ruck_id}: {len(locations_resp.data) if locations_resp.data else 0} points")
            if locations_resp.data:
                # Attach both 'route' (legacy) and 'location_points' (for frontend compatibility)
                session['route'] = [{'lat': loc['latitude'], 'lng': loc['longitude']} for loc in locations_resp.data]
                session['location_points'] = [{'lat': loc['latitude'], 'lng': loc['longitude']} for loc in locations_resp.data]
            else:
                session['route'] = []
                session['location_points'] = []
            
            # Fetch splits data
            splits_resp = supabase.table('session_splits') \
                .select('split_number,split_distance_km,split_duration_seconds') \
                .eq('session_id', ruck_id) \
                .order('split_number') \
                .execute()
            
            if splits_resp.data:
                # Convert splits to the format expected by frontend
                session['splits'] = []
                for split in splits_resp.data:
                    distance_km = split['split_distance_km']
                    duration_seconds = split['split_duration_seconds']
                    
                    # Calculate pace (seconds per km)
                    pace_seconds_per_km = duration_seconds / distance_km if distance_km > 0 else 0
                    
                    session['splits'].append({
                        'splitNumber': split['split_number'],
                        'distance': distance_km * 1000, # Convert km to meters
                        'duration': duration_seconds,
                        'paceSecondsPerKm': pace_seconds_per_km
                    })
            else:
                session['splits'] = []
            
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
                            'split_number': split.get('splitNumber'),
                            'split_distance_km': split.get('distance', 0) / 1000.0 if split.get('distance') else 0,  # Convert meters to km
                            'split_duration_seconds': split.get('duration', {}).get('inSeconds') if isinstance(split.get('duration'), dict) else split.get('duration'),
                            'total_distance_km': 0,  # Will be calculated by database trigger or set separately
                            'total_duration_seconds': 0,  # Will be calculated by database trigger or set separately
                            'split_timestamp': datetime.now(tz.tzutc()).isoformat()
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
            return update_resp.data[0], 200
        except Exception as e:
            logger.error(f"Error resuming ruck session {ruck_id}: {e}")
            return {'message': f"Error resuming ruck session: {str(e)}"}, 500

class RuckSessionCompleteResource(Resource):
    def post(self, ruck_id):
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
        
            return completed_session, 200
        except Exception as e:
            logger.error(f"Error ending ruck session {ruck_id}: {e}")
            return {'message': f"Error ending ruck session: {str(e)}"}, 500

class RuckSessionLocationResource(Resource):
    def post(self, ruck_id):
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            data = request.get_json()
            if not data or 'latitude' not in data or 'longitude' not in data:
                return {'message': 'Missing location data'}, 400
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
            # Insert location point
            location_data = {
                'session_id': ruck_id,
                'latitude': data['latitude'],
                'longitude': data['longitude'],
                'altitude': data.get('elevation') or data.get('elevation_meters'),
                'timestamp': data.get('timestamp', datetime.now(tz.tzutc()).isoformat())
            }
            insert_resp = supabase.table('location_point') \
                .insert(location_data) \
                .execute()
            if not insert_resp.data or len(insert_resp.data) == 0:
                logger.error(f"Failed to add location point for session {ruck_id}: {insert_resp.error}")
                return {'message': 'Failed to add location point'}, 500
            return insert_resp.data[0], 201
        except Exception as e:
            logger.error(f"Error adding location point for ruck session {ruck_id}: {e}")
            return {'message': f"Error adding location point: {str(e)}"}, 500

from flask import request, g
from flask_restful import Resource

from flask_limiter.util import get_remote_address

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
                .single() \
                .execute()
                
            if not session_resp.data:
                return {'message': 'Session not found'}, 404
            
            # Get heart rate samples for this session
            response = supabase.table('heart_rate_sample') \
                .select('*') \
                .eq('session_id', ruck_id) \
                .order('timestamp') \
                .execute()
            
            logger.info(f"Retrieved {len(response.data)} heart rate samples for session {ruck_id}")
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
                .select('id,user_id') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .single() \
                .execute()
            if not session_resp.data:
                return {'message': 'Session not found'}, 404
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
            return {'status': 'ok', 'inserted': len(insert_resp.data)}, 201
        except Exception as e:
            return {'message': f'Error uploading heart rate samples: {str(e)}'}, 500