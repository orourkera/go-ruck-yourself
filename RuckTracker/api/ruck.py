from flask import request, g
from flask_restful import Resource
from datetime import datetime
import uuid
import logging

from supabase_client import supabase

logger = logging.getLogger(__name__)

class RuckSessionListResource(Resource):
    def get(self):
        """Get all ruck sessions for the current user"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
                
            # Query Supabase for ruck sessions
            response = supabase.table('ruck_sessions') \
                .select('*') \
                .eq('user_id', g.user.id) \
                .order('created_at', desc=True) \
                .execute()
                
            return response.data, 200
        except Exception as e:
            return {'message': f'Error retrieving sessions: {str(e)}'}, 500

    def post(self):
        """Create a new ruck session"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
                
            data = request.get_json()
            
            # Create a new session
            session_data = {
                'id': str(uuid.uuid4()),
                'user_id': g.user.id,
                'status': 'created',
                'ruck_weight_id': data.get('ruck_weight_id'),
                'ruck_weight_kg': data.get('ruck_weight_kg', 0),
                'user_weight_kg': data.get('user_weight_kg'),
                'planned_duration_minutes': data.get('planned_duration_minutes'),
                'notes': data.get('notes'),
                'created_at': datetime.utcnow().isoformat()
            }
            
            # Insert into Supabase
            response = supabase.table('ruck_sessions') \
                .insert(session_data) \
                .execute()
                
            return response.data[0], 201
        except Exception as e:
            return {'message': f'Error creating session: {str(e)}'}, 500

class RuckSessionResource(Resource):
    def get(self, ruck_id):
        """Get a specific ruck session"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
                
            # Query Supabase for the specific session
            response = supabase.table('ruck_sessions') \
                .select('*, ruck_weights(name, weight_kg)') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .single() \
                .execute()
                
            if not response.data:
                return {'message': 'Session not found'}, 404
                
            return response.data, 200
        except Exception as e:
            return {'message': f'Error retrieving session: {str(e)}'}, 500

class RuckSessionStartResource(Resource):
    def post(self, ruck_id):
        """Start a ruck session"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
                
            # Get current session status
            check = supabase.table('ruck_sessions') \
                .select('status') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .single() \
                .execute()
                
            if not check.data:
                return {'message': 'Session not found'}, 404
                
            if check.data['status'] != 'created':
                return {'message': 'Session already started'}, 400
                
            # Update the session
            update_data = {
                'status': 'in_progress',
                'started_at': datetime.utcnow().isoformat()
            }
            
            response = supabase.table('ruck_sessions') \
                .update(update_data) \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            
            return {'message': 'Session started'}, 200
        except Exception as e:
            return {'message': f'Error starting session: {str(e)}'}, 500

class RuckSessionPauseResource(Resource):
    def post(self, ruck_id):
        """Pause a ruck session"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
                
            # Get current session status
            check = supabase.table('ruck_sessions') \
                .select('status') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .single() \
                .execute()
                
            if not check.data:
                return {'message': 'Session not found'}, 404
                
            if check.data['status'] != 'in_progress':
                return {'message': 'Session not in progress'}, 400
                
            # Update the session
            update_data = {
                'status': 'paused',
                'paused_at': datetime.utcnow().isoformat()
            }
            
            response = supabase.table('ruck_sessions') \
                .update(update_data) \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            
            return {'message': 'Session paused'}, 200
        except Exception as e:
            return {'message': f'Error pausing session: {str(e)}'}, 500

class RuckSessionResumeResource(Resource):
    def post(self, ruck_id):
        """Resume a paused ruck session"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
                
            # Get current session status
            check = supabase.table('ruck_sessions') \
                .select('status') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .single() \
                .execute()
                
            if not check.data:
                return {'message': 'Session not found'}, 404
                
            if check.data['status'] != 'paused':
                return {'message': 'Session not paused'}, 400
                
            # Update the session
            update_data = {
                'status': 'in_progress'
            }
            
            response = supabase.table('ruck_sessions') \
                .update(update_data) \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            
            return {'message': 'Session resumed'}, 200
        except Exception as e:
            return {'message': f'Error resuming session: {str(e)}'}, 500

