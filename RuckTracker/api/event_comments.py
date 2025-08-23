"""
Event Comments API endpoints for event discussion and updates
"""
import logging
from flask import Blueprint, request, jsonify
from flask_restful import Api, Resource
from RuckTracker.api.auth import auth_required, get_user_id
from datetime import datetime
from RuckTracker.supabase_client import get_supabase_admin_client
from RuckTracker.services.push_notification_service import PushNotificationService, get_user_device_tokens

logger = logging.getLogger(__name__)

event_comments_bp = Blueprint('event_comments', __name__)
api = Api(event_comments_bp)

# Initialize push notification service
push_service = PushNotificationService()

class EventCommentsResource(Resource):
    """Handle event comments listing and creation"""
    
    @auth_required
    def get(self, event_id):
        """Get event comments"""
        try:
            current_user_id = get_user_id()
            admin_client = get_supabase_admin_client()
            
            # Check if user can view comments (must be participant in any status or creator)
            participant_check = admin_client.table('event_participants').select('status').eq('event_id', event_id).eq('user_id', current_user_id).execute()
            event_check = admin_client.table('events').select('creator_user_id').eq('id', event_id).execute()
            
            # Allow viewing for any participant (approved or pending) or the event creator
            is_participant = bool(participant_check.data)
            is_creator = event_check.data and event_check.data[0]['creator_user_id'] == current_user_id
            
            if not (is_participant or is_creator):
                return {'error': 'Only event participants can view comments'}, 403
            
            # Get comments with user info
            result = admin_client.table('event_comments').select("""
                *,
                user:user_id(id, username, avatar_url)
            """).eq('event_id', event_id).order('created_at', desc=False).execute()
            
            comments = result.data
            
            # Add user interaction flags
            for comment in comments:
                comment['is_own_comment'] = comment['user_id'] == current_user_id
            
            logger.info(f"Found {len(comments)} comments for event {event_id}")
            return {'comments': comments}, 200
            
        except Exception as e:
            logger.error(f"Error fetching comments for event {event_id}: {e}", exc_info=True)
            return {'error': f'Failed to fetch comments: {str(e)}'}, 500
    
    @auth_required
    def post(self, event_id):
        """Add event comment"""
        try:
            current_user_id = get_user_id()
            data = request.get_json()
            
            if not data or 'comment' not in data:
                return {'error': 'Comment text is required'}, 400
            
            if not data['comment'].strip():
                return {'error': 'Comment cannot be empty'}, 400
            
            admin_client = get_supabase_admin_client()
            
            # Check if user can comment (must be approved participant or creator)
            participant_check = admin_client.table('event_participants').select('status').eq('event_id', event_id).eq('user_id', current_user_id).execute()
            event_check = admin_client.table('events').select('creator_user_id, title').eq('id', event_id).execute()
            
            if not event_check.data:
                return {'error': 'Event not found'}, 404
            
            event = event_check.data[0]
            is_participant = participant_check.data and participant_check.data[0]['status'] == 'approved'
            is_creator = event['creator_user_id'] == current_user_id
            
            if not (is_participant or is_creator):
                return {'error': 'Only approved event participants can comment'}, 403
            
            # Create comment
            comment_data = {
                'event_id': event_id,
                'user_id': current_user_id,
                'comment': data['comment'].strip()
            }
            
            result = admin_client.table('event_comments').insert(comment_data).execute()
            
            if result.data:
                comment = result.data[0]
                
                # Get user info for the response
                user_result = admin_client.table('user').select('id, username, avatar_url').eq('id', current_user_id).execute()
                if user_result.data:
                    comment['user'] = user_result.data[0]
                
                comment['is_own_comment'] = True
                
                logger.info(f"Comment added to event {event_id} by user {current_user_id}")
                
                # Send notifications to other participants
                try:
                    # Get all participants except the commenter
                    participants = admin_client.table('event_participants').select('user_id').eq('event_id', event_id).eq('status', 'approved').neq('user_id', current_user_id).execute()
                    
                    if participants.data:
                        participant_ids = [p['user_id'] for p in participants.data]
                        participant_tokens = get_user_device_tokens(participant_ids)
                        
                        if participant_tokens:
                            # Get commenter name
                            commenter_name = f"{user_result.data[0]['username']}" if user_result.data else "Someone"
                            
                            push_service.send_event_comment_notification(
                                device_tokens=participant_tokens,
                                event_title=event['title'],
                                commenter_name=commenter_name,
                                comment_preview=data['comment'][:50] + ('...' if len(data['comment']) > 50 else ''),
                                event_id=event_id
                            )
                            logger.info(f"Sent comment notifications to {len(participant_tokens)} participants")
                except Exception as notification_error:
                    logger.error(f"Failed to send comment notifications: {notification_error}")
                
                return {'comment': comment, 'message': 'Comment added successfully'}, 201
            else:
                return {'error': 'Failed to add comment'}, 500
                
        except Exception as e:
            logger.error(f"Error adding comment to event {event_id}: {e}", exc_info=True)
            return {'error': f'Failed to add comment: {str(e)}'}, 500


