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
            
            # Query notifications from Supabase
            response = supabase_client.table('notifications').select('*').eq('recipient_id', user_id).order('data->>created_at', desc=True).execute()
            
            if hasattr(response, 'error') and response.error:
                logger.error(f"Error fetching notifications: {response.error}")
                return {"error": "Failed to fetch notifications"}, 500
                
            notifications = response.data
            
            # Format the response
            return jsonify({
                "notifications": notifications,
                "count": len(notifications)
            })
            
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
                
            # Update all notifications for this user in Supabase
            response = supabase_client.table('notifications').update({"is_read": True}).eq('recipient_id', user_id).execute()
            
            if hasattr(response, 'error') and response.error:
                logger.error(f"Error marking all notifications as read: {response.error}")
                return {"error": "Failed to mark all notifications as read"}, 500
            
            return {"success": True, "message": "All notifications marked as read"}
            
        except Exception as e:
            logger.error(f"Exception in mark all notifications as read: {str(e)}")
            return {"error": "Internal server error"}, 500
