"""
Event Progress API endpoints for leaderboards and session tracking
"""
import logging
from flask import Blueprint, request, jsonify
from flask_restful import Api, Resource
from RuckTracker.api.auth import auth_required, get_user_id
from datetime import datetime
from RuckTracker.supabase_client import get_supabase_admin_client
from RuckTracker.services.push_notification_service import PushNotificationService, get_user_device_tokens

logger = logging.getLogger(__name__)

event_progress_bp = Blueprint('event_progress', __name__)
api = Api(event_progress_bp)

# Initialize push notification service
push_service = PushNotificationService()

class EventProgressResource(Resource):
    """Handle event progress and leaderboard"""
    
    @auth_required
    def get(self, event_id):
        """Get event leaderboard/progress"""
        try:
            current_user_id = get_user_id()
            admin_client = get_supabase_admin_client()
            
            # Check if user can view progress (must be participant or creator)
            participant_check = admin_client.table('event_participants').select('status').eq('event_id', event_id).eq('user_id', current_user_id).execute()
            event_check = admin_client.table('events').select('creator_user_id').eq('id', event_id).execute()
            
            if not event_check.data:
                return {'error': 'Event not found'}, 404
            
            is_participant = participant_check.data and participant_check.data[0]['status'] == 'approved'
            is_creator = event_check.data[0]['creator_user_id'] == current_user_id
            
            if not (is_participant or is_creator):
                return {'error': 'Only event participants can view progress'}, 403
            
            # Get progress for all participants
            result = admin_client.table('event_participant_progress').select("""
                *,
                user:user_id(id, first_name, last_name),
                ruck_session:ruck_session_id(*)
            """).eq('event_id', event_id).execute()
            
            progress_data = result.data
            
            # Sort by distance completed (descending), then by completion time
            progress_data.sort(key=lambda x: (
                -x['distance_km'] if x['distance_km'] else 0,  # Distance descending
                x['completed_at'] if x['completed_at'] else datetime.max.isoformat()  # Completion time ascending (faster wins)
            ))
            
            # Add ranking
            for i, progress in enumerate(progress_data):
                progress['rank'] = i + 1
                progress['is_current_user'] = progress['user_id'] == current_user_id
            
            logger.info(f"Found progress for {len(progress_data)} participants in event {event_id}")
            return {'progress': progress_data}, 200
            
        except Exception as e:
            logger.error(f"Error fetching progress for event {event_id}: {e}", exc_info=True)
            return {'error': f'Failed to fetch progress: {str(e)}'}, 500
    
    @auth_required
    def put(self, event_id):
        """Update user's event progress (internal API for session completion)"""
        try:
            current_user_id = get_user_id()
            data = request.get_json()
            
            admin_client = get_supabase_admin_client()
            
            # Check if user is participating
            participant_check = admin_client.table('event_participants').select('status').eq('event_id', event_id).eq('user_id', current_user_id).execute()
            if not participant_check.data or participant_check.data[0]['status'] != 'approved':
                return {'error': 'User is not an approved participant'}, 403
            
            # Check if progress entry exists
            progress_check = admin_client.table('event_participant_progress').select('id, status').eq('event_id', event_id).eq('user_id', current_user_id).execute()
            if not progress_check.data:
                return {'error': 'Progress entry not found'}, 404
            
            # Prepare update data
            update_data = {}
            
            if 'ruck_session_id' in data:
                update_data['ruck_session_id'] = data['ruck_session_id']
            if 'distance_km' in data:
                update_data['distance_km'] = data['distance_km']
            if 'duration_minutes' in data:
                update_data['duration_minutes'] = data['duration_minutes']
            if 'calories_burned' in data:
                update_data['calories_burned'] = data['calories_burned']
            if 'elevation_gain_m' in data:
                update_data['elevation_gain_m'] = data['elevation_gain_m']
            if 'average_pace_min_per_km' in data:
                update_data['average_pace_min_per_km'] = data['average_pace_min_per_km']
            
            # Update status based on progress
            current_status = progress_check.data[0]['status']
            if current_status == 'not_started' and data.get('distance_km', 0) > 0:
                update_data['status'] = 'in_progress'
                update_data['started_at'] = datetime.utcnow().isoformat()
            elif data.get('completed', False):
                update_data['status'] = 'completed'
                update_data['completed_at'] = datetime.utcnow().isoformat()
            
            if not update_data:
                return {'error': 'No valid fields to update'}, 400
            
            # Update progress
            result = admin_client.table('event_participant_progress').update(update_data).eq('event_id', event_id).eq('user_id', current_user_id).execute()
            
            if result.data:
                logger.info(f"Progress updated for user {current_user_id} in event {event_id}")
                return {'progress': result.data[0], 'message': 'Progress updated successfully'}, 200
            else:
                return {'error': 'Failed to update progress'}, 500
                
        except Exception as e:
            logger.error(f"Error updating progress for event {event_id}: {e}", exc_info=True)
            return {'error': f'Failed to update progress: {str(e)}'}, 500