class EventCommentResource(Resource):
    """Handle individual event comment operations"""
    
    @auth_required
    def put(self, event_id, comment_id):
        """Edit event comment (own comments only)"""
        try:
            current_user_id = get_user_id()
            data = request.get_json()
            
            if not data or 'comment' not in data:
                return {'error': 'Comment text is required'}, 400
            
            if not data['comment'].strip():
                return {'error': 'Comment cannot be empty'}, 400
            
            admin_client = get_supabase_admin_client()
            
            # Check if comment exists and user owns it
            comment_result = admin_client.table('event_comments').select('user_id').eq('id', comment_id).eq('event_id', event_id).execute()
            if not comment_result.data:
                return {'error': 'Comment not found'}, 404
            
            if comment_result.data[0]['user_id'] != current_user_id:
                return {'error': 'You can only edit your own comments'}, 403
            
            # Update comment
            update_data = {
                'comment': data['comment'].strip(),
                'updated_at': datetime.utcnow().isoformat()
            }
            
            result = admin_client.table('event_comments').update(update_data).eq('id', comment_id).execute()
            
            if result.data:
                logger.info(f"Comment {comment_id} updated by user {current_user_id}")
                return {'comment': result.data[0], 'message': 'Comment updated successfully'}, 200
            else:
                return {'error': 'Failed to update comment'}, 500
                
        except Exception as e:
            logger.error(f"Error updating comment {comment_id}: {e}", exc_info=True)
            return {'error': f'Failed to update comment: {str(e)}'}, 500
    
    @auth_required
    def delete(self, event_id, comment_id):
        """Delete event comment (own comments only)"""
        try:
            current_user_id = get_user_id()
            admin_client = get_supabase_admin_client()
            
            # Check if comment exists and user owns it
            comment_result = admin_client.table('event_comments').select('user_id').eq('id', comment_id).eq('event_id', event_id).execute()
            if not comment_result.data:
                return {'error': 'Comment not found'}, 404
            
            if comment_result.data[0]['user_id'] != current_user_id:
                return {'error': 'You can only delete your own comments'}, 403
            
            # Delete comment
            result = admin_client.table('event_comments').delete().eq('id', comment_id).execute()
            
            if result.data:
                logger.info(f"Comment {comment_id} deleted by user {current_user_id}")
                return {'message': 'Comment deleted successfully'}, 200
            else:
                return {'error': 'Failed to delete comment'}, 500
                
        except Exception as e:
            logger.error(f"Error deleting comment {comment_id}: {e}", exc_info=True)
            return {'error': f'Failed to delete comment: {str(e)}'}, 500


# Register API endpoints
api.add_resource(EventCommentsResource, '/events/<event_id>/comments')
api.add_resource(EventCommentResource, '/events/<event_id>/comments/<comment_id>')
