"""
Ruck Messages API
Handles live messaging during active ruck sessions
"""
import logging
from flask import Blueprint, request, g
from flask_restful import Resource, Api
from RuckTracker.supabase_client import get_supabase_client
from RuckTracker.services.voice_message_service import voice_message_service
from RuckTracker.services.notification_manager import notification_manager
from datetime import datetime

logger = logging.getLogger(__name__)

class RuckMessagesResource(Resource):
    """Send and retrieve messages for a ruck session"""

    def post(self, ruck_id):
        """Send a message to someone during their active ruck"""
        try:
            data = request.get_json()
            message = data.get('message', '').strip()
            voice_id = data.get('voice_id', 'supportive_friend')

            if not message:
                return {'error': 'Message is required'}, 400

            if len(message) > 200:
                return {'error': 'Message must be 200 characters or less'}, 400

            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            sender_id = g.user.id

            # Get session details
            session_response = supabase.table('ruck_session').select(
                'id, user_id, status, allow_live_following'
            ).eq('id', ruck_id).single().execute()

            if not session_response.data:
                return {'error': 'Session not found'}, 404

            session = session_response.data
            recipient_id = session['user_id']

            # Validation checks
            if session['status'] != 'active':
                return {'error': 'Can only send messages to active rucks'}, 400

            if not session.get('allow_live_following', True):
                return {'error': 'This user has disabled live following'}, 403

            if sender_id == recipient_id:
                return {'error': 'Cannot send messages to your own ruck'}, 400

            # Check if sender follows recipient
            follow_check = supabase.table('follows').select('id').eq(
                'follower_id', sender_id
            ).eq('followed_id', recipient_id).execute()

            if not follow_check.data:
                return {'error': 'You must follow this user to send messages'}, 403

            # Get sender name for notification
            sender_response = supabase.table('user').select('username').eq('id', sender_id).single().execute()
            sender_name = sender_response.data.get('username', 'Someone') if sender_response.data else 'Someone'

            # Generate voice audio
            logger.info(f"Generating voice message for ruck {ruck_id}: voice={voice_id}, length={len(message)}")
            audio_url = voice_message_service.generate_voice_message(message, voice_id)

            if not audio_url:
                logger.warning("Voice generation failed, saving message without audio")
                # Still save the message even if voice generation fails
                audio_url = None

            # Save message to database
            message_data = {
                'ruck_id': ruck_id,
                'sender_id': sender_id,
                'recipient_id': recipient_id,
                'message': message,
                'voice_id': voice_id,
                'audio_url': audio_url,
                'created_at': datetime.utcnow().isoformat()
            }

            insert_result = supabase.table('ruck_messages').insert(message_data).execute()

            if not insert_result.data:
                return {'error': 'Failed to save message'}, 500

            saved_message = insert_result.data[0]

            # Send push notification to rucker
            logger.info(f"Sending ruck message notification to {recipient_id}")
            notification_manager.send_notification(
                recipients=[recipient_id],
                notification_type='ruck_message',
                title=f'🎤 {sender_name}',
                body=message,
                data={
                    'ruck_id': ruck_id,
                    'message_id': saved_message['id'],
                    'sender_id': sender_id,
                    'audio_url': audio_url,
                    'voice_id': voice_id,
                    'click_action': 'FLUTTER_NOTIFICATION_CLICK'
                },
                sender_id=sender_id
            )

            return {
                'status': 'success',
                'message': saved_message
            }, 201

        except Exception as e:
            logger.error(f"Error sending ruck message: {e}", exc_info=True)
            return {'error': 'Failed to send message'}, 500

    def get(self, ruck_id):
        """Get all messages for a ruck session"""
        try:
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            user_id = g.user.id

            # Get session to check authorization
            session_response = supabase.table('ruck_session').select(
                'user_id, allow_live_following'
            ).eq('id', ruck_id).single().execute()

            if not session_response.data:
                return {'error': 'Session not found'}, 404

            session = session_response.data
            is_owner = session['user_id'] == user_id

            # Check if user is allowed to view messages
            if not is_owner:
                # Check if user follows the rucker
                follow_check = supabase.table('follows').select('id').eq(
                    'follower_id', user_id
                ).eq('followed_id', session['user_id']).execute()

                if not follow_check.data:
                    return {'error': 'Not authorized to view these messages'}, 403

            # Get messages for this ruck
            messages_response = supabase.table('ruck_messages').select(
                '*, sender:sender_id(username, avatar_url)'
            ).eq('ruck_id', ruck_id).order('created_at', desc=False).execute()

            return {
                'status': 'success',
                'messages': messages_response.data or []
            }, 200

        except Exception as e:
            logger.error(f"Error fetching ruck messages: {e}", exc_info=True)
            return {'error': 'Failed to fetch messages'}, 500


# Create Blueprint
ruck_messages_bp = Blueprint('ruck_messages', __name__)
ruck_messages_api = Api(ruck_messages_bp)

# Register resources
ruck_messages_api.add_resource(RuckMessagesResource, '/rucks/<int:ruck_id>/messages')
