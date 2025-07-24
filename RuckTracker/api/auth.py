from flask import g, request
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
from services.mailjet_service import sync_user_to_mailjet

logger = logging.getLogger(__name__)

# Auth decorators
def auth_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not hasattr(g, 'user') or g.user is None:
            logger.warning(f"Authentication failed for {request.path}: No user in context")
            return {'message': 'Authentication required', 'error': 'no_user'}, 401
        
        if not hasattr(g, 'user_id') or g.user_id is None:
            logger.warning(f"Authentication failed for {request.path}: No user_id in context")
            return {'message': 'Authentication required', 'error': 'no_user_id'}, 401
            
        return f(*args, **kwargs)
    return decorated

def get_user_id():
    """Helper function to get the current user's ID"""
    if hasattr(g, 'user_id') and g.user_id:
        return g.user_id
    elif hasattr(g, 'user') and g.user and hasattr(g.user, 'id'):
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
                
                # Check if user was created by trigger (new approach)
                admin_supabase = get_supabase_admin_client()
                
                # Wait briefly for trigger to complete
                import time
                time.sleep(0.1)  # Give trigger time to complete
                
                # Check if user already exists (created by trigger)
                try:
                    existing_user = admin_supabase.table('user').select('*').eq('id', str(user_id)).execute()
                    
                    if existing_user.data and len(existing_user.data) > 0:
                        # User exists - update with additional data from registration
                        logger.info(f"User {user_id} already exists (created by trigger), updating with registration data")
                        
                        update_data = {}
                        if data.get('weight_kg'):
                            update_data['weight_kg'] = data.get('weight_kg')
                        if data.get('height_cm'):
                            update_data['height_cm'] = data.get('height_cm')
                        if data.get('date_of_birth'):
                            update_data['date_of_birth'] = data.get('date_of_birth')
                        if data.get('gender'):
                            update_data['gender'] = data.get('gender')
                        if data.get('preferMetric') is not None:
                            update_data['prefer_metric'] = data.get('preferMetric')
                        if username:
                            update_data['username'] = username
                        
                        if update_data:
                            user_insert_response = admin_supabase.table('user').update(update_data).eq('id', str(user_id)).execute()
                        else:
                            user_insert_response = existing_user
                    else:
                        # User doesn't exist - create manually (fallback)
                        logger.warning(f"User {user_id} not created by trigger, creating manually")
                        user_data = {
                            'id': str(user_id), 
                            'username': username,
                            'email': email,
                            'weight_kg': data.get('weight_kg'),
                            'height_cm': data.get('height_cm'),
                            'date_of_birth': data.get('date_of_birth'),
                            'gender': data.get('gender'),
                            'prefer_metric': data.get('preferMetric', True)
                        }
                        user_data_clean = {k: v for k, v in user_data.items() if v is not None}
                        user_insert_response = admin_supabase.table('user').insert(user_data_clean).execute()
                        
                except Exception as user_insert_err:
                    db_error_message = str(user_insert_err)
                    logger.error(f"Error handling user record for user {user_id}: {db_error_message}", exc_info=True)
                    
                    # Check if it's a duplicate/conflict error (common patterns)
                    is_duplicate_error = any([
                        "duplicate key" in db_error_message.lower(),
                        "already exists" in db_error_message.lower(),
                        "409" in db_error_message,
                        "conflict" in db_error_message.lower(),
                        "unique constraint" in db_error_message.lower(),
                        "violates unique constraint" in db_error_message.lower()
                    ])
                    
                    if is_duplicate_error:
                        logger.info(f"User {user_id} already exists (duplicate/conflict), continuing with success response")
                        # Get the existing user data
                        try:
                            existing_user = admin_supabase.table('user').select('*').eq('id', str(user_id)).execute()
                            user_insert_response = existing_user
                        except Exception as fetch_err:
                            logger.error(f"Failed to fetch existing user {user_id}: {fetch_err}")
                            # Create a minimal response if we can't fetch the user
                            user_insert_response = type('obj', (object,), {'data': [{'id': str(user_id), 'email': email, 'username': username}]})
                    else:
                        # Real error - delete auth user and return error
                        logger.critical(f"CRITICAL: Real error creating user record for {user_id}: {db_error_message}")
                        logger.critical(f"CRITICAL: User signup failed - Error type: USER_CREATION_FAILED, User ID: {user_id}, Error: {db_error_message}")
                        try:
                            logger.warning(f"Attempting to delete auth user {user_id} due to user record creation failure.")
                            admin_supabase.auth.admin.delete_user(user_id)
                        except Exception as delete_err:
                            logger.error(f"Failed to delete auth user {user_id} after insert failure: {delete_err}", exc_info=True)
                        return {'message': f'User created in auth, but failed to create user record: {db_error_message}'}, 500
                
                logger.info(f"Successfully handled user record for user {user_id}")
                
                # Sync user to Mailjet for email marketing
                try:
                    from datetime import datetime
                    user_metadata = {
                        'user_id': str(user_id),
                        'signup_date': datetime.now().strftime('%d/%m/%Y'),
                        'signup_source': 'mobile_app',
                        'name': username,  # Full name/username for Mailjet 'name' field
                        'firstname': username.split(' ')[0] if username else username  # First name extracted
                    }
                    
                    # Add additional metadata from registration data
                    if data.get('gender'):
                        user_metadata['gender'] = data.get('gender')
                    if data.get('date_of_birth'):
                        user_metadata['date_of_birth'] = data.get('date_of_birth')
                    
                    mailjet_success = sync_user_to_mailjet(
                        email=email,
                        username=username,
                        user_metadata=user_metadata
                    )
                    
                    if mailjet_success:
                        logger.info(f"✅ User {email} successfully synced to Mailjet")
                    else:
                        logger.warning(f"⚠️ Failed to sync user {email} to Mailjet (non-blocking)")
                        
                except Exception as mailjet_err:
                    logger.error(f"❌ Mailjet sync error for {email}: {mailjet_err}")
                    # Don't fail the registration if Mailjet sync fails
                    
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
        logger.debug("SignInResource POST method called")
        try:
            data = request.get_json()
            email = data.get('email')
            password = data.get('password')
            
            if not email or not password:
                logger.warning("Login attempt with missing email or password")
                return {'message': 'Email and password are required'}, 400
                
            # Sign in with Supabase
            supabase = get_supabase_client()
            
            try:
                auth_response = supabase.auth.sign_in_with_password({
                    "email": email,
                    "password": password,
                })
                
                if not auth_response or not hasattr(auth_response, 'user') or not auth_response.user:
                    logger.warning(f"Invalid credentials for email: {email}")
                    return {'message': 'Invalid email or password'}, 401
                
                # Convert user model to a JSON-serializable dictionary
                user_data = auth_response.user.model_dump(mode='json')
                logger.info(f"User {user_data.get('id')} logged in successfully")
                
                return {
                    'token': auth_response.session.access_token if auth_response.session else None,
                    'refresh_token': auth_response.session.refresh_token if auth_response.session else None,
                    'user': user_data
                }, 200
                
            except Exception as auth_error:
                # Handle specific Supabase auth errors
                error_msg = str(auth_error).lower()
                if 'wrong password' in error_msg or 'email not confirmed' in error_msg:
                    logger.warning(f"Authentication failed for {email}: {error_msg}")
                    return {'message': 'Invalid email or password'}, 401
                if 'too many requests' in error_msg:
                    logger.warning(f"Rate limited login attempt for {email}")
                    return {'message': 'Too many login attempts. Please try again later.'}, 429
                
                # Re-raise unexpected errors to be caught by the outer try/except
                raise
                
        except Exception as e:
            logger.error(f"Unexpected error during signin: {str(e)}", exc_info=True)
            return {'message': 'An unexpected error occurred during sign in. Please try again.'}, 500

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
            
            try:
                auth_response = supabase.auth.refresh_session(refresh_token)
                
                # Check if we got a valid response with a session
                if auth_response and auth_response.session:
                    # Convert user model to a JSON-serializable dictionary
                    user_data = auth_response.user.model_dump(mode='json') if auth_response.user else None
                    
                    return {
                        'token': auth_response.session.access_token,
                        'refresh_token': auth_response.session.refresh_token,
                        'user': user_data
                    }, 200
                else:
                    logger.error("Invalid auth response or no session in refresh token response")
                    return {'message': 'Invalid refresh token'}, 401
                    
            except Exception as auth_error:
                # Check if this is a rate limit error
                error_message = str(auth_error)
                if '429' in error_message or 'Too Many Requests' in error_message:
                    logger.warning(f"Rate limit hit for refresh token: {error_message}")
                    return {'message': 'Too many requests. Please try again later.'}, 429
                else:
                    logger.error(f"Supabase auth error during refresh: {error_message}")
                    return {'message': 'Authentication service error'}, 503
                
        except Exception as e:
            logger.error(f"Unexpected error in refresh token: {str(e)}")
            return {'message': f'Error refreshing token: {str(e)}'}, 500

