"""
App Update Notification API endpoints
"""
import logging
from flask import request
from flask_restful import Resource

from ..services.push_notification_service import PushNotificationService
from ..supabase_client import get_supabase_admin_client
from ..utils.api_response import build_api_response

logger = logging.getLogger(__name__)

class AppUpdateNotificationResource(Resource):
    """Resource for sending app update push notifications"""
    
    def post(self):
        """Send app update notification to users"""
        try:
            data = request.get_json() or {}
            
            # Parameters
            platform = data.get('platform', 'ios').lower()  # Default to iOS
            version = data.get('version', '3.5.1')
            is_critical = data.get('is_critical', True)
            test_mode = data.get('test_mode', False)  # For testing with limited users
            specific_tokens = data.get('device_tokens', [])  # For testing with specific tokens
            
            logger.info(f"🔔 App update notification request: platform={platform}, version={version}, critical={is_critical}, test={test_mode}, specific_tokens={len(specific_tokens)}")
            
            # Get device tokens
            if specific_tokens:
                # Use provided device tokens directly
                device_tokens = specific_tokens
                logger.info(f"🎯 Using {len(specific_tokens)} specific device tokens provided")
            else:
                # Get device tokens for specified platform
                device_tokens = self._get_device_tokens(platform, test_mode)
            
            if not device_tokens:
                return build_api_response(
                    success=False,
                    error=f"No active {platform} device tokens found",
                    status_code=404
                )
            
            # Initialize push service and send notifications
            push_service = PushNotificationService()
            success = push_service.send_app_update_notification(
                device_tokens=device_tokens,
                version=version,
                is_critical=is_critical
            )
            
            if success:
                return build_api_response(
                    success=True,
                    data={
                        'message': f'Successfully sent app update notifications to {len(device_tokens)} {platform} devices',
                        'platform': platform,
                        'version': version,
                        'is_critical': is_critical,
                        'devices_notified': len(device_tokens)
                    }
                )
            else:
                return build_api_response(
                    success=False,
                    error="Failed to send some app update notifications",
                    status_code=500
                )
                
        except Exception as e:
            logger.error(f"Error sending app update notifications: {e}")
            return build_api_response(
                success=False,
                error=f"Internal server error: {str(e)}",
                status_code=500
            )
    
    def _get_device_tokens(self, platform: str, test_mode: bool = False):
        """Get device tokens for specified platform"""
        try:
            supabase = get_supabase_admin_client()
            
            # Base query for active device tokens
            query = supabase.table('user_device_tokens') \
                .select('token, user_id, platform, device_model') \
                .eq('platform', platform) \
                .eq('is_active', True)
            
            # In test mode, limit to fewer devices
            if test_mode:
                query = query.limit(10)
                logger.info(f"🧪 Test mode: limiting to 10 {platform} devices")
            
            result = query.execute()
            
            if result.data:
                tokens = [row['token'] for row in result.data if row.get('token')]
                logger.info(f"📱 Found {len(tokens)} active {platform} device tokens")
                return tokens
            else:
                logger.warning(f"No {platform} device tokens found")
                return []
                
        except Exception as e:
            logger.error(f"Error fetching {platform} device tokens: {e}")
            return []