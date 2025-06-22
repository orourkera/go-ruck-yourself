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
            
            logger.info(f"Getting progress for event {event_id}, user {current_user_id}")
            
            # Check if user can view progress (must be participant or creator)
            participant_check = admin_client.table('event_participants').select('status').eq('event_id', event_id).eq('user_id', current_user_id).execute()
            event_check = admin_client.table('events').select('creator_user_id').eq('id', event_id).execute()
            
            if not event_check.data:
                logger.warning(f"Event {event_id} not found")
                return {'error': 'Event not found'}, 404
            
            is_participant = participant_check.data and participant_check.data[0]['status'] == 'approved'
            is_creator = event_check.data[0]['creator_user_id'] == current_user_id
            
            logger.info(f"User {current_user_id}: is_participant={is_participant}, is_creator={is_creator}")
            logger.info(f"Participant check result: {participant_check.data}")
            
            if not (is_participant or is_creator):
                logger.warning(f"User {current_user_id} not authorized to view progress for event {event_id}")
                return {'error': 'Only event participants can view progress'}, 403
            
            # Get all approved participants for this event
            participants_result = admin_client.table('event_participants').select("""
                user_id,
                user!user_id(id, username, avatar_url)
            """).eq('event_id', event_id).eq('status', 'approved').execute()
            
            participants = participants_result.data or []
            logger.info(f"Found {len(participants)} approved participants")
            
            # Get completed ruck sessions for this event
            sessions_result = admin_client.table('ruck_session').select("""
                id,
                user_id,
                distance_km,
                duration_seconds,
                completed_at
            """).eq('event_id', event_id).eq('status', 'completed').execute()
            
            completed_sessions = sessions_result.data or []
            logger.info(f"Found {len(completed_sessions)} completed ruck sessions for event {event_id}")
            
            # Create a map of user sessions
            user_sessions = {}
            for session in completed_sessions:
                user_id = session['user_id']
                if user_id not in user_sessions or session['distance_km'] > user_sessions[user_id]['distance_km']:
                    # Keep the best (longest distance) session for each user
                    user_sessions[user_id] = session
            
            # Build progress data for each participant
            progress_data = []
            for participant in participants:
                user_id = participant['user_id']
                user_data = participant.get('user')
                
                if user_id in user_sessions:
                    # User has completed a ruck session for this event
                    session = user_sessions[user_id]
                    progress_entry = {
                        'id': f"progress_{user_id}_{event_id}",  # Generate a unique ID
                        'event_id': event_id,
                        'user_id': user_id,
                        'session_id': session['id'],
                        'distance_km': session['distance_km'],
                        'duration_seconds': session['duration_seconds'],
                        'rank': 1,  # Will be calculated after sorting
                        'completed_at': session['completed_at'],
                        'user': user_data
                    }
                else:
                    # User hasn't completed a ruck session yet
                    progress_entry = {
                        'id': f"progress_{user_id}_{event_id}",  # Generate a unique ID
                        'event_id': event_id,
                        'user_id': user_id,
                        'session_id': None,
                        'distance_km': 0.0,
                        'duration_seconds': 0,
                        'rank': 999,  # Will be calculated after sorting
                        'completed_at': None,
                        'user': user_data
                    }
                
                progress_data.append(progress_entry)
            
            # User enrichment fallback - fix missing user data
            missing_user_ids = [entry['user_id'] for entry in progress_data if not entry.get('user')]
            if missing_user_ids:
                logger.info(f"Enriching {len(missing_user_ids)} missing users: {missing_user_ids}")
                try:
                    missing_users = admin_client.table('user').select('id, username, avatar_url').in_('id', missing_user_ids).execute()
                    user_lookup = {user['id']: user for user in missing_users.data or []}
                    
                    for entry in progress_data:
                        if not entry.get('user') and entry['user_id'] in user_lookup:
                            entry['user'] = user_lookup[entry['user_id']]
                            logger.info(f"Enriched user {entry['user_id']} with username: {entry['user']['username']}")
                except Exception as e:
                    logger.error(f"Failed to enrich missing users: {e}")
            
            # Sort by distance completed (descending), then by completion time (ascending for ties)
            progress_data.sort(key=lambda x: (-x['distance_km'], x['completed_at'] or '9999-12-31'))
            
            # Assign ranks
            for i, entry in enumerate(progress_data):
                if entry['distance_km'] > 0:
                    entry['rank'] = i + 1
                else:
                    entry['rank'] = 999  # No completion rank
            
            logger.info(f"Processed leaderboard for event {event_id} with {len(progress_data)} participants")
            
            return {
                'event_id': event_id,
                'progress': progress_data,
                'last_updated': datetime.utcnow().isoformat()
            }, 200
            
        except Exception as e:
            logger.error(f"Error getting progress for event {event_id}: {e}", exc_info=True)
            return {'error': f'Failed to get progress: {str(e)}'}, 500
    
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
        """Prepare to start a ruck session for this event"""
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
            active_session_check = admin_client.table('ruck_session').select('id').eq('user_id', current_user_id).eq('status', 'in_progress').execute()
            if active_session_check.data:
                return {'error': 'User already has an active ruck session'}, 400
            
            # Return event context for create session screen
            logger.info(f"User {current_user_id} is ready to start ruck session for event {event_id}")
            return {
                'status': 'ready',
                'event_id': event_id,
                'event_title': event['title'],
                'message': 'Ready to start ruck session for event'
            }, 200
            
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
            
            is_participant = bool(participant_check.data)
            is_creator = event_check.data[0]['creator_user_id'] == current_user_id
            
            if not (is_participant or is_creator):
                logger.warning(f"User {current_user_id} not authorized to view participants for event {event_id}")
                return {'error': 'Only event participants can view participant list'}, 403
            
            # Get participants with user info
            result = admin_client.table('event_participants').select("""
                *,
                user!user_id(id, username, avatar_url)
            """).eq('event_id', event_id).order('joined_at', desc=False).execute()
            
            participants = result.data or []

            # --- Ensure user data is populated (fallback lookup) ---
            missing_user_ids = [p['user_id'] for p in participants if not p.get('user')]
            if missing_user_ids:
                logger.info(
                    f"Participant join returned null for {len(missing_user_ids)} users – performing fallback lookup"
                )
                users_response = admin_client.table('user').select('id, username, avatar_url').in_('id', missing_user_ids).execute()
                user_map = {u['id']: u for u in (users_response.data or [])}
                for participant in participants:
                    if not participant.get('user'):
                        participant['user'] = user_map.get(participant['user_id'])

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