class ForgotPasswordResource(Resource):
    def post(self):
        """Trigger password reset email using Supabase"""
        try:
            data = request.get_json()
            email = data.get('email')
            if not email:
                logger.warning("Password reset attempt with no email provided")
                return {'message': 'Email is required'}, 400
                
            # Use our web callback endpoint that will redirect to the mobile app
            # This ensures Supabase uses a proper HTTPS URL instead of a custom scheme
            callback_url = 'https://getrucky.com/auth/callback'
            
            logger.info(f"Sending password reset email to {email} with callback URL: {callback_url}")
            
            # Get the Supabase client
            supabase = get_supabase_client()
            
            # Send the password reset email with the web callback URL
            # This will redirect to our /auth/callback endpoint which handles mobile app redirect
            response = supabase.auth.reset_password_email(
                email=email,
                options={
                    'redirect_to': callback_url,
                    'data': {
                        'email': email,
                        'app_name': 'RuckTracker'
                    }
                }
            )
            
            # Log the response for debugging
            logger.debug(f"Password reset response: {response}")
            
            # Check for errors in the response
            if hasattr(response, 'error') and response.error:
                logger.error(f"Error sending password reset email to {email}: {response.error.message}")
            else:
                logger.info(f"Password reset email sent to {email}")
                
                # The actual sending of the email is handled by Supabase
                return {
                    'message': 'If an account exists for this email, a password reset link has been sent.',
                    'email_sent': True
                }, 200
            
            # If we get here, something went wrong but we don't want to leak info
            logger.warning(f"Unexpected response from reset_password_email: {response}")
            return {
                'message': 'If an account exists for this email, a password reset link has been sent.',
                'email_sent': True
            }, 200
            
        except Exception as e:
            logger.error(f"Unexpected error during password reset for {email}: {str(e)}", exc_info=True)
            # Still return success to avoid email enumeration
            return {
                'message': 'If an account exists for this email, a password reset link has been sent.',
                'email_sent': True
            }, 200

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
            # Enhanced debugging for Google Auth users
            logger.info(f"Profile update request - User: {getattr(g, 'user', None)}")
            logger.info(f"Has access_token: {hasattr(g, 'access_token') and g.access_token is not None}")
            logger.info(f"Authorization header: {request.headers.get('Authorization', 'None')[:50]}...")
            
            if not hasattr(g, 'user') or g.user is None:
                logger.error("Profile update failed: User not authenticated - no g.user")
                return {'message': 'User not authenticated'}, 401
                
            data = request.get_json()
            if not data:
                logger.error("Profile update failed: No update data provided")
                return {'message': 'No update data provided'}, 400
                
            logger.info(f"Profile update data received: {list(data.keys())}")
                 
            update_data = {}
            # Assuming these fields exist in the new 'user' model
            allowed_fields = ['username', 'weight_kg', 'prefer_metric', 'height_cm', 'allow_ruck_sharing', 'gender', 'date_of_birth', 'avatar_url', 'notification_clubs', 'notification_buddies', 'notification_events', 'notification_duels']
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
                # Handle notification preferences (all expect snake_case keys)
                elif field in ['notification_clubs', 'notification_buddies', 'notification_events', 'notification_duels']:
                    if field in data:
                        update_data[field] = data[field]
                elif field in data:
                    update_data[field] = data[field]
                 
            if not update_data:
                 return {'message': 'No valid fields provided for update'}, 400

            logger.debug(f"Authenticated user id: {g.user.id}")
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # First check if user profile exists
            logger.info(f"Checking if user profile exists for user ID: {g.user.id}")
            try:
                existing_response = supabase.table('user').select('id').eq('id', str(g.user.id)).execute()
                logger.info(f"Profile existence check result: {len(existing_response.data) if existing_response.data else 0} records found")
            except Exception as profile_check_error:
                logger.error(f"RLS Error during profile existence check for {g.user.id}: {str(profile_check_error)}")
                # If we can't check existence due to RLS, assume it doesn't exist and try to create
                existing_response = type('obj', (object,), {'data': []})()
            
            if not existing_response.data or len(existing_response.data) == 0:
                # User profile doesn't exist - create it first (common for Google Auth users)
                logger.info(f"User profile not found for {g.user.id}, creating before update")
                create_data = {
                    'id': str(g.user.id),
                    'email': getattr(g.user, 'email', ''),
                    'username': update_data.get('username', ''),
                    'prefer_metric': update_data.get('prefer_metric', True),
                    'weight_kg': update_data.get('weight_kg', 70.0),
                    'created_at': 'now()',
                    'updated_at': 'now()'
                }
                # Add any other fields from update_data
                for field, value in update_data.items():
                    if field not in create_data:
                        create_data[field] = value
                        
                insert_response = supabase.table('user').insert(create_data).execute()
                logger.info(f"Created user profile for {g.user.id} during avatar update")
                
                if not insert_response.data or len(insert_response.data) == 0:
                    logger.error(f"Profile creation failed during update for user ID {g.user.id}")
                    return {'message': 'Failed to create user profile'}, 500
                    
                profile_data = insert_response.data[0]
            else:
                # User profile exists - update it
                logger.debug(f"Updating existing profile for {g.user.id} with: {update_data}")
                response = supabase.table('user') \
                    .update(update_data) \
                    .eq('id', str(g.user.id)) \
                    .execute()
                logger.debug(f"Update response: {response.__dict__}")
                
                # Fetch the updated data
                fetch_response = supabase.table('user').select('*').eq('id', str(g.user.id)).execute()
                
                if not fetch_response.data or len(fetch_response.data) == 0:
                    logger.error(f"Profile update seemed successful but failed to fetch updated data for user ID {g.user.id}")
                    return {'message': 'Profile update may have succeeded, but failed to retrieve updated data.'}, 500
                    
                profile_data = fetch_response.data[0]
            
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
            
    def post(self):
        """Create new user profile (primarily for Google OAuth users)"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
                
            data = request.get_json()
            if not data:
                return {'message': 'No profile data provided'}, 400
                
            # Check if user profile already exists by ID OR email
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            user_email = getattr(g.user, 'email', data.get('email'))
            
            # Check by ID first
            existing_by_id = supabase.table('user') \
                .select('id, email') \
                .eq('id', str(g.user.id)) \
                .execute()
                
            # Check by email to prevent duplicate emails
            existing_by_email = supabase.table('user') \
                .select('id, email') \
                .eq('email', user_email) \
                .execute()
                
            if existing_by_id.data and len(existing_by_id.data) > 0:
                logger.info(f"User profile already exists for ID: {g.user.id}, updating instead")
                return self.put()
                
            if existing_by_email.data and len(existing_by_email.data) > 0:
                existing_user = existing_by_email.data[0]
                logger.warning(f"User profile already exists for email: {user_email} with different ID: {existing_user['id']}. This suggests an orphaned user or auth/user table mismatch.")
                
                # Critical decision: Should we update the existing user or return an error?
                # For now, return an error to prevent data corruption
                return {
                    'message': f'A user profile already exists for this email address. Please contact support if you believe this is an error.',
                    'error': 'duplicate_email',
                    'existing_user_id': existing_user['id']
                }, 409
                
            # Create new user profile
            create_data = {
                'id': str(g.user.id),
                'email': getattr(g.user, 'email', data.get('email')),
                'username': data.get('username', ''),
                'prefer_metric': data.get('is_metric', True),  # Google users get 'is_metric' field
                'weight_kg': 70.0,  # Default weight
                'created_at': 'now()',
                'updated_at': 'now()'
            }
            
            logger.info(f"Creating new user profile for Google OAuth user: {g.user.id}")
            logger.debug(f"Profile data: {create_data}")
            
            insert_response = supabase.table('user').insert(create_data).execute()
            
            if not insert_response.data or len(insert_response.data) == 0:
                logger.error(f"Profile creation failed - no data returned for user ID {g.user.id}")
                return {'message': 'Failed to create user profile'}, 500
                
            profile_data = insert_response.data[0]
            logger.info(f"Successfully created user profile for Google OAuth user: {g.user.id}")
            
            # Sync Google OAuth user to Mailjet for email marketing
            try:
                from datetime import datetime
                user_email = getattr(g.user, 'email', data.get('email'))
                username = data.get('username', '')
                
                user_metadata = {
                    'user_id': str(g.user.id),
                    'signup_date': datetime.now().strftime('%d/%m/%Y'),
                    'signup_source': 'google_oauth',
                    'name': username,  # Full name/username for Mailjet 'name' field
                    'firstname': username.split(' ')[0] if username else username  # First name extracted
                }
                
                mailjet_success = sync_user_to_mailjet(
                    email=user_email,
                    username=username,
                    user_metadata=user_metadata
                )
                
                if mailjet_success:
                    logger.info(f"✅ Google OAuth user {user_email} successfully synced to Mailjet")
                else:
                    logger.warning(f"⚠️ Failed to sync Google OAuth user {user_email} to Mailjet (non-blocking)")
                    
            except Exception as mailjet_err:
                logger.error(f"❌ Mailjet sync error for Google OAuth user {user_email}: {mailjet_err}")
                # Don't fail the profile creation if Mailjet sync fails
            
            return profile_data, 201
            
        except Exception as e:
            logger.error(f"Error creating user profile: {str(e)}", exc_info=True)
            return {'message': f'Error creating user profile: {str(e)}'}, 500


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