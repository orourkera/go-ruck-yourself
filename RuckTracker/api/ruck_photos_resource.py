# /Users/rory/RuckingApp/RuckTracker/api/ruck_photos_resource.py
from flask import request, jsonify, g
from flask_restful import Resource
import logging

# Assuming get_supabase_client is the way to get a Supabase client instance
# It's crucial that this client is initialized in the context of the authenticated user for RLS to work.
from RuckTracker.supabase_client import get_supabase_client

logger = logging.getLogger(__name__)

# A simple response utility, as one wasn't found in app.py
def build_api_response(data=None, success=True, error=None, status_code=200):
    response_body = {"success": success}
    if data is not None:
        response_body["data"] = data
    if error is not None:
        response_body["error"] = error
    return jsonify(response_body), status_code

class RuckPhotosResource(Resource):
    def get(self):
        """
        Get photos for a specific ruck session.
        Expects 'ruck_id' as a query parameter.
        The user must be authenticated.
        """
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            logger.warning("RuckPhotosResource: Missing or invalid Authorization header.")
            return build_api_response(success=False, error="Unauthorized", status_code=401)
        
        token = auth_header.split("Bearer ")[1]

        # Initialize Supabase client with the user's token to respect RLS
        try:
            supabase = get_supabase_client(user_jwt=token)
            user_response = supabase.auth.get_user(token)
            if not user_response.user:
                logger.warning("RuckPhotosResource: Invalid token or user not found.")
                return build_api_response(success=False, error="Invalid token or user not found.", status_code=401)
            # logger.debug(f"RuckPhotosResource: Authenticated user {user_response.user.id}")
        except Exception as e:
            logger.error(f"RuckPhotosResource: Error during Supabase client initialization or user auth: {e}")
            return build_api_response(success=False, error="Authentication error.", status_code=500)

        ruck_id_str = request.args.get('ruck_id')

        if not ruck_id_str:
            logger.info("RuckPhotosResource: Missing ruck_id query parameter.")
            return build_api_response(success=False, error="Missing ruck_id query parameter", status_code=400)

        try:
            ruck_id = int(ruck_id_str)
        except ValueError:
            logger.info(f"RuckPhotosResource: Invalid ruck_id format: {ruck_id_str}")
            return build_api_response(success=False, error="Invalid ruck_id format, must be an integer.", status_code=400)

        try:
            logger.debug(f"RuckPhotosResource: Fetching photos for ruck_id: {ruck_id}")
            # Ensure the select statement matches the RuckPhoto model fields in Dart
            # Expected: id, ruckId, userId, url, thumbnailUrl, createdAt, filename, originalFilename, contentType, size
            query_result = supabase.table('ruck_photos') \
                                   .select('id, ruck_id, user_id, filename, original_filename, content_type, size, url, thumbnail_url, created_at') \
                                   .eq('ruck_id', ruck_id) \
                                   .execute()
            
            if hasattr(query_result, 'error') and query_result.error:
                logger.error(f"RuckPhotosResource: Supabase query error: {query_result.error}")
                return build_api_response(success=False, error="Failed to fetch photos from database.", status_code=500)

            if query_result.data:
                logger.debug(f"RuckPhotosResource: Found {len(query_result.data)} photos for ruck_id: {ruck_id}")
                return build_api_response(data=query_result.data, status_code=200)
            else:
                logger.debug(f"RuckPhotosResource: No photos found for ruck_id: {ruck_id}")
                return build_api_response(data=[], status_code=200)

        except Exception as e:
            logger.error(f"RuckPhotosResource: Error fetching ruck photos from database: {e}", exc_info=True)
            return build_api_response(success=False, error="An error occurred while fetching photos.", status_code=500)