class RuckSessionCompleteResource(Resource):
    def post(self, ruck_id):
        """Complete a ruck session and save final stats directly in the session"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
                
            # --- Add Logging --- 
            logger.info(f"Complete endpoint called for ruck_id: {ruck_id}")
            logger.info(f"Authenticated user ID (g.user.id): {g.user.id if hasattr(g, 'user') and g.user else 'Not Set'}")
            # --- End Logging ---
            
            # Get current session status and start time
            session_check = supabase.table('ruck_sessions') \
                .select('status, started_at') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .single() \
                .execute()
                
            if not session_check.data:
                return {'message': 'Session not found'}, 404
                
            current_status = session_check.data['status']
            started_at_str = session_check.data.get('started_at')
            
            # --- Add Logging --- 
            logger.info(f"Attempting to complete session {ruck_id}. Current status from DB: {current_status}")
            # --- End Logging ---
            
            if current_status not in ['in_progress', 'paused']:
                logger.warning(f"Completion rejected for session {ruck_id} because status is '{current_status}'")
                return {'message': 'Session not in progress or paused'}, 400
                
            # Calculate duration if started_at exists
            duration_seconds = 0
            completed_at = datetime.utcnow()
            if started_at_str:
                try:
                    started_at = datetime.fromisoformat(started_at_str.replace('Z', '+00:00'))
                    if started_at.tzinfo:
                         completed_at = completed_at.replace(tzinfo=started_at.tzinfo)
                    elif completed_at.tzinfo:
                         completed_at = completed_at.replace(tzinfo=None)
                         
                    duration = completed_at - started_at
                    duration_seconds = int(duration.total_seconds())
                    if duration_seconds < 0: duration_seconds = 0
                except ValueError as parse_error:
                    print(f"Warning: Could not parse started_at '{started_at_str}': {parse_error}")
                    duration_seconds = 0
            
            # Prepare session update data, including calculated/client-provided stats
            data = request.get_json() or {}
            session_update_data = {
                'status': 'completed',
                'completed_at': completed_at.isoformat(),
                'duration_seconds': duration_seconds, # Add calculated duration
                # Add other stats if sent from client (ensure column names match table)
                'distance_km': data.get('final_distance_km'),
                'calories_burned': data.get('final_calories_burned'),
                'average_pace_min_km': data.get('final_average_pace'),
                'elevation_gain_meters': data.get('final_elevation_gain'),
                'elevation_loss_meters': data.get('final_elevation_loss'),
                # Add notes if provided
                'notes': data.get('notes')
            }
            
            # Remove keys with None values to avoid overwriting existing DB values with null
            session_update_data_clean = {k: v for k, v in session_update_data.items() if v is not None}

            # Update the session in ruck_sessions table
            session_response = supabase.table('ruck_sessions') \
                .update(session_update_data_clean) \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            
            # Check if the update was successful (optional)
            if not session_response.data:
                 print(f"Warning: Update for session {ruck_id} returned no data.")
                 # Consider if returning an error is appropriate here

            return {'message': 'Session completed', 'calculated_duration_seconds': duration_seconds}, 200
        except Exception as e:
            print(f"Error completing session {ruck_id}: {str(e)}") 
            import traceback
            traceback.print_exc()
            return {'message': f'Error completing session: {str(e)}'}, 500

class RuckSessionLocationResource(Resource):
    def post(self, ruck_id):
        """Add location point to a ruck session"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
                
            # Get current session status
            check = supabase.table('ruck_sessions') \
                .select('status') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .single() \
                .execute()
                
            if not check.data:
                return {'message': 'Session not found'}, 404
                
            if check.data['status'] != 'in_progress':
                return {'message': 'Session not in progress'}, 400
                
            data = request.get_json()
            
            # Create location point
            location_data = {
                'id': str(uuid.uuid4()),
                'session_id': ruck_id,
                'latitude': data.get('latitude'),
                'longitude': data.get('longitude'),
                'elevation': data.get('elevation'),
                'timestamp': datetime.utcnow().isoformat(),
                'created_at': datetime.utcnow().isoformat()
            }
            
            # Insert location
            location_response = supabase.table('ruck_session_locations') \
                .insert(location_data) \
                .execute()
            
            # Update session stats
            stats_data = {
                'distance_km': data.get('distance_km'),
                'elevation_gain_meters': data.get('elevation_gain_meters'),
                'elevation_loss_meters': data.get('elevation_loss_meters'),
                'calories_burned': data.get('calories_burned'),
                'duration_seconds': data.get('duration_seconds'),
                'average_pace_min_km': data.get('average_pace_min_km')
            }
            
            # Remove None values
            stats_data = {k: v for k, v in stats_data.items() if v is not None}
            
            if stats_data:
                stats_response = supabase.table('ruck_sessions') \
                    .update(stats_data) \
                    .eq('id', ruck_id) \
                    .execute()
                
            return {
                'current_stats': {
                    'distance_km': data.get('distance_km') or 0,
                    'elevation_gain_meters': data.get('elevation_gain_meters') or 0,
                    'elevation_loss_meters': data.get('elevation_loss_meters') or 0,
                    'calories_burned': data.get('calories_burned') or 0,
                    'duration_seconds': data.get('duration_seconds') or 0,
                    'average_pace_min_km': data.get('average_pace_min_km') or 0,
                }
            }, 200
        except Exception as e:
            return {'message': f'Error updating location: {str(e)}'}, 500 