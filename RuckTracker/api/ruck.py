from flask import request, g
from flask_restful import Resource
from datetime import datetime
import uuid
import logging

from supabase_client import supabase

logger = logging.getLogger(__name__)

class RuckSessionListResource(Resource):
    def get(self):
        """Get all ruck sessions for the authenticated user"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                logger.warning("No authenticated user found for session request")
                return {'message': 'Authentication required to access ruck sessions'}, 401
            
            # Query all sessions for the user
            response = supabase.table('ruck_sessions') \
                .select('*') \
                .eq('user_id', g.user.id) \
                .order('created_at', desc=True) \
                .execute()
                
            return {'sessions': response.data}, 200
            
        except Exception as e:
            logger.error(f"Error retrieving sessions: {str(e)}", exc_info=True)
            return {'message': f'Error retrieving sessions: {str(e)}', 'error_type': type(e).__name__}, 500
            
    def post(self):
        """Create a new ruck session"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
                
            data = request.get_json()
            
            session_id = str(uuid.uuid4())
            
            # Create new session record with only fields we know exist in the database
            session_data = {
                'id': session_id,
                'user_id': g.user.id,
                'status': 'created',
                'created_at': datetime.utcnow().isoformat(),
                'notes': data.get('notes', '')
            }
            
            # Add ruck weight in kg and lbs
            if 'weight_kg' in data:
                ruck_weight_kg = data.get('weight_kg')
                session_data['ruck_weight_kg'] = ruck_weight_kg
                # Calculate and store imperial weight (lbs)
                session_data['ruck_weight_imperial'] = round(ruck_weight_kg * 2.20462, 1)
                
            # Add user weight in kg and lbs
            if 'user_weight_kg' in data:
                user_weight_kg = data.get('user_weight_kg')
                session_data['user_weight_kg'] = user_weight_kg
                # Calculate and store imperial weight (lbs)
                session_data['user_weight_imperial'] = round(user_weight_kg * 2.20462, 1)
            
            # Insert the new session into the database
            response = supabase.table('ruck_sessions') \
                .insert(session_data) \
                .execute()
                
            return {'message': 'Session created successfully', 'session_id': session_id}, 201
            
        except Exception as e:
            logger.error(f"Error creating session: {str(e)}", exc_info=True)
            return {'message': f'Error creating session: {str(e)}', 'error_type': type(e).__name__}, 500

