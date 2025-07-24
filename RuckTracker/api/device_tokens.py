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

            # NEW STRATEGY: Deactivate all existing tokens for this user/device_type, then insert new one
            # This prevents duplication and ensures clean state
            try:
                # Step 1: Deactivate all existing active tokens for this user and device type
                logger.info(f"Deactivating existing tokens for user {user_id}, device_type {device_type}")
                deactivate_result = supabase.table('user_device_tokens').update({
                    'is_active': False,
                    'updated_at': 'now()'
                }).eq('user_id', user_id).eq('device_type', device_type).eq('is_active', True).execute()
                
                deactivated_count = len(deactivate_result.data) if deactivate_result.data else 0
                logger.info(f"Deactivated {deactivated_count} existing tokens for user {user_id}")
                
                # Step 2: Insert new active token
                try:
                    insert_result = supabase.table('user_device_tokens').insert({
                        'user_id': user_id,
                        'fcm_token': fcm_token,
                        'device_id': device_id,
                        'device_type': device_type,
                        'app_version': app_version,
                        'is_active': True
                    }).execute()
                    
                    if insert_result.data and len(insert_result.data) > 0:
                        result_data = {'token_id': str(insert_result.data[0]['id'])}
                        if deactivated_count > 0:
                            logger.info(f"Replaced {deactivated_count} old tokens with new token for user {user_id}")
                        else:
                            logger.info(f"Registered first device token for user {user_id}")
                    else:
                        logger.error(f"Insert succeeded but no data returned for user {user_id}")
                        return build_api_response(
                            success=False, 
                            error="Failed to register device token - no data returned", 
                            status_code=500
                        )
                        
                except Exception as e:
                    logger.error(f"Error inserting new device token for user {user_id}: {e}")
                    return build_api_response(
                        success=False, 
                        error="Failed to register device token", 
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
