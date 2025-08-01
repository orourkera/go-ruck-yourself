# /Users/rory/RuckingApp/RuckTracker/api/duel_comments.py
from flask import request, jsonify, g
from flask_restful import Resource
import logging
import uuid
from datetime import datetime
from supabase import Client

# Import Supabase client
from RuckTracker.supabase_client import get_supabase_client, get_supabase_admin_client
from RuckTracker.api.auth import auth_required
from RuckTracker.services.push_notification_service import PushNotificationService, get_user_device_tokens
from RuckTracker.utils.api_response import build_api_response

logger = logging.getLogger(__name__)

# Initialize push notification service
push_service = PushNotificationService()

def create_duel_comment_notification(duel_id, comment_id, commenter_id, commenter_name):
    """
    Create notifications for all duel participants except the commenter
    """
    try:
        # Validate input parameters
        logger.info(f"create_duel_comment_notification called with: duel_id={duel_id}, comment_id={comment_id}, commenter_id={commenter_id}, commenter_name='{commenter_name}'")
        
        if not commenter_name or not str(commenter_name).strip():
            logger.error(f"Invalid commenter_name: '{commenter_name}' for comment {comment_id}")
            return
            
        admin_client = get_supabase_admin_client()
        
        # Get all participants in the duel except the commenter
        participants_response = admin_client.table('duel_participants') \
            .select('user_id') \
            .eq('duel_id', duel_id) \
            .neq('user_id', commenter_id) \
            .execute()
        
        if not participants_response.data:
            logger.info(f"No other participants to notify for duel {duel_id}")
            return
            
        logger.info(f"Found {len(participants_response.data)} participants to notify")
            
        # Get duel name for notification message
        duel_response = admin_client.table('duels') \
            .select('title') \
            .eq('id', duel_id) \
            .single() \
            .execute()
        
        duel_name = duel_response.data.get('title') if duel_response.data else None
        if not duel_name or not str(duel_name).strip():
            logger.warning(f"No valid duel title found for duel {duel_id}, using fallback")
            duel_name = 'a duel'
        
        logger.info(f"Duel name: '{duel_name}'")
        
        # Create notifications for each participant
        notifications = []
        message_text = f"{commenter_name} commented on the duel '{duel_name}'"
        
        # Ensure message_text is not null or empty
        if not message_text or not message_text.strip():
            logger.error(f"Invalid message_text generated: '{message_text}' for duel {duel_id}, comment {comment_id}")
            return
            
        logger.info(f"Generated message_text: '{message_text}'")
            
        for participant in participants_response.data:
            notification = {
                'recipient_id': participant['user_id'],
                'sender_id': commenter_id,
                'type': 'duel_comment',
                'duel_id': duel_id,
                'duel_comment_id': comment_id,
                'message': message_text,
                'data': {
                    'message': message_text,
                    'duel_name': duel_name,
                    'commenter_name': commenter_name,
                    'duel_id': duel_id,
                    'duel_comment_id': comment_id,
                    'created_at': 'NOW()'
                }
            }
            notifications.append(notification)
            logger.info(f"Created notification for participant {participant['user_id']}: message='{notification['message']}'")
        
        if notifications:
            logger.info(f"Inserting {len(notifications)} notifications into database...")
            for i, notif in enumerate(notifications):
                logger.info(f"Notification {i}: message='{notif['message']}', recipient_id={notif['recipient_id']}")
            
            admin_client.table('notifications').insert(notifications).execute()
            logger.info(f"Successfully created {len(notifications)} notifications for duel comment {comment_id}")
            
            # Send push notifications
            logger.info(f"🔔 PUSH NOTIFICATION: Starting duel comment push notification for duel {duel_id}")
            participant_ids = [p['user_id'] for p in participants_response.data if p['user_id'] != commenter_id]
            
            if participant_ids:
                device_tokens = get_user_device_tokens(participant_ids)
                logger.info(f"🔔 PUSH NOTIFICATION: Retrieved {len(device_tokens)} device tokens for {len(participant_ids)} participants")
                if device_tokens:
                    result = push_service.send_duel_comment_notification(
                        device_tokens=device_tokens,
                        commenter_name=commenter_name,
                        duel_name=duel_name,
                        duel_id=duel_id,
                        comment_id=str(comment_id)
                    )
                    
    except Exception as e:
        logger.error(f"Failed to create duel comment notifications: {e}")
        # Don't fail the comment creation if notification fails