class RuckSessionResource(Resource):
    def get(self, ruck_id):
        """Get a specific ruck session"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
                
            # Query Supabase for the specific session
            response = supabase.table('ruck_sessions') \
                .select('*') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .single() \
                .execute()
                
            if not response.data:
                return {'message': 'Session not found'}, 404
                
            return response.data, 200
                
        except Exception as e:
            logger.error(f"Error retrieving session: {str(e)}", exc_info=True)
            return {'message': f'Error retrieving session: {str(e)}', 'error_type': type(e).__name__}, 500

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
            logger.error(f"Error starting session: {str(e)}", exc_info=True)
            return {'message': f'Error starting session: {str(e)}', 'error_type': type(e).__name__}, 500

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
            logger.error(f"Error pausing session: {str(e)}", exc_info=True)
            return {'message': f'Error pausing session: {str(e)}', 'error_type': type(e).__name__}, 500

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
            logger.error(f"Error resuming session: {str(e)}", exc_info=True)
            return {'message': f'Error resuming session: {str(e)}', 'error_type': type(e).__name__}, 500

class RuckSessionCompleteResource(Resource):
    def post(self, ruck_id):
        """Complete a ruck session"""
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
                
            if check.data['status'] not in ['in_progress', 'paused']:
                return {'message': 'Session not in progress or paused'}, 400
                
            # Update the session
            data = request.get_json() or {}
            update_data = {
                'status': 'completed',
                'completed_at': datetime.utcnow().isoformat()
            }
            
            if 'notes' in data:
                update_data['notes'] = data['notes']
            
            response = supabase.table('ruck_sessions') \
                .update(update_data) \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            
            return {'message': 'Session completed'}, 200
                
        except Exception as e:
            logger.error(f"Error completing session: {str(e)}", exc_info=True)
            return {'message': f'Error completing session: {str(e)}', 'error_type': type(e).__name__}, 500

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
                'elevation_meters': data.get('elevation_meters'),
                'timestamp': data.get('timestamp') or datetime.utcnow().isoformat(),
                'accuracy_meters': data.get('accuracy_meters'),
                'created_at': datetime.utcnow().isoformat()
            }
            
            # Insert location
            location_response = supabase.table('ruck_session_locations') \
                .insert(location_data) \
                .execute()
            
            # Get current session details
            session = supabase.table('ruck_sessions') \
                .select('*') \
                .eq('id', ruck_id) \
                .single() \
                .execute()
                
            # Mock/compute some statistics
            # In production, you would calculate these based on all location points
            distance_km = session.data.get('distance_km', 0) + 0.1  # Increment by 100m
            calories_burned = session.data.get('calories_burned', 0) + 10
            elevation_gain = session.data.get('elevation_gain_meters', 0)
            elevation_loss = session.data.get('elevation_loss_meters', 0)
            
            # Add elevation changes if present
            if data.get('elevation_meters') is not None and session.data.get('last_elevation') is not None:
                elevation_diff = data.get('elevation_meters') - session.data.get('last_elevation')
                if elevation_diff > 0:
                    elevation_gain += elevation_diff
                else:
                    elevation_loss += abs(elevation_diff)
            
            # Update session stats
            stats_data = {
                'distance_km': distance_km,
                'elevation_gain_meters': elevation_gain,
                'elevation_loss_meters': elevation_loss,
                'calories_burned': calories_burned,
                'last_elevation': data.get('elevation_meters'),
                'last_updated': datetime.utcnow().isoformat()
            }
            
            # Update the session with new stats
            stats_response = supabase.table('ruck_sessions') \
                .update(stats_data) \
                .eq('id', ruck_id) \
                .execute()
            
            return {
                'current_stats': {
                    'distance_km': distance_km,
                    'elevation_gain_meters': elevation_gain,
                    'elevation_loss_meters': elevation_loss,
                    'calories_burned': calories_burned,
                    'average_pace_min_km': 12.5  # Mock value
                }
            }, 200
                
        except Exception as e:
            logger.error(f"Error updating location: {str(e)}", exc_info=True)
            return {'message': f'Error updating location: {str(e)}', 'error_type': type(e).__name__}, 500

class RuckSessionDetailResource(Resource):
    def get(self, session_id):
        """Get details of a specific ruck session"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
                
            # Get the session details
            response = supabase.table('ruck_sessions') \
                .select('*') \
                .eq('id', session_id) \
                .eq('user_id', g.user.id) \
                .limit(1) \
                .execute()
                
            if not response.data:
                return {'message': 'Session not found'}, 404
                
            # Get location data for this session
            locations_response = supabase.table('ruck_session_locations') \
                .select('*') \
                .eq('session_id', session_id) \
                .order('timestamp', desc=False) \
                .execute()
                
            session_data = response.data[0]
            session_data['locations'] = locations_response.data
            
            return session_data, 200
        except Exception as e:
            logger.error(f"Error retrieving session details: {str(e)}", exc_info=True)
            return {'message': f'Error retrieving session details: {str(e)}', 'error_type': type(e).__name__}, 500
            
    def put(self, session_id):
        """Update a ruck session"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
                
            # Verify the session exists and belongs to the user
            session_response = supabase.table('ruck_sessions') \
                .select('*') \
                .eq('id', session_id) \
                .eq('user_id', g.user.id) \
                .limit(1) \
                .execute()
                
            if not session_response.data:
                return {'message': 'Session not found'}, 404
                
            data = request.get_json()
            update_data = {}
            
            # Only update fields that are provided and exist in the database
            allowed_fields = ['notes', 'status']
            for field in allowed_fields:
                if field in data:
                    update_data[field] = data[field]
            
            # Handle ruck weight with both metric and imperial units
            if 'weight_kg' in data or 'ruck_weight_kg' in data:
                ruck_weight_kg = data.get('weight_kg', data.get('ruck_weight_kg'))
                update_data['ruck_weight_kg'] = ruck_weight_kg
                update_data['ruck_weight_imperial'] = round(ruck_weight_kg * 2.20462, 1)
            
            # Handle user weight with both metric and imperial units
            if 'user_weight_kg' in data:
                user_weight_kg = data.get('user_weight_kg')
                update_data['user_weight_kg'] = user_weight_kg
                update_data['user_weight_imperial'] = round(user_weight_kg * 2.20462, 1)
                    
            if update_data:
                # Update the session
                response = supabase.table('ruck_sessions') \
                    .update(update_data) \
                    .eq('id', session_id) \
                    .execute()
                    
                return {'message': 'Session updated successfully'}, 200
            else:
                return {'message': 'No valid fields to update'}, 400
        except Exception as e:
            logger.error(f"Error updating session: {str(e)}", exc_info=True)
            return {'message': f'Error updating session: {str(e)}', 'error_type': type(e).__name__}, 500

    def delete(self, session_id):
        """Delete a ruck session"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
                
            # Verify the session exists and belongs to the user
            session_response = supabase.table('ruck_sessions') \
                .select('*') \
                .eq('id', session_id) \
                .eq('user_id', g.user.id) \
                .limit(1) \
                .execute()
                
            if not session_response.data:
                return {'message': 'Session not found'}, 404
                
            # Delete associated location data first
            supabase.table('ruck_session_locations') \
                .delete() \
                .eq('session_id', session_id) \
                .execute()
                
            # Delete the session
            supabase.table('ruck_sessions') \
                .delete() \
                .eq('id', session_id) \
                .execute()
                
            return {'message': 'Session deleted successfully'}, 200
        except Exception as e:
            logger.error(f"Error deleting session: {str(e)}", exc_info=True)
            return {'message': f'Error deleting session: {str(e)}', 'error_type': type(e).__name__}, 500

