# /Users/rory/RuckingApp/RuckTracker/api/ruck_comments_resource.py
from flask import request, jsonify, g
from flask_restful import Resource
import logging

# Import Supabase client
from RuckTracker.supabase_client import get_supabase_client

logger = logging.getLogger(__name__)

# Utility function for API responses
def build_api_response(data=None, success=True, error=None, status_code=200):
    response_body = {"success": success}
    if data is not None:
        response_body["data"] = data
    if error is not None:
        response_body["error"] = error
    return jsonify(response_body), status_code

class RuckCommentsResource(Resource):
    def get(self):
        """
        Get comments for a specific ruck session.
        
        Expects 'ruck_id' as a query parameter.
        The user must be authenticated.
        """
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            logger.warning("RuckCommentsResource: Missing or invalid Authorization header.")
            return build_api_response(success=False, error="Unauthorized", status_code=401)
        
        token = auth_header.split("Bearer ")[1]

        # Initialize Supabase client with the user's token to respect RLS
        try:
            supabase = get_supabase_client(user_jwt=token)
            user_response = supabase.auth.get_user(token)
            if not user_response.user:
                logger.warning("RuckCommentsResource: Invalid token or user not found.")
                return build_api_response(success=False, error="Invalid token or user not found.", status_code=401)
            
            user_id = user_response.user.id
            logger.debug(f"RuckCommentsResource: Authenticated user {user_id}")
        except Exception as e:
            logger.error(f"RuckCommentsResource: Error during Supabase client initialization or user auth: {e}")
            return build_api_response(success=False, error="Authentication error.", status_code=500)

        # Get ruck_id from query parameters
        ruck_id_str = request.args.get('ruck_id')
        if not ruck_id_str:
            logger.info("RuckCommentsResource: Missing ruck_id query parameter.")
            return build_api_response(success=False, error="Missing ruck_id query parameter", status_code=400)
        
        try:
            ruck_id = int(ruck_id_str)
        except ValueError:
            logger.info(f"RuckCommentsResource: Invalid ruck_id format: {ruck_id_str}")
            return build_api_response(success=False, error="Invalid ruck_id format, must be an integer.", status_code=400)

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
    
    def post(self):
        """
        Add a comment to a ruck session.
        
        Expects JSON body with 'ruck_id' and 'content'.
        The user must be authenticated.
        """
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            logger.warning("RuckCommentsResource: Missing or invalid Authorization header.")
            return build_api_response(success=False, error="Unauthorized", status_code=401)
        
        token = auth_header.split("Bearer ")[1]

        # Initialize Supabase client with the user's token to respect RLS
        try:
            supabase = get_supabase_client(user_jwt=token)
            user_response = supabase.auth.get_user(token)
            if not user_response.user:
                logger.warning("RuckCommentsResource: Invalid token or user not found.")
                return build_api_response(success=False, error="Invalid token or user not found.", status_code=401)
            
            user_id = user_response.user.id
            user_email = user_response.user.email
            user_display_name = user_email.split('@')[0] if user_email else 'Anonymous'
            
            logger.debug(f"RuckCommentsResource: Authenticated user {user_id}")
        except Exception as e:
            logger.error(f"RuckCommentsResource: Error during Supabase client initialization or user auth: {e}")
            return build_api_response(success=False, error="Authentication error.", status_code=500)

        # Get request data
        request_data = request.get_json()
        if not request_data:
            logger.info("RuckCommentsResource: Missing request body.")
            return build_api_response(success=False, error="Missing request body", status_code=400)
        
        ruck_id = request_data.get('ruck_id')
        content = request_data.get('content')
        
        if ruck_id is None:
            logger.info("RuckCommentsResource: Missing ruck_id in request body.")
            return build_api_response(success=False, error="Missing ruck_id in request body", status_code=400)
            
        if not content or not content.strip():
            logger.info("RuckCommentsResource: Missing or empty content in request body.")
            return build_api_response(success=False, error="Comment content cannot be empty", status_code=400)
        
        try:
            ruck_id = int(ruck_id)
        except (ValueError, TypeError):
            logger.info(f"RuckCommentsResource: Invalid ruck_id format: {ruck_id}")
            return build_api_response(success=False, error="Invalid ruck_id format, must be an integer.", status_code=400)
            
        # Check if the ruck exists
        try:
            ruck_query = supabase.table('ruck_session') \
                                 .select('id') \
                                 .eq('id', ruck_id) \
                                 .execute()
            
            if not ruck_query.data:
                logger.info(f"RuckCommentsResource: Ruck session with ID {ruck_id} not found.")
                return build_api_response(success=False, error=f"Ruck session with ID {ruck_id} not found.", status_code=404)
        except Exception as e:
            logger.error(f"RuckCommentsResource: Error verifying ruck session: {e}")
            return build_api_response(success=False, error="Error verifying ruck session", status_code=500)
            
        # Add the comment
        try:
            # Get the user's profile info for display name
            profile_query = supabase.table('profiles') \
                                   .select('display_name, avatar_url') \
                                   .eq('id', user_id) \
                                   .execute()
            
            if profile_query.data:
                user_display_name = profile_query.data[0].get('display_name', user_display_name)
                user_avatar_url = profile_query.data[0].get('avatar_url')
            else:
                user_avatar_url = None
            
            # Insert the comment
            comment_data = {
                'ruck_id': ruck_id,
                'user_id': user_id,
                'user_display_name': user_display_name,
                'user_avatar_url': user_avatar_url,
                'content': content.strip()
            }
            
            insert_response = supabase.table('ruck_comments').insert(comment_data).execute()
            
            if hasattr(insert_response, 'error') and insert_response.error:
                logger.error(f"RuckCommentsResource: Error adding comment: {insert_response.error}")
                return build_api_response(success=False, error="Failed to add comment", status_code=500)
            
            # Return the created comment
            return build_api_response(data=insert_response.data[0], status_code=201)
            
        except Exception as e:
            logger.error(f"RuckCommentsResource: Error adding comment: {e}", exc_info=True)
            return build_api_response(success=False, error="An error occurred while adding comment.", status_code=500)
    
    def put(self):
        """
        Update an existing comment.
        
        Expects JSON body with 'comment_id' and 'content'.
        The user must be authenticated and must be the author of the comment.
        """
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            logger.warning("RuckCommentsResource: Missing or invalid Authorization header.")
            return build_api_response(success=False, error="Unauthorized", status_code=401)
        
        token = auth_header.split("Bearer ")[1]

        # Initialize Supabase client with the user's token to respect RLS
        try:
            supabase = get_supabase_client(user_jwt=token)
            user_response = supabase.auth.get_user(token)
            if not user_response.user:
                logger.warning("RuckCommentsResource: Invalid token or user not found.")
                return build_api_response(success=False, error="Invalid token or user not found.", status_code=401)
            
            user_id = user_response.user.id
            logger.debug(f"RuckCommentsResource: Authenticated user {user_id}")
        except Exception as e:
            logger.error(f"RuckCommentsResource: Error during Supabase client initialization or user auth: {e}")
            return build_api_response(success=False, error="Authentication error.", status_code=500)

        # Get request data
        request_data = request.get_json()
        if not request_data:
            logger.info("RuckCommentsResource: Missing request body.")
            return build_api_response(success=False, error="Missing request body", status_code=400)
        
        comment_id = request_data.get('comment_id')
        content = request_data.get('content')
        
        if not comment_id:
            logger.info("RuckCommentsResource: Missing comment_id in request body.")
            return build_api_response(success=False, error="Missing comment_id in request body", status_code=400)
            
        if not content or not content.strip():
            logger.info("RuckCommentsResource: Missing or empty content in request body.")
            return build_api_response(success=False, error="Comment content cannot be empty", status_code=400)
            
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
                logger.warning(f"RuckCommentsResource: User {user_id} attempted to update comment {comment_id} belonging to user {comment_data['user_id']}")
                return build_api_response(
                    success=False, 
                    error="You don't have permission to edit this comment.",
                    status_code=403
                )
        except Exception as e:
            logger.error(f"RuckCommentsResource: Error verifying comment: {e}")
            return build_api_response(success=False, error="Error verifying comment", status_code=500)
            
        # Update the comment
        try:
            # Note: updated_at will be set automatically by the database trigger
            update_data = {
                'content': content.strip(),
            }
            
            update_response = supabase.table('ruck_comments') \
                                    .update(update_data) \
                                    .eq('id', comment_id) \
                                    .execute()
            
            if hasattr(update_response, 'error') and update_response.error:
                logger.error(f"RuckCommentsResource: Error updating comment: {update_response.error}")
                return build_api_response(success=False, error="Failed to update comment", status_code=500)
            
            # Return the updated comment
            return build_api_response(data=update_response.data[0], status_code=200)
            
        except Exception as e:
            logger.error(f"RuckCommentsResource: Error updating comment: {e}", exc_info=True)
            return build_api_response(success=False, error="An error occurred while updating comment.", status_code=500)
    
    def delete(self):
        """
        Delete a comment.
        
        Expects 'comment_id' as a query parameter.
        The user must be authenticated and must be the author of the comment.
        """
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            logger.warning("RuckCommentsResource: Missing or invalid Authorization header.")
            return build_api_response(success=False, error="Unauthorized", status_code=401)
        
        token = auth_header.split("Bearer ")[1]

        # Initialize Supabase client with the user's token to respect RLS
        try:
            supabase = get_supabase_client(user_jwt=token)
            user_response = supabase.auth.get_user(token)
            if not user_response.user:
                logger.warning("RuckCommentsResource: Invalid token or user not found.")
                return build_api_response(success=False, error="Invalid token or user not found.", status_code=401)
            
            user_id = user_response.user.id
            logger.debug(f"RuckCommentsResource: Authenticated user {user_id}")
        except Exception as e:
            logger.error(f"RuckCommentsResource: Error during Supabase client initialization or user auth: {e}")
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
