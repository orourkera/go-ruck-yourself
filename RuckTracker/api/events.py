"""
Events API endpoints for event management, participation, comments, and progress tracking
"""
import logging
from flask import Blueprint, request, jsonify
from flask_restful import Api, Resource
from RuckTracker.api.auth import auth_required, get_user_id
from datetime import datetime, timedelta
from RuckTracker.supabase_client import get_supabase_admin_client
from RuckTracker.services.push_notification_service import PushNotificationService, get_user_device_tokens

logger = logging.getLogger(__name__)

events_bp = Blueprint('events', __name__)
api = Api(events_bp)

# Initialize push notification service
push_service = PushNotificationService()

class EventsListResource(Resource):
    """Handle event listing and creation"""
    
    @auth_required
    def get(self):
        """List events with optional filtering"""
        try:
            current_user_id = get_user_id()
            logger.info(f"Fetching events for user: {current_user_id}")
            
            admin_client = get_supabase_admin_client()
            
            # Get query parameters
            search = request.args.get('search', '')
            club_id = request.args.get('club_id')
            joined_only = request.args.get('joined_only', 'false').lower() == 'true'
            upcoming_only = request.args.get('upcoming_only', 'true').lower() == 'true'
            end_before = request.args.get('end_before')  # Filter for completed events
            latitude = request.args.get('latitude')
            longitude = request.args.get('longitude')
            radius_km = request.args.get('radius_km', '50')
            
            logger.info(f"Query params - search: {search}, club_id: {club_id}, joined_only: {joined_only}, upcoming_only: {upcoming_only}, end_before: {end_before}")
            
            # Base query - fetch events without clubs join, we'll enrich separately
            query = admin_client.table('events').select("""
                *,
                creator:creator_user_id(id, username, avatar_url)
            """)
            
            # Apply filters
            if search:
                query = query.ilike('title', f'%{search}%')
            
            if club_id:
                query = query.eq('club_id', club_id)
            
            if end_before:
                # Filter for events that ended before the specified time (completed events)
                query = query.lt('scheduled_start_time', end_before)
            elif upcoming_only:
                # Only show upcoming/active events if not looking for completed ones
                now = datetime.utcnow().isoformat()
                query = query.gte('scheduled_start_time', now)
            
            if joined_only:
                # Get user's joined events only
                user_participants = admin_client.table('event_participants').select('event_id').eq('user_id', current_user_id).in_('status', ['approved', 'pending']).execute()
                if user_participants.data:
                    event_ids = [p['event_id'] for p in user_participants.data]
                    query = query.in_('id', event_ids)
                else:
                    return {'events': [], 'total': 0}, 200
            
            # Execute query
            result = query.order('scheduled_start_time', desc=False).execute()
            
            events = []
            for event in result.data:
                logger.info(f"Processing event: {event['id']}")
                
                # Get participant count
                participant_count_result = admin_client.table('event_participants').select('id', count='exact').eq('event_id', event['id']).eq('status', 'approved').execute()
                participant_count = participant_count_result.count or 0
                
                # Check user's participation status
                user_participation = None
                if current_user_id:
                    participation_result = admin_client.table('event_participants').select('status').eq('event_id', event['id']).eq('user_id', current_user_id).execute()
                    user_participation = participation_result.data[0]['status'] if participation_result.data else None
                
                # Enrich with club data if applicable
                hosting_club_data = None
                if event.get('club_id'):
                    try:
                        club_result = admin_client.table('clubs').select('id, name, logo_url').eq('id', event['club_id']).execute()
                        hosting_club_data = club_result.data[0] if club_result.data else None
                    except Exception as club_fetch_error:
                        logger.error(f"Error fetching club data for event {event['id']}: {club_fetch_error}")
                
                event_data = {
                    **event,
                    'participant_count': participant_count,
                    'user_participation_status': user_participation,
                    'is_creator': event['creator_user_id'] == current_user_id,
                    'hosting_club': hosting_club_data  # Map clubs field to hosting_club for frontend
                }
                
                events.append(event_data)
            
            logger.info(f"Found {len(events)} events")
            return {'events': events, 'total': len(events)}, 200
            
        except Exception as e:
            logger.error(f"Error fetching events: {e}", exc_info=True)
            return {'error': f'Failed to fetch events: {str(e)}'}, 500
    
    @auth_required
    def post(self):
        """Create a new event"""
        try:
            current_user_id = get_user_id()
            data = request.get_json()
            
            # Validate required fields
            required_fields = ['title', 'description', 'scheduled_start_time', 'duration_minutes', 'location_name']
            for field in required_fields:
                if field not in data:
                    return {'error': f'Missing required field: {field}'}, 400
            
            admin_client = get_supabase_admin_client()
            
            # Prepare event data
            event_data = {
                'title': data['title'],
                'description': data['description'],
                'creator_user_id': current_user_id,
                'scheduled_start_time': data['scheduled_start_time'],
                'duration_minutes': data['duration_minutes'],
                'location_name': data['location_name'],
                'latitude': data.get('latitude'),
                'longitude': data.get('longitude'),
                'max_participants': data.get('max_participants'),
                'min_participants': data.get('min_participants', 1),
                'approval_required': data.get('approval_required', False),
                'difficulty_level': data.get('difficulty_level'),
                'ruck_weight_kg': data.get('ruck_weight_kg'),
                'banner_image_url': data.get('banner_image_url'),
                'club_id': data.get('club_id'),
                'status': 'active'
            }
            
            # If club event, verify user is member
            if event_data['club_id']:
                membership_result = admin_client.table('club_memberships').select('role').eq('club_id', event_data['club_id']).eq('user_id', current_user_id).eq('status', 'approved').execute()
                if not membership_result.data:
                    return {'error': 'You must be a club member to create club events'}, 403
            
            # Create event
            result = admin_client.table('events').insert(event_data).execute()
            
            if result.data:
                event = result.data[0]
                logger.info(f"Event created: {event['id']} by user {current_user_id}")
                
                # Automatically add creator as approved participant
                participant_data = {
                    'event_id': event['id'],
                    'user_id': current_user_id,
                    'status': 'approved'
                }
                admin_client.table('event_participants').insert(participant_data).execute()
                
                # Create initial progress entry for creator
                progress_data = {
                    'event_id': event['id'],
                    'user_id': current_user_id,
                    'status': 'not_started'
                }
                admin_client.table('event_participant_progress').insert(progress_data).execute()
                
                # Send notifications to club members if club event
                if event_data['club_id']:
                    try:
                        # Get club members
                        club_members = admin_client.table('club_memberships').select('user_id').eq('club_id', event_data['club_id']).eq('status', 'approved').neq('user_id', current_user_id).execute()
                        
                        if club_members.data:
                            member_ids = [member['user_id'] for member in club_members.data]
                            member_tokens = get_user_device_tokens(member_ids)
                            
                            if member_tokens:
                                # Get club info for notification
                                club_result = admin_client.table('clubs').select('name').eq('id', event_data['club_id']).execute()
                                club_name = club_result.data[0]['name'] if club_result.data else 'Unknown Club'
                                
                                push_service.send_club_event_notification(
                                    device_tokens=member_tokens,
                                    event_title=event['title'],
                                    club_name=club_name,
                                    event_id=event['id'],
                                    club_id=event_data['club_id']
                                )
                                logger.info(f"Sent club event notifications to {len(member_tokens)} members")
                    except Exception as notification_error:
                        logger.error(f"Failed to send club event notifications: {notification_error}")
                
                return {'event': event, 'message': 'Event created successfully'}, 201
            else:
                return {'error': 'Failed to create event'}, 500
                
        except Exception as e:
            logger.error(f"Error creating event: {e}", exc_info=True)
            return {'error': f'Failed to create event: {str(e)}'}, 500


