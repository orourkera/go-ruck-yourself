# /Users/rory/RuckingApp/RuckTracker/api/ruck_comments_resource.py
from flask import request, g
from flask_restful import Resource
import logging
from RuckTracker.supabase_client import get_supabase_client
from RuckTracker.utils.api_response import build_api_response
from RuckTracker.api.auth import auth_required
from RuckTracker.services.push_notification_service import PushNotificationService, get_user_device_tokens

logger = logging.getLogger(__name__)

class RuckCommentsResource(Resource):
    @auth_required
    def get(self, ruck_id):
        """
        Get comments for a specific ruck session.
        
        Expects 'ruck_id' from the URL path.
        The user must be authenticated.
        """
        # Initialize Supabase client with the user's token to respect RLS
        try:
            supabase = get_supabase_client(user_jwt=g.access_token)
            user_response = supabase.auth.get_user(g.access_token)
            if not user_response.user:
                logger.warning("RuckCommentsResource: Invalid token or user not found.")
                return build_api_response(success=False, error="Invalid token or user not found.", status_code=401)
            
            user_id = user_response.user.id
            logger.debug(f"RuckCommentsResource: Authenticated user {user_id}")
        except Exception as e:
            logger.error(f"RuckCommentsResource: Error during Supabase client initialization or user auth: {str(e)}")
            logger.error(f"RuckCommentsResource: Token length: {len(g.access_token) if g.access_token else 'None'}")
            return build_api_response(success=False, error="Authentication error.", status_code=500)

        # Get comments for the ruck
        try:
            query_result = supabase.table('ruck_comments') \
                                 .select('id, ruck_id, user_id, user_display_name, user_avatar_url, content, created_at, updated_at') \
                                 .eq('ruck_id', ruck_id) \
                                 .order('created_at', desc=True) \
                                 .execute()
            
            if hasattr(query_result, 'error') and query_result.error:
                logger.error(f"RuckCommentsResource: Supabase query error: {query_result.error}")
                return build_api_response(success=False, error="Failed to fetch comments from database.", status_code=500)

            return build_api_response(data=query_result.data, status_code=200)
            
        except Exception as e:
            logger.error(f"RuckCommentsResource: Error fetching ruck comments: {e}", exc_info=True)
            return build_api_response(success=False, error="An error occurred while fetching comments.", status_code=500)
    
    @auth_required
    def post(self, ruck_id):
        """
        Add a comment to a ruck session.
        
        Expects 'ruck_id' from the URL path and JSON body with 'content'.
        The user must be authenticated.
        """
        # Initialize Supabase client with the user's token to respect RLS
        try:
            supabase = get_supabase_client(user_jwt=g.access_token)
            user_response = supabase.auth.get_user(g.access_token)
            if not user_response.user:
                logger.warning("RuckCommentsResource: Invalid token or user not found.")
                return build_api_response(success=False, error="Invalid token or user not found.", status_code=401)
            
            user_id = user_response.user.id
            user_email = user_response.user.email
            logger.debug(f"RuckCommentsResource: Authenticated user {user_id} ({user_email})")
        except Exception as e:
            logger.error(f"RuckCommentsResource: Error during Supabase client initialization or user auth: {str(e)}")
            logger.error(f"RuckCommentsResource: Token length: {len(g.access_token) if g.access_token else 'None'}")
            return build_api_response(success=False, error="Authentication error.", status_code=500)

        # Get request data
        request_data = request.get_json()
        if not request_data:
            logger.info("RuckCommentsResource: Missing request body.")
            return build_api_response(success=False, error="Missing request body", status_code=400)

        # Validate required fields
        content = request_data.get('content')

        if content is None:
            logger.info("RuckCommentsResource: Missing content field.")
            return build_api_response(success=False, error="Missing content field", status_code=400)
        
        # Validate content length
        if len(content.strip()) == 0:
            logger.info("RuckCommentsResource: Empty content.")
            return build_api_response(success=False, error="Comment content cannot be empty", status_code=400)
        
        if len(content) > 500:
            logger.info("RuckCommentsResource: Content too long.")
            return build_api_response(success=False, error="Comment content exceeds maximum length (500 characters)", status_code=400)
            
        # Fetch user profile information (username)
        # Fallback to a default if the profile doesn't exist or an error occurs
        user_profile = {'username': 'Unknown User', 'avatar_url': None} 
        try:
            profile_response = supabase.table('user') \
                .select('username') \
                .eq('id', user_id) \
                .execute()
            
            if profile_response.data and len(profile_response.data) > 0:
                user_profile['username'] = profile_response.data[0].get('username', 'Unknown User')
            else:
                logger.warning(f"RuckCommentsResource: User profile not found for user_id: {user_id}")

        except Exception as e:
            logger.error(f"RuckCommentsResource: Error fetching user profile: {e}")

        # Create the comment
        try:
            insert_data = {
                'ruck_id': ruck_id,
                'user_id': user_id,
                'user_display_name': user_profile['username'],
                'user_avatar_url': user_profile.get('avatar_url'), 
                'content': content
            }
            
            logger.debug(f"RuckCommentsResource: Inserting comment data: {insert_data}")
            
            insert_result = supabase.table('ruck_comments') \
                                   .insert(insert_data) \
                                   .execute()
            
            if hasattr(insert_result, 'error') and insert_result.error:
                logger.error(f"RuckCommentsResource: Supabase insert error: {insert_result.error}")
                return build_api_response(success=False, error="Failed to create comment in database.", status_code=500)

            created_comment = insert_result.data[0] if insert_result.data else None
            
            # Send push notification to ruck owner
            try:
                # Get ruck owner info
                ruck_response = supabase.table('ruck_sessions') \
                    .select('user_id') \
                    .eq('id', ruck_id) \
                    .execute()
                
                if ruck_response.data and ruck_response.data[0]['user_id'] != user_id:
                    ruck_owner_id = ruck_response.data[0]['user_id']
                    commenter_name = user_profile['username']
                    
                    # Send push notification
                    push_notification_service = PushNotificationService()
                    device_tokens = get_user_device_tokens([ruck_owner_id])
                    
                    if device_tokens:
                        push_notification_service.send_ruck_comment_notification(
                            device_tokens=device_tokens,
                            commenter_name=commenter_name,
                            ruck_id=ruck_id,
                            comment_id=str(created_comment['id'])
                        )
                        
            except Exception as e:
                logger.error(f"Failed to send comment notification: {e}")
                # Don't fail the comment if notification fails

            return build_api_response(data=created_comment, status_code=201)
            
        except Exception as e:
            logger.error(f"RuckCommentsResource: Error creating comment: {e}", exc_info=True)
            return build_api_response(success=False, error="An error occurred while creating the comment.", status_code=500)
    
    @auth_required
    def put(self, ruck_id):
        """
        Update an existing comment.
        
        Expects 'ruck_id' from URL path and JSON body with 'comment_id' and 'content'.
        The user must be authenticated and must be the author of the comment.
        """
        # Initialize Supabase client with the user's token to respect RLS
        try:
            supabase = get_supabase_client(user_jwt=g.access_token)
            user_response = supabase.auth.get_user(g.access_token)
            if not user_response.user:
                logger.warning("RuckCommentsResource: Invalid token or user not found.")
                return build_api_response(success=False, error="Invalid token or user not found.", status_code=401)
            
            user_id = user_response.user.id
            logger.debug(f"RuckCommentsResource: Authenticated user {user_id}")
        except Exception as e:
            logger.error(f"RuckCommentsResource: Error during Supabase client initialization or user auth: {str(e)}")
            logger.error(f"RuckCommentsResource: Token length: {len(g.access_token) if g.access_token else 'None'}")
            return build_api_response(success=False, error="Authentication error.", status_code=500)

        # Get request data
        request_data = request.get_json()
        if not request_data:
            logger.info("RuckCommentsResource: Missing request body.")
            return build_api_response(success=False, error="Missing request body", status_code=400)

        # Validate required fields
        comment_id = request_data.get('comment_id')
        content = request_data.get('content')

        if not comment_id:
            logger.info("RuckCommentsResource: Missing comment_id field.")
            return build_api_response(success=False, error="Missing comment_id field", status_code=400)
        
        if content is None:
            logger.info("RuckCommentsResource: Missing content field.")
            return build_api_response(success=False, error="Missing content field", status_code=400)
        
        # Validate content length
        if len(content.strip()) == 0:
            logger.info("RuckCommentsResource: Empty content.")
            return build_api_response(success=False, error="Comment content cannot be empty", status_code=400)
        
        if len(content) > 500:
            logger.info("RuckCommentsResource: Content too long.")
            return build_api_response(success=False, error="Comment content exceeds maximum length (500 characters)", status_code=400)
        
        # Check if the comment exists and belongs to the user
        try:
            comment_query = supabase.table('ruck_comments') \
                                   .select('id, user_id') \
                                   .eq('id', comment_id) \
                                   .execute()
            
            if not comment_query.data:
                logger.info(f"RuckCommentsResource: Comment with ID {comment_id} not found.")
                return build_api_response(success=False, error=f"Comment with ID {comment_id} not found.", status_code=404)
            
            comment_data = comment_query.data[0]
            
            # Verify ownership (RLS should handle this, but double check)
            if comment_data['user_id'] != user_id:
                logger.warning(f"RuckCommentsResource: User {user_id} attempted to update comment {comment_id} belonging to user {comment_data['user_id']}")
                return build_api_response(
                    success=False, 
                    error="You don't have permission to update this comment.",
                    status_code=403
                )
        except Exception as e:
            logger.error(f"RuckCommentsResource: Error verifying comment: {e}")
            return build_api_response(success=False, error="Error verifying comment", status_code=500)
        
        # Update the comment
        try:
            update_data = {
                'content': content,
                'updated_at': 'now()'  # Supabase will interpret this as the current timestamp
            }
            
            logger.debug(f"RuckCommentsResource: Updating comment {comment_id} with data: {update_data}")
            
            update_response = supabase.table('ruck_comments') \
                                    .update(update_data) \
                                    .eq('id', comment_id) \
                                    .execute()
            
            if hasattr(update_response, 'error') and update_response.error:
                logger.error(f"RuckCommentsResource: Supabase update error: {update_response.error}")
                return build_api_response(success=False, error="Failed to update comment in database.", status_code=500)

            updated_comment = update_response.data[0] if update_response.data else None
            
            return build_api_response(data=updated_comment, status_code=200)
            
        except Exception as e:
            logger.error(f"RuckCommentsResource: Error updating comment: {e}", exc_info=True)
            return build_api_response(success=False, error="An error occurred while updating the comment.", status_code=500)
    
    @auth_required
    def delete(self, ruck_id):
        """
        Delete a comment.
        
        Expects 'ruck_id' from URL path and 'comment_id' as a query parameter.
        The user must be authenticated and must be the author of the comment.
        """
        # Initialize Supabase client with the user's token to respect RLS
        try:
            supabase = get_supabase_client(user_jwt=g.access_token)
            user_response = supabase.auth.get_user(g.access_token)
            if not user_response.user:
                logger.warning("RuckCommentsResource: Invalid token or user not found.")
                return build_api_response(success=False, error="Invalid token or user not found.", status_code=401)
            
            user_id = user_response.user.id
            logger.debug(f"RuckCommentsResource: Authenticated user {user_id}")
        except Exception as e:
            logger.error(f"RuckCommentsResource: Error during Supabase client initialization or user auth: {str(e)}")
            logger.error(f"RuckCommentsResource: Token length: {len(g.access_token) if g.access_token else 'None'}")
            return build_api_response(success=False, error="Authentication error.", status_code=500)

        # Get comment_id from query parameters
        comment_id = request.args.get('comment_id')
        if not comment_id:
            logger.info("RuckCommentsResource: Missing comment_id query parameter.")
            return build_api_response(success=False, error="Missing comment_id query parameter", status_code=400)
            
        # Check if the comment exists and belongs to the user
        try:
            comment_query = supabase.table('ruck_comments') \
                                   .select('id, user_id, ruck_id') \
                                   .eq('id', comment_id) \
                                   .execute()
            
            if not comment_query.data:
                logger.info(f"RuckCommentsResource: Comment with ID {comment_id} not found.")
                return build_api_response(success=False, error=f"Comment with ID {comment_id} not found.", status_code=404)
            
            comment_data = comment_query.data[0]
            
            # Verify ownership (RLS should handle this, but double check)
            if comment_data['user_id'] != user_id:
                logger.warning(f"RuckCommentsResource: User {user_id} attempted to delete comment {comment_id} belonging to user {comment_data['user_id']}")
                return build_api_response(
                    success=False, 
                    error="You don't have permission to delete this comment.",
                    status_code=403
                )
        except Exception as e:
            logger.error(f"RuckCommentsResource: Error verifying comment: {e}")
            return build_api_response(success=False, error="Error verifying comment", status_code=500)
            
        # Delete the comment
        try:
            delete_response = supabase.table('ruck_comments') \
                                    .delete() \
                                    .eq('id', comment_id) \
                                    .execute()
            
            if hasattr(delete_response, 'error') and delete_response.error:
                logger.error(f"RuckCommentsResource: Error deleting comment: {delete_response.error}")
                return build_api_response(success=False, error="Failed to delete comment", status_code=500)
            
            return build_api_response(
                data={'message': 'Comment deleted successfully', 'comment_id': comment_id},
                status_code=200
            )
            
        except Exception as e:
            logger.error(f"RuckCommentsResource: Error deleting comment: {e}", exc_info=True)
            return build_api_response(success=False, error="An error occurred while deleting comment.", status_code=500)
