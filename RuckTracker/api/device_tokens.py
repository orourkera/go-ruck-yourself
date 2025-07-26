"""
Device Token API endpoints for FCM push notifications
"""
import logging
from flask import request, g
from flask_restful import Resource

from RuckTracker.supabase_client import get_supabase_admin_client
from RuckTracker.utils.auth_helper import get_current_user_id
from RuckTracker.utils.api_response import build_api_response, check_auth_and_respond

logger = logging.getLogger(__name__)


class DeviceTokenResource(Resource):
    """Resource for managing user device tokens"""
    
    def post(self):
        """Register or update a device token for push notifications"""
        try:
            # Check authentication
            user_id = get_current_user_id()
            auth_response = check_auth_and_respond(user_id)
            if auth_response:
                return auth_response
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
            
            # Get supabase client
            supabase = get_supabase_admin_client()

            # UPSERT STRATEGY: Use Supabase upsert to handle duplicate device tokens gracefully
            try:
                # Prepare token data
                token_data = {
                    'user_id': user_id,
                    'fcm_token': fcm_token,
                    'device_id': device_id,
                    'device_type': device_type,
                    'app_version': app_version,
                    'is_active': True,
                    'updated_at': 'now()'
                }
                
                # Use upsert to insert or update if exists
                # On conflict with (user_id, device_id), update the existing record
                upsert_result = supabase.table('user_device_tokens').upsert(
                    token_data,
                    on_conflict='user_id,device_id'  # Specify the unique constraint columns
                ).execute()
                
                if upsert_result.data and len(upsert_result.data) > 0:
                    token_record = upsert_result.data[0]
                    result_data = {'token_id': str(token_record['id'])}
                    logger.info(f"Successfully upserted device token for user {user_id}, device {device_id}")
                else:
                    logger.error(f"Upsert succeeded but no data returned for user {user_id}")
                    return build_api_response(
                        success=False, 
                        error="Failed to register device token - no data returned", 
                        status_code=500
                    )
                    
                # Return success response
                return build_api_response(
                    success=True,
                    data=result_data,
                    status_code=200
                )
                
            except Exception as db_error:
                logger.error(f"Database error in device token registration: {db_error}")
                return build_api_response(
                    success=False, 
                    error="Failed to register device token", 
                    status_code=500
                )
            
        except Exception as e:
            logger.error(f"Error in DeviceTokenResource POST: {e}", exc_info=True)
            return build_api_response(
                success=False, 
                error="Internal server error", 
                status_code=500
            )
    
    def delete(self):
        """Deactivate device tokens for the current user"""
        try:
            # Check authentication
            user_id = get_current_user_id()
            auth_response = check_auth_and_respond(user_id)
            if auth_response:
                return auth_response
                
            data = request.get_json() or {}
            supabase = get_supabase_admin_client()
            
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
            
            try:
                query.execute()
            except Exception as e:
                logger.error(f"Error deactivating device token: {e}")
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