class EventResource(Resource):
    """Handle individual event operations"""
    
    @auth_required
    def get(self, event_id):
        """Get event details"""
        try:
            current_user_id = get_user_id()
            admin_client = get_supabase_admin_client()
            
            # Get event details
            result = admin_client.table('events').select("""
                *,
                creator:creator_user_id(id, username, avatar_url)
            """).eq('id', event_id).execute()
            
            if not result.data:
                return {'error': 'Event not found'}, 404
            
            event = result.data[0]
            
            # Get participants
            participants_result = admin_client.table('event_participants').select("""
                *,
                user!user_id(id, username, avatar_url)
            """).eq('event_id', event_id).execute()
            participants = participants_result.data or []
            
            # Fallback enrichment if some participants are missing nested user data
            missing_user_ids = [p['user_id'] for p in participants if not p.get('user')]
            if missing_user_ids:
                try:
                    users_result = admin_client.table('user').select('id, username, avatar_url').in_('id', missing_user_ids).execute()
                    users_dict = {u['id']: u for u in users_result.data} if users_result.data else {}
                    for p in participants:
                        if not p.get('user') and p['user_id'] in users_dict:
                            p['user'] = users_dict[p['user_id']]
                except Exception as user_fetch_error:
                    logger.error(f"Error fetching user data for participants fallback: {user_fetch_error}")
            
            # Check user's participation status
            user_participation = None
            if current_user_id:
                participation_result = admin_client.table('event_participants').select('status').eq('event_id', event_id).eq('user_id', current_user_id).execute()
                user_participation = participation_result.data[0]['status'] if participation_result.data else None
            
            # Enrich with club data if applicable
            hosting_club_data = None
            if event.get('club_id'):
                try:
                    club_result = admin_client.table('clubs').select('id, name, logo_url').eq('id', event['club_id']).execute()
                    hosting_club_data = club_result.data[0] if club_result.data else None
                except Exception as club_fetch_error:
                    logger.error(f"Error fetching club data for event {event['id']}: {club_fetch_error}")
            
            event_details = {
                **event,
                'participant_count': len(participants),
                'user_participation_status': user_participation,
                'is_creator': event['creator_user_id'] == current_user_id,
                'hosting_club': hosting_club_data  # Map clubs field to hosting_club for frontend
            }
            
            response_data = {
                'event': event_details,
                'participants': participants
            }
            
            return response_data, 200
            
        except Exception as e:
            logger.error(f"Error fetching event {event_id}: {e}", exc_info=True)
            return {'error': f'Failed to fetch event: {str(e)}'}, 500
    
    @auth_required
    def put(self, event_id):
        """Update event details (creator only)"""
        try:
            current_user_id = get_user_id()
            data = request.get_json()
            admin_client = get_supabase_admin_client()
            
            # Check if event exists and user is creator
            event_result = admin_client.table('events').select('creator_user_id, title').eq('id', event_id).execute()
            if not event_result.data:
                return {'error': 'Event not found'}, 404
            
            event = event_result.data[0]
            if event['creator_user_id'] != current_user_id:
                return {'error': 'Only event creator can update event'}, 403
            
            # Prepare update data
            allowed_fields = ['title', 'description', 'scheduled_start_time', 'duration_minutes', 
                            'location_name', 'latitude', 'longitude', 'max_participants', 
                            'min_participants', 'approval_required', 'difficulty_level', 
                            'ruck_weight_kg', 'banner_image_url']
            
            update_data = {k: v for k, v in data.items() if k in allowed_fields}
            
            if not update_data:
                return {'error': 'No valid fields to update'}, 400
            
            # Update event
            result = admin_client.table('events').update(update_data).eq('id', event_id).execute()
            
            if result.data:
                logger.info(f"Event {event_id} updated by creator {current_user_id}")
                return {'event': result.data[0], 'message': 'Event updated successfully'}, 200
            else:
                return {'error': 'Failed to update event'}, 500
                
        except Exception as e:
            logger.error(f"Error updating event {event_id}: {e}", exc_info=True)
            return {'error': f'Failed to update event: {str(e)}'}, 500
    
    @auth_required
    def delete(self, event_id):
        """Cancel event (creator only)"""
        try:
            current_user_id = get_user_id()
            admin_client = get_supabase_admin_client()
            
            # Check if event exists and user is creator
            event_result = admin_client.table('events').select('creator_user_id, title').eq('id', event_id).execute()
            if not event_result.data:
                return {'error': 'Event not found'}, 404
            
            event = event_result.data[0]
            if event['creator_user_id'] != current_user_id:
                return {'error': 'Only event creator can cancel event'}, 403
            
            # Update status to cancelled instead of deleting
            result = admin_client.table('events').update({'status': 'cancelled'}).eq('id', event_id).execute()
            
            if result.data:
                logger.info(f"Event {event_id} cancelled by creator {current_user_id}")
                
                # Notify participants about cancellation
                try:
                    participants = admin_client.table('event_participants').select('user_id').eq('event_id', event_id).eq('status', 'approved').neq('user_id', current_user_id).execute()
                    
                    if participants.data:
                        participant_ids = [p['user_id'] for p in participants.data]
                        participant_tokens = get_user_device_tokens(participant_ids)
                        
                        if participant_tokens:
                            push_service.send_event_cancelled_notification(
                                device_tokens=participant_tokens,
                                event_title=event['title'],
                                event_id=event_id
                            )
                            logger.info(f"Sent event cancellation notifications to {len(participant_tokens)} participants")
                except Exception as notification_error:
                    logger.error(f"Failed to send event cancellation notifications: {notification_error}")
                
                return {'message': 'Event cancelled successfully'}, 200
            else:
                return {'error': 'Failed to cancel event'}, 500
                
        except Exception as e:
            logger.error(f"Error cancelling event {event_id}: {e}", exc_info=True)
            return {'error': f'Failed to cancel event: {str(e)}'}, 500


