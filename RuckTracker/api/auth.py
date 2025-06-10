from flask import g, jsonify, request
from flask_restful import Resource
from flask import Blueprint, make_response
import uuid
from datetime import datetime, timedelta
import sys
import logging
from functools import wraps
from google.auth.transport import requests
from google.oauth2 import id_token

import sys
import os

# Add the parent directory to the path to allow importing from the root directory
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from supabase_client import get_supabase_client, get_supabase_admin_client

logger = logging.getLogger(__name__)

# Auth decorators
def auth_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not hasattr(g, 'user') or g.user is None:
            return jsonify({'message': 'Authentication required'}), 401
        return f(*args, **kwargs)
    return decorated

def get_user_id():
    """Helper function to get the current user's ID"""
    if hasattr(g, 'user') and g.user and hasattr(g.user, 'id'):
        return g.user.id
    return None

class SignUpResource(Resource):
    def post(self):
        """Register a new user and create their corresponding record in the user table""" 
        try:
            data = request.get_json()
            email = data.get('email')
            password = data.get('password')
            username = data.get('username') # This contains the display name from Flutter
            
            if not email or not password or not username: 
                return {'message': 'Email, password, and username (display name) are required'}, 400
                
            # Create user in Supabase Auth
            supabase = get_supabase_client()
            auth_response = supabase.auth.sign_up({
                "email": email,
                "password": password,
            })
            
            if auth_response.user:
                user_id = auth_response.user.id
                
                # Prepare data for the public.user table
                # Only include columns defined in the User model, EXCLUDING email
                user_data = {
                    'id': str(user_id), 
                    'username': username, # Save username (display name) as username
                    'email': email, # User table needs the email column
                    'weight_kg': data.get('weight_kg'),
                    'height_cm': data.get('height_cm'),
                    'date_of_birth': data.get('date_of_birth'),
                    'gender': data.get('gender'),
                    'prefer_metric': data.get('preferMetric') # Read camelCase from request
                }
                user_data_clean = {k: v for k, v in user_data.items() if v is not None}
                
                logger.debug(f"Inserting into user table for user {user_id}: {user_data_clean}") 
                try:
                    admin_supabase = get_supabase_admin_client()
                    user_insert_response = admin_supabase.table('user').insert(user_data_clean).execute()
                except Exception as user_insert_err:
                    db_error_message = str(user_insert_err)
                    logger.error(f"Error inserting user record using admin client for user {user_id}: {db_error_message}", exc_info=True)
                    try:
                        logger.warning(f"Attempting to delete auth user {user_id} due to user record creation failure.")
                        admin_supabase.auth.admin.delete_user(user_id)
                    except Exception as delete_err:
                        logger.error(f"Failed to delete auth user {user_id} after insert failure: {delete_err}", exc_info=True)
                    return {'message': f'User created in auth, but failed to create user record: {db_error_message}'}, 500 
                
                logger.info(f"Successfully created user record for user {user_id}")
                
                user_response_data = auth_response.user.model_dump(mode='json') if auth_response.user else {}
                
                # Merge data from the user table insert into the response
                if user_insert_response.data:
                    user_details = user_insert_response.data[0]
                    user_response_data['username'] = user_details.get('username', username)
                    user_response_data['weight_kg'] = user_details.get('weight_kg')
                    user_response_data['prefer_metric'] = user_details.get('prefer_metric')
                else:
                    user_response_data['username'] = username
                    
                # Add the email from the auth response to the final user object sent to client
                user_response_data['email'] = email
                
                return {
                    'message': 'User registered successfully',
                    'token': auth_response.session.access_token if auth_response.session else None,
                    'user': user_response_data 
                }, 201
            else:
                error_message = "Failed to register user"
                auth_error = getattr(auth_response, 'error', None) or getattr(auth_response, 'message', None)
                if auth_error:
                     error_message += f": {str(auth_error)}"
                     
                logger.warning(f"{error_message} for email: {email}")
                status_code = 409 if "user already exists" in error_message.lower() else 400
                return {'message': error_message}, status_code
                
        except Exception as e:
            logger.error(f"Error during signup: {str(e)}", exc_info=True)
            return {'message': f'Error during signup: {str(e)}'}, 500