def create_duel_joined_notification(duel_id, joiner_id, joiner_name):
    """
    Create notification for duel creator when someone joins their duel
    """
    try:
        admin_client = get_supabase_admin_client()
        
        # Get duel creator and name
        duel_response = admin_client.table('duels') \
            .select('creator_id, title') \
            .eq('id', duel_id) \
            .single() \
            .execute()
            
        if not duel_response.data:
            logger.warning(f"Duel {duel_id} not found for join notification")
            return
            
        creator_id = duel_response.data.get('creator_id')
        duel_name = duel_response.data.get('title', 'Unknown Duel')
        
        # Validate duel_name
        if not duel_name or not str(duel_name).strip():
            logger.warning(f"No valid duel title found for duel {duel_id}, using fallback")
            duel_name = 'a duel'
        
        # Don't notify if creator joined their own duel (shouldn't happen)
        if creator_id == joiner_id:
            return
            
        # Prepare notification message
        message_text = f"{joiner_name} joined your duel '{duel_name}'"
        
        # Ensure message_text is not null or empty
        if not message_text or not message_text.strip():
            logger.error(f"Invalid message_text generated for duel {duel_id}")
            return
            
        # Create notification for creator
        notification = {
            'recipient_id': creator_id,
            'sender_id': joiner_id,
            'type': 'duel_joined',
            'message': message_text,
            'duel_id': duel_id,
            'data': {
                'message': f"{joiner_name} joined your duel '{duel_name}'",
                'duel_name': duel_name,
                'joiner_name': joiner_name,
                'duel_id': duel_id,
                'created_at': 'NOW()'
            }
        }
        
        admin_client.table('notifications').insert(notification).execute()
        logger.info(f"Created duel joined notification for creator {creator_id}")
        
        # Send push notification
        logger.info(f"🔔 PUSH NOTIFICATION: Starting duel joined push notification for duel {duel_id}")
        device_tokens = get_user_device_tokens([creator_id])
        if device_tokens:
            result = push_service.send_duel_joined_notification(
                device_tokens=device_tokens,
                joiner_name=joiner_name,
                duel_name=duel_name,
                duel_id=duel_id
            )
            
    except Exception as e:
        logger.error(f"Failed to create duel joined notification: {e}")


def create_duel_started_notification(duel_id):
    """
    Create notifications for all participants when duel starts
    """
    try:
        admin_client = get_supabase_admin_client()
        
        # Get duel details and participants
        duel_response = admin_client.table('duels') \
            .select('title') \
            .eq('id', duel_id) \
            .single() \
            .execute()
            
        if not duel_response.data:
            logger.warning(f"Duel {duel_id} not found for started notification")
            return
            
        duel_name = duel_response.data.get('title', 'Unknown Duel')
        
        # Validate duel_name
        if not duel_name or not str(duel_name).strip():
            logger.warning(f"No valid duel title found for duel {duel_id}, using fallback")
            duel_name = 'a duel'
        
        # Get all participants
        participants_response = admin_client.table('duel_participants') \
            .select('user_id') \
            .eq('duel_id', duel_id) \
            .eq('status', 'accepted') \
            .execute()
        
        if not participants_response.data:
            logger.info(f"No participants to notify for duel start {duel_id}")
            return
            
        # Create notifications for each participant
        notifications = []
        message_text = f"'{duel_name}' has started! Begin your challenge"
        participant_ids = [p['user_id'] for p in participants_response.data]
        for user_id in participant_ids:
            notification = {
                'recipient_id': user_id,
                'sender_id': None,  # System notification
                'type': 'duel_started',
                'message': message_text,
                'duel_id': duel_id,
                'data': {
                    'message': message_text,
                    'duel_name': duel_name,
                    'duel_id': duel_id,
                    'created_at': 'NOW()'
                }
            }
            notifications.append(notification)
        
        if notifications:
            admin_client.table('notifications').insert(notifications).execute()
            logger.info(f"Created {len(notifications)} duel started notifications")
            
            # Send push notifications
            logger.info(f"🔔 PUSH NOTIFICATION: Starting duel started push notification for duel {duel_id}")
            device_tokens = get_user_device_tokens(participant_ids)
            if device_tokens:
                result = push_service.send_duel_started_notification(
                    device_tokens=device_tokens,
                    duel_name=duel_name,
                    duel_id=duel_id
                )
                    
    except Exception as e:
        logger.error(f"Failed to create duel started notifications: {e}")


