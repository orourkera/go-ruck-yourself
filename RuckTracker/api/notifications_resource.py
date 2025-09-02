"""
Notifications resource module for handling user notifications.
"""
from flask import g, jsonify, request
from flask_restful import Resource
from functools import wraps
from ..supabase_client import get_supabase_admin_client
import logging

logger = logging.getLogger(__name__)

# Authentication decorator
def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not g.user:
            return {"error": "Authentication required"}, 401
        return f(*args, **kwargs)
    return decorated

# Helper to get user ID from the session
def get_user_id():
    if g.user and hasattr(g.user, 'id'):
        return g.user.id
    return None

class NotificationsResource(Resource):
    """Resource for getting and creating notifications"""
    
    @require_auth
    def get(self):
        """
        Get all notifications for the current user
        """
        try:
            user_id = get_user_id()
            if not user_id:
                return {"error": "Not authenticated"}, 401
                
            # Get Supabase client
            supabase_client = get_supabase_admin_client()
            
            # Get pagination parameters
            page = int(request.args.get('page', 1))
            limit = min(int(request.args.get('limit', 50)), 100)  # Cap at 100
            offset = (page - 1) * limit
            
            # Query notifications from Supabase - only select needed fields with pagination
            response = supabase_client.table('notifications').select(
                'id, type, message, data, is_read, read_at, created_at, sender_id, duel_id, event_id, club_id'
            ).eq('recipient_id', user_id).order('created_at', desc=True).range(offset, offset + limit - 1).execute()
            
            if hasattr(response, 'error') and response.error:
                logger.error(f"Error fetching notifications: {response.error}")
                return {"error": "Failed to fetch notifications"}, 500
                
            notifications = response.data
            
            # Format the response with pagination info
            return {
                "notifications": notifications,
                "count": len(notifications),
                "page": page,
                "limit": limit,
                "has_more": len(notifications) == limit
            }
            
        except Exception as e:
            logger.error(f"Exception in get notifications: {str(e)}")
            return {"error": "Internal server error"}, 500

class NotificationReadResource(Resource):
    """Resource for marking a notification as read"""
    
    @require_auth
    def post(self, notification_id):
        """
        Mark a notification as read
        """
        try:
            user_id = get_user_id()
            if not user_id:
                return {"error": "Not authenticated"}, 401
                
            # Get Supabase client
            supabase_client = get_supabase_admin_client()
                
            # Update the notification in Supabase
            response = supabase_client.table('notifications').update({"is_read": True}).eq('id', notification_id).eq('recipient_id', user_id).execute()
            
            if hasattr(response, 'error') and response.error:
                logger.error(f"Error marking notification as read: {response.error}")
                return {"error": "Failed to mark notification as read"}, 500
            
            return {"success": True, "message": "Notification marked as read"}
            
        except Exception as e:
            logger.error(f"Exception in mark notification as read: {str(e)}")
            return {"error": "Internal server error"}, 500

class ReadAllNotificationsResource(Resource):
    """Resource for marking all notifications as read"""
    
    @require_auth
    def post(self):
        """
        Mark all notifications as read for the current user
        """
        try:
            user_id = get_user_id()
            if not user_id:
                return {"error": "Not authenticated"}, 401
                
            # Get Supabase client
            supabase_client = get_supabase_admin_client()
            
            # Use more efficient approach: only update unread notifications to avoid unnecessary updates
            response = supabase_client.table('notifications').update({
                "is_read": True,
                "read_at": "now()"  # Set read timestamp
            }).eq('recipient_id', user_id).eq('is_read', False).execute()
            
            if hasattr(response, 'error') and response.error:
                logger.error(f"Error marking all notifications as read: {response.error}")
                return {"error": "Failed to mark all notifications as read"}, 500
            
            # Return count of updated notifications
            updated_count = len(response.data) if response.data else 0
            logger.info(f"Marked {updated_count} notifications as read for user {user_id}")
            
            return {"success": True, "message": f"Marked {updated_count} notifications as read"}
            
        except Exception as e:
            logger.error(f"Exception in mark all notifications as read: {str(e)}")
            return {"error": "Internal server error"}, 500
