from flask import request, g
from flask_restful import Resource
from datetime import datetime, timedelta
import uuid
import logging
from dateutil import tz

from ..supabase_client import get_supabase_client

logger = logging.getLogger(__name__)

class RuckSessionListResource(Resource):
    def get(self):
        """Get all ruck sessions for the current user"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            supabase = get_supabase_client(user_jwt=getattr(g.user, 'token', None))
            limit = request.args.get('limit', type=int) or 3
            response = supabase.table('ruck_session') \
                .select('*') \
                .eq('user_id', g.user.id) \
                .eq('status', 'completed') \
                .order('completed_at', desc=True) \
                .limit(limit) \
                .execute()
            sessions = response.data
            if sessions is None:
                sessions = []
            # Attach route (list of lat/lng) to each session
            for session in sessions:
                locations_resp = supabase.table('location_point') \
                    .select('latitude,longitude') \
                    .eq('session_id', session['id']) \
                    .order('timestamp') \
                    .execute()
                logger.info(f"Location response data for session {session['id']}: {locations_resp.data}")
                if locations_resp.data:
                    # Attach both 'route' (legacy) and 'location_points' (for frontend compatibility)
                    session['route'] = [{'lat': loc['latitude'], 'lng': loc['longitude']} for loc in locations_resp.data]
                    session['location_points'] = [{'lat': loc['latitude'], 'lng': loc['longitude']} for loc in locations_resp.data]
                else:
                    session['route'] = []
                    session['location_points'] = []
            return {'sessions': sessions}, 200
        except Exception as e:
            logger.error(f"Error fetching ruck sessions: {e}")
            return {'message': f"Error fetching ruck sessions: {str(e)}"}, 500

    def post(self):
        """Create a new ruck session for the current user"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            data = request.get_json()
            if not data:
                return {'message': 'Missing required data for session creation'}, 400
            supabase = get_supabase_client(user_jwt=getattr(g.user, 'token', None))

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
            supabase = get_supabase_client(user_jwt=getattr(g.user, 'token', None))
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
            logger.info(f"Location response data for session {ruck_id}: {locations_resp.data}")
            if locations_resp.data:
                # Attach both 'route' (legacy) and 'location_points' (for frontend compatibility)
                session['route'] = [{'lat': loc['latitude'], 'lng': loc['longitude']} for loc in locations_resp.data]
                session['location_points'] = [{'lat': loc['latitude'], 'lng': loc['longitude']} for loc in locations_resp.data]
            else:
                session['route'] = []
                session['location_points'] = []
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

            allowed_fields = ['notes', 'rating', 'perceived_exertion', 'tags']
            update_data = {k: v for k, v in data.items() if k in allowed_fields}

            if not update_data:
                return {'message': 'No valid fields to update'}, 400

            supabase = get_supabase_client(user_jwt=getattr(g.user, 'token', None))
            update_resp = supabase.table('ruck_session') \
                .update(update_data) \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()

            if not update_resp.data or len(update_resp.data) == 0:
                return {'message': 'Failed to update session'}, 500

            return update_resp.data[0], 200
        except Exception as e:
            logger.error(f"Error updating ruck session {ruck_id}: {e}")
            return {'message': f"Error updating ruck session: {str(e)}"}, 500

    def delete(self, ruck_id):
        """Hard delete a ruck session and all associated location_point records for the authenticated user."""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            supabase = get_supabase_client(user_jwt=getattr(g.user, 'token', None))
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

        """Allow updating notes, rating, perceived_exertion, and tags on any session."""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            data = request.get_json()
            if not data:
                return {'message': 'No data provided'}, 400

            allowed_fields = ['notes', 'rating', 'perceived_exertion', 'tags']
            update_data = {k: v for k, v in data.items() if k in allowed_fields}

            if not update_data:
                return {'message': 'No valid fields to update'}, 400

            supabase = get_supabase_client(user_jwt=getattr(g.user, 'token', None))
            update_resp = supabase.table('ruck_session') \
                .update(update_data) \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()

            if not update_resp.data or len(update_resp.data) == 0:
                return {'message': 'Failed to update session'}, 500

            return update_resp.data[0], 200
        except Exception as e:
            logger.error(f"Error updating ruck session {ruck_id}: {e}")
            return {'message': f"Error updating ruck session: {str(e)}"}, 500

        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            supabase = get_supabase_client(user_jwt=getattr(g.user, 'token', None))
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
            logger.info(f"Location response data for session {ruck_id}: {locations_resp.data}")
            if locations_resp.data:
                # Attach both 'route' (legacy) and 'location_points' (for frontend compatibility)
                session['route'] = [{'lat': loc['latitude'], 'lng': loc['longitude']} for loc in locations_resp.data]
                session['location_points'] = [{'lat': loc['latitude'], 'lng': loc['longitude']} for loc in locations_resp.data]
            else:
                session['route'] = []
                session['location_points'] = []
            return session, 200
        except Exception as e:
            logger.error(f"Error fetching ruck session {ruck_id}: {e}")
            return {'message': f"Error fetching ruck session: {str(e)}"}, 500

class RuckSessionStartResource(Resource):
    def post(self, ruck_id):
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            supabase = get_supabase_client(user_jwt=getattr(g.user, 'token', None))
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
            supabase = get_supabase_client(user_jwt=getattr(g.user, 'token', None))
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
            supabase = get_supabase_client(user_jwt=getattr(g.user, 'token', None))
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
            supabase = get_supabase_client(user_jwt=getattr(g.user, 'token', None))
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
            # Only calculate if both duration and distance are valid
            final_average_pace = None
            if distance_km and distance_km > 0 and duration_seconds > 0:
                final_average_pace = duration_seconds / distance_km  # seconds per km
            # Update session status to completed with end data
            update_data = {
                'status': 'completed',
                'duration_seconds': duration_seconds
            }
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
            if 'completed_at' in data:
                update_data['completed_at'] = data['completed_at']
            if 'start_time' in data:
                update_data['start_time'] = data['start_time']
            if 'end_time' in data:
                update_data['end_time'] = data['end_time']
            if 'final_average_pace' in data:
                update_data['final_average_pace'] = data['final_average_pace']
            if 'average_pace' in data:
                update_data['final_average_pace'] = data['average_pace']
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
            # Continue with update as before
            update_resp = supabase.table('ruck_session') \
                .update(update_data) \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            if not update_resp.data or len(update_resp.data) == 0:
                logger.error(f"Failed to end session {ruck_id}: {update_resp.error}")
                return {'message': 'Failed to end session'}, 500
            return update_resp.data[0], 200
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
            supabase = get_supabase_client(user_jwt=getattr(g.user, 'token', None))
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

class HeartRateSampleUploadResource(Resource):
    def post(self, ruck_id):
        """Upload heart rate samples to a ruck session (POST /api/rucks/<ruck_id>/heart_rate)"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            data = request.get_json()
            if not data or 'samples' not in data or not isinstance(data['samples'], list):
                return {'message': 'Missing or invalid samples'}, 400
            supabase = get_supabase_client(user_jwt=getattr(g.user, 'token', None))
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
                    'bpm': sample['bpm'],
                    'user_id': g.user.id
                })
            if not heart_rate_rows:
                return {'message': 'No valid heart rate samples'}, 400
            insert_resp = supabase.table('heart_rate_sample').insert(heart_rate_rows).execute()
            if not insert_resp.data:
                return {'message': 'Failed to insert heart rate samples'}, 500
            return {'status': 'ok', 'inserted': len(insert_resp.data)}, 201
        except Exception as e:
            return {'message': f'Error uploading heart rate samples: {str(e)}'}, 500