def create_duel_completed_notification(duel_id):
    """
    Create notifications for all participants when duel completes
    """
    try:
        admin_client = get_supabase_admin_client()
        
        # Get duel details and participants
        duel_response = admin_client.table('duels') \
            .select('title') \
            .eq('id', duel_id) \
            .single() \
            .execute()
            
        if not duel_response.data:
            logger.warning(f"Duel {duel_id} not found for completed notification")
            return
            
        duel_name = duel_response.data.get('title', 'Unknown Duel')
        
        # Validate duel_name
        if not duel_name or not str(duel_name).strip():
            logger.warning(f"No valid duel title found for duel {duel_id}, using fallback")
            duel_name = 'a duel'
        
        # Get all participants
        participants_response = admin_client.table('duel_participants') \
            .select('user_id') \
            .eq('duel_id', duel_id) \
            .eq('status', 'accepted') \
            .execute()
        
        if not participants_response.data:
            logger.info(f"No participants to notify for duel completion {duel_id}")
            return
            
        # Create notifications for each participant
        notifications = []
        message_text = f"'{duel_name}' has completed! Check the results"
        
        # Debug logging
        logger.info(f"🔍 [DUEL_COMPLETION_NOTIFICATION] Creating notifications for duel {duel_id}")
        logger.info(f"🔍 [DUEL_COMPLETION_NOTIFICATION] Duel name: '{duel_name}'")
        logger.info(f"🔍 [DUEL_COMPLETION_NOTIFICATION] Message text: '{message_text}'")
        logger.info(f"🔍 [DUEL_COMPLETION_NOTIFICATION] Number of participants: {len(participants_response.data)}")
        
        participant_ids = []
        for participant in participants_response.data:
            user_id = participant['user_id']
            participant_ids.append(user_id)
            notification = {
                'recipient_id': user_id,
                'sender_id': None,  # System notification
                'type': 'duel_completed',
                'message': message_text,
                'duel_id': duel_id,
                'data': {
                    'message': message_text,
                    'duel_name': duel_name,
                    'duel_id': duel_id,
                    'created_at': 'NOW()'
                }
            }
            notifications.append(notification)
            logger.info(f"🔍 [DUEL_COMPLETION_NOTIFICATION] Created notification for user {user_id}: {notification}")
        
        if notifications:
            logger.info(f"🔍 [DUEL_COMPLETION_NOTIFICATION] About to insert {len(notifications)} notifications")
            admin_client.table('notifications').insert(notifications).execute()
            logger.info(f"Created {len(notifications)} duel completed notifications")
            
            # Send push notifications
            logger.info(f"🔔 PUSH NOTIFICATION: Starting duel completed push notification for duel {duel_id}")
            device_tokens = get_user_device_tokens(participant_ids)
            if device_tokens:
                result = push_service.send_duel_completed_notification(
                    device_tokens=device_tokens,
                    duel_name=duel_name,
                    duel_id=duel_id
                )
                    
    except Exception as e:
        logger.error(f"Failed to create duel completed notifications: {e}")


def create_duel_progress_notification(duel_id, participant_id, participant_name, ruck_id):
    """
    Create notifications for all other participants when someone completes a ruck for the duel
    """
    try:
        admin_client = get_supabase_admin_client()
        
        # Get duel name
        duel_response = admin_client.table('duels') \
            .select('title') \
            .eq('id', duel_id) \
            .single() \
            .execute()
            
        if not duel_response.data:
            logger.warning(f"Duel {duel_id} not found for progress notification")
            return
            
        duel_name = duel_response.data.get('title', 'Unknown Duel')
        
        # Validate duel_name
        if not duel_name or not str(duel_name).strip():
            logger.warning(f"No valid duel title found for duel {duel_id}, using fallback")
            duel_name = 'a duel'
        
        # Get all other participants (excluding the one who completed the ruck)
        participants_response = admin_client.table('duel_participants') \
            .select('user_id') \
            .eq('duel_id', duel_id) \
            .eq('status', 'accepted') \
            .neq('user_id', participant_id) \
            .execute()
        
        if not participants_response.data:
            logger.info(f"No other participants to notify for duel progress {duel_id}")
            return
            
        # Create notifications for other participants
        notifications = []
        message_text = f"{participant_name} completed a ruck for '{duel_name}'"
        other_participant_ids = [p['user_id'] for p in participants_response.data]
        for user_id in other_participant_ids:
            notification = {
                'recipient_id': user_id,
                'sender_id': participant_id,
                'type': 'duel_progress',
                'message': message_text,
                'duel_id': duel_id,
                'ruck_id': ruck_id,
                'data': {
                    'message': message_text,
                    'duel_name': duel_name,
                    'participant_name': participant_name,
                    'ruck_id': ruck_id,
                    'duel_id': duel_id,
                    'created_at': 'NOW()'
                }
            }
            notifications.append(notification)
        
        if notifications:
            admin_client.table('notifications').insert(notifications).execute()
            logger.info(f"Created {len(notifications)} duel progress notifications")
            
            # Send push notifications
            logger.info(f"🔔 PUSH NOTIFICATION: Starting duel progress push notification for duel {duel_id}")
            device_tokens = get_user_device_tokens(other_participant_ids)
            if device_tokens:
                result = push_service.send_duel_progress_notification(
                    device_tokens=device_tokens,
                    participant_name=participant_name,
                    duel_name=duel_name,
                    duel_id=duel_id,
                    ruck_id=str(ruck_id)
                )
                    
    except Exception as e:
        logger.error(f"Failed to create duel progress notifications: {e}")


