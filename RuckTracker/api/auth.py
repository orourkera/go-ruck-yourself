import logging
from flask import request, jsonify, g
from flask_restful import Resource
import datetime
import os

from supabase_client import supabase

logger = logging.getLogger(__name__)

class SignUpResource(Resource):
    def post(self):
        """Register a new user with Supabase Auth"""
        try:
            data = request.get_json()
            
            # Validate required fields
            if not data.get('email') or not data.get('password'):
                return {'message': 'Email and password are required'}, 400
                
            # Register user with Supabase Auth
            response = supabase.auth.sign_up({
                'email': data.get('email'),
                'password': data.get('password'),
                'options': {
                    'data': {
                        'full_name': data.get('name', ''),
                        'display_name': data.get('display_name', data.get('name', '')),
                        'username': data.get('username', '')
                    }
                }
            })
            
            # Create profile record in the profiles table
            if response.user:
                # Create a profile in the profiles table
                profile_data = {
                    'id': response.user.id,
                    'username': data.get('username', response.user.email.split('@')[0]),
                    'display_name': data.get('display_name', data.get('name', '')),
                    'full_name': data.get('name', ''),
                    'avatar_url': '',
                    'weight_kg': data.get('weight_kg'),
                    'prefer_metric': data.get('prefer_metric', False)
                }
                
                try:
                    # Now that we have the user, we can create the profile
                    supabase.from_('profiles').insert(profile_data).execute()
                except Exception as profile_error:
                    logger.error(f"Error creating profile: {str(profile_error)}")
                    # Continue with signup even if profile creation fails
                
                # Format response to match the expected format from the original API
                user_dict = {
                    'id': response.user.id,
                    'email': response.user.email,
                    'username': data.get('username', response.user.email.split('@')[0]),
                    'display_name': data.get('display_name', data.get('name', '')),
                    'weight_kg': data.get('weight_kg'),
                    'prefer_metric': data.get('prefer_metric', False)
                }
                
                # Get the token
                token = response.session.access_token if response.session else ""
                
                return {
                    'token': token,
                    'user': user_dict
                }, 201
            
            # Fallback to the original format
            return {
                'user': response.user.model_dump() if response.user else None,
                'session': response.session.model_dump() if response.session else None
            }, 201
        except Exception as e:
            logger.error(f"Error during signup: {str(e)}")
            return {'message': f'Error during signup: {str(e)}', 'error_type': type(e).__name__}, 500

class SignInResource(Resource):
    def post(self):
        """Sign in an existing user with Supabase Auth"""
        try:
            data = request.get_json()
            
            # Validate required fields
            if not data.get('email') or not data.get('password'):
                return {'message': 'Email and password are required'}, 400
                
            # Authenticate user with Supabase
            response = supabase.auth.sign_in_with_password({
                'email': data.get('email'),
                'password': data.get('password')
            })
            
            if response.user:
                try:
                    # Check if profile exists and create it if it doesn't
                    profile_response = supabase.table('profiles').select('*').eq('id', response.user.id).execute()
                    
                    if not profile_response.data:
                        # Profile doesn't exist, try to create it
                        profile_data = {
                            'id': response.user.id,
                            'username': response.user.user_metadata.get('username', response.user.email.split('@')[0]),
                            'full_name': response.user.user_metadata.get('full_name', ''),
                            'avatar_url': response.user.user_metadata.get('avatar_url', '')
                        }
                        
                        # Now that we're authenticated, we can create the profile
                        supabase.table('profiles').insert(profile_data).execute()
                        profile_response = supabase.table('profiles').select('*').eq('id', response.user.id).execute()
                except Exception as profile_error:
                    logger.error(f"Error checking/creating profile: {str(profile_error)}")
                    # Continue with login even if profile creation fails
                    profile_response = None
                
                # Get the user's metadata
                user_metadata = response.user.user_metadata
                display_name = user_metadata.get('display_name', '')
                
                # If no display_name in metadata, try to get it from the profile
                if not display_name and profile_response and profile_response.data:
                    display_name = profile_response.data[0].get('display_name', '')
                
                # Only as a last resort, use the email
                if not display_name:
                    display_name = response.user.email.split('@')[0]
                
                # Format response to match the expected format from the original API
                user_dict = {
                    'id': response.user.id,
                    'email': response.user.email,
                    'username': profile_response.data[0].get('username') if profile_response and profile_response.data else response.user.email.split('@')[0],
                    'display_name': display_name,
                    'weight_kg': profile_response.data[0].get('weight_kg') if profile_response and profile_response.data else None,
                    'prefer_metric': profile_response.data[0].get('prefer_metric', False) if profile_response and profile_response.data else False
                }
                
                # Get the token
                token = response.session.access_token if response.session else ""
                
                return {
                    'token': token,
                    'user': user_dict
                }, 200
            
            # Fallback to the original format
            return {
                'user': response.user.model_dump() if response.user else None,
                'session': response.session.model_dump() if response.session else None
            }, 200
        except Exception as e:
            logger.error(f"Error during signin: {str(e)}")
            return {'message': f'Error during signin: {str(e)}', 'error_type': type(e).__name__}, 401

class SignOutResource(Resource):
    def post(self):
        """Sign out the current user"""
        try:
            # The JWT is automatically used because it's in the auth header
            supabase.auth.sign_out()
            return {'message': 'Successfully signed out'}, 200
        except Exception as e:
            logger.error(f"Error during signout: {str(e)}")
            return {'message': f'Error during signout: {str(e)}', 'error_type': type(e).__name__}, 500

