from flask import request, g
from flask_restful import Resource
from datetime import datetime
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
            response = supabase.table('ruck_session') \
                .select('*') \
                .eq('user_id', g.user.id) \
                .order('created_at', desc=True) \
                .execute()
            sessions = response.data
            if sessions is None:
                sessions = []
            # Attach route (list of lat/lng) to each session
            for session in sessions:
                locations_resp = supabase.table('location_point') \
                    .select('latitude,longitude') \
                    .eq('session_id', session['id']) \
                    .order('timestamp', desc=True) \
                    .execute()
                if locations_resp.data:
                    session['route'] = [{'lat': loc['latitude'], 'lng': loc['longitude']} for loc in locations_resp.data]
                else:
                    session['route'] = []
            # Get limit from query params, if provided
            limit = request.args.get('limit', type=int)
            if limit is not None:
                sessions = sessions[:limit]
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
            session_data = {
                'user_id': g.user.id,
                'status': 'in_progress',
                'started_at': datetime.now(tz.tzutc()).isoformat()
            }
            # Only add optional fields if they exist in data
            if 'planned_duration_minutes' in data and data.get('planned_duration_minutes') is not None:
                session_data['planned_duration_minutes'] = data.get('planned_duration_minutes')
            if 'ruck_weight_kg' in data and data.get('ruck_weight_kg') is not None:
                session_data['ruck_weight_kg'] = data.get('ruck_weight_kg')
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
                .single() \
                .execute()
            if not response.data:
                return {'message': 'Session not found'}, 404
            locations_resp = supabase.table('location_point') \
                .select('latitude,longitude') \
                .eq('session_id', ruck_id) \
                .order('timestamp', desc=True) \
                .execute()
            session = response.data
            if locations_resp.data:
                session['route'] = [{'lat': loc['latitude'], 'lng': loc['longitude']} for loc in locations_resp.data]
            else:
                session['route'] = []
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
                .single() \
                .execute()
            if not check.data:
                return {'message': 'Session not found'}, 404
            if check.data['status'] != 'created':
                # Instead of error, return the existing session with 200
                return check.data, 200
            # Update status to in_progress
            update_resp = supabase.table('ruck_session') \
                .update({'status': 'in_progress', 'started_at': datetime.now(tz.tzutc()).isoformat()}) \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .single() \
                .execute()
            if not update_resp.data:
                logger.error(f"Failed to start session {ruck_id}: {update_resp.error}")
                return {'message': 'Failed to start session'}, 500
            return update_resp.data, 200
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
                .single() \
                .execute()
            if not check.data:
                return {'message': 'Session not found'}, 404
            if check.data['status'] != 'in_progress':
                return {'message': 'Session not in progress'}, 400
            # Update status to paused
            update_resp = supabase.table('ruck_session') \
                .update({'status': 'paused'}) \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .single() \
                .execute()
            if not update_resp.data:
                logger.error(f"Failed to pause session {ruck_id}: {update_resp.error}")
                return {'message': 'Failed to pause session'}, 500
            return update_resp.data, 200
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
                .single() \
                .execute()
            if not check.data:
                return {'message': 'Session not found'}, 404
            if check.data['status'] != 'paused':
                return {'message': 'Session not paused'}, 400
            # Update status to in_progress
            update_resp = supabase.table('ruck_session') \
                .update({'status': 'in_progress'}) \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .single() \
                .execute()
            if not update_resp.data:
                logger.error(f"Failed to resume session {ruck_id}: {update_resp.error}")
                return {'message': 'Failed to resume session'}, 500
            return update_resp.data, 200
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
                .single() \
                .execute()
            if not session_check.data:
                return {'message': 'Session not found'}, 404
            current_status = session_check.data['status']
            started_at_str = session_check.data.get('started_at')
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
            # Update session status to completed with end data
            update_data = {
                'status': 'completed',
                'ended_at': datetime.now(tz.tzutc()).isoformat(),
                'duration_seconds': duration_seconds
            }
            # Add optional fields if provided
            if 'distance_meters' in data:
                update_data['distance_meters'] = data['distance_meters']
            if 'weight_kg' in data:
                update_data['weight_kg'] = data['weight_kg']
            update_resp = supabase.table('ruck_session') \
                .update(update_data) \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .single() \
                .execute()
            if not update_resp.data:
                logger.error(f"Failed to end session {ruck_id}: {update_resp.error}")
                return {'message': 'Failed to end session'}, 500
            return update_resp.data, 200
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
                .single() \
                .execute()
            if not check.data:
                return {'message': 'Session not found'}, 404
            if check.data['status'] != 'in_progress':
                return {'message': 'Session not in progress'}, 400
            # Insert location point
            location_data = {
                'session_id': ruck_id,
                'latitude': data['latitude'],
                'longitude': data['longitude'],
                'timestamp': datetime.now(tz.tzutc()).isoformat()
            }
            insert_resp = supabase.table('location_point') \
                .insert(location_data) \
                .execute()
            if not insert_resp.data:
                logger.error(f"Failed to add location point for session {ruck_id}: {insert_resp.error}")
                return {'message': 'Failed to add location point'}, 500
            return insert_resp.data[0], 201
        except Exception as e:
            logger.error(f"Error adding location point for ruck session {ruck_id}: {e}")
            return {'message': f"Error adding location point: {str(e)}"}, 500