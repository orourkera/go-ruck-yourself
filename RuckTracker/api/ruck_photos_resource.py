# /Users/rory/RuckingApp/RuckTracker/api/ruck_photos_resource.py
from flask import request, g
from flask_restful import Resource
import logging
import tempfile
from pathlib import Path
import uuid

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
    return response_body, status_code

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
            
    def post(self):
        """
        Upload photos for a specific ruck session.
        Expects 'ruck_id' as a form field and 'photos' as a list of files.
        The user must be authenticated, and the ruck session must belong to the user.
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
            
            user_id = user_response.user.id
            logger.debug(f"RuckPhotosResource: Authenticated user {user_id}")
        except Exception as e:
            logger.error(f"RuckPhotosResource: Error during Supabase client initialization or user auth: {e}")
            return build_api_response(success=False, error="Authentication error.", status_code=500)

        # Check if form data is present
        if 'ruck_id' not in request.form:
            logger.info("RuckPhotosResource: Missing ruck_id form field.")
            return build_api_response(success=False, error="Missing ruck_id form field", status_code=400)
        
        # Check if files are present
        if 'photos' not in request.files:
            logger.info("RuckPhotosResource: No photos were uploaded.")
            return build_api_response(success=False, error="No photos were uploaded", status_code=400)
        
        try:
            ruck_id = int(request.form['ruck_id'])
        except ValueError:
            logger.info(f"RuckPhotosResource: Invalid ruck_id format: {request.form['ruck_id']}")
            return build_api_response(success=False, error="Invalid ruck_id format, must be an integer.", status_code=400)
        
        # Verify the ruck exists and belongs to the user
        try:
            ruck_query = supabase.table('ruck_session') \
                                 .select('id, user_id') \
                                 .eq('id', ruck_id) \
                                 .execute()
            
            if not ruck_query.data:
                return build_api_response(success=False, error=f"Ruck session with ID {ruck_id} not found.", status_code=404)
            
            # Due to RLS, if the ruck doesn't belong to the user, it won't be found
            # But for extra validation:
            if ruck_query.data[0]['user_id'] != user_id:
                return build_api_response(success=False, error="You don't have permission to upload photos to this ruck session.", status_code=403)
            
        except Exception as e:
            logger.error(f"RuckPhotosResource: Error verifying ruck session: {e}")
            return build_api_response(success=False, error="Error verifying ruck session", status_code=500)
        
        uploaded_photos = []
        photo_files = request.files.getlist('photos')
        
        # Limit the number of photos that can be uploaded at once (e.g., 5)
        MAX_PHOTOS = 5
        if len(photo_files) > MAX_PHOTOS:
            return build_api_response(
                success=False, 
                error=f"Maximum {MAX_PHOTOS} photos can be uploaded at once.", 
                status_code=400
            )
        
        for photo_file in photo_files:
            if photo_file.filename == '':
                logger.debug("RuckPhotosResource: Skipping photo with empty filename.")
                continue
                
            if not photo_file.content_type.startswith('image/'):
                logger.warning(f"RuckPhotosResource: Skipping non-image file {photo_file.filename} with type {photo_file.content_type}")
                continue
            
            temp_file_path = None  # Initialize path for finally block
            try:
                # Generate a unique filename
                original_filename = photo_file.filename
                extension = Path(original_filename).suffix
                unique_filename = f"{uuid.uuid4()}{extension}"
                storage_path = f"{user_id}/{ruck_id}/{unique_filename}"

                logger.debug(f"RuckPhotosResource: Processing photo {original_filename} to be saved as {unique_filename}")

                # Create and use a temporary file
                with tempfile.NamedTemporaryFile(delete=False, suffix=extension) as temp_file:
                    photo_file.save(temp_file) # Save incoming stream to temp_file object
                    temp_file_path = temp_file.name # Get the path for upload and cleanup
                
                logger.debug(f"RuckPhotosResource: Saved to temporary file {temp_file_path}. Uploading to Supabase Storage at {storage_path}...")
                
                # Upload to Supabase storage
                with open(temp_file_path, 'rb') as f_for_upload:
                    storage_response = supabase.storage.from_('ruck-photos').upload(
                        path=storage_path,
                        file=f_for_upload, # Pass file object
                        file_options={"content-type": photo_file.content_type, "cache-control": "3600"}
                    )

                logger.debug(f"RuckPhotosResource: Successfully uploaded {unique_filename} to Supabase Storage.")
                
                # Get the public URL
                public_url_data = supabase.storage.from_('ruck-photos').get_public_url(storage_path)
                public_url = public_url_data # get_public_url usually returns the string directly
                
                if isinstance(public_url, str) and public_url.endswith('?'):
                    public_url = public_url[:-1] # Remove trailing '?'
                
                thumbnail_url = public_url # For MVP, thumbnail is same as original
                
                # Prepare metadata for database insert
                photo_metadata = {
                    'ruck_id': ruck_id,
                    'user_id': user_id,
                    'filename': unique_filename,
                    'original_filename': original_filename,
                    'content_type': photo_file.content_type,
                    'size': Path(temp_file_path).stat().st_size, # Get size from temp file
                    'url': public_url,
                    'thumbnail_url': thumbnail_url
                }
                
                logger.debug(f"RuckPhotosResource: Inserting metadata for {unique_filename} into database: {photo_metadata}")
                
                insert_response = supabase.table('ruck_photos').insert(photo_metadata).execute()
                
                if hasattr(insert_response, 'error') and insert_response.error:
                    logger.error(f"RuckPhotosResource: Supabase DB insert error for {unique_filename}: {insert_response.error}")
                    continue 
                
                if not insert_response.data:
                    logger.error(f"RuckPhotosResource: Supabase DB insert for {unique_filename} returned no data but no explicit error.")
                    continue

                logger.info(f"RuckPhotosResource: Successfully processed and stored photo {unique_filename} with ID {insert_response.data[0].get('id')}")
                uploaded_photos.append(insert_response.data[0])
                
            except Exception as e:
                logger.error(f"RuckPhotosResource: Unhandled exception while processing photo {photo_file.filename if photo_file else 'unknown'}: {e}", exc_info=True)
                continue
            finally:
                if temp_file_path and Path(temp_file_path).exists():
                    try:
                        import os
                        os.unlink(temp_file_path)
                        logger.debug(f"RuckPhotosResource: Successfully deleted temporary file {temp_file_path}")
                    except Exception as e_unlink:
                        logger.error(f"RuckPhotosResource: Error deleting temporary file {temp_file_path}: {e_unlink}")
        
        if not uploaded_photos:
            return build_api_response(
                success=False, 
                error="Failed to upload any photos. Please try again.", 
                status_code=500
            )
            
        # Update the ruck_session has_photos flag if needed
        try:
            supabase.table('ruck_session').update({'has_photos': True}).eq('id', ruck_id).execute()
        except Exception as e:
            logger.warning(f"RuckPhotosResource: Error updating has_photos flag: {e}")
            # We don't fail the request for this
            
        return build_api_response(
            data={
                'count': len(uploaded_photos),
                'photos': uploaded_photos
            },
            status_code=201
        )
        
    def delete(self):
        """
        Delete a specific photo from a ruck session.
        Expects 'photo_id' as a query parameter.
        The user must be authenticated, and the photo must belong to the user.
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
            
            user_id = user_response.user.id
            logger.debug(f"RuckPhotosResource: Authenticated user {user_id}")
        except Exception as e:
            logger.error(f"RuckPhotosResource: Error during Supabase client initialization or user auth: {e}")
            return build_api_response(success=False, error="Authentication error.", status_code=500)

        photo_id = request.args.get('photo_id')
        if not photo_id:
            logger.info("RuckPhotosResource: Missing photo_id query parameter.")
            return build_api_response(success=False, error="Missing photo_id query parameter", status_code=400)
        
        # First, get the photo information to verify ownership and get details needed for cleanup
        try:
            photo_query = supabase.table('ruck_photos') \
                                  .select('id, ruck_id, user_id, filename') \
                                  .eq('id', photo_id) \
                                  .execute()
            
            if not photo_query.data:
                logger.info(f"RuckPhotosResource: Photo with ID {photo_id} not found.")
                return build_api_response(success=False, error=f"Photo with ID {photo_id} not found.", status_code=404)
            
            # Due to RLS, if the photo doesn't belong to the user, it won't be found
            # But for extra validation:
            photo_data = photo_query.data[0]
            if photo_data['user_id'] != user_id:
                logger.warning(f"RuckPhotosResource: User {user_id} attempted to delete photo {photo_id} belonging to user {photo_data['user_id']}")
                return build_api_response(
                    success=False, 
                    error="You don't have permission to delete this photo.", 
                    status_code=403
                )
            
            ruck_id = photo_data['ruck_id']
            filename = photo_data['filename']
            
        except Exception as e:
            logger.error(f"RuckPhotosResource: Error getting photo information: {e}")
            return build_api_response(success=False, error="Error getting photo information", status_code=500)
        
        # Delete the photo file from storage
        try:
            storage_path = f"{user_id}/{ruck_id}/{filename}"
            supabase.storage.from_('ruck-photos').remove([storage_path])
        except Exception as e:
            logger.error(f"RuckPhotosResource: Error deleting photo file from storage: {e}")
            # Continue even if storage deletion fails, as the metadata is more important
        
        # Delete the photo metadata from the database
        try:
            delete_response = supabase.table('ruck_photos').delete().eq('id', photo_id).execute()
            
            if hasattr(delete_response, 'error') and delete_response.error:
                logger.error(f"RuckPhotosResource: Error deleting photo metadata: {delete_response.error}")
                return build_api_response(
                    success=False, 
                    error="Failed to delete photo metadata.", 
                    status_code=500
                )
                
            # Check if this was the last photo for this ruck
            remaining_photos = supabase.table('ruck_photos').select('id').eq('ruck_id', ruck_id).execute()
            
            if not remaining_photos.data:
                # Update the ruck's has_photos flag to false
                supabase.table('ruck_session').update({'has_photos': False}).eq('id', ruck_id).execute()
            
            return build_api_response(
                success=True,
                data={
                    "message": "Photo deleted successfully",
                    "photo_id": photo_id
                },
                status_code=200
            )
            
        except Exception as e:
            logger.error(f"RuckPhotosResource: Error deleting photo metadata: {e}")
            return build_api_response(
                success=False, 
                error="Failed to delete photo. Please try again.", 
                status_code=500
            )