class RefreshTokenResource(Resource):
    def post(self):
        """Refresh the authentication token"""
        try:
            # The refresh token is automatically used because it's in the auth header
            response = supabase.auth.refresh_session()
            
            return {
                'token': response.session.access_token if response.session else None
            }, 200
        except Exception as e:
            logger.error(f"Error refreshing token: {str(e)}")
            return {'message': f'Error refreshing token: {str(e)}', 'error_type': type(e).__name__}, 401

class UserProfileResource(Resource):
    def get(self):
        """Get current user profile"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
                
            # Get profile data from the profiles table
            profile_response = supabase.table('profiles').select('*').eq('id', g.user.id).single().execute()
            
            # Get the user's metadata
            user_metadata = g.user.user_metadata or {}
            display_name = user_metadata.get('display_name', '')
            
            # If no display_name in metadata, try to get it from the profile
            if not display_name and profile_response and profile_response.data:
                display_name = profile_response.data.get('display_name', '')
            
            # Only as a last resort, use the email
            if not display_name:
                display_name = g.user.email.split('@')[0]
            
            # Get ruck sessions for the user to calculate statistics
            sessions_response = supabase.table('ruck_sessions').select('*').eq('user_id', g.user.id).execute()
            
            # Calculate statistics
            total_rucks = len(sessions_response.data) if sessions_response.data else 0
            total_distance_km = sum(session.get('distance_km', 0) for session in sessions_response.data) if sessions_response.data else 0
            total_calories = sum(session.get('calories_burned', 0) for session in sessions_response.data) if sessions_response.data else 0
            
            # Calculate this month's statistics
            now = datetime.datetime.now()
            start_of_month = datetime.datetime(now.year, now.month, 1).isoformat()
            
            this_month_sessions = [
                session for session in sessions_response.data
                if session.get('created_at') and session.get('created_at') >= start_of_month
            ] if sessions_response.data else []
            
            this_month_rucks = len(this_month_sessions)
            this_month_distance = sum(session.get('distance_km', 0) for session in this_month_sessions)
            this_month_calories = sum(session.get('calories_burned', 0) for session in this_month_sessions)
            
            # Format the response to match the expected format from the original API
            user_dict = {
                'id': g.user.id,
                'email': g.user.email,
                'username': profile_response.data.get('username') if profile_response.data else '',
                'display_name': display_name,
                'full_name': profile_response.data.get('full_name') if profile_response.data else '',
                'avatar_url': profile_response.data.get('avatar_url') if profile_response.data else '',
                'weight_kg': profile_response.data.get('weight_kg') if profile_response.data else None,
                'height_cm': profile_response.data.get('height_cm') if profile_response.data else None,
                'prefer_metric': profile_response.data.get('prefer_metric', False) if profile_response.data else False,
                'stats': {
                    'total_rucks': total_rucks,
                    'total_distance_km': float(total_distance_km),
                    'total_calories': total_calories,
                    'this_month': {
                        'rucks': this_month_rucks,
                        'distance_km': float(this_month_distance),
                        'calories': this_month_calories
                    }
                }
            }
            
            return user_dict, 200
        except Exception as e:
            logger.error(f"Error getting user profile: {str(e)}")
            return {'message': f'Error getting user profile: {str(e)}', 'error_type': type(e).__name__}, 500
            
    def put(self):
        """Update current user profile"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
                
            data = request.get_json()
            
            # Update profile data
            update_data = {
                'username': data.get('username'),
                'full_name': data.get('full_name'),
                'display_name': data.get('display_name'),
                'avatar_url': data.get('avatar_url'),
                'weight_kg': data.get('weight_kg'),
                'prefer_metric': data.get('prefer_metric')
            }
            
            # Remove None values
            update_data = {k: v for k, v in update_data.items() if v is not None}
            
            # Update profile in database
            response = supabase.table('profiles').update(update_data).eq('id', g.user.id).execute()
            
            # Try to update user metadata if display_name is provided
            if 'display_name' in data and data['display_name'] is not None:
                try:
                    # Update user metadata in auth
                    supabase.auth.admin.update_user_by_id(
                        g.user.id,
                        {'user_metadata': {'display_name': data['display_name']}}
                    )
                except Exception as metadata_error:
                    logger.error(f"Error updating user metadata: {str(metadata_error)}")
                    # Continue even if metadata update fails
            
            # Get the updated user's metadata
            user_metadata = g.user.user_metadata or {}
            display_name = data.get('display_name') or user_metadata.get('display_name', '')
            
            # If still no display_name, try to get it from the updated profile
            if not display_name and response.data:
                display_name = response.data[0].get('display_name', '')
            
            # Format the response to match the expected format from the original API
            user_dict = {
                'id': g.user.id,
                'email': g.user.email,
                'username': response.data[0].get('username') if response.data else data.get('username'),
                'display_name': display_name,
                'full_name': response.data[0].get('full_name') if response.data else data.get('full_name'),
                'avatar_url': response.data[0].get('avatar_url') if response.data else data.get('avatar_url'),
                'weight_kg': response.data[0].get('weight_kg') if response.data else data.get('weight_kg'),
                'prefer_metric': response.data[0].get('prefer_metric', False) if response.data else data.get('prefer_metric', False)
            }
            
            return user_dict, 200
        except Exception as e:
            logger.error(f"Error updating user profile: {str(e)}")
            return {'message': f'Error updating user profile: {str(e)}', 'error_type': type(e).__name__}, 500 