class RuckSessionReviewResource(Resource):
    """Resource for adding/updating reviews for a ruck session"""
    
    def post(self, ruck_id):
        """Create or update a review for a ruck session"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
                
            # Verify the session exists and belongs to the user
            session_response = supabase.table('ruck_sessions') \
                .select('id, status') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .single() \
                .execute()
                
            if not session_response.data:
                return {'message': 'Session not found'}, 404
                
            # Session should be completed to add a review
            if session_response.data['status'] != 'completed':
                # Update the session status to completed first
                supabase.table('ruck_sessions') \
                    .update({'status': 'completed', 'completed_at': datetime.utcnow().isoformat()}) \
                    .eq('id', ruck_id) \
                    .execute()
            
            # Get review data from request
            data = request.get_json()
            
            # Check if a review exists for this session
            review_response = supabase.table('session_reviews') \
                .select('id') \
                .eq('session_id', ruck_id) \
                .execute()
                
            review_data = {
                'rating': data.get('rating', 3),
                'notes': data.get('notes', ''),
                'perceived_exertion': data.get('perceived_exertion'),
                'tags': data.get('tags', []),
                'updated_at': datetime.utcnow().isoformat()
            }
            
            if review_response.data and len(review_response.data) > 0:
                # Update existing review
                review_id = review_response.data[0]['id']
                supabase.table('session_reviews') \
                    .update(review_data) \
                    .eq('id', review_id) \
                    .execute()
            else:
                # Create new review
                review_data.update({
                    'id': str(uuid.uuid4()),
                    'session_id': ruck_id,
                    'created_at': datetime.utcnow().isoformat()
                })
                
                supabase.table('session_reviews') \
                    .insert(review_data) \
                    .execute()
            
            # Return the updated session with review
            updated_session = supabase.table('ruck_sessions') \
                .select('*, session_reviews(*)') \
                .eq('id', ruck_id) \
                .single() \
                .execute()
                
            return updated_session.data, 200
                
        except Exception as e:
            logger.error(f"Error saving session review: {str(e)}", exc_info=True)
            return {'message': f'Error saving session review: {str(e)}', 'error_type': type(e).__name__}, 500 