def create_duel_deleted_notification(duel_id, deleter_id):
    """
    Create notifications for all participants when a duel is deleted
    """
    try:
        admin_client = get_supabase_admin_client()
        
        # Get duel details before it gets deleted
        duel_response = admin_client.table('duels') \
            .select('title, creator_id') \
            .eq('id', duel_id) \
            .single() \
            .execute()
            
        if not duel_response.data:
            logger.warning(f"Duel {duel_id} not found for deletion notification")
            return
            
        duel_name = duel_response.data.get('title', 'Unknown Duel')
        
        # Validate duel_name
        if not duel_name or not str(duel_name).strip():
            logger.warning(f"No valid duel title found for duel {duel_id}, using fallback")
            duel_name = 'a duel'
        
        creator_id = duel_response.data.get('creator_id')
        
        # Get all participants in the duel except the deleter (who is the creator)
        participants_response = admin_client.table('duel_participants') \
            .select('user_id') \
            .eq('duel_id', duel_id) \
            .neq('user_id', deleter_id) \
            .execute()
        
        if not participants_response.data:
            logger.info(f"No participants to notify for duel deletion {duel_id}")
            return
            
        # Get deleter's name
        deleter_response = admin_client.table('users') \
            .select('username, display_name') \
            .eq('id', deleter_id) \
            .single() \
            .execute()
            
        deleter_name = 'Someone'
        if deleter_response.data:
            deleter_name = deleter_response.data.get('display_name') or deleter_response.data.get('username', 'Someone')
        
        # Create notifications for each participant
        notifications = []
        message_text = f"The duel '{duel_name}' has been deleted by {deleter_name}"
        for participant in participants_response.data:
            notification = {
                'recipient_id': participant['user_id'],
                'sender_id': deleter_id,
                'type': 'duel_deleted',
                'message': message_text,
                'duel_id': duel_id,
                'data': {
                    'message': message_text,
                    'duel_name': duel_name,
                    'deleter_name': deleter_name,
                    'duel_id': duel_id,
                    'created_at': 'NOW()'
                }
            }
            notifications.append(notification)
        
        if notifications:
            admin_client.table('notifications').insert(notifications).execute()
            logger.info(f"Created {len(notifications)} notifications for duel deletion {duel_id}")
            
            # Send push notifications
            logger.info(f"🔔 PUSH NOTIFICATION: Starting duel deleted push notification for duel {duel_id}")
            participant_ids = [p['user_id'] for p in participants_response.data]
            
            if participant_ids:
                device_tokens = get_user_device_tokens(participant_ids)
                if device_tokens:
                    result = push_service.send_duel_deleted_notification(
                        device_tokens=device_tokens,
                        deleter_name=deleter_name,
                        duel_name=duel_name,
                        duel_id=duel_id
                    )
                    
    except Exception as e:
        logger.error(f"Failed to create duel deletion notifications: {e}")