class SignInResource(Resource):
    def post(self):
        """Sign in a user"""
        print("--- SignInResource POST method entered ---", file=sys.stderr)
        try:
            data = request.get_json()
            email = data.get('email')
            password = data.get('password')
            
            if not email or not password:
                return {'message': 'Email and password are required'}, 400
                
            # Sign in with Supabase
            supabase = get_supabase_client()
            auth_response = supabase.auth.sign_in_with_password({
                "email": email,
                "password": password,
            })
            
            if auth_response.user:
                # Convert user model to a JSON-serializable dictionary
                user_data = auth_response.user.model_dump(mode='json')
                logger.debug(f"Returning user data: {user_data}")
                
                return {
                    'token': auth_response.session.access_token if auth_response.session else None,
                    'refresh_token': auth_response.session.refresh_token if auth_response.session else None,
                    'user': user_data
                }, 200
            else:
                logger.warning("Sign in failed: Invalid credentials")
                return {'message': 'Invalid credentials'}, 401
                
        except Exception as e:
            logger.error(f"Error during signin: {str(e)}", exc_info=True)
            return {'message': f'Error during signin: {str(e)}'}, 500

class SignOutResource(Resource):
    def post(self):
        """Sign out a user"""
        try:
            # Sign out with Supabase
            supabase = get_supabase_client()
            supabase.auth.sign_out()
            return {'message': 'User signed out successfully'}, 200
        except Exception as e:
            return {'message': f'Error during signout: {str(e)}'}, 500

class RefreshTokenResource(Resource):
    def post(self):
        """Refresh an authentication token"""
        try:
            data = request.get_json()
            refresh_token = data.get('refresh_token')
            
            if not refresh_token:
                return {'message': 'Refresh token is required'}, 400
                
            # Refresh token with Supabase
            supabase = get_supabase_client()
            auth_response = supabase.auth.refresh_session(refresh_token)
            
            if auth_response.session:
                # Convert user model to a JSON-serializable dictionary
                user_data = auth_response.user.model_dump(mode='json') if auth_response.user else None
                
                return {
                    'token': auth_response.session.access_token,
                    'refresh_token': auth_response.session.refresh_token,
                    'user': user_data
                }, 200
            else:
                return {'message': 'Invalid refresh token'}, 401
                
        except Exception as e:
            return {'message': f'Error refreshing token: {str(e)}'}, 500

class ForgotPasswordResource(Resource):
    def post(self):
        """Trigger password reset email using Supabase"""
        try:
            data = request.get_json()
            email = data.get('email')
            if not email:
                return {'message': 'Email is required'}, 400
            supabase = get_supabase_client()
            
            # Use the correct redirect URL for mobile app callback
            redirect_url = 'com.getrucky.app://auth/callback'
            response = supabase.auth.reset_password_email(
                email=email,
                options={'redirect_to': redirect_url}
            )
            
            if hasattr(response, 'error') and response.error:
                return {'message': f'Failed to send reset email: {response.error.message}'}, 400
            return {'message': 'If an account exists for this email, a password reset link has been sent.'}, 200
        except Exception as e:
            logger.error(f"Error during forgot password: {str(e)}", exc_info=True)
            return {'message': f'Error during forgot password: {str(e)}'}, 500

