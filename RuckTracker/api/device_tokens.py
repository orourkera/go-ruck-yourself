"""
Device Token API endpoints for FCM push notifications
"""
import logging
from flask import request, g
from flask_restful import Resource

from RuckTracker.supabase_client import get_supabase_client
from RuckTracker.auth.decorators import token_required
from RuckTracker.utils.api_response import build_api_response

logger = logging.getLogger(__name__)


class DeviceTokenResource(Resource):
    """Resource for managing user device tokens"""
    
    @token_required
    def post(self):
        """Register or update a device token for push notifications"""
        try:
            data = request.get_json()
            
            if not data:
                return build_api_response(
                    success=False, 
                    error="Request body is required", 
                    status_code=400
                )
            
            # Validate required fields
            fcm_token = data.get('fcm_token')
            if not fcm_token:
                return build_api_response(
                    success=False, 
                    error="fcm_token is required", 
                    status_code=400
                )
            
            # Optional fields
            device_id = data.get('device_id')
            device_type = data.get('device_type')  # 'ios' or 'android'
            app_version = data.get('app_version')
            
            # Get user from token
            user_id = g.user_id
            supabase = get_supabase_client()
            
            # Use the upsert function to insert or update the token
            result = supabase.rpc('upsert_device_token', {
                'p_user_id': user_id,
                'p_fcm_token': fcm_token,
                'p_device_id': device_id,
                'p_device_type': device_type,
                'p_app_version': app_version
            }).execute()
            
            if result.error:
                logger.error(f"Error upserting device token: {result.error}")
                return build_api_response(
                    success=False, 
                    error="Failed to register device token", 
                    status_code=500
                )
            
            logger.info(f"Device token registered for user {user_id}")
            
            return build_api_response(
                success=True,
                message="Device token registered successfully",
                data={'token_id': result.data},
                status_code=200
            )
            
        except Exception as e:
            logger.error(f"Error in DeviceTokenResource POST: {e}", exc_info=True)
            return build_api_response(
                success=False, 
                error="Internal server error", 
                status_code=500
            )
    
    @token_required
    def delete(self):
        """Deactivate device tokens for the current user"""
        try:
            data = request.get_json() or {}
            user_id = g.user_id
            supabase = get_supabase_client()
            
            # If specific token or device_id provided, deactivate only that
            fcm_token = data.get('fcm_token')
            device_id = data.get('device_id')
            
            query = supabase.table('user_device_tokens') \
                .update({'is_active': False}) \
                .eq('user_id', user_id)
            
            if fcm_token:
                query = query.eq('fcm_token', fcm_token)
            elif device_id:
                query = query.eq('device_id', device_id)
            
            result = query.execute()
            
            if result.error:
                logger.error(f"Error deactivating device token: {result.error}")
                return build_api_response(
                    success=False, 
                    error="Failed to deactivate device token", 
                    status_code=500
                )
            
            logger.info(f"Device token(s) deactivated for user {user_id}")
            
            return build_api_response(
                success=True,
                message="Device token deactivated successfully",
                status_code=200
            )
            
        except Exception as e:
            logger.error(f"Error in DeviceTokenResource DELETE: {e}", exc_info=True)
            return build_api_response(
                success=False, 
                error="Internal server error", 
                status_code=500
            )
