"""
Test notification endpoint for debugging push notification issues
"""
from flask import g, request
from flask_restful import Resource
from ..services.push_notification_service import PushNotificationService, get_user_device_tokens
from ..supabase_client import get_supabase_admin_client
import logging

logger = logging.getLogger(__name__)

class TestNotificationResource(Resource):
    """Resource for sending test notifications"""
    
    def post(self):
        """Send a test notification to the current user"""
        try:
            # Get user ID from auth header
            auth_header = request.headers.get('Authorization', '')
            if not auth_header.startswith('Bearer '):
                return {"error": "Authorization header required"}, 401
                
            token = auth_header.split(' ')[1]
            
            # Verify token with Supabase
            from ..supabase_client import get_supabase_client
            supabase = get_supabase_client()
            
            try:
                user_response = supabase.auth.get_user(token)
                if not user_response.user:
                    return {"error": "Invalid token"}, 401
                user_id = user_response.user.id
            except Exception as e:
                logger.error(f"Token verification failed: {e}")
                return {"error": "Invalid token"}, 401
            
            logger.info(f"🧪 TEST NOTIFICATION REQUEST for user {user_id}")
            
            # Get device tokens for this user
            device_tokens = get_user_device_tokens([user_id])
            
            if not device_tokens:
                logger.error(f"❌ No device tokens found for user {user_id}")
                return {
                    "error": "No device tokens found", 
                    "message": "Make sure the app has registered device tokens"
                }, 400
            
            logger.info(f"🎯 Found {len(device_tokens)} device tokens for user {user_id}")
            
            # Log token details for debugging
            for i, token in enumerate(device_tokens):
                token_length = len(token)
                token_preview = f"{token[:10]}...{token[-10:]}" if len(token) > 20 else token
                logger.info(f"   Token {i+1}: Length={token_length}, Preview={token_preview}")
                
                # Try to identify iOS vs Android tokens
                if token_length > 100:
                    logger.info(f"   → Likely iOS token (length: {token_length})")
                else:
                    logger.info(f"   → Likely Android token (length: {token_length})")
            
            # Send test notification
            push_service = PushNotificationService()
            
            success = push_service.send_notification(
                device_tokens=device_tokens,
                title="🧪 Test Notification",
                body="This is a test notification from your profile!",
                notification_data={
                    "type": "test",
                    "test_id": "profile_test",
                    "click_action": "FLUTTER_NOTIFICATION_CLICK"
                }
            )
            
            if success:
                return {
                    "success": True,
                    "message": f"Test notification sent to {len(device_tokens)} devices",
                    "device_count": len(device_tokens),
                    "tokens_sent": len(device_tokens)
                }
            else:
                return {
                    "error": "Failed to send notifications", 
                    "message": "Check server logs for details"
                }, 500
                
        except Exception as e:
            logger.error(f"❌ Test notification failed: {e}", exc_info=True)
            return {"error": f"Server error: {str(e)}"}, 500
