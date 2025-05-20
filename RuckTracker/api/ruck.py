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
            # Attach route (list of lat/lng) to each session
            for session in sessions:
                locations_resp = supabase.table('location_point') \
                    .select('latitude,longitude') \
                    .eq('session_id', session['id']) \
                    .order('timestamp') \
                    .execute()
                
                logger.info(f"Location response data for session {session['id']}: {locations_resp.data}")
                
                if locations_resp.data:
                    # Process and verify location data is valid
                    valid_location_points = []
                    for loc in locations_resp.data:
                        # Ensure the location data contains latitude and longitude
                        if 'latitude' in loc and 'longitude' in loc:
                            try:
                                # Convert numeric values if needed
                                lat = float(loc['latitude']) if loc['latitude'] is not None else None
                                lng = float(loc['longitude']) if loc['longitude'] is not None else None
                                
                                if lat is not None and lng is not None:
                                    valid_location_points.append({'lat': lat, 'lng': lng})
                            except (ValueError, TypeError) as e:
                                logger.warning(f"Invalid location data for session {session['id']}: {e}")
                    
                    logger.info(f"Processed {len(valid_location_points)} valid location points for session {session['id']}")
                    
                    # Attach both 'route' (legacy) and 'location_points' (for frontend compatibility)
                    session['route'] = valid_location_points
                    session['location_points'] = valid_location_points
                else:
                    session['route'] = []
                    session['location_points'] = []
            
            # Log the sessions data before returning to client
            logger.info(f"Session data being returned to client (sample of up to 3 sessions):")
            for i, session_data in enumerate(sessions[:3]): # Log first 3 sessions as sample
                log_output = {
                    'id': session_data.get('id'),
                    'start_time': session_data.get('start_time'),
                    'created_at': session_data.get('created_at'),
                    'completed_at': session_data.get('completed_at'),
                    'end_time': session_data.get('end_time'),
                    'status': session_data.get('status')
                }
                logger.info(f"Session sample {i+1}: {log_output}")
            if len(sessions) > 3:
                logger.info(f"...(and {len(sessions) - 3} more sessions)")

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
            logger.info(f"Location response data for session {ruck_id}: {locations_resp.data}")
            if locations_resp.data:
                # Attach both 'route' (legacy) and 'location_points' (for frontend compatibility)
                session['route'] = [{'lat': loc['latitude'], 'lng': loc['longitude']} for loc in locations_resp.data]
                session['location_points'] = [{'lat': loc['latitude'], 'lng': loc['longitude']} for loc in locations_resp.data]
            else:
                session['route'] = []
                session['location_points'] = []
            # Attach heart rate samples to the session response
            hr_resp = supabase.table('heart_rate_sample') \
                .select('*') \
                .eq('session_id', ruck_id) \
                .order('timestamp') \
                .execute()
            session['heart_rate_samples'] = hr_resp.data if hr_resp.data else []
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

            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
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