class EventStartRuckResource(Resource):
    """Handle starting a ruck session for an event"""
    
    @auth_required
    def post(self, event_id):
        """Start a ruck session for this event"""
        try:
            current_user_id = get_user_id()
            admin_client = get_supabase_admin_client()
            
            # Check if user is approved participant
            participant_check = admin_client.table('event_participants').select('status').eq('event_id', event_id).eq('user_id', current_user_id).execute()
            if not participant_check.data or participant_check.data[0]['status'] != 'approved':
                return {'error': 'User is not an approved participant'}, 403
            
            # Check if event exists and is active
            event_result = admin_client.table('events').select('title, status, scheduled_start_time').eq('id', event_id).execute()
            if not event_result.data:
                return {'error': 'Event not found'}, 404
            
            event = event_result.data[0]
            if event['status'] != 'active':
                return {'error': 'Event is not active'}, 400
            
            # Check if user already has an active session
            active_session_check = admin_client.table('ruck_session').select('id').eq('user_id', current_user_id).eq('is_active', True).execute()
            if active_session_check.data:
                return {'error': 'User already has an active ruck session'}, 400
            
            # Return event information for starting session
            # The actual session creation happens in the ruck session API with event_id parameter
            session_context = {
                'event_id': event_id,
                'event_title': event['title'],
                'event_start_time': event['scheduled_start_time'],
                'ready_to_start': True
            }
            
            # Update progress status to indicate session is about to start
            admin_client.table('event_participant_progress').update({
                'status': 'in_progress',
                'started_at': datetime.utcnow().isoformat()
            }).eq('event_id', event_id).eq('user_id', current_user_id).execute()
            
            logger.info(f"User {current_user_id} ready to start ruck session for event {event_id}")
            return {'session_context': session_context, 'message': 'Ready to start ruck session'}, 200
            
        except Exception as e:
            logger.error(f"Error preparing ruck session for event {event_id}: {e}", exc_info=True)
            return {'error': f'Failed to prepare ruck session: {str(e)}'}, 500


class EventParticipantsResource(Resource):
    """Handle event participants listing"""
    
    @auth_required
    def get(self, event_id):
        """Get event participants"""
        try:
            current_user_id = get_user_id()
            admin_client = get_supabase_admin_client()
            
            # Check if user can view participants (must be participant or creator)
            participant_check = admin_client.table('event_participants').select('status').eq('event_id', event_id).eq('user_id', current_user_id).execute()
            event_check = admin_client.table('events').select('creator_user_id').eq('id', event_id).execute()
            
            if not event_check.data:
                return {'error': 'Event not found'}, 404
            
            is_participant = participant_check.data and participant_check.data[0]['status'] == 'approved'
            is_creator = event_check.data[0]['creator_user_id'] == current_user_id
            
            if not (is_participant or is_creator):
                return {'error': 'Only event participants can view participant list'}, 403
            
            # Get participants with user info
            result = admin_client.table('event_participants').select("""
                *,
                user:user_id(id, first_name, last_name)
            """).eq('event_id', event_id).order('joined_at', desc=False).execute()
            
            participants = result.data
            
            # Add user flags
            for participant in participants:
                participant['is_current_user'] = participant['user_id'] == current_user_id
                participant['is_creator'] = participant['user_id'] == event_check.data[0]['creator_user_id']
            
            # Group by status
            approved = [p for p in participants if p['status'] == 'approved']
            pending = [p for p in participants if p['status'] == 'pending']
            
            logger.info(f"Found {len(approved)} approved and {len(pending)} pending participants for event {event_id}")
            return {
                'participants': {
                    'approved': approved,
                    'pending': pending,
                    'total_approved': len(approved),
                    'total_pending': len(pending)
                }
            }, 200
            
        except Exception as e:
            logger.error(f"Error fetching participants for event {event_id}: {e}", exc_info=True)
            return {'error': f'Failed to fetch participants: {str(e)}'}, 500


# Register API endpoints
api.add_resource(EventProgressResource, '/events/<event_id>/progress')
api.add_resource(EventStartRuckResource, '/events/<event_id>/start-ruck')
api.add_resource(EventParticipantsResource, '/events/<event_id>/participants')