class EventParticipationResource(Resource):
    """Handle event participation (join/leave)"""
    
    @auth_required
    def post(self, event_id):
        """Join event"""
        try:
            current_user_id = get_user_id()
            admin_client = get_supabase_admin_client()
            
            # Check if event exists and is active
            event_result = admin_client.table('events').select('title, max_participants, approval_required, status, scheduled_start_time').eq('id', event_id).execute()
            if not event_result.data:
                return {'error': 'Event not found'}, 404
            
            event = event_result.data[0]
            if event['status'] != 'active':
                return {'error': 'Event is not active'}, 400
            
            # Check if event is in the past
            event_time = datetime.fromisoformat(event['scheduled_start_time'].replace('Z', '+00:00'))
            if event_time < datetime.now(event_time.tzinfo):
                return {'error': 'Cannot join past events'}, 400
            
            # Check if user is already participating
            existing_result = admin_client.table('event_participants').select('status').eq('event_id', event_id).eq('user_id', current_user_id).execute()
            if existing_result.data:
                status = existing_result.data[0]['status']
                if status == 'approved':
                    return {'error': 'Already participating in this event'}, 400
                elif status == 'pending':
                    return {'error': 'Participation request is pending approval'}, 400
            
            # Check participant limit
            if event['max_participants']:
                approved_count = admin_client.table('event_participants').select('id', count='exact').eq('event_id', event_id).eq('status', 'approved').execute()
                if approved_count.count >= event['max_participants']:
                    return {'error': 'Event is full'}, 400
            
            # Determine participation status
            participation_status = 'pending' if event['approval_required'] else 'approved'
            
            # Add participant
            participant_data = {
                'event_id': event_id,
                'user_id': current_user_id,
                'status': participation_status
            }
            
            result = admin_client.table('event_participants').insert(participant_data).execute()
            
            if result.data:
                # Create progress entry if approved
                if participation_status == 'approved':
                    progress_data = {
                        'event_id': event_id,
                        'user_id': current_user_id,
                        'status': 'not_started'
                    }
                    admin_client.table('event_participant_progress').insert(progress_data).execute()
                
                logger.info(f"User {current_user_id} joined event {event_id} with status {participation_status}")
                
                message = 'Successfully joined event' if participation_status == 'approved' else 'Request to join event submitted for approval'
                return {'message': message, 'status': participation_status}, 201
            else:
                return {'error': 'Failed to join event'}, 500
                
        except Exception as e:
            logger.error(f"Error joining event {event_id}: {e}", exc_info=True)
            return {'error': f'Failed to join event: {str(e)}'}, 500
    
    @auth_required
    def delete(self, event_id):
        """Leave event"""
        try:
            current_user_id = get_user_id()
            admin_client = get_supabase_admin_client()
            
            # Check if user is participating
            participation_result = admin_client.table('event_participants').select('status').eq('event_id', event_id).eq('user_id', current_user_id).execute()
            if not participation_result.data:
                return {'error': 'Not participating in this event'}, 400
            
            # Remove participation
            admin_client.table('event_participants').delete().eq('event_id', event_id).eq('user_id', current_user_id).execute()
            
            # Remove progress entry
            admin_client.table('event_participant_progress').delete().eq('event_id', event_id).eq('user_id', current_user_id).execute()
            
            logger.info(f"User {current_user_id} left event {event_id}")
            return {'message': 'Successfully left event'}, 200
            
        except Exception as e:
            logger.error(f"Error leaving event {event_id}: {e}", exc_info=True)
            return {'error': f'Failed to leave event: {str(e)}'}, 500


# Register API endpoints
api.add_resource(EventsListResource, '/events')
api.add_resource(EventResource, '/events/<event_id>')
api.add_resource(EventParticipationResource, '/events/<event_id>/participation')
