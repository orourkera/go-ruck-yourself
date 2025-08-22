# /Users/rory/RuckingApp/RuckTracker/api/ruck_likes_resource.py
from flask import request, g
from flask_restful import Resource
import logging
from RuckTracker.supabase_client import get_supabase_client
from RuckTracker.utils.api_response import build_api_response
from RuckTracker.api.auth import auth_required
from RuckTracker.services.push_notification_service import PushNotificationService, get_user_device_tokens
from RuckTracker.services.redis_cache_service import cache_get, cache_set
import time

logger = logging.getLogger(__name__)

# Initialize push notification service
push_service = PushNotificationService()

class RuckLikesResource(Resource):
    @auth_required
    def get(self):
        """
        Get likes for a specific ruck session.
        
        Endpoints:
        - /api/ruck-likes?ruck_id=<ruck_id> - Get all likes for a ruck session
        - /api/ruck-likes/check?ruck_id=<ruck_id> - Check if current user has liked a ruck
        
        The user must be authenticated.
        """
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            logger.warning("RuckLikesResource: Missing or invalid Authorization header.")
            return build_api_response(success=False, error="Unauthorized", status_code=401)
        
        token = auth_header.split("Bearer ")[1]

        # Initialize Supabase client with the user's token to respect RLS
        try:
            supabase = get_supabase_client(user_jwt=token)
            user_response = supabase.auth.get_user(token)
            if not user_response.user:
                logger.warning("RuckLikesResource: Invalid token or user not found.")
                return build_api_response(success=False, error="Invalid token or user not found.", status_code=401)
            
            user_id = user_response.user.id
            logger.debug(f"RuckLikesResource: Authenticated user {user_id}")
        except Exception as e:
            logger.error(f"RuckLikesResource: Error during Supabase client initialization or user auth: {e}")
            return build_api_response(success=False, error="Authentication error.", status_code=500)

        # Check if this is a like status check request
        path_info = request.path
        is_check_endpoint = '/api/ruck-likes/check' in path_info
        
        logger.debug(f"RuckLikesResource: Path info: {path_info}, is_check_endpoint: {is_check_endpoint}")
        
        # Also check the route rule to be more reliable
        if hasattr(request, 'url_rule') and request.url_rule:
            endpoint_path = request.url_rule.rule
            is_check_endpoint = is_check_endpoint or '/check' in endpoint_path
            logger.debug(f"RuckLikesResource: URL rule: {endpoint_path}, is_check_endpoint: {is_check_endpoint}")
        
        # Get ruck_id from query parameters
        ruck_id_str = request.args.get('ruck_id')
        if not ruck_id_str:
            logger.info("RuckLikesResource: Missing ruck_id query parameter.")
            return build_api_response(success=False, error="Missing ruck_id query parameter", status_code=400)
        
        try:
            ruck_id = int(ruck_id_str)
        except ValueError:
            logger.info(f"RuckLikesResource: Invalid ruck_id format: {ruck_id_str}")
            return build_api_response(success=False, error="Invalid ruck_id format, must be an integer.", status_code=400)

        # If this is a check endpoint, check if user has liked the ruck
        if is_check_endpoint:
            try:
                query_result = supabase.table('ruck_likes') \
                                     .select('id') \
                                     .eq('ruck_id', ruck_id) \
                                     .eq('user_id', user_id) \
                                     .execute()
                
                has_liked = len(query_result.data) > 0
                
                return build_api_response(
                    data={'has_liked': has_liked},
                    status_code=200
                )
            except Exception as e:
                logger.error(f"RuckLikesResource: Error checking like status: {e}")
                return build_api_response(success=False, error="Failed to check like status", status_code=500)
        
        # Otherwise, get all likes for the ruck
        try:
            query_result = supabase.table('ruck_likes') \
                                 .select('id, ruck_id, user_id, user_display_name, user_avatar_url, created_at') \
                                 .eq('ruck_id', ruck_id) \
                                 .order('created_at', desc=True) \
                                 .execute()
            
            if hasattr(query_result, 'error') and query_result.error:
                logger.error(f"RuckLikesResource: Supabase query error: {query_result.error}")
                return build_api_response(success=False, error="Failed to fetch likes from database.", status_code=500)

            return build_api_response(data=query_result.data, status_code=200)
            
        except Exception as e:
            logger.error(f"RuckLikesResource: Error fetching ruck likes: {e}", exc_info=True)
            return build_api_response(success=False, error="An error occurred while fetching likes.", status_code=500)
    
    @auth_required
    def post(self):
        """
        Add a like to a ruck session.
        
        Expects 'ruck_id' in JSON body.
        The user must be authenticated.
        """
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            logger.warning("RuckLikesResource: Missing or invalid Authorization header.")
            return build_api_response(success=False, error="Unauthorized", status_code=401)
        
        token = auth_header.split("Bearer ")[1]

        # Initialize Supabase client with the user's token to respect RLS
        try:
            supabase = get_supabase_client(user_jwt=token)
            user_response = supabase.auth.get_user(token)
            if not user_response.user:
                logger.warning("RuckLikesResource: Invalid token or user not found.")
                return build_api_response(success=False, error="Invalid token or user not found.", status_code=401)
            
            user_id = user_response.user.id
            user_email = user_response.user.email
            user_display_name = user_email.split('@')[0] if user_email else 'Anonymous'
            
            logger.debug(f"RuckLikesResource: Authenticated user {user_id}")
        except Exception as e:
            logger.error(f"RuckLikesResource: Error during Supabase client initialization or user auth: {e}")
            return build_api_response(success=False, error="Authentication error.", status_code=500)

        # Get request data
        request_data = request.get_json()
        if not request_data:
            logger.info("RuckLikesResource: Missing request body.")
            return build_api_response(success=False, error="Missing request body", status_code=400)
        
        ruck_id = request_data.get('ruck_id')
        if ruck_id is None:
            logger.info("RuckLikesResource: Missing ruck_id in request body.")
            return build_api_response(success=False, error="Missing ruck_id in request body", status_code=400)
        
        try:
            ruck_id = int(ruck_id)
        except (ValueError, TypeError):
            logger.info(f"RuckLikesResource: Invalid ruck_id format: {ruck_id}")
            return build_api_response(success=False, error="Invalid ruck_id format, must be an integer.", status_code=400)
            
        start_time = time.time()

        # Check if the ruck exists
        try:
            ruck_query = supabase.table('ruck_session') \
                                 .select('id') \
                                 .eq('id', ruck_id) \
                                 .execute()
            
            if not ruck_query.data:
                logger.info(f"RuckLikesResource: Ruck session with ID {ruck_id} not found.")
                return build_api_response(success=False, error=f"Ruck session with ID {ruck_id} not found.", status_code=404)
        except Exception as e:
            logger.error(f"RuckLikesResource: Error verifying ruck session: {e}")
            return build_api_response(success=False, error="Error verifying ruck session", status_code=500)

        logger.info(f"[LIKE_PERF] Ruck exists check took {(time.time() - start_time)*1000:.2f}ms")
        check_time = time.time()

        # Check if the user has already liked this ruck
        try:
            existing_like = supabase.table('ruck_likes') \
                                   .select('id') \
                                   .eq('ruck_id', ruck_id) \
                                   .eq('user_id', user_id) \
                                   .execute()
            
            if existing_like.data:
                logger.info(f"RuckLikesResource: User {user_id} has already liked ruck {ruck_id}.")
                return build_api_response(
                    data=existing_like.data[0],
                    status_code=200,
                    error="You've already liked this ruck session."
                )
        except Exception as e:
            logger.error(f"RuckLikesResource: Error checking existing like: {e}")
            return build_api_response(success=False, error="Error checking existing like", status_code=500)

        logger.info(f"[LIKE_PERF] Existing like check took {(time.time() - check_time)*1000:.2f}ms")
        insert_start = time.time()

        # Add the like
        try:
            # Simplified approach: don't query user table for profile info
            # Just use the user ID which is all we really need
            
            # Insert the like with minimal required data
            like_data = {
                'ruck_id': ruck_id,
                'user_id': user_id,
                # Use fallback values for display info
                'user_display_name': 'Rucker', # Generic fallback name
                'user_avatar_url': None        # No avatar fallback
            }
            
            insert_response = supabase.table('ruck_likes').insert(like_data).execute()
            
            if hasattr(insert_response, 'error') and insert_response.error:
                logger.error(f"RuckLikesResource: Error adding like: {insert_response.error}")
                return build_api_response(success=False, error="Failed to add like", status_code=500)
            
            # Send push notification to ruck owner
            try:
                logger.info(f"🔔 PUSH NOTIFICATION: Starting ruck like push notification for ruck {ruck_id}")
                
                # Get ruck owner info
                ruck_response = supabase.table('ruck_session') \
                    .select('user_id') \
                    .eq('id', ruck_id) \
                    .execute()
                
                logger.info(f"🔔 PUSH NOTIFICATION: Ruck owner query result: {ruck_response.data}")
                
                if ruck_response.data and ruck_response.data[0]['user_id'] != user_id:
                    ruck_owner_id = ruck_response.data[0]['user_id']
                    
                    # Get liker display name
                    user_response = supabase.table('user') \
                        .select('username') \
                        .eq('id', user_id) \
                        .execute()
                    
                    liker_name = user_response.data[0]['username'] if user_response.data else 'Someone'
                    
                    logger.info(f"🔔 PUSH NOTIFICATION: Sending to ruck owner {ruck_owner_id}, from liker {liker_name}")
                    
                    # Send push notification
                    logger.info(f"🔔 PUSH NOTIFICATION: Using global push service")
                    cache_key = f'user_device_tokens:{ruck_owner_id}'
                    cached_tokens = cache_get(cache_key)
                    if cached_tokens:
                        device_tokens = cached_tokens
                        logger.info(f"[LIKE_PERF] Using cached device tokens for {ruck_owner_id}")
                    else:
                        device_tokens = get_user_device_tokens([ruck_owner_id])
                        cache_set(cache_key, device_tokens, 3600)
                    
                    logger.info(f"🔔 PUSH NOTIFICATION: Retrieved {len(device_tokens)} device tokens: {device_tokens}")
                    
                    if device_tokens:
                        logger.info(f"🔔 PUSH NOTIFICATION: Calling send_ruck_like_notification...")
                        result = push_service.send_ruck_like_notification(
                            device_tokens=device_tokens,
                            liker_name=liker_name,
                            ruck_id=ruck_id
                        )
                        logger.info(f"🔔 PUSH NOTIFICATION: Like notification sent successfully, result: {result}")

                    # Notify other prior participants (commenters and likers) except owner and current liker
                    try:
                        prior_participants = set()
                        # prior commenters
                        prev_comments = supabase.table('ruck_comments') \
                            .select('user_id') \
                            .eq('ruck_id', ruck_id) \
                            .neq('user_id', user_id) \
                            .order('created_at', desc=True) \
                            .limit(100) \
                            .execute()
                        if prev_comments.data:
                            for c in prev_comments.data:
                                if c['user_id'] != ruck_owner_id:
                                    prior_participants.add(c['user_id'])

                        # prior likers
                        prev_likes = supabase.table('ruck_likes') \
                            .select('user_id') \
                            .eq('ruck_id', ruck_id) \
                            .neq('user_id', user_id) \
                            .order('created_at', desc=True) \
                            .limit(200) \
                            .execute()
                        if prev_likes.data:
                            for l in prev_likes.data:
                                if l['user_id'] != ruck_owner_id:
                                    prior_participants.add(l['user_id'])

                        if prior_participants:
                            logger.info(f"🔔 PUSH NOTIFICATION: Notifying {len(prior_participants)} prior participants of like activity")
                            tokens_pp = get_user_device_tokens(list(prior_participants))
                            if tokens_pp:
                                push_service.send_ruck_participant_activity_notification(
                                    device_tokens=tokens_pp,
                                    actor_name=liker_name,
                                    ruck_id=str(ruck_id),
                                    activity_type='like'
                                )
                    except Exception as e:
                        logger.error(f"🔔 PUSH NOTIFICATION: Failed notifying prior participants: {e}")
                    else:
                        logger.warning(f"🔔 PUSH NOTIFICATION: No device tokens found for user {ruck_owner_id}")
                else:
                    logger.info(f"🔔 PUSH NOTIFICATION: Skipping notification (same user or no ruck owner found)")
                        
            except Exception as e:
                logger.error(f"🔔 PUSH NOTIFICATION: Failed to send like notification: {e}", exc_info=True)
                # Don't fail the like if notification fails
            
            # Return the created like
            return build_api_response(data=insert_response.data[0], status_code=201)
            
        except Exception as e:
            logger.error(f"RuckLikesResource: Error adding like: {e}", exc_info=True)
            return build_api_response(success=False, error="An error occurred while adding like.", status_code=500)

        logger.info(f"[LIKE_PERF] Like insert took {(time.time() - insert_start)*1000:.2f}ms")
        notif_start = time.time()

        logger.info(f"[LIKE_PERF] Notification section took {(time.time() - notif_start)*1000:.2f}ms")
        total_time = time.time() - start_time
        logger.info(f"[LIKE_PERF] Total like request took {total_time*1000:.2f}ms")
    
    @auth_required
    def delete(self):
        """
        Remove a like from a ruck session.
        
        Expects 'ruck_id' as a query parameter.
        The user must be authenticated and must be the one who added the like.
        """
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            logger.warning("RuckLikesResource: Missing or invalid Authorization header.")
            return build_api_response(success=False, error="Unauthorized", status_code=401)
        
        token = auth_header.split("Bearer ")[1]

        # Initialize Supabase client with the user's token to respect RLS
        try:
            supabase = get_supabase_client(user_jwt=token)
            user_response = supabase.auth.get_user(token)
            if not user_response.user:
                logger.warning("RuckLikesResource: Invalid token or user not found.")
                return build_api_response(success=False, error="Invalid token or user not found.", status_code=401)
            
            user_id = user_response.user.id
            logger.debug(f"RuckLikesResource: Authenticated user {user_id}")
        except Exception as e:
            logger.error(f"RuckLikesResource: Error during Supabase client initialization or user auth: {e}")
            return build_api_response(success=False, error="Authentication error.", status_code=500)

        # Get ruck_id from query parameters
        ruck_id_str = request.args.get('ruck_id')
        if not ruck_id_str:
            logger.info("RuckLikesResource: Missing ruck_id query parameter.")
            return build_api_response(success=False, error="Missing ruck_id query parameter", status_code=400)
        
        try:
            ruck_id = int(ruck_id_str)
        except ValueError:
            logger.info(f"RuckLikesResource: Invalid ruck_id format: {ruck_id_str}")
            return build_api_response(success=False, error="Invalid ruck_id format, must be an integer.", status_code=400)
            
        # Check if the like exists
        try:
            like_query = supabase.table('ruck_likes') \
                               .select('id') \
                               .eq('ruck_id', ruck_id) \
                               .eq('user_id', user_id) \
                               .execute()
            
            if not like_query.data:
                logger.info(f"RuckLikesResource: Like not found for ruck {ruck_id} and user {user_id}.")
                return build_api_response(success=False, error="You haven't liked this ruck session.", status_code=404)
            
            like_id = like_query.data[0]['id']
        except Exception as e:
            logger.error(f"RuckLikesResource: Error finding like: {e}")
            return build_api_response(success=False, error="Error finding like", status_code=500)
            
        # Delete the like
        try:
            delete_response = supabase.table('ruck_likes') \
                                    .delete() \
                                    .eq('id', like_id) \
                                    .execute()
            
            if hasattr(delete_response, 'error') and delete_response.error:
                logger.error(f"RuckLikesResource: Error removing like: {delete_response.error}")
                return build_api_response(success=False, error="Failed to remove like", status_code=500)
            
            return build_api_response(
                data={'message': 'Like removed successfully', 'like_id': like_id},
                status_code=200
            )
            
        except Exception as e:
            logger.error(f"RuckLikesResource: Error removing like: {e}", exc_info=True)
            return build_api_response(success=False, error="An error occurred while removing like.", status_code=500)


