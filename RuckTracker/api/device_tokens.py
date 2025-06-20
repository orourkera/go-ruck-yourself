"""
Device Token API endpoints for FCM push notifications
"""
import logging
from flask import request, g
from flask_restful import Resource

from RuckTracker.supabase_client import get_supabase_admin_client
from RuckTracker.api.auth import auth_required
from RuckTracker.utils.api_response import build_api_response

logger = logging.getLogger(__name__)


class DeviceTokenResource(Resource):
    """Resource for managing user device tokens"""
    
    @auth_required
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
            supabase = get_supabase_admin_client()

            # First, try to find and update existing token
            try:
                # Look for existing token for this user
                existing_query = supabase.table('user_device_tokens').select('id')
                
                if device_id:
                    # Try to find by device_id first
                    existing_query = existing_query.eq('user_id', user_id).eq('device_id', device_id)
                else:
                    # Fallback to FCM token
                    existing_query = existing_query.eq('user_id', user_id).eq('fcm_token', fcm_token)
                
                existing_result = existing_query.execute()
                
                if existing_result.data and len(existing_result.data) > 0:
                    # Update existing token
                    token_id = existing_result.data[0]['id']
                    update_result = supabase.table('user_device_tokens').update({
                        'fcm_token': fcm_token,
                        'device_id': device_id,
                        'device_type': device_type,
                        'app_version': app_version,
                        'is_active': True,
                        'updated_at': 'now()'
                    }).eq('id', token_id).execute()
                    
                    if update_result.error:
                        logger.error(f"Error updating device token: {update_result.error}")
                        return build_api_response(
                            success=False, 
                            error="Failed to update device token", 
                            status_code=500
                        )
                    
                    logger.info(f"Device token updated for user {user_id}")
                    result_data = {'token_id': str(token_id)}
                else:
                    # Insert new token
                    insert_result = supabase.table('user_device_tokens').insert({
                        'user_id': user_id,
                        'fcm_token': fcm_token,
                        'device_id': device_id,
                        'device_type': device_type,
                        'app_version': app_version,
                        'is_active': True
                    }).execute()
                    
                    if insert_result.error:
                        logger.error(f"Error inserting device token: {insert_result.error}")
                        return build_api_response(
                            success=False, 
                            error="Failed to register device token", 
                            status_code=500
                        )
                    
                    logger.info(f"New device token registered for user {user_id}")
                    result_data = {'token_id': str(insert_result.data[0]['id']) if insert_result.data else None}
                
                return build_api_response(
                    success=True,
                    message="Device token registered successfully",
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
    
    @auth_required
    def delete(self):
        """Deactivate device tokens for the current user"""
        try:
            data = request.get_json() or {}
            user_id = g.user_id
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
