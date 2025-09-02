import logging
import requests as http_requests
import xml.etree.ElementTree as ET
import io
from datetime import datetime
from flask import g
from flask_restful import Resource, request
from RuckTracker.supabase_client import get_supabase_client
from RuckTracker.api.auth import auth_required
from typing import Dict, List, Any, Optional, Tuple

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
            
            # Fetch the session - handle both integer IDs and string offline IDs
            if str(session_id).startswith('offline_'):
                # For offline sessions, search by session_id field (string)
                session_resp = supabase.table('ruck_session').select(
                    'id, user_id, duration_seconds, distance_km, elevation_gain_m, '
                    'elevation_loss_m, calories_burned, ruck_weight_kg, started_at, '
                    'completed_at, avg_heart_rate, max_heart_rate, session_id'
                ).eq('session_id', session_id).eq('user_id', g.user.id).execute()
            else:
                # For regular sessions, search by integer id field
                try:
                    session_id_int = int(session_id)
                    session_resp = supabase.table('ruck_session').select(
                        'id, user_id, duration_seconds, distance_km, elevation_gain_m, '
                        'elevation_loss_m, calories_burned, ruck_weight_kg, started_at, '
                        'completed_at, avg_heart_rate, max_heart_rate'
                    ).eq('id', session_id_int).eq('user_id', g.user.id).execute()
                except (ValueError, TypeError):
                    # Invalid session ID format
                    return {'message': 'Invalid session ID format'}, 400
            
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
                logger.warning(f"[STRAVA_EXPORT] User {g.user.id} attempted export without Strava connection")
                return {
                    'success': False,
                    'message': 'Strava not connected. Please connect your Strava account in your profile settings and try again.',
                    'error_code': 'STRAVA_NOT_CONNECTED',
                    'action_required': 'connect_strava'
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
                        logger.warning(f"[STRAVA_EXPORT] Token refresh failed for user {g.user.id}")
                        return {
                            'success': False,
                            'message': 'Strava token expired. Please reconnect your Strava account in profile settings.',
                            'error_code': 'STRAVA_TOKEN_EXPIRED',
                            'action_required': 'reconnect_strava'
                        }, 400
            
            # Get request data
            request_data = request.get_json() or {}
            session_name = request_data.get('session_name', f'Ruck Session {session_id}')
            description = request_data.get('description', '')
            
            # Fetch location points and heart rate data for GPS route
            location_points = self._fetch_location_points(supabase, session_id)
            heart_rate_samples = self._fetch_heart_rate_samples(supabase, session_id)
            
            # Upload to Strava with GPS data if available, otherwise fallback to basic activity
            if location_points and len(location_points) > 2:
                logger.info(f"[STRAVA] Uploading GPS route with {len(location_points)} location points and {len(heart_rate_samples)} HR samples")
                activity_id, duplicate = self._upload_gpx_to_strava(
                    access_token=access_token,
                    session=session,
                    session_name=session_name,
                    description=description,
                    location_points=location_points,
                    heart_rate_samples=heart_rate_samples
                )
            else:
                logger.info("[STRAVA] No GPS data available, using basic activity creation")
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
            
            # Calculate additional metrics
            elapsed_time = int(session.get('duration_seconds', 0) or 0)
            paused_time = int(session.get('paused_duration_seconds', 0) or 0)
            moving_time = max(0, elapsed_time - paused_time)
            distance_meters = float(session.get('distance_km', 0) or 0) * 1000
            
            # Prepare activity data with ALL supported fields
            activity_data = {
                'name': session_name,
                'type': 'Hike',  # Strava activity type for rucking
                'start_date_local': start_time.isoformat(),
                'elapsed_time': elapsed_time,
                'distance': distance_meters,
                'description': description,
                # Use deterministic external_id so repeated exports are deduped by Strava
                'external_id': f"ruck_session:{session.get('id')}"
            }
            
            # Add moving_time if we have pause data
            if moving_time > 0 and moving_time != elapsed_time:
                activity_data['moving_time'] = moving_time
            
            # Add elevation data
            if session.get('elevation_gain_m'):
                activity_data['total_elevation_gain'] = float(session['elevation_gain_m'])
            
            # Add average speed (m/s) if we have distance and time
            if distance_meters > 0 and moving_time > 0:
                average_speed = distance_meters / moving_time  # m/s
                activity_data['average_speed'] = average_speed
            
            # Add heart rate data if available
            if session.get('avg_heart_rate'):
                activity_data['average_heartrate'] = float(session['avg_heart_rate'])
            if session.get('max_heart_rate'):
                activity_data['max_heartrate'] = float(session['max_heart_rate'])
            
            # Add calories if available
            if session.get('calories_burned'):
                activity_data['calories'] = float(session['calories_burned'])
            
            # Generate fun AI summary for description instead of technical details
            # (Technical metrics are now sent as structured data to Strava)
            if not description or description.strip() == "":
                # Generate a motivational summary if no custom description provided
                description = self._generate_fun_summary(session, distance_meters, elapsed_time, moving_time)
                activity_data['description'] = description
            
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
            
    def _fetch_location_points(self, supabase, session_id: int) -> List[Dict[str, Any]]:
        """Fetch location points for the session from the database."""
        try:
            # Query location_point table for this session
            location_resp = supabase.table('location_point').select(
                'latitude, longitude, altitude, timestamp'
            ).eq('session_id', session_id).order('timestamp').execute()
            
            if location_resp.data:
                logger.info(f"[STRAVA] Found {len(location_resp.data)} location points for session {session_id}")
                return location_resp.data
            else:
                logger.info(f"[STRAVA] No location points found for session {session_id}")
                return []
        except Exception as e:
            logger.error(f"[STRAVA] Error fetching location points: {e}")
            return []
    
    def _fetch_heart_rate_samples(self, supabase, session_id: int) -> List[Dict[str, Any]]:
        """Fetch heart rate samples for the session from the database."""
        try:
            # Query heart_rate_sample table for this session
            hr_resp = supabase.table('heart_rate_sample').select(
                'heart_rate, timestamp'
            ).eq('session_id', session_id).order('timestamp').execute()
            
            if hr_resp.data:
                logger.info(f"[STRAVA] Found {len(hr_resp.data)} heart rate samples for session {session_id}")
                return hr_resp.data
            else:
                logger.info(f"[STRAVA] No heart rate samples found for session {session_id}")
                return []
        except Exception as e:
            logger.error(f"[STRAVA] Error fetching heart rate samples: {e}")
            return []
    
    def _generate_gpx_content(self, session: Dict[str, Any], session_name: str, description: str, location_points: List[Dict[str, Any]]) -> str:
        """Generate GPX XML content from session data and location points."""
        # Create root GPX element with proper Strava-compatible creator
        gpx = ET.Element('gpx')
        gpx.set('version', '1.1')
        # Use proper device name format that Strava recognizes + barometer indicator
        gpx.set('creator', 'Rucking App with barometer')
        gpx.set('xmlns', 'http://www.topografix.com/GPX/1/1')
        gpx.set('xmlns:xsi', 'http://www.w3.org/2001/XMLSchema-instance')
        gpx.set('xmlns:gpxtpx', 'http://www.garmin.com/xmlschemas/TrackPointExtensionv1.xsd')
        gpx.set('xsi:schemaLocation', 'http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd http://www.garmin.com/xmlschemas/TrackPointExtensionv1.xsd http://www.garmin.com/xmlschemas/TrackPointExtensionv1.xsd')
        
        # Add metadata
        metadata = ET.SubElement(gpx, 'metadata')
        
        name_elem = ET.SubElement(metadata, 'name')
        name_elem.text = session_name
        
        desc_elem = ET.SubElement(metadata, 'desc')
        desc_elem.text = description
        
        time_elem = ET.SubElement(metadata, 'time')
        started_at = session.get('started_at')
        if started_at:
            if isinstance(started_at, str):
                time_elem.text = started_at
            else:
                time_elem.text = started_at.isoformat() + 'Z'
        else:
            time_elem.text = datetime.utcnow().isoformat() + 'Z'
        
        # Add track
        trk = ET.SubElement(gpx, 'trk')
        
        trk_name = ET.SubElement(trk, 'name')
        trk_name.text = session_name
        
        trk_type = ET.SubElement(trk, 'type')
        trk_type.text = 'Hike'  # Strava activity type
        
        # Add track segment
        trkseg = ET.SubElement(trk, 'trkseg')
        
        # Create a mapping of timestamps to heart rate values for efficient lookup
        hr_by_timestamp = {}
        if hasattr(self, '_current_hr_samples'):
            for hr_sample in self._current_hr_samples:
                hr_timestamp = hr_sample.get('timestamp')
                if hr_timestamp:
                    # Convert to comparable format
                    if isinstance(hr_timestamp, str):
                        hr_by_timestamp[hr_timestamp] = hr_sample.get('heart_rate')
                    else:
                        hr_by_timestamp[hr_timestamp.isoformat()] = hr_sample.get('heart_rate')
        
        for point in location_points:
            trkpt = ET.SubElement(trkseg, 'trkpt')
            trkpt.set('lat', str(point['latitude']))
            trkpt.set('lon', str(point['longitude']))
            
            # Add elevation if available
            if point.get('altitude'):
                ele = ET.SubElement(trkpt, 'ele')
                ele.text = str(point['altitude'])
            
            # Add timestamp
            point_timestamp = None
            if point.get('timestamp'):
                time_pt = ET.SubElement(trkpt, 'time')
                timestamp = point['timestamp']
                if isinstance(timestamp, str):
                    time_pt.text = timestamp
                    point_timestamp = timestamp
                else:
                    time_pt.text = timestamp.isoformat() + 'Z'
                    point_timestamp = timestamp.isoformat()
            
            # Add heart rate extension if available for this timestamp
            if point_timestamp and point_timestamp in hr_by_timestamp:
                heart_rate = hr_by_timestamp[point_timestamp]
                if heart_rate and heart_rate > 0:
                    # Add Garmin TrackPoint Extension for heart rate
                    extensions = ET.SubElement(trkpt, 'extensions')
                    tpx_elem = ET.SubElement(extensions, 'gpxtpx:TrackPointExtension')
                    hr_elem = ET.SubElement(tpx_elem, 'gpxtpx:hr')
                    hr_elem.text = str(int(heart_rate))
        
        # Convert to string
        return ET.tostring(gpx, encoding='unicode')
    
    def _upload_gpx_to_strava(self, access_token: str, session: Dict[str, Any], session_name: str, description: str, location_points: List[Dict[str, Any]], heart_rate_samples: List[Dict[str, Any]] = None) -> Tuple[Optional[int], bool]:
        """Upload GPX file to Strava and poll for completion."""
        try:
            # Generate fun AI summary for description if none provided
            if not description or description.strip() == "":
                distance_meters = float(session.get('distance_km', 0) or 0) * 1000
                elapsed_time = int(session.get('duration_seconds', 0) or 0)
                paused_time = int(session.get('paused_duration_seconds', 0) or 0)
                moving_time = max(0, elapsed_time - paused_time)
                description = self._generate_fun_summary(session, distance_meters, elapsed_time, moving_time)
            
            # Store heart rate samples for GPX generation
            self._current_hr_samples = heart_rate_samples or []
            
            # Generate GPX content with heart rate data
            gpx_content = self._generate_gpx_content(session, session_name, description, location_points)
            
            # Prepare upload data
            files = {
                'file': ('activity.gpx', gpx_content, 'application/gpx+xml'),
            }
            
            data = {
                'data_type': 'gpx',
                'name': session_name,
                'description': description,
                'activity_type': 'Hike',
                'external_id': f"ruck_session:{session.get('id')}",
            }
            
            headers = {
                'Authorization': f'Bearer {access_token}',
            }
            
            logger.info(f"[STRAVA] Uploading GPX file with {len(location_points)} points")
            
            # Upload to Strava
            response = http_requests.post(
                'https://www.strava.com/api/v3/uploads',
                files=files,
                data=data,
                headers=headers,
                timeout=30
            )
            
            if response.status_code == 201:
                upload_data = response.json()
                upload_id = upload_data.get('id')
                logger.info(f"[STRAVA] Upload started with ID: {upload_id}")
                
                # Poll for completion
                activity_id = self._poll_upload_status(access_token, upload_id)
                if activity_id:
                    return activity_id, False
                else:
                    logger.error("[STRAVA] Upload processing failed or timed out")
                    return None, False
            elif response.status_code == 409:
                # Duplicate detected
                logger.info(f"[STRAVA] Duplicate upload for session {session.get('id')} (409)")
                return None, True
            else:
                logger.error(f"[STRAVA] Upload failed: {response.status_code} - {response.text}")
                return None, False
                
        except Exception as e:
            logger.error(f"[STRAVA] Error uploading GPX: {str(e)}")
            return None, False
    
    def _poll_upload_status(self, access_token: str, upload_id: int, max_attempts: int = 12, delay: int = 5) -> Optional[int]:
        """Poll upload status until completion or timeout."""
        import time
        
        headers = {
            'Authorization': f'Bearer {access_token}',
        }
        
        for attempt in range(max_attempts):
            try:
                response = http_requests.get(
                    f'https://www.strava.com/api/v3/uploads/{upload_id}',
                    headers=headers,
                    timeout=10
                )
                
                if response.status_code == 200:
                    status_data = response.json()
                    status = status_data.get('status')
                    activity_id = status_data.get('activity_id')
                    error = status_data.get('error')
                    
                    logger.info(f"[STRAVA] Upload {upload_id} status: {status} (attempt {attempt + 1})")
                    
                    if status == 'Your activity is ready.':
                        return activity_id
                    elif status == 'There was an error processing your activity.':
                        logger.error(f"[STRAVA] Upload processing error: {error}")
                        return None
                    elif status in ['Your activity is still being processed.', 'Your activity is being processed.']:
                        if attempt < max_attempts - 1:
                            time.sleep(delay)
                            continue
                        else:
                            logger.error("[STRAVA] Upload processing timeout")
                            return None
                    else:
                        logger.warning(f"[STRAVA] Unknown upload status: {status}")
                        if attempt < max_attempts - 1:
                            time.sleep(delay)
                            continue
                else:
                    logger.error(f"[STRAVA] Status check failed: {response.status_code}")
                    return None
                    
            except Exception as e:
                logger.error(f"[STRAVA] Error checking upload status: {e}")
                if attempt < max_attempts - 1:
                    time.sleep(delay)
                    continue
                return None
        
        return None

    def _generate_fun_summary(self, session: Dict[str, Any], distance_meters: float, elapsed_time: int, moving_time: int) -> str:
        """Generate a fun, motivational summary for the Strava description."""
        import random
        
        # Get session metrics
        distance_km = distance_meters / 1000
        ruck_weight = session.get('ruck_weight_kg', 0)
        elevation_gain = session.get('elevation_gain_m', 0)
        calories = session.get('calories_burned', 0)
        
        # Calculate pace (min/km)
        pace_min_km = (moving_time / 60) / distance_km if distance_km > 0 else 0
        
        # Fun opening phrases
        openings = [
            "Crushed another ruck! 💪",
            "Pack on, head up, feet moving! 🎯",
            "Another day, another ruck conquered! 🔥",
            "Ruck life is the good life! 🎒",
            "Miles earned, not given! ⚡",
            "Heavy pack, light heart! ❤️",
            "Embracing the suck, loving the journey! 🚶‍♂️",
            "Ruck hard or go home! 💯"
        ]
        
        # Achievement highlights based on metrics
        achievements = []
        
        if ruck_weight >= 20:
            achievements.append(f"Carrying {ruck_weight:.0f}kg like a beast! 🦍")
        elif ruck_weight >= 10:
            achievements.append(f"Solid {ruck_weight:.0f}kg load handled with style! 💼")
        
        if distance_km >= 10:
            achievements.append("Double digits on the distance - legendary! 🏆")
        elif distance_km >= 5:
            achievements.append("Solid mileage in the books! 📚")
        
        if elevation_gain and elevation_gain >= 200:
            achievements.append(f"Conquered {elevation_gain:.0f}m of elevation - hill crushing mode! ⛰️")
        elif elevation_gain and elevation_gain >= 100:
            achievements.append("Hills didn't stand a chance! 🏔️")
        
        if pace_min_km > 0 and pace_min_km <= 8:
            achievements.append("Keeping that pace tight! ⚡")
        
        if calories and calories >= 500:
            achievements.append(f"Torched {calories:.0f} calories - furnace mode! 🔥")
        
        # Motivational endings
        endings = [
            "One step closer to greatness! 🌟",
            "The grind never stops! 💪",
            "Building that mental toughness! 🧠",
            "Earned every step! 👟",
            "Ruck on! 🎯",
            "Stay hard! 💎",
            "Progress over perfection! 📈",
            "This is the way! 🛡️"
        ]
        
        # Construct the summary
        summary_parts = [random.choice(openings)]
        
        if achievements:
            if len(achievements) == 1:
                summary_parts.append(achievements[0])
            else:
                # Pick 1-2 achievements randomly
                selected = random.sample(achievements, min(2, len(achievements)))
                summary_parts.extend(selected)
        
        summary_parts.append(random.choice(endings))
        
        return " ".join(summary_parts)
