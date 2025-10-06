"""
Live Following API
Provides real-time session data for followers
"""
import logging
from flask import Blueprint, g
from flask_restful import Resource, Api
from RuckTracker.supabase_client import get_supabase_client, get_supabase_admin_client
from datetime import datetime

logger = logging.getLogger(__name__)

class LiveRuckDataResource(Resource):
    """Get live data for an active ruck session"""

    def get(self, ruck_id):
        """Get current position and stats for live following"""
        try:
            # Use admin client to bypass RLS (we do auth checks manually)
            supabase = get_supabase_admin_client()
            viewer_id = g.user.id

            # Get session
            session_response = supabase.table('ruck_session').select(
                'id, user_id, status, allow_live_following, distance_km, duration_seconds, average_pace, started_at'
            ).eq('id', ruck_id).execute()

            if not session_response.data or len(session_response.data) == 0:
                return {'error': 'Session not found'}, 404

            session = session_response.data[0]
            rucker_id = session['user_id']

            # Check if session is active (in_progress or active)
            if session['status'] not in ['active', 'in_progress']:
                logger.warning(f"Session {ruck_id} is not active: status={session['status']}")
                return {'error': 'This ruck is not currently active'}, 400

            # Check if live following is enabled
            if not session.get('allow_live_following', True):
                logger.warning(f"Session {ruck_id} has live following disabled")
                return {'error': 'Live following is disabled for this ruck'}, 403

            # Check if viewer follows the rucker (unless they are the rucker)
            if viewer_id != rucker_id:
                follow_check = supabase.table('user_follows').select('id').eq(
                    'follower_id', viewer_id
                ).eq('followed_id', rucker_id).execute()

                if not follow_check.data:
                    return {'error': 'You must follow this user to view their live ruck'}, 403

            # Get latest location point
            location_response = supabase.table('location_point').select(
                'latitude, longitude, timestamp'
            ).eq('session_id', ruck_id).order('timestamp', desc=True).limit(1).execute()

            current_location = None
            last_location_update = None

            if location_response.data:
                point = location_response.data[0]
                current_location = {
                    'latitude': point['latitude'],
                    'longitude': point['longitude']
                }
                last_location_update = point['timestamp']

            # Get route (sampled for performance)
            route_response = supabase.table('location_point').select(
                'latitude, longitude'
            ).eq('session_id', ruck_id).order('timestamp', desc=False).execute()

            route = []
            if route_response.data:
                # Sample route points (take every 5th point to reduce data)
                points = route_response.data
                step = max(1, len(points) // 100)  # Max 100 points
                route = [
                    {'lat': p['latitude'], 'lng': p['longitude']}
                    for i, p in enumerate(points) if i % step == 0
                ]

            return {
                'status': 'success',
                'ruck_id': ruck_id,
                'distance_km': session['distance_km'],
                'duration_seconds': session['duration_seconds'],
                'average_pace': session['average_pace'],
                'current_location': current_location,
                'route': route,
                'last_location_update': last_location_update,
                'started_at': session['started_at']
            }, 200

        except Exception as e:
            logger.error(f"Error fetching live ruck data: {e}", exc_info=True)
            return {'error': 'Failed to fetch live ruck data'}, 500


# Create Blueprint
live_following_bp = Blueprint('live_following', __name__)
live_following_api = Api(live_following_bp)

# Register resources
live_following_api.add_resource(LiveRuckDataResource, '/rucks/<int:ruck_id>/live')