class UserProfileResource(Resource):
    def get(self):
        """Get the current user's profile from the user table AND include email"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
                
            logger.debug(f"Fetching profile for user ID: {g.user.id}")
            # Use the authenticated user's JWT for RLS
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            response = supabase.table('user') \
                .select('*') \
                .eq('id', str(g.user.id)) \
                .execute()
                
            if not response.data or len(response.data) == 0:
                logger.warning(f"User profile not found in 'user' table for ID: {g.user.id}")
                # Still return basic info if profile row is missing
                return {'message': 'User not found'}, 404
            
            profile_data = response.data[0]
            logger.debug(f"Profile data found in 'user' table: {profile_data}")
            
            # Ensure essential auth info (like email) is present in the final response
            # Even if the profile row was missing, we return the email associated with the token
            if 'email' not in profile_data or not profile_data['email']:
                # Try to get email from g.user (JWT/session)
                if hasattr(g.user, 'email') and g.user.email:
                    profile_data['email'] = g.user.email
                else:
                    # Fallback: fetch from auth.users (Supabase internal table)
                    try:
                        # Use the same Supabase client instance
                        auth_user_resp = supabase.auth.get_user(jwt=getattr(g, 'access_token', None))
                        if auth_user_resp.user and auth_user_resp.user.email:
                             profile_data['email'] = auth_user_resp.user.email
                        else:
                             logger.warning(f"Could not fetch email from Supabase auth for user {g.user.id}")
                    except Exception as auth_err:
                        logger.warning(f"Error fetching email from Supabase auth for user {g.user.id}: {auth_err}")
            
            # Also ensure ID is present, using the authenticated user ID as definitive source
            if 'id' not in profile_data or profile_data['id'] != str(g.user.id):
                 profile_data['id'] = str(g.user.id)

            # Return the combined/ensured data
            # If profile row was missing, this will primarily contain id and email
            # If profile row existed, it contains profile data + potentially added email/id
            return profile_data, 200
                
        except Exception as e:
            logger.error(f"Error retrieving user profile: {str(e)}", exc_info=True)
            # Check for specific Postgrest errors if helpful
            if hasattr(e, 'code') and e.code == 'PGRST116': # Resource Not Found
                 logger.warning(f"User profile row likely missing for user {g.user.id} in 'user' table.")
                 # Return minimal data even if row not found
                 minimal_data = {'id': str(g.user.id)}
                 if hasattr(g.user, 'email') and g.user.email:
                     minimal_data['email'] = g.user.email
                 return minimal_data, 200 # Return 200 OK with minimal data
            return {'message': f'Error retrieving user profile: {str(e)}'}, 500
            
    def put(self):
        """Update the current user's profile in the user table"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
                
            data = request.get_json()
            if not data:
                 return {'message': 'No update data provided'}, 400
                 
            update_data = {}
            # Assuming these fields exist in the new 'user' model
            allowed_fields = ['username', 'weight_kg', 'prefer_metric', 'height_cm', 'allow_ruck_sharing', 'gender', 'date_of_birth', 'avatar_url']
            for field in allowed_fields:
                if field == 'prefer_metric': # Check for snake_case field name
                    # Expect camelCase 'preferMetric' in the incoming JSON data for updates too
                    if 'preferMetric' in data:
                         update_data['prefer_metric'] = data['preferMetric'] # Use snake_case for DB update dict key
                # Handle camelCase for height_cm
                elif field == 'height_cm' and 'heightCm' in data:
                    update_data['height_cm'] = data['heightCm']
                # Handle gender parameter
                elif field == 'gender':
                    if 'gender' in data:
                        update_data['gender'] = data['gender']
                # Handle date_of_birth parameter (both formats)
                elif field == 'date_of_birth':
                    if 'date_of_birth' in data:
                        update_data['date_of_birth'] = data['date_of_birth']
                    elif 'dateOfBirth' in data:
                        update_data['date_of_birth'] = data['dateOfBirth']
                # Handle allow_ruck_sharing - check for both camelCase and snake_case versions
                elif field == 'allow_ruck_sharing':
                    if 'allowRuckSharing' in data:  # Check for camelCase version from mobile app
                        update_data['allow_ruck_sharing'] = data['allowRuckSharing']
                    elif 'allow_ruck_sharing' in data:  # Also check for snake_case
                        update_data['allow_ruck_sharing'] = data['allow_ruck_sharing']
                elif field in data:
                    update_data[field] = data[field]
                 
            if not update_data:
                 return {'message': 'No valid fields provided for update'}, 400

            logger.debug(f"Authenticated user id: {g.user.id}")
            logger.debug(f"Attempting update on 'user' table where id = {g.user.id} with: {update_data}")
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            # Only allow updating the row where id = g.user.id
            response = supabase.table('user') \
                .update(update_data) \
                .eq('id', str(g.user.id)) \
                .execute()
            logger.debug(f"Update response: {response.__dict__}")
            
            # After update/insert, fetch the complete user data to return
            fetch_response = supabase.table('user').select('*').eq('id', str(g.user.id)).execute()

            if not fetch_response.data or len(fetch_response.data) == 0:
                 logger.error(f"Profile update seemed successful but failed to fetch updated data for user ID {g.user.id}")
                 return {'message': 'Profile update may have succeeded, but failed to retrieve updated data.'}, 500
            
            profile_data = fetch_response.data[0]
            logger.debug(f"Profile updated/fetched successfully: {profile_data}")
            
            # Ensure email from auth is included if missing
            if 'email' not in profile_data or not profile_data['email']:
                 if hasattr(g.user, 'email') and g.user.email:
                    profile_data['email'] = g.user.email
            
            return profile_data, 200
                
        except Exception as e:
            logger.error(f"Error updating user profile: {str(e)}", exc_info=True)
            return {'message': f'Error updating user profile: {str(e)}'}, 500