class RuckLikesBatchResource(Resource):
    @auth_required
    def get(self):
        """
        Get social data (likes and comments) for multiple ruck sessions in a batch.
        
        Endpoint:
        - /api/ruck-likes/batch?ruck_ids=1,2,3 - Get likes/comments for multiple rucks
        
        The user must be authenticated.
        """
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            logger.warning("RuckLikesBatchResource: Missing or invalid Authorization header.")
            return build_api_response(success=False, error="Unauthorized", status_code=401)
        
        token = auth_header.split("Bearer ")[1]

        # Initialize Supabase client with the user's token to respect RLS
        try:
            supabase = get_supabase_client(user_jwt=token)
            user_response = supabase.auth.get_user(token)
            if not user_response.user:
                logger.warning("RuckLikesBatchResource: Invalid token or user not found.")
                return build_api_response(success=False, error="Invalid token or user not found.", status_code=401)
            
            user_id = user_response.user.id
            logger.debug(f"RuckLikesBatchResource: Authenticated user {user_id}")
        except Exception as e:
            logger.error(f"RuckLikesBatchResource: Error during Supabase client initialization or user auth: {e}")
            return build_api_response(success=False, error="Authentication error.", status_code=500)

        # Get ruck_ids from query parameters
        ruck_ids_str = request.args.get('ruck_ids')
        if not ruck_ids_str:
            logger.info("RuckLikesBatchResource: Missing ruck_ids query parameter.")
            return build_api_response(success=False, error="Missing ruck_ids query parameter", status_code=400)
        
        try:
            ruck_ids = [int(x.strip()) for x in ruck_ids_str.split(',') if x.strip()]
            if not ruck_ids:
                raise ValueError("No valid ruck IDs provided")
        except ValueError as e:
            logger.info(f"RuckLikesBatchResource: Invalid ruck_ids format: {ruck_ids_str}")
            return build_api_response(success=False, error="Invalid ruck_ids format, must be comma-separated integers.", status_code=400)

        # Limit batch size to prevent abuse
        if len(ruck_ids) > 50:
            logger.warning(f"RuckLikesBatchResource: Too many ruck IDs requested: {len(ruck_ids)}")
            return build_api_response(success=False, error="Too many ruck IDs requested, maximum 50 allowed.", status_code=400)

        try:
            # Get all likes for the requested rucks
            likes_response = supabase.table('ruck_likes') \
                                   .select('ruck_id, user_id, created_at') \
                                   .in_('ruck_id', ruck_ids) \
                                   .execute()
            
            # Get user's like status for each ruck
            user_likes_response = supabase.table('ruck_likes') \
                                        .select('ruck_id') \
                                        .in_('ruck_id', ruck_ids) \
                                        .eq('user_id', user_id) \
                                        .execute()
            
            # Get comment counts for each ruck
            comments_response = supabase.table('ruck_comments') \
                                      .select('ruck_id') \
                                      .in_('ruck_id', ruck_ids) \
                                      .execute()
            
            # Process the data
            user_liked_rucks = {item['ruck_id'] for item in user_likes_response.data}
            
            # Group likes by ruck_id
            likes_by_ruck = {}
            for like in likes_response.data:
                ruck_id = like['ruck_id']
                if ruck_id not in likes_by_ruck:
                    likes_by_ruck[ruck_id] = []
                likes_by_ruck[ruck_id].append(like)
            
            # Count comments by ruck_id
            comments_by_ruck = {}
            for comment in comments_response.data:
                ruck_id = comment['ruck_id']
                comments_by_ruck[ruck_id] = comments_by_ruck.get(ruck_id, 0) + 1
            
            # Build response data
            batch_data = {}
            for ruck_id in ruck_ids:
                likes = likes_by_ruck.get(ruck_id, [])
                batch_data[str(ruck_id)] = {
                    'likes': likes,
                    'likes_count': len(likes),
                    'comments_count': comments_by_ruck.get(ruck_id, 0),
                    'user_has_liked': ruck_id in user_liked_rucks
                }
            
            return build_api_response(
                data=batch_data,
                status_code=200
            )
            
        except Exception as e:
            logger.error(f"RuckLikesBatchResource: Error fetching batch data: {e}", exc_info=True)
            return build_api_response(success=False, error="An error occurred while fetching batch data.", status_code=500)
