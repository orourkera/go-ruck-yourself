from flask import request, g
from flask_restful import Resource
import uuid
from datetime import datetime, timedelta
import sys
import logging

from ..supabase_client import get_supabase_client, get_supabase_admin_client

logger = logging.getLogger(__name__)

class SignUpResource(Resource):
    def post(self):
        """Register a new user and create their profile"""
        try:
            data = request.get_json()
            email = data.get('email')
            password = data.get('password')
            
            if not email or not password:
                return {'message': 'Email and password are required'}, 400
                
            # Create user in Supabase Auth
            supabase = get_supabase_client()
            auth_response = supabase.auth.sign_up({
                "email": email,
                "password": password,
                # Note: Supabase Auth sign_up doesn't take arbitrary options like name here
            })
            
            if auth_response.user:
                user_id = auth_response.user.id # Get the ID of the newly created auth user
                
                # Create profile in the public.profiles table using ADMIN client to bypass RLS
                profile_data = {
                    'id': user_id, # Link to auth.users
                    'name': data.get('name'),
                    'weight_kg': data.get('weight_kg'),
                    'height_cm': data.get('height_cm'),
                    'preferMetric': data['preferMetric'] if 'preferMetric' in data else False
                }
                # Clean data - remove None values before insert
                profile_data_clean = {k: v for k, v in profile_data.items() if v is not None}
                
                logger.debug(f"Inserting into profiles for user {user_id}: {profile_data_clean}")
                try:
                    admin_supabase = get_supabase_admin_client() # Get admin client
                    profile_response = admin_supabase.table('profiles').insert(profile_data_clean).execute()
                except Exception as profile_insert_err:
                    logger.error(f"Error inserting profile using admin client for user {user_id}: {profile_insert_err}", exc_info=True)
                    # Consider deleting the auth user here for consistency?
                    # supabase.auth.admin.delete_user(user_id) # Requires admin client again
                    return {'message': f'User created in auth, but failed to create profile: {profile_insert_err}'}, 500
                
                logger.info(f"Successfully created profile for user {user_id}")
                
                # Convert user model to a JSON-serializable dictionary
                user_response_data = auth_response.user.model_dump(mode='json') if auth_response.user else None
                
                # Optionally merge profile data into response if needed by client immediately
                if user_response_data and profile_response.data:
                    # Add profile fields to the user dict sent back
                    # Be careful not to overwrite fields from auth like 'id', 'email', 'created_at'
                    profile_details = profile_response.data[0]
                    user_response_data['name'] = profile_details.get('name')
                    user_response_data['weight_kg'] = profile_details.get('weight_kg')
                    user_response_data['height_cm'] = profile_details.get('height_cm')
                    user_response_data['preferMetric'] = profile_details.get('preferMetric')
                
                return {
                    'message': 'User registered successfully',
                    'token': auth_response.session.access_token if auth_response.session else None,
                    'user': user_response_data
                }, 201
            else:
                # Handle case where auth_response.user is None (e.g., email already exists)
                error_message = "Failed to register user"
                if hasattr(auth_response, 'error') and auth_response.error:
                     error_message += f": {auth_response.error.message}"
                elif hasattr(auth_response, 'message') and auth_response.message: # Sometimes error is in message
                     error_message += f": {auth_response.message}"
                logger.warning(error_message)
                # Return 409 Conflict if email likely exists
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
            response = supabase.auth.reset_password_email(email)
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
            supabase = get_supabase_client(user_jwt=getattr(g.user, 'token', None))
            response = supabase.table('user') \
                .select('*') \
                .eq('id', str(g.user.id)) \
                .maybe_single() \
                .execute()
                
            profile_data = {}
            if response.data:
                logger.debug(f"Profile data found in 'user' table: {response.data}")
                profile_data = response.data
            else:
                logger.warning(f"User profile not found in 'user' table for ID: {g.user.id}")
                # Still return basic info if profile row is missing

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
                        auth_user_resp = supabase.auth.get_user(jwt=getattr(g.user, 'token', None))
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
            allowed_fields = ['name', 'weight_kg', 'height_cm', 'preferMetric', 'sex', 'date_of_birth'] 
            for field in allowed_fields:
                if field in data:
                    # Basic type validation/conversion could be added here
                    update_data[field] = data[field]
                 
            if not update_data:
                 return {'message': 'No valid fields provided for update'}, 400

            logger.debug(f"Authenticated user id: {g.user.id}")
            logger.debug(f"Attempting update on 'user' table where id = {g.user.id} with: {update_data}")
            supabase = get_supabase_client(user_jwt=getattr(g.user, 'token', None))
            # Only allow updating the row where id = g.user.id
            response = supabase.table('user') \
                .update(update_data) \
                .eq('id', str(g.user.id)) \
                .execute()
            logger.debug(f"Update response: {response.__dict__}")
            
            # After update/insert, fetch the complete user data to return
            fetch_response = supabase.table('user').select('*').eq('id', str(g.user.id)).maybe_single().execute()

            if fetch_response.data:
                logger.debug(f"Profile updated/fetched successfully: {fetch_response.data}")
                # Ensure email from auth is included if missing
                if 'email' not in fetch_response.data or not fetch_response.data['email']:
                     if hasattr(g.user, 'email') and g.user.email:
                        fetch_response.data['email'] = g.user.email
                return fetch_response.data, 200
            else:
                 # This case should be less common if update worked, but handle it.
                 logger.error(f"Profile update seemed successful but failed to fetch updated data for user ID {g.user.id}")
                 return {'message': 'Profile update may have succeeded, but failed to retrieve updated data.'}, 500

        except Exception as e:
            logger.error(f"Error updating user profile: {str(e)}", exc_info=True)
            return {'message': f'Error updating user profile: {str(e)}'}, 500