class UserAvatarUploadResource(Resource):
    @auth_required
    def post(self):
        """Upload user avatar image"""
        try:
            from flask import request
            import base64
            import io
            from PIL import Image
            
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
                
            user_id = g.user.id
            logger.debug(f"Avatar upload for user ID: {user_id}")
            
            # Get image data from request
            data = request.get_json()
            if not data or 'image' not in data:
                return {'message': 'Image data is required'}, 400
                
            image_data = data['image']
            
            # Handle base64 encoded image
            if image_data.startswith('data:image/'):
                # Remove data URL prefix
                header, image_data = image_data.split(',', 1)
                
            try:
                # Decode base64 image
                image_bytes = base64.b64decode(image_data)
                
                # Process image with PIL (resize and compress)
                image = Image.open(io.BytesIO(image_bytes))
                
                # Convert to RGB if necessary
                if image.mode in ('RGBA', 'LA', 'P'):
                    background = Image.new('RGB', image.size, (255, 255, 255))
                    if image.mode == 'P':
                        image = image.convert('RGBA')
                    background.paste(image, mask=image.split()[-1] if 'A' in image.mode else None)
                    image = background
                
                # Resize to 200x200 for avatars
                image = image.resize((200, 200), Image.Resampling.LANCZOS)
                
                # Save as JPEG with compression
                output = io.BytesIO()
                image.save(output, format='JPEG', quality=85, optimize=True)
                compressed_bytes = output.getvalue()
                
                # Upload to Supabase Storage
                supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
                
                # Generate unique filename
                filename = f"avatars/{user_id}_{uuid.uuid4().hex}.jpg"
                
                # Upload file to Supabase storage
                storage_response = supabase.storage.from_('user-avatars').upload(
                    filename, 
                    compressed_bytes,
                    file_options={'content-type': 'image/jpeg'}
                )
                
                if hasattr(storage_response, 'error') and storage_response.error:
                    logger.error(f"Storage upload error: {storage_response.error}")
                    return {'message': 'Failed to upload avatar'}, 500
                
                # Get public URL
                avatar_url = supabase.storage.from_('user-avatars').get_public_url(filename)
                
                # Update user profile with avatar URL
                profile_update = {'avatar_url': avatar_url}
                update_response = supabase.table('user').update(profile_update).eq('id', user_id).execute()
                
                if hasattr(update_response, 'error') and update_response.error:
                    logger.error(f"Profile update error: {update_response.error}")
                    return {'message': 'Failed to update profile with avatar URL'}, 500
                
                return {
                    'message': 'Avatar uploaded successfully',
                    'avatar_url': avatar_url
                }, 200
                
            except Exception as img_error:
                logger.error(f"Image processing error: {img_error}")
                return {'message': 'Invalid image format'}, 400
                
        except Exception as e:
            logger.error(f"Avatar upload error: {str(e)}", exc_info=True)
            return {'message': f'Error uploading avatar: {str(e)}'}, 500