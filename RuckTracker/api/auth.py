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
        """Register a new user and create their corresponding record in the user table""" 
        try:
            data = request.get_json()
            email = data.get('email')
            password = data.get('password')
            username = data.get('username')
            
            if not email or not password or not username: 
                return {'message': 'Username, email, and password are required'}, 400
                
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
                    'username': username,
                    # 'email': email, # <<< REMOVED: Email only stored in auth.users >>>
                    'weight_kg': data.get('weight_kg'),
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
                     
                logger.warning(error_message)
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
            allowed_fields = ['username', 'weight_kg', 'prefer_metric'] 
            for field in allowed_fields:
                if field == 'prefer_metric': # Check for snake_case field name
                    # Expect camelCase 'preferMetric' in the incoming JSON data for updates too
                    if 'preferMetric' in data:
                         update_data['prefer_metric'] = data['preferMetric'] # Use snake_case for DB update dict key
                elif field in data:
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