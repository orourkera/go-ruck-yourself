# /Users/rory/RuckingApp/RuckTracker/api/ruck_likes_resource.py
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
    # Return just the response body and status code for Flask-RESTful
    # (not jsonify which returns a Response object)
    return response_body, status_code

class RuckLikesResource(Resource):
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
            
        # Add the like
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
            
            # Insert the like
            like_data = {
                'ruck_id': ruck_id,
                'user_id': user_id,
                'user_display_name': user_display_name,
                'user_avatar_url': user_avatar_url
            }
            
            insert_response = supabase.table('ruck_likes').insert(like_data).execute()
            
            if hasattr(insert_response, 'error') and insert_response.error:
                logger.error(f"RuckLikesResource: Error adding like: {insert_response.error}")
                return build_api_response(success=False, error="Failed to add like", status_code=500)
            
            # Return the created like
            return build_api_response(data=insert_response.data[0], status_code=201)
            
        except Exception as e:
            logger.error(f"RuckLikesResource: Error adding like: {e}", exc_info=True)
            return build_api_response(success=False, error="An error occurred while adding like.", status_code=500)
    
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
