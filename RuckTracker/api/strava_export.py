import logging
import requests as http_requests
from datetime import datetime
from flask import g
from flask_restful import Resource, request
from RuckTracker.supabase_client import get_supabase_client
from RuckTracker.api.auth import auth_required

logger = logging.getLogger(__name__)

class StravaExportResource(Resource):
    @auth_required
    def post(self, session_id):
        """Export a completed ruck session to Strava"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401

            # Get session data from database
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Fetch the session
            session_resp = supabase.table('ruck_session').select(
                'id, user_id, duration_seconds, distance_km, elevation_gain_m, '
                'elevation_loss_m, calories_burned, ruck_weight_kg, started_at, '
                'completed_at, avg_heart_rate, max_heart_rate'
            ).eq('id', session_id).eq('user_id', g.user.id).execute()
            
            if not session_resp.data:
                return {'message': 'Session not found'}, 404
                
            session = session_resp.data[0]
            
            # Check if session is completed
            if not session.get('completed_at'):
                return {'message': 'Session must be completed before exporting'}, 400
            
            # Get user's Strava tokens (correct table is 'user', not 'users')
            try:
                user_resp = supabase.table('user').select(
                    'strava_access_token, strava_refresh_token, strava_expires_at'
                ).eq('id', g.user.id).execute()
            except Exception as e:
                # Handle missing column/schema issues gracefully (e.g., 42703 undefined column)
                err = str(e)
                if '42703' in err or 'column' in err and 'strava_' in err:
                    logger.error(f"[STRAVA] Token columns missing: {err}")
                    return {
                        'success': False,
                        'message': 'Strava is not connected. Please re-authorize Strava from your profile settings.'
                    }, 400
                raise
            
            if not user_resp.data:
                return {'message': 'User profile not found'}, 404
                
            user_data = user_resp.data[0]
            access_token = user_data.get('strava_access_token')
            refresh_token = user_data.get('strava_refresh_token')
            expires_at = user_data.get('strava_expires_at')
            
            if not access_token or not refresh_token:
                return {
                    'success': False,
                    'message': 'Strava not connected. Please re-authorize Strava in your profile.'
                }, 400
            
            # Check if token needs refresh
            if expires_at is not None:
                # Support both BIGINT epoch seconds and ISO8601 strings just in case
                try:
                    if isinstance(expires_at, (int, float)):
                        expires_ts = int(expires_at)
                    elif isinstance(expires_at, str):
                        # If it's all digits, treat as epoch seconds; otherwise parse ISO string
                        expires_ts = int(expires_at) if expires_at.isdigit() else int(datetime.fromisoformat(expires_at.replace('Z', '+00:00')).timestamp())
                    else:
                        expires_ts = 0
                except Exception:
                    # If parsing fails, force a refresh attempt
                    expires_ts = 0

                now_ts = int(datetime.now().timestamp())
                if now_ts >= (expires_ts - 300):  # Refresh 5 minutes early
                    logger.info(f"[STRAVA] Refreshing expired token for user {g.user.id}")
                    access_token = self._refresh_strava_token(user_data, supabase)
                    if not access_token:
                        return {'message': 'Failed to refresh Strava token. Please reconnect your account.'}, 400
            
            # Get request data
            request_data = request.get_json() or {}
            session_name = request_data.get('session_name', f'Ruck Session {session_id}')
            description = request_data.get('description', '')
            
            # Create Strava activity
            activity_id, duplicate = self._create_strava_activity(
                access_token=access_token,
                session=session,
                session_name=session_name,
                description=description
            )
            
            if activity_id:
                logger.info(f"[STRAVA] Successfully exported session {session_id} to Strava as activity {activity_id}")
                return {
                    'success': True,
                    'message': 'Session successfully exported to Strava',
                    'activity_id': activity_id
                }, 200
            if duplicate:
                logger.info(f"[STRAVA] Session {session_id} already exported previously (duplicate detected)")
                return {
                    'success': True,
                    'message': 'Session already exported to Strava',
                    'activity_id': None,
                    'duplicate': True
                }, 200
            else:
                return {'success': False, 'message': 'Failed to create Strava activity'}, 500
                
        except Exception as e:
            logger.error(f"[STRAVA] Error exporting session {session_id}: {str(e)}")
            return {'success': False, 'message': f'Export failed: {str(e)}'}, 500
    
    def _refresh_strava_token(self, user_data, supabase):
        """Refresh Strava access token"""
        try:
            import os
            
            strava_client_id = os.getenv('STRAVA_CLIENT_ID')
            strava_client_secret = os.getenv('STRAVA_CLIENT_SECRET')
            refresh_token = user_data.get('strava_refresh_token')
            
            if not all([strava_client_id, strava_client_secret, refresh_token]):
                logger.error("[STRAVA] Missing credentials for token refresh")
                return None
            
            # Refresh token request
            refresh_data = {
                'client_id': strava_client_id,
                'client_secret': strava_client_secret,
                'refresh_token': refresh_token,
                'grant_type': 'refresh_token'
            }
            
            response = http_requests.post(
                'https://www.strava.com/oauth/token',
                data=refresh_data,
                timeout=10
            )
            
            if response.status_code != 200:
                logger.error(f"[STRAVA] Token refresh failed: {response.status_code} - {response.text}")
                return None
            
            token_data = response.json()
            new_access_token = token_data.get('access_token')
            new_refresh_token = token_data.get('refresh_token')
            expires_at = token_data.get('expires_at')
            
            if not new_access_token:
                logger.error("[STRAVA] No access token in refresh response")
                return None
            
            # Update tokens in database (store BIGINT epoch seconds as per schema)
            try:
                # Correct table is 'user' not 'users'
                supabase.table('user').update({
                    'strava_access_token': new_access_token,
                    'strava_refresh_token': new_refresh_token,
                    'strava_expires_at': expires_at
                }).eq('id', g.user.id).execute()
            except Exception as db_err:
                err = str(db_err)
                if '42703' in err or ('column' in err and 'strava_' in err):
                    logger.error(f"[STRAVA] Token columns missing during refresh: {err}")
                    return None
                raise
            
            logger.info(f"[STRAVA] Successfully refreshed token for user {g.user.id}")
            return new_access_token
            
        except Exception as e:
            logger.error(f"[STRAVA] Error refreshing token: {str(e)}")
            return None
    
    def _create_strava_activity(self, access_token, session, session_name, description):
        """Create a Strava activity from session data
        Returns: (activity_id, duplicate)
        - activity_id: int|str|None
        - duplicate: bool (True if Strava reported a duplicate based on external_id)
        """
        try:
            # Parse timestamps
            started_at = session.get('started_at')
            if not started_at:
                logger.error("[STRAVA] Session missing started_at timestamp")
                return None, False

            # Normalize started_at to a datetime, supporting multiple formats
            start_time = None
            try:
                if isinstance(started_at, (int, float)):
                    # Epoch seconds
                    start_time = datetime.fromtimestamp(int(started_at))
                elif isinstance(started_at, str):
                    # Try ISO8601 first, fallback to epoch-in-string
                    s = started_at
                    try:
                        start_time = datetime.fromisoformat(s.replace('Z', '+00:00'))
                    except Exception:
                        start_time = datetime.fromtimestamp(int(s))
                elif isinstance(started_at, datetime):
                    start_time = started_at
                else:
                    logger.error(f"[STRAVA] Unsupported started_at type: {type(started_at)}")
                    return None, False
            except Exception as e:
                logger.error(f"[STRAVA] Failed to parse started_at ({started_at}): {e}")
                return None, False
            
            # Prepare activity data
            activity_data = {
                'name': session_name,
                'type': 'Hike',  # Strava activity type for rucking
                'start_date_local': start_time.isoformat(),
                'elapsed_time': int(session.get('duration_seconds', 0) or 0),
                'distance': float(session.get('distance_km', 0) or 0) * 1000,  # Convert km to meters
                'description': description,
                # Use deterministic external_id so repeated exports are deduped by Strava
                'external_id': f"ruck_session:{session.get('id')}"
            }
            
            # Add optional fields if available
            if session.get('elevation_gain_m'):
                activity_data['total_elevation_gain'] = session['elevation_gain_m']
            
            # Add ruck weight to description if not already included
            # Check for various weight indicators (kg, lbs, or weight emoji)
            ruck_weight = session.get('ruck_weight_kg', 0)
            desc_lower = description.lower()
            has_weight = any(indicator in desc_lower for indicator in ['kg', 'lbs', 'ruck weight', '⚖️'])
            
            if ruck_weight > 0 and not has_weight:
                if description:
                    description += f"\n\nRuck Weight: {ruck_weight:.1f}kg"
                else:
                    description = f"Ruck Weight: {ruck_weight:.1f}kg"
                activity_data['description'] = description
            
            # Add heart rate data if available
            if session.get('avg_heart_rate'):
                activity_data['average_heartrate'] = session['avg_heart_rate']
            if session.get('max_heart_rate'):
                activity_data['max_heartrate'] = session['max_heart_rate']
            
            logger.info(f"[STRAVA] Creating activity with data: {activity_data}")
            
            # Create activity via Strava API
            headers = {
                'Authorization': f'Bearer {access_token}',
                'Content-Type': 'application/json'
            }
            
            response = http_requests.post(
                'https://www.strava.com/api/v3/activities',
                json=activity_data,
                headers=headers,
                timeout=30
            )
            
            if response.status_code == 201:
                activity = response.json()
                activity_id = activity.get('id')
                logger.info(f"[STRAVA] Successfully created activity {activity_id}")
                return activity_id, False
            elif response.status_code == 409:
                # Duplicate detected by Strava due to same external_id
                logger.info(f"[STRAVA] Duplicate activity for session {session.get('id')} (409). Treating as already exported.")
                return None, True
            else:
                logger.error(f"[STRAVA] Failed to create activity: {response.status_code} - {response.text}")
                return None, False
                
        except Exception as e:
            logger.error(f"[STRAVA] Error creating Strava activity: {str(e)}")
            return None, False
