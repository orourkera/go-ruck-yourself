from flask import request, g
from flask_restful import Resource
from datetime import datetime
import json
import logging
from .resources import get_supabase, require_auth, get_user_id

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class NotificationsResource(Resource):
    """
    Resource for handling notifications
    GET: Fetch all notifications for the current user
    """
    
    @require_auth
    def get(self):
        """Get all notifications for the current user"""
        try:
            user_id = get_user_id()
            supabase = get_supabase()
            
            # Parse pagination parameters
            page = int(request.args.get('page', 1))
            per_page = int(request.args.get('per_page', 20))
            offset = (page - 1) * per_page
            
            # Query notifications for this user, ordered by creation date (newest first)
            response = supabase.table('notifications') \
                .select('*') \
                .eq('recipient_id', user_id) \
                .order('created_at', desc=True) \
                .limit(per_page) \
                .offset(offset) \
                .execute()
            
            # Check if we have more notifications beyond this page
            total_count_response = supabase.table('notifications') \
                .select('id', count='exact') \
                .eq('recipient_id', user_id) \
                .execute()
            
            total_count = total_count_response.count if hasattr(total_count_response, 'count') else len(response.data)
            has_more = total_count > (offset + len(response.data))
            
            return {
                'notifications': response.data,
                'pagination': {
                    'page': page,
                    'per_page': per_page,
                    'total': total_count,
                    'has_more': has_more
                }
            }
            
        except Exception as e:
            logger.error(f"Error fetching notifications: {str(e)}")
            return {'error': 'Failed to fetch notifications', 'details': str(e)}, 500


class NotificationReadResource(Resource):
    """
    Resource for marking a specific notification as read
    PUT: Mark a notification as read
    """
    
    @require_auth
    def put(self, notification_id):
        """Mark a specific notification as read"""
        try:
            user_id = get_user_id()
            supabase = get_supabase()
            
            # Verify the notification belongs to this user before updating
            notification = supabase.table('notifications') \
                .select('*') \
                .eq('id', notification_id) \
                .eq('recipient_id', user_id) \
                .execute()
            
            if not notification.data:
                return {'error': 'Notification not found or does not belong to the current user'}, 404
            
            # Update the notification
            result = supabase.table('notifications') \
                .update({'is_read': True, 'read_at': datetime.utcnow().isoformat()}) \
                .eq('id', notification_id) \
                .eq('recipient_id', user_id) \
                .execute()
            
            return {'success': True, 'notification': result.data[0] if result.data else None}
            
        except Exception as e:
            logger.error(f"Error marking notification as read: {str(e)}")
            return {'error': 'Failed to mark notification as read', 'details': str(e)}, 500


class ReadAllNotificationsResource(Resource):
    """
    Resource for marking all notifications for a user as read
    PUT: Mark all notifications as read
    """
    
    @require_auth
    def put(self):
        """Mark all notifications for the current user as read"""
        try:
            user_id = get_user_id()
            supabase = get_supabase()
            
            # Update all unread notifications for this user
            result = supabase.table('notifications') \
                .update({'is_read': True, 'read_at': datetime.utcnow().isoformat()}) \
                .eq('recipient_id', user_id) \
                .eq('is_read', False) \
                .execute()
            
            # Get the count of affected notifications
            affected_count = len(result.data) if result.data else 0
            
            return {
                'success': True,
                'count': affected_count,
                'message': f'{affected_count} notifications marked as read'
            }
            
        except Exception as e:
            logger.error(f"Error marking all notifications as read: {str(e)}")
            return {'error': 'Failed to mark all notifications as read', 'details': str(e)}, 500