def send_duel_completed_push_notifications(duel_id):
    """
    Send push notifications for duel completion.
    Database notifications are handled by trigger.
    """
    try:
        admin_client = get_supabase_admin_client()
        
        # Get duel details and participants
        duel_response = admin_client.table('duels') \
            .select('title') \
            .eq('id', duel_id) \
            .single() \
            .execute()
            
        if not duel_response.data:
            logger.warning(f"Duel {duel_id} not found for push notifications")
            return
            
        duel_name = duel_response.data.get('title', 'Unknown Duel')
        
        # Validate duel_name
        if not duel_name or not str(duel_name).strip():
            logger.warning(f"No valid duel title found for duel {duel_id}, using fallback")
            duel_name = 'a duel'
        
        # Get all participants
        participants_response = admin_client.table('duel_participants') \
            .select('user_id') \
            .eq('duel_id', duel_id) \
            .eq('status', 'accepted') \
            .execute()
        
        if not participants_response.data:
            logger.info(f"No participants to notify for duel completion {duel_id}")
            return
            
        participant_ids = [p['user_id'] for p in participants_response.data]
        
        # Send push notifications only
        logger.info(f"🔔 PUSH NOTIFICATION: Starting final duel completed push notification for duel {duel_id}")
        device_tokens = get_user_device_tokens(participant_ids)
        if device_tokens:
            result = push_service.send_duel_completed_notification(
                device_tokens=device_tokens,
                duel_name=duel_name,
                duel_id=duel_id
            )
            logger.info(f"✅ [DUEL_COMPLETION_PUSH] Sent push notifications to {len(device_tokens)} devices for duel completion")
        else:
            logger.info(f"🔕 [DUEL_COMPLETION_PUSH] No device tokens found for duel {duel_id} participants")
                    
    except Exception as e:
        logger.error(f"❌ [DUEL_COMPLETION_PUSH] Failed to send duel completed push notifications: {e}")


class DuelCommentsResource(Resource):
    @auth_required
    def get(self, duel_id):
        """
        Get comments for a specific duel.
        
        Expects 'duel_id' from the URL path.
        The user must be authenticated and must be a participant in the duel.
        """
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            logger.warning("DuelCommentsResource: Missing or invalid Authorization header.")
            return build_api_response(success=False, error="Unauthorized", status_code=401)
        
        token = auth_header.split("Bearer ")[1]

        # Initialize Supabase client with the user's token to respect RLS
        try:
            supabase = get_supabase_client(user_jwt=token)
            user_response = supabase.auth.get_user(token)
            if not user_response.user:
                logger.warning("DuelCommentsResource: Invalid token or user not found.")
                return build_api_response(success=False, error="Invalid token or user not found.", status_code=401)
            
            user_id = user_response.user.id
            logger.debug(f"DuelCommentsResource: Authenticated user {user_id}")
        except Exception as e:
            logger.error(f"DuelCommentsResource: Error during Supabase client initialization or user auth: {e}")
            return build_api_response(success=False, error="Authentication error.", status_code=500)

        # Check if user is a participant in the duel
        try:
            participant_check = supabase.table('duel_participants') \
                                      .select('duel_id') \
                                      .eq('duel_id', duel_id) \
                                      .eq('user_id', user_id) \
                                      .execute()
            
            if not participant_check.data:
                logger.warning(f"DuelCommentsResource: User {user_id} is not a participant in duel {duel_id}")
                return build_api_response(success=False, error="You must be a participant to view comments.", status_code=403)
            
        except Exception as e:
            logger.error(f"DuelCommentsResource: Error checking duel participation: {e}")
            return build_api_response(success=False, error="Error verifying participation.", status_code=500)

        # Get comments for the duel
        try:
            query_result = supabase.table('duel_comments') \
                                 .select('id, duel_id, user_id, user_display_name, user_avatar_url, content, created_at, updated_at') \
                                 .eq('duel_id', duel_id) \
                                 .order('created_at', desc=True) \
                                 .execute()
            
            if hasattr(query_result, 'error') and query_result.error:
                logger.error(f"DuelCommentsResource: Supabase query error: {query_result.error}")
                return build_api_response(success=False, error="Failed to fetch comments from database.", status_code=500)

            return build_api_response(data=query_result.data, status_code=200)
            
        except Exception as e:
            logger.error(f"DuelCommentsResource: Error fetching duel comments: {e}", exc_info=True)
            return build_api_response(success=False, error="An error occurred while fetching comments.", status_code=500)
    
    @auth_required
    def post(self, duel_id):
        """
        Add a comment to a duel.
        
        Expects 'duel_id' from the URL path and JSON body with 'content'.
        The user must be authenticated and must be a participant in the duel.
        """
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            logger.warning("DuelCommentsResource: Missing or invalid Authorization header.")
            return build_api_response(success=False, error="Unauthorized", status_code=401)
        
        token = auth_header.split("Bearer ")[1]

        # Initialize Supabase client with the user's token to respect RLS
        try:
            supabase = get_supabase_client(user_jwt=token)
            user_response = supabase.auth.get_user(token)
            if not user_response.user:
                logger.warning("DuelCommentsResource: Invalid token or user not found.")
                return build_api_response(success=False, error="Invalid token or user not found.", status_code=401)
            
            user_id = user_response.user.id
            user_email = user_response.user.email
            logger.debug(f"DuelCommentsResource: Authenticated user {user_id}")
        except Exception as e:
            logger.error(f"DuelCommentsResource: Error during Supabase client initialization or user auth: {e}")
            return build_api_response(success=False, error="Authentication error.", status_code=500)

        # Check if user is a participant in the duel
        try:
            participant_check = supabase.table('duel_participants') \
                                      .select('duel_id') \
                                      .eq('duel_id', duel_id) \
                                      .eq('user_id', user_id) \
                                      .execute()
            
            if not participant_check.data:
                logger.warning(f"DuelCommentsResource: User {user_id} is not a participant in duel {duel_id}")
                return build_api_response(success=False, error="You must be a participant to comment.", status_code=403)
            
        except Exception as e:
            logger.error(f"DuelCommentsResource: Error checking duel participation: {e}")
            return build_api_response(success=False, error="Error verifying participation.", status_code=500)

        # Get user profile information for display name
        try:
            user_profile = supabase.table('user') \
                                 .select('username, avatar_url') \
                                 .eq('id', user_id) \
                                 .execute()
            
            if user_profile.data and user_profile.data[0].get('username'):
                user_display_name = user_profile.data[0]['username']
                user_avatar_url = user_profile.data[0].get('avatar_url')
            else:
                # Fallback: try to get username with admin client if user client fails
                logger.warning(f"DuelCommentsResource: Could not fetch username for user {user_id} with user client, trying admin client")
                admin_client = get_supabase_admin_client()
                admin_profile = admin_client.table('user') \
                                          .select('username, avatar_url') \
                                          .eq('id', user_id) \
                                          .execute()
                
                if admin_profile.data and admin_profile.data[0].get('username'):
                    user_display_name = admin_profile.data[0]['username']
                    user_avatar_url = admin_profile.data[0].get('avatar_url')
                else:
                    logger.error(f"DuelCommentsResource: No username found for user {user_id} in user table")
                    return build_api_response(success=False, error="User profile not found", status_code=500)
            
        except Exception as e:
            logger.error(f"DuelCommentsResource: Error fetching user profile: {e}")
            # Try with admin client as fallback
            try:
                admin_client = get_supabase_admin_client()
                admin_profile = admin_client.table('user') \
                                          .select('username, avatar_url') \
                                          .eq('id', user_id) \
                                          .execute()
                
                if admin_profile.data and admin_profile.data[0].get('username'):
                    user_display_name = admin_profile.data[0]['username']
                    user_avatar_url = admin_profile.data[0].get('avatar_url')
                else:
                    logger.error(f"DuelCommentsResource: No username found for user {user_id} even with admin client")
                    return build_api_response(success=False, error="User profile not found", status_code=500)
            except Exception as admin_e:
                logger.error(f"DuelCommentsResource: Admin client also failed to fetch user profile: {admin_e}")
                return build_api_response(success=False, error="User profile lookup failed", status_code=500)

        # Get content from request
        try:
            data = request.get_json()
            if not data:
                logger.info("DuelCommentsResource: No JSON data provided.")
                return build_api_response(success=False, error="No JSON data provided", status_code=400)
            
            content = data.get('content', '').strip()
            if not content:
                logger.info("DuelCommentsResource: Content is required for adding a comment.")
                return build_api_response(success=False, error="Content is required", status_code=400)
                
        except Exception as e:
            logger.error(f"DuelCommentsResource: Error parsing request data: {e}")
            return build_api_response(success=False, error="Invalid request data", status_code=400)

        # Insert the comment
        try:
            insert_data = {
                'duel_id': duel_id,
                'user_id': user_id,
                'user_display_name': user_display_name,
                'user_avatar_url': user_avatar_url,
                'content': content
            }
            
            insert_response = supabase.table('duel_comments').insert(insert_data).execute()
            
            if hasattr(insert_response, 'error') and insert_response.error:
                logger.error(f"DuelCommentsResource: Error inserting comment: {insert_response.error}")
                return build_api_response(success=False, error="Failed to add comment", status_code=500)
            
            new_comment = insert_response.data[0]
            # Create notification for duel participants (disabled - handled by database trigger)
            # create_duel_comment_notification(duel_id, new_comment['id'], user_id, user_display_name)
            
            return build_api_response(data=new_comment, status_code=201)
            
        except Exception as e:
            logger.error(f"DuelCommentsResource: Error adding comment: {e}", exc_info=True)
            return build_api_response(success=False, error="An error occurred while adding comment.", status_code=500)
    
    @auth_required
    def put(self, duel_id):
        """
        Update an existing comment.
        
        Expects 'duel_id' from URL path and JSON body with 'comment_id' and 'content'.
        The user must be authenticated, be a participant, and be the author of the comment.
        """
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            logger.warning("DuelCommentsResource: Missing or invalid Authorization header.")
            return build_api_response(success=False, error="Unauthorized", status_code=401)
        
        token = auth_header.split("Bearer ")[1]

        # Initialize Supabase client with the user's token to respect RLS
        try:
            supabase = get_supabase_client(user_jwt=token)
            user_response = supabase.auth.get_user(token)
            if not user_response.user:
                logger.warning("DuelCommentsResource: Invalid token or user not found.")
                return build_api_response(success=False, error="Invalid token or user not found.", status_code=401)
            
            user_id = user_response.user.id
            logger.debug(f"DuelCommentsResource: Authenticated user {user_id}")
        except Exception as e:
            logger.error(f"DuelCommentsResource: Error during Supabase client initialization or user auth: {e}")
            return build_api_response(success=False, error="Authentication error.", status_code=500)

        # Check if user is a participant in the duel
        try:
            participant_check = supabase.table('duel_participants') \
                                      .select('duel_id') \
                                      .eq('duel_id', duel_id) \
                                      .eq('user_id', user_id) \
                                      .execute()
            
            if not participant_check.data:
                logger.warning(f"DuelCommentsResource: User {user_id} is not a participant in duel {duel_id}")
                return build_api_response(success=False, error="You must be a participant to edit comments.", status_code=403)
            
        except Exception as e:
            logger.error(f"DuelCommentsResource: Error checking duel participation: {e}")
            return build_api_response(success=False, error="Error verifying participation.", status_code=500)

        # Get request data
        try:
            data = request.get_json()
            if not data:
                logger.info("DuelCommentsResource: No JSON data provided.")
                return build_api_response(success=False, error="No JSON data provided", status_code=400)
            
            comment_id = data.get('comment_id')
            content = data.get('content', '').strip()
            
            if not comment_id:
                logger.info("DuelCommentsResource: Missing comment_id in request body.")
                return build_api_response(success=False, error="Missing comment_id", status_code=400)
            
            if not content:
                logger.info("DuelCommentsResource: Content is required for updating a comment.")
                return build_api_response(success=False, error="Content is required", status_code=400)
                
        except Exception as e:
            logger.error(f"DuelCommentsResource: Error parsing request data: {e}")
            return build_api_response(success=False, error="Invalid request data", status_code=400)

        # Check if the comment exists and belongs to the user
        try:
            comment_query = supabase.table('duel_comments') \
                                   .select('id, user_id, duel_id') \
                                   .eq('id', comment_id) \
                                   .eq('duel_id', duel_id) \
                                   .execute()
            
            if not comment_query.data:
                logger.info(f"DuelCommentsResource: Comment with ID {comment_id} not found in duel {duel_id}.")
                return build_api_response(success=False, error=f"Comment not found.", status_code=404)
            
            comment_data = comment_query.data[0]
            
            # Verify ownership
            if comment_data['user_id'] != user_id:
                logger.warning(f"DuelCommentsResource: User {user_id} attempted to edit comment {comment_id} belonging to user {comment_data['user_id']}")
                return build_api_response(
                    success=False, 
                    error="You can only edit your own comments.",
                    status_code=403
                )
        except Exception as e:
            logger.error(f"DuelCommentsResource: Error verifying comment: {e}")
            return build_api_response(success=False, error="Error verifying comment", status_code=500)
            
        # Update the comment
        try:
            update_response = supabase.table('duel_comments') \
                                    .update({
                                        'content': content,
                                        'updated_at': 'now()'
                                    }) \
                                    .eq('id', comment_id) \
                                    .execute()
            
            if hasattr(update_response, 'error') and update_response.error:
                logger.error(f"DuelCommentsResource: Error updating comment: {update_response.error}")
                return build_api_response(success=False, error="Failed to update comment", status_code=500)
            
            return build_api_response(data=update_response.data[0], status_code=200)
            
        except Exception as e:
            logger.error(f"DuelCommentsResource: Error updating comment: {e}", exc_info=True)
            return build_api_response(success=False, error="An error occurred while updating comment.", status_code=500)

    @auth_required
    def delete(self, duel_id):
        """
        Delete a comment.
        
        Expects 'duel_id' from URL path and 'comment_id' as a query parameter.
        The user must be authenticated, be a participant, and be the author of the comment.
        """
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            logger.warning("DuelCommentsResource: Missing or invalid Authorization header.")
            return build_api_response(success=False, error="Unauthorized", status_code=401)
        
        token = auth_header.split("Bearer ")[1]

        # Initialize Supabase client with the user's token to respect RLS
        try:
            supabase = get_supabase_client(user_jwt=token)
            user_response = supabase.auth.get_user(token)
            if not user_response.user:
                logger.warning("DuelCommentsResource: Invalid token or user not found.")
                return build_api_response(success=False, error="Invalid token or user not found.", status_code=401)
            
            user_id = user_response.user.id
            logger.debug(f"DuelCommentsResource: Authenticated user {user_id}")
        except Exception as e:
            logger.error(f"DuelCommentsResource: Error during Supabase client initialization or user auth: {e}")
            return build_api_response(success=False, error="Authentication error.", status_code=500)

        # Check if user is a participant in the duel
        try:
            participant_check = supabase.table('duel_participants') \
                                      .select('duel_id') \
                                      .eq('duel_id', duel_id) \
                                      .eq('user_id', user_id) \
                                      .execute()
            
            if not participant_check.data:
                logger.warning(f"DuelCommentsResource: User {user_id} is not a participant in duel {duel_id}")
                return build_api_response(success=False, error="You must be a participant to delete comments.", status_code=403)
            
        except Exception as e:
            logger.error(f"DuelCommentsResource: Error checking duel participation: {e}")
            return build_api_response(success=False, error="Error verifying participation.", status_code=500)

        # Get comment_id from query parameters
        comment_id = request.args.get('comment_id')
        if not comment_id:
            logger.info("DuelCommentsResource: Missing comment_id query parameter.")
            return build_api_response(success=False, error="Missing comment_id query parameter", status_code=400)
            
        # Check if the comment exists and belongs to the user
        try:
            comment_query = supabase.table('duel_comments') \
                                   .select('id, user_id, duel_id') \
                                   .eq('id', comment_id) \
                                   .eq('duel_id', duel_id) \
                                   .execute()
            
            if not comment_query.data:
                logger.info(f"DuelCommentsResource: Comment with ID {comment_id} not found in duel {duel_id}.")
                return build_api_response(success=False, error=f"Comment not found.", status_code=404)
            
            comment_data = comment_query.data[0]
            
            # Verify ownership (RLS should handle this, but double check)
            if comment_data['user_id'] != user_id:
                logger.warning(f"DuelCommentsResource: User {user_id} attempted to delete comment {comment_id} belonging to user {comment_data['user_id']}")
                return build_api_response(
                    success=False, 
                    error="You can only delete your own comments.",
                    status_code=403
                )
        except Exception as e:
            logger.error(f"DuelCommentsResource: Error verifying comment: {e}")
            return build_api_response(success=False, error="Error verifying comment", status_code=500)
            
        # Delete the comment
        try:
            delete_response = supabase.table('duel_comments') \
                                    .delete() \
                                    .eq('id', comment_id) \
                                    .execute()
            
            if hasattr(delete_response, 'error') and delete_response.error:
                logger.error(f"DuelCommentsResource: Error deleting comment: {delete_response.error}")
                return build_api_response(success=False, error="Failed to delete comment", status_code=500)
            
            return build_api_response(
                data={'message': 'Comment deleted successfully', 'comment_id': comment_id},
                status_code=200
            )
            
        except Exception as e:
            logger.error(f"DuelCommentsResource: Error deleting comment: {e}", exc_info=True)
            return build_api_response(success=False, error="An error occurred while deleting comment.", status_code=500)
