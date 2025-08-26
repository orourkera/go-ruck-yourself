from flask import request, g
from flask_restful import Resource
from datetime import datetime, timedelta
from dateutil import tz
import uuid
import logging
import json
import os
import math

from ..supabase_client import get_supabase_client
from ..services.redis_cache_service import cache_get, cache_set, cache_delete_pattern
from .goals import _compute_window_bounds, _km_to_mi
from ..utils.auth_helper import get_current_user_id
from ..utils.api_response import check_auth_and_respond
from ..services.push_notification_service import PushNotificationService, get_user_device_tokens

logger = logging.getLogger(__name__)

def validate_ruck_id(ruck_id):
    """Coerce a path parameter ruck_id into an int, or return None if invalid."""
    try:
        return int(ruck_id)
    except (TypeError, ValueError):
        try:
            return int(str(ruck_id).strip())
        except Exception:
            return None

class RuckSessionListResource(Resource):
    def get(self):
        """List ruck sessions for the authenticated user (GET /api/rucks)"""
        if not hasattr(g, 'user') or g.user is None:
            return {'message': 'User not authenticated'}, 401

        supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))

        # Basic pagination
        try:
            limit = int(request.args.get('limit', 20))
            offset = int(request.args.get('offset', 0))
        except Exception:
            limit, offset = 20, 0

        # Return user's sessions ordered by completion/start time
        try:
            resp = (
                supabase.table('ruck_session')
                .select('*')
                .eq('user_id', g.user.id)
                .order('completed_at', desc=True, nullsfirst=False)
                .order('started_at', desc=True)
                .range(offset, offset + max(limit - 1, 0))
                .execute()
            )
            return resp.data or [], 200
        except Exception as e:
            logger.error(f"Error listing ruck sessions: {e}")
            return {'message': f'Error listing ruck sessions: {str(e)}'}, 500

    def post(self):
        """Create a new ruck session (POST /api/rucks)"""
        if not hasattr(g, 'user') or g.user is None:
            return {'message': 'User not authenticated'}, 401

        supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))

        try:
            data = request.get_json()
            if not data:
                return {'message': 'No data provided'}, 400

            # Check for existing active session
            existing_resp = (
                supabase.table('ruck_session')
                .select('id, status, started_at, ruck_weight_kg')
                .eq('user_id', g.user.id)
                .in_('status', ['in_progress', 'paused'])
                .execute()
            )

            if existing_resp.data:
                # Return existing active session info
                active_session = existing_resp.data[0]
                return {
                    'has_active_session': True,
                    'id': active_session['id'],
                    'status': active_session['status'],
                    'started_at': active_session['started_at'],
                    'ruck_weight_kg': active_session['ruck_weight_kg']
                }, 200

            # Create new session
            session_data = {
                'user_id': g.user.id,
                'ruck_weight_kg': data.get('ruck_weight_kg', 0.0),
                'weight_kg': data.get('weight_kg'),
                'is_manual': data.get('is_manual', False),
                'status': 'created',
                'created_at': datetime.utcnow().isoformat()
            }

            # Add optional fields
            if data.get('event_id'):
                session_data['event_id'] = data['event_id']
            if data.get('route_id'):
                session_data['route_id'] = data['route_id']
            if data.get('planned_ruck_id'):
                session_data['planned_ruck_id'] = data['planned_ruck_id']
            if data.get('planned_duration_minutes'):
                session_data['planned_duration_minutes'] = data['planned_duration_minutes']

            resp = supabase.table('ruck_session').insert(session_data).execute()
            
            if not resp.data:
                return {'message': 'Failed to create session'}, 500

            return resp.data[0], 201

        except Exception as e:
            logger.error(f"Error creating ruck session: {e}")
            return {'message': f'Error creating ruck session: {str(e)}'}, 500

class RuckSessionResource(Resource):
    def get(self, ruck_id):
        """Get a single ruck session by ID for the authenticated user"""
        if not hasattr(g, 'user') or g.user is None:
            return {'message': 'User not authenticated'}, 401

        ruck_id = validate_ruck_id(ruck_id)
        if ruck_id is None:
            return {'message': 'Invalid ruck session ID format'}, 400

        supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
        try:
            # Allow self-owned session, or public session (read-only)
            session_resp = (
                supabase.table('ruck_session')
                .select('*')
                .eq('id', ruck_id)
                .execute()
            )
            if not session_resp.data:
                return {'message': 'Session not found'}, 404

            session = session_resp.data[0]
            if session.get('user_id') != g.user.id and not session.get('is_public'):
                return {'message': 'Forbidden'}, 403

            return session, 200
        except Exception as e:
            logger.error(f"Error fetching session {ruck_id}: {e}")
            return {'message': f'Error fetching session: {str(e)}'}, 500

    def delete(self, ruck_id):
        """Delete a ruck session owned by the authenticated user (DELETE /api/rucks/<id>)

        This will cascade-delete dependent records where applicable and then
        remove the ruck_session row. Only the session owner may delete.
        """
        if not hasattr(g, 'user') or g.user is None:
            return {'message': 'User not authenticated'}, 401

        ruck_id = validate_ruck_id(ruck_id)
        if ruck_id is None:
            return {'message': 'Invalid ruck session ID format'}, 400

        supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))

        try:
            # Verify session exists and ownership
            session_resp = (
                supabase.table('ruck_session')
                .select('id,user_id')
                .eq('id', ruck_id)
                .single()
                .execute()
            )
            if not session_resp.data:
                return {'message': 'Session not found'}, 404

            if session_resp.data.get('user_id') != g.user.id:
                return {'message': 'Forbidden'}, 403

            # Best-effort cascading deletes for related data
            def _safe_delete(table_name, col, val):
                try:
                    supabase.table(table_name).delete().eq(col, val).execute()
                except Exception as del_err:
                    logger.warning(f"[RUCK_DELETE] Skipping optional table {table_name} delete: {del_err}")

            # Known related tables/columns
            _safe_delete('heart_rate_sample', 'session_id', ruck_id)
            _safe_delete('location_point', 'session_id', ruck_id)
            _safe_delete('session_splits', 'session_id', ruck_id)
            _safe_delete('ruck_likes', 'ruck_id', ruck_id)
            _safe_delete('ruck_comments', 'ruck_id', ruck_id)
            _safe_delete('ruck_photos', 'ruck_id', ruck_id)

            # Finally delete the session itself (owner constraint)
            delete_resp = (
                supabase.table('ruck_session')
                .delete()
                .eq('id', ruck_id)
                .eq('user_id', g.user.id)
                .execute()
            )
            if delete_resp.data is None:
                # Some clients of supabase-py return None on delete; treat as success
                pass

            # Invalidate any cached user session lists
            try:
                cache_delete_pattern(f"ruck_session:{g.user.id}:*")
            except Exception:
                pass

            return {'message': 'Session deleted', 'id': ruck_id}, 200
        except Exception as e:
            logger.error(f"Error deleting session {ruck_id}: {e}")
            return {'message': f'Error deleting session: {str(e)}'}, 500

class RuckSessionDetailResource(Resource):
    """Return enriched ruck session details (GET /api/rucks/<id>/details)

    Includes:
    - user profile subset
    - privacy-clipped and sampled route points
    - photos
    - like/comment counts and liked-by-current-user flag
    """

    def _haversine_distance(self, lat1, lon1, lat2, lon2):
        lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
        dlat = lat2 - lat1
        dlon = lon2 - lon1
        a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
        c = 2 * math.asin(math.sqrt(a))
        r = 6371000  # meters
        return c * r

    def _clip_route_for_privacy(self, location_points):
        if not location_points or len(location_points) < 5:
            logger.warning(f"[PRIVACY_DEBUG] Route too short ({len(location_points) if location_points else 0} points) - hiding for privacy")
            return []
        PRIVACY_DISTANCE_METERS = 400.0  # Increased to 400m for better privacy
        sorted_points = sorted(location_points, key=lambda p: p.get('timestamp', ''))
        if len(sorted_points) < 3:
            return sorted_points
        start_idx = 0
        cumulative_distance = 0
        for i in range(1, len(sorted_points)):
            prev_point = sorted_points[i-1]
            curr_point = sorted_points[i]
            if prev_point.get('latitude') and prev_point.get('longitude') and \
               curr_point.get('latitude') and curr_point.get('longitude'):
                distance = self._haversine_distance(
                    float(prev_point['latitude']), float(prev_point['longitude']),
                    float(curr_point['latitude']), float(curr_point['longitude'])
                )
                cumulative_distance += distance
                if cumulative_distance >= PRIVACY_DISTANCE_METERS:
                    start_idx = i
                    break
        end_idx = len(sorted_points)
        cumulative_distance = 0
        for i in range(len(sorted_points) - 2, -1, -1):
            curr_point = sorted_points[i]
            next_point = sorted_points[i+1]
            if curr_point.get('latitude') and curr_point.get('longitude') and \
               next_point.get('latitude') and next_point.get('longitude'):
                distance = self._haversine_distance(
                    float(curr_point['latitude']), float(curr_point['longitude']),
                    float(next_point['latitude']), float(next_point['longitude'])
                )
                cumulative_distance += distance
                if cumulative_distance >= PRIVACY_DISTANCE_METERS:
                    end_idx = i + 1
                    break
        if start_idx >= end_idx or start_idx >= len(sorted_points) or end_idx <= 0:
            logger.warning(f"[PRIVACY_DEBUG] Clipping failed - start_idx={start_idx}, end_idx={end_idx}, total={len(sorted_points)} - hiding route for privacy")
            return []  # Return empty for privacy instead of fallback
        clipped_points = sorted_points[start_idx:end_idx]
        if len(clipped_points) < 3:
            logger.warning(f"[PRIVACY_DEBUG] Clipped route too short ({len(clipped_points)} points) - hiding for privacy")
            return []
        logger.info(f"[PRIVACY_DEBUG] Successfully clipped route: {len(clipped_points)} points (removed {start_idx} from start, {len(sorted_points) - end_idx} from end)")
        return clipped_points

    def _sample_route_points(self, location_points, target_distance_between_points_m=35):
        if not location_points or len(location_points) <= 2:
            return location_points
        sampled = [location_points[0]]
        cumulative_distance = 0
        last_included_idx = 0
        for i in range(1, len(location_points)):
            prev_point = location_points[i-1]
            curr_point = location_points[i]
            if prev_point.get('latitude') and prev_point.get('longitude') and \
               curr_point.get('latitude') and curr_point.get('longitude'):
                distance = self._haversine_distance(
                    float(prev_point['latitude']), float(prev_point['longitude']),
                    float(curr_point['latitude']), float(curr_point['longitude'])
                )
                cumulative_distance += distance
                if cumulative_distance >= target_distance_between_points_m:
                    sampled.append(curr_point)
                    cumulative_distance = 0
                    last_included_idx = i
        if last_included_idx < len(location_points) - 1:
            sampled.append(location_points[-1])
        if len(sampled) > 500:
            interval = len(sampled) / 500
            final_sampled = [sampled[0]]
            for i in range(1, 499):
                index = int(i * interval)
                if index < len(sampled):
                    final_sampled.append(sampled[index])
            final_sampled.append(sampled[-1])
            # Enforce maximum segment length by interpolating if needed (defense-in-depth)
            try:
                final_sampled = self._cap_max_segment_length(final_sampled, max_segment_length_m=60.0)
            except Exception as e:
                logger.debug(f"[ROUTE_SAMPLING_DEBUG] Failed to cap max segment length (final_sampled): {e}")
            # Post-sampling diagnostics: log long segments
            try:
                self._log_long_segments(final_sampled)
            except Exception as e:
                logger.debug(f"[ROUTE_SAMPLING_DEBUG] Failed to log long segments: {e}")
            return final_sampled
        # Enforce maximum segment length by interpolating if needed (defense-in-depth)
        try:
            sampled = self._cap_max_segment_length(sampled, max_segment_length_m=60.0)
        except Exception as e:
            logger.debug(f"[ROUTE_SAMPLING_DEBUG] Failed to cap max segment length: {e}")
        # Post-sampling diagnostics: log long segments
        try:
            self._log_long_segments(sampled)
        except Exception as e:
            logger.debug(f"[ROUTE_SAMPLING_DEBUG] Failed to log long segments: {e}")
        return sampled

    def _log_long_segments(self, points, threshold_m=60.0):
        """Diagnostic helper: logs segments longer than threshold after sampling.
        No behavior change. Helps identify potential visual artifacts where the
        polyline might cut across private property due to long straight segments.
        """
        if not points or len(points) < 2:
            return
        long_segments = []
        for i in range(1, len(points)):
            p1 = points[i-1]
            p2 = points[i]
            if p1.get('latitude') is None or p1.get('longitude') is None:
                continue
            if p2.get('latitude') is None or p2.get('longitude') is None:
                continue
            d = self._haversine_distance(
                float(p1['latitude']), float(p1['longitude']),
                float(p2['latitude']), float(p2['longitude'])
            )
            if d >= threshold_m:
                long_segments.append({
                    'idx1': i-1,
                    'idx2': i,
                    'distance_m': round(d, 2),
                    'p1': {'lat': p1.get('latitude'), 'lng': p1.get('longitude')},
                    'p2': {'lat': p2.get('latitude'), 'lng': p2.get('longitude')},
                })
        if long_segments:
            try:
                logger.info(f"[ROUTE_SAMPLING_DEBUG] {len(long_segments)} long segments >= {threshold_m}m after sampling")
                # Log first few details to avoid log spam
                for seg in long_segments[:10]:
                    logger.info(
                        f"[ROUTE_SAMPLING_DEBUG] seg {seg['idx1']}->{seg['idx2']} distance={seg['distance_m']}m "
                        f"p1=({seg['p1']['lat']},{seg['p1']['lng']}) p2=({seg['p2']['lat']},{seg['p2']['lng']})"
                    )
                if len(long_segments) > 10:
                    logger.info(f"[ROUTE_SAMPLING_DEBUG] ... {len(long_segments) - 10} more long segments not shown")
            except Exception:
                # Ensure diagnostics never crash request handling
                pass

    def _cap_max_segment_length(self, points, max_segment_length_m=60.0):
        """Ensure no consecutive points are farther apart than max_segment_length_m.
        Inserts linearly interpolated points as needed. Returns a new list.
        """
        if not points or len(points) < 2:
            return points
        capped = [points[0]]
        inserted_count = 0
        for i in range(1, len(points)):
            p1 = capped[-1]
            p2 = points[i]
            if p1.get('latitude') is None or p1.get('longitude') is None or \
               p2.get('latitude') is None or p2.get('longitude') is None:
                capped.append(p2)
                continue
            d = self._haversine_distance(
                float(p1['latitude']), float(p1['longitude']),
                float(p2['latitude']), float(p2['longitude'])
            )
            if d <= max_segment_length_m:
                capped.append(p2)
                continue
            # Determine number of intermediate points needed
            # We aim for segments <= max_segment_length_m
            n_segments = int(math.ceil(d / max_segment_length_m))
            # Insert n_segments-1 intermediate points
            lat1 = float(p1['latitude']); lon1 = float(p1['longitude'])
            lat2 = float(p2['latitude']); lon2 = float(p2['longitude'])
            for k in range(1, n_segments):
                t = k / n_segments
                new_lat = lat1 + (lat2 - lat1) * t
                new_lon = lon1 + (lon2 - lon1) * t
                new_point = dict(p2)  # copy structure to preserve keys
                new_point['latitude'] = new_lat
                new_point['longitude'] = new_lon
                # Timestamp interpolation if both timestamps present and ISO-8601
                try:
                    ts1 = p1.get('timestamp'); ts2 = p2.get('timestamp')
                    if ts1 and ts2 and isinstance(ts1, str) and isinstance(ts2, str) and 'T' in ts1 and 'T' in ts2:
                        dt1 = datetime.fromisoformat(ts1.replace('Z', '+00:00'))
                        dt2 = datetime.fromisoformat(ts2.replace('Z', '+00:00'))
                        delta = dt2 - dt1
                        new_ts = dt1 + delta * t
                        new_point['timestamp'] = new_ts.isoformat()
                except Exception:
                    pass
                capped.append(new_point)
                inserted_count += 1
            capped.append(p2)
        if inserted_count > 0:
            try:
                logger.info(f"[ROUTE_SAMPLING_DEBUG] Inserted {inserted_count} interpolated points to cap segments at <= {max_segment_length_m}m")
            except Exception:
                pass
        return capped

    def get(self, ruck_id):
        if not hasattr(g, 'user') or g.user is None:
            return {'message': 'User not authenticated'}, 401

        ruck_id = validate_ruck_id(ruck_id)
        if ruck_id is None:
            return {'message': 'Invalid ruck session ID format'}, 400
        try:
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))

            # Fetch base session (no embedded photos to avoid FK join issues)
            session_resp = (
                supabase.table('ruck_session')
                .select('*')
                .eq('id', ruck_id)
                .single()
                .execute()
            )
            if not session_resp.data:
                return {'message': 'Session not found'}, 404
            session = session_resp.data

            # Authorization: allow owner or public
            if session.get('user_id') != g.user.id and not session.get('is_public'):
                return {'message': 'Forbidden'}, 403

            current_user_id = g.user.id

            # Route points: fetch from table and attach
            try:
                lp_resp = (
                    supabase.table('location_point')
                    .select('latitude,longitude,altitude,timestamp')
                    .eq('session_id', ruck_id)
                    .order('timestamp', desc=False)
                    .execute()
                )
                location_points = lp_resp.data or []
            except Exception as lp_err:
                logger.warning(f"[RUCK_DETAILS] Failed to fetch location points for session {ruck_id}: {lp_err}")
                location_points = []

            # Process route points
            clipped_points = self._clip_route_for_privacy(location_points)
            sampled_points = self._sample_route_points(clipped_points)

            # Build a frontend-friendly 'route' array with lat/lng keys as well
            route_for_map = [
                {
                    'lat': p.get('latitude'),
                    'lng': p.get('longitude'),
                    'alt': p.get('altitude'),
                    'timestamp': p.get('timestamp'),
                }
                for p in sampled_points if p.get('latitude') is not None and p.get('longitude') is not None
            ]

            # Likes/comments aggregates via separate lightweight queries
            like_count = 0
            comment_count = 0
            is_liked_by_current_user = False
            try:
                likes_count_resp = (
                    supabase.table('ruck_likes')
                    .select('id', count='exact')
                    .eq('ruck_id', ruck_id)
                    .execute()
                )
                like_count = likes_count_resp.count or 0
                liked_by_me_resp = (
                    supabase.table('ruck_likes')
                    .select('id', count='exact')
                    .eq('ruck_id', ruck_id)
                    .eq('user_id', current_user_id)
                    .execute()
                )
                is_liked_by_current_user = (liked_by_me_resp.count or 0) > 0
            except Exception as likes_err:
                logger.warning(f"[RUCK_DETAILS] Failed to compute likes aggregates for {ruck_id}: {likes_err}")
            try:
                comments_count_resp = (
                    supabase.table('ruck_comments')
                    .select('id', count='exact')
                    .eq('ruck_id', ruck_id)
                    .execute()
                )
                comment_count = comments_count_resp.count or 0
            except Exception as comments_err:
                logger.warning(f"[RUCK_DETAILS] Failed to compute comments count for {ruck_id}: {comments_err}")

            # Photos (separate query to avoid dependency on missing FK embedding)
            try:
                photos_resp = (
                    supabase.table('ruck_photos')
                    .select('id,ruck_id,user_id,filename,original_filename,content_type,size,url,thumbnail_url,created_at')
                    .eq('ruck_id', ruck_id)
                    .execute()
                )
                photos = photos_resp.data or []
            except Exception as photo_err:
                logger.warning(f"[RUCK_DETAILS] Failed to fetch photos for ruck_id {ruck_id}: {photo_err}")
                photos = []

            # Attach aggregates and derived fields
            session['like_count'] = like_count
            session['comment_count'] = comment_count
            session['is_liked_by_current_user'] = is_liked_by_current_user
            session['location_points'] = sampled_points
            session['route'] = route_for_map
            session['photos'] = photos

            # Add compatibility aliases for elevation keys used by some clients
            if 'elevation_gain_m' in session and session.get('elevation_gain_m') is not None:
                session.setdefault('elevation_gain_meters', session.get('elevation_gain_m'))
            if 'elevation_loss_m' in session and session.get('elevation_loss_m') is not None:
                session.setdefault('elevation_loss_meters', session.get('elevation_loss_m'))

            # Ensure raw likes/comments arrays are not present
            session.pop('likes', None)
            session.pop('comments', None)

            return session, 200
        except Exception as e:
            logger.error(f"Error fetching enriched session details for {ruck_id}: {e}")
            return {'message': f'Error fetching session details: {str(e)}'}, 500

    def patch(self, ruck_id):
        """Partially update a ruck session owned by the authenticated user (PATCH /api/rucks/<id>)

        Currently used by the app to set flags like has_photos after background uploads.
        Only whitelisted fields are accepted.
        """
        if not hasattr(g, 'user') or g.user is None:
            return {'message': 'User not authenticated'}, 401

        ruck_id = validate_ruck_id(ruck_id)
        if ruck_id is None:
            return {'message': 'Invalid ruck session ID format'}, 400

        try:
            data = request.get_json() or {}
        except Exception:
            data = {}

        if not isinstance(data, dict) or not data:
            return {'message': 'No data provided'}, 400

        supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))

        try:
            # Verify ownership
            session_resp = (
                supabase.table('ruck_session')
                .select('id,user_id')
                .eq('id', ruck_id)
                .single()
                .execute()
            )
            if not session_resp.data:
                return {'message': 'Session not found'}, 404
            if session_resp.data.get('user_id') != g.user.id:
                return {'message': 'Forbidden'}, 403

            # Whitelist allowed fields for partial update
            allowed_fields = {
                'has_photos',
                'notes',
                'rating',
                'perceived_exertion',
                'tags',
                'is_public',
                'title',
                'route_id',
                'planned_duration_minutes',
            }

            update_data = {k: v for k, v in data.items() if k in allowed_fields}
            if not update_data:
                return {'message': 'No allowed fields to update'}, 400

            update_resp = (
                supabase.table('ruck_session')
                .update(update_data)
                .eq('id', ruck_id)
                .eq('user_id', g.user.id)
                .execute()
            )
            if not update_resp.data:
                return {'message': 'Failed to update session'}, 500

            # Invalidate caches for this user's session lists/details
            try:
                cache_delete_pattern(f"ruck_session:{g.user.id}:*")
            except Exception:
                pass

            return update_resp.data[0], 200
        except Exception as e:
            logger.error(f"Error patching session {ruck_id}: {e}")
            return {'message': f'Error patching session: {str(e)}'}, 500

class RuckSessionStartResource(Resource):
    def post(self, ruck_id):
        """Mark a ruck session as started (POST /api/rucks/<ruck_id>/start)"""
        if not hasattr(g, 'user') or g.user is None:
            return {'message': 'User not authenticated'}, 401

        ruck_id = validate_ruck_id(ruck_id)
        if ruck_id is None:
            return {'message': 'Invalid ruck session ID format'}, 400

        supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
        try:
            update = {
                'status': 'in_progress',
                'started_at': datetime.now(tz.tzutc()).isoformat(),
            }
            resp = (
                supabase.table('ruck_session')
                .update(update)
                .eq('id', ruck_id)
                .eq('user_id', g.user.id)
                .execute()
            )
            if not resp.data:
                return {'message': 'Session not found or not owned by user'}, 404

            cache_delete_pattern(f"ruck_session:{g.user.id}:*")
            return resp.data[0], 200
        except Exception as e:
            logger.error(f"Error starting session {ruck_id}: {e}")
            return {'message': f'Error starting session: {str(e)}'}, 500

class RuckSessionPauseResource(Resource):
    def post(self, ruck_id):
        """Pause an in-progress ruck session (POST /api/rucks/<ruck_id>/pause)"""
        if not hasattr(g, 'user') or g.user is None:
            return {'message': 'User not authenticated'}, 401

        ruck_id = validate_ruck_id(ruck_id)
        if ruck_id is None:
            return {'message': 'Invalid ruck session ID format'}, 400

        supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
        try:
            update = {
                'status': 'paused',
                'paused_at': datetime.now(tz.tzutc()).isoformat(),
            }
            resp = (
                supabase.table('ruck_session')
                .update(update)
                .eq('id', ruck_id)
                .eq('user_id', g.user.id)
                .execute()
            )
            if not resp.data:
                return {'message': 'Session not found or not owned by user'}, 404

            cache_delete_pattern(f"ruck_session:{g.user.id}:*")
            return resp.data[0], 200
        except Exception as e:
            logger.error(f"Error pausing session {ruck_id}: {e}")
            return {'message': f'Error pausing session: {str(e)}'}, 500

class RuckSessionResumeResource(Resource):
    def post(self, ruck_id):
        """Resume a paused ruck session (POST /api/rucks/<ruck_id>/resume)"""
        if not hasattr(g, 'user') or g.user is None:
            return {'message': 'User not authenticated'}, 401

        ruck_id = validate_ruck_id(ruck_id)
        if ruck_id is None:
            return {'message': 'Invalid ruck session ID format'}, 400

        supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
        try:
            update = {
                'status': 'in_progress',
                'resumed_at': datetime.now(tz.tzutc()).isoformat(),
            }
            resp = (
                supabase.table('ruck_session')
                .update(update)
                .eq('id', ruck_id)
                .eq('user_id', g.user.id)
                .execute()
            )
            if not resp.data:
                return {'message': 'Session not found or not owned by user'}, 404

            cache_delete_pattern(f"ruck_session:{g.user.id}:*")
            return resp.data[0], 200
        except Exception as e:
            logger.error(f"Error resuming session {ruck_id}: {e}")
            return {'message': f'Error resuming session: {str(e)}'}, 500

class RuckSessionCompleteResource(Resource):
    def post(self, ruck_id):
        """Complete a ruck session"""
        try:
            # Convert string ruck_id to integer for database operations
            ruck_id = validate_ruck_id(ruck_id)
            if ruck_id is None:
                return {'message': 'Invalid ruck session ID format'}, 400
            
            # Check authentication (use same pattern as location endpoint)
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            
            user_id = g.user.id
            data = request.get_json()
            if not data:
                return {'message': 'No data provided'}, 400
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            # Check if session exists
            session_check = supabase.table('ruck_session') \
                .select('id,status,started_at') \
                .eq('id', ruck_id) \
                .eq('user_id', user_id) \
                .execute()
            if not session_check.data or len(session_check.data) == 0:
                return {'message': 'Session not found'}, 404
            current_status = session_check.data[0]['status']
            started_at_str = session_check.data[0].get('started_at')
            # Allow 'created' sessions to be completed (auto-start them first)
            if current_status == 'created':
                logger.info(f"Auto-starting session {ruck_id} for completion")
                try:
                    supabase.table('ruck_session').update({
                        'status': 'in_progress',
                        'started_at': started_at_str or datetime.now(tz.tzutc()).isoformat(),
                    }).eq('id', ruck_id).execute()
                    current_status = 'in_progress'
                except Exception as e:
                    logger.error(f"Failed to auto-start session {ruck_id} for completion: {e}")
                    return {'message': f"Failed to start session for completion: {str(e)}"}, 500
            elif current_status not in ['in_progress', 'paused', 'completed']:
                return {'message': f'Session not in valid state for completion (current status: {current_status})'}, 400
            
            # Check if this is a manual session being updated after auto-completion
            session_resp = supabase.table('ruck_session') \
                .select('is_manual') \
                .eq('id', ruck_id) \
                .eq('user_id', user_id) \
                .single() \
                .execute()
            
            is_manual_session = session_resp.data.get('is_manual', False) if session_resp.data else False
            
            if current_status == 'completed' and not is_manual_session:
                # Non-manual session already completed, return early
                return {
                    'message': 'Session already completed',
                    'session_id': ruck_id,
                    'status': 'already_completed'
                }, 200
            elif current_status == 'completed' and is_manual_session:
                logger.info(f"Updating already-completed manual session {ruck_id} with new data")
            
            # Fetch user's allow_ruck_sharing preference to set default for is_public
            user_resp = supabase.table('user') \
                .select('allow_ruck_sharing') \
                .eq('id', user_id) \
                .single() \
                .execute()
        
            user_allows_sharing = user_resp.data.get('allow_ruck_sharing', False) if user_resp.data else False
        
            # Calculate duration - prioritize manually provided duration over calculated duration
            if 'duration_seconds' in data and data['duration_seconds'] is not None:
                # Use manually provided duration (for manual sessions)
                duration_seconds = int(data['duration_seconds'])
                logger.info(f"Using manually provided duration: {duration_seconds} seconds")
            elif started_at_str:
                # Calculate duration from timestamps (for live sessions)
                try:
                    started_at = datetime.fromisoformat(started_at_str.replace('Z', '+00:00'))
                    ended_at = datetime.now(tz.tzutc())
                    duration_seconds = int((ended_at - started_at).total_seconds())
                    logger.info(f"Calculated duration from timestamps: {duration_seconds} seconds")
                except Exception as e:
                    logger.error(f"Error calculating duration for session {ruck_id}: {e}")
                    duration_seconds = 0
            else:
                duration_seconds = 0
            # Calculate pace if possible
            distance_km = None
            if 'distance_km' in data and data['distance_km']:
                distance_km = data['distance_km']
        
            # Pace will be calculated later using processed distance, not client-sent distance

            # Update session status to completed with end data
            update_data = {
                'status': 'completed',
                'duration_seconds': duration_seconds
            }
        
            # Set is_public based on user preference or explicit override from client
            if 'is_public' in data:
                # Client explicitly set sharing preference for this session
                update_data['is_public'] = data['is_public']
            else:
                # Default based on user's global preference
                update_data['is_public'] = user_allows_sharing
            
            # Add all relevant fields if provided
            if 'distance_km' in data:
                update_data['distance_km'] = data['distance_km']
            if 'weight_kg' in data:
                update_data['weight_kg'] = data['weight_kg']
            if 'ruck_weight_kg' in data:
                update_data['ruck_weight_kg'] = data['ruck_weight_kg']
            if 'calories_burned' in data:
                update_data['calories_burned'] = data['calories_burned']
            # Optional steps support
            if 'steps' in data:
                try:
                    steps_val = int(data['steps']) if data['steps'] is not None else None
                    if steps_val is not None and steps_val >= 0:
                        update_data['steps'] = steps_val
                except Exception:
                    logger.warning(f"Invalid steps value provided: {data.get('steps')}")
            if 'calorie_method' in data and data['calorie_method'] in ['fusion','mechanical','hr']:
                update_data['calorie_method'] = data['calorie_method']
            # Heart rate zones: snapshot of thresholds and per-zone time (seconds)
            if 'hr_zone_snapshot' in data and isinstance(data['hr_zone_snapshot'], (dict, list)):
                update_data['hr_zone_snapshot'] = data['hr_zone_snapshot']
                logger.info(f"[HR_ZONES] Saving hr_zone_snapshot for session {ruck_id}: {data['hr_zone_snapshot']}")
            if 'time_in_zones' in data and isinstance(data['time_in_zones'], dict):
                update_data['time_in_zones'] = data['time_in_zones']
                logger.info(f"[HR_ZONES] Saving time_in_zones for session {ruck_id}: {data['time_in_zones']}")
                
                # If we have time_in_zones but no hr_zone_snapshot, try to reconstruct zones from user profile
                if 'hr_zone_snapshot' not in data or not data['hr_zone_snapshot']:
                    try:
                        user_resp = supabase.table('user_profile').select('resting_hr, max_hr, date_of_birth, gender').eq('id', g.user.id).single().execute()
                        if user_resp.data:
                            user_data = user_resp.data
                            if user_data.get('resting_hr') and user_data.get('max_hr'):
                                # Calculate zones using the same logic as Flutter
                                resting_hr = user_data['resting_hr']
                                max_hr = user_data['max_hr']
                                
                                # Basic 5-zone calculation (no colors - Flutter will handle that)
                                hr_reserve = max_hr - resting_hr
                                zones = [
                                    {'name': 'Z1', 'min_bpm': resting_hr, 'max_bpm': int(resting_hr + hr_reserve * 0.6)},
                                    {'name': 'Z2', 'min_bpm': int(resting_hr + hr_reserve * 0.6), 'max_bpm': int(resting_hr + hr_reserve * 0.7)},
                                    {'name': 'Z3', 'min_bpm': int(resting_hr + hr_reserve * 0.7), 'max_bpm': int(resting_hr + hr_reserve * 0.8)},
                                    {'name': 'Z4', 'min_bpm': int(resting_hr + hr_reserve * 0.8), 'max_bpm': int(resting_hr + hr_reserve * 0.9)},
                                    {'name': 'Z5', 'min_bpm': int(resting_hr + hr_reserve * 0.9), 'max_bpm': max_hr}
                                ]
                                update_data['hr_zone_snapshot'] = zones
                                logger.info(f"[HR_ZONES] Reconstructed hr_zone_snapshot for session {ruck_id} from user profile")
                    except Exception as zone_err:
                        logger.warning(f"[HR_ZONES] Could not reconstruct hr_zone_snapshot for session {ruck_id}: {zone_err}")
            if 'elevation_gain_m' in data:
                update_data['elevation_gain_m'] = data['elevation_gain_m']
            if 'elevation_loss_m' in data:
                update_data['elevation_loss_m'] = data['elevation_loss_m']
            if 'avg_heart_rate' in data:
                update_data['avg_heart_rate'] = data['avg_heart_rate']
            if 'min_heart_rate' in data:
                update_data['min_heart_rate'] = data['min_heart_rate']
            if 'max_heart_rate' in data:
                update_data['max_heart_rate'] = data['max_heart_rate']

            # Always set completed_at to now (UTC) when completing session
            update_data['completed_at'] = datetime.now(tz.tzutc()).isoformat()

            # Pace will be calculated later using processed distance

            if 'start_time' in data:
                update_data['started_at'] = data['start_time']
            if 'end_time' in data: # Keep this for now, though completed_at should be primary
                update_data['completed_at'] = data['end_time']
            if 'final_average_pace' in data: # Client-sent pace (legacy key), overrides server calc
                update_data['average_pace'] = data['final_average_pace']
            if 'average_pace' in data:     # Client-sent pace (current key), overrides server calc / legacy key
                update_data['average_pace'] = data['average_pace']
            if 'rating' in data:
                update_data['rating'] = data['rating']
            if 'perceived_exertion' in data:
                update_data['perceived_exertion'] = data['perceived_exertion']
            if 'notes' in data:
                update_data['notes'] = data['notes']
            if 'tags' in data:
                update_data['tags'] = data['tags']
            if 'planned_duration_minutes' in data:
                update_data['planned_duration_minutes'] = data['planned_duration_minutes']
            if 'is_manual' in data:
                update_data['is_manual'] = data['is_manual']
                logger.info(f"[IS_MANUAL_DEBUG] Setting is_manual to {data['is_manual']} for session {ruck_id} completion")
            else:
                logger.info(f"[IS_MANUAL_DEBUG] No is_manual field provided in completion data for session {ruck_id}")
            
            # Log the sharing decision for debugging
            logger.info(f"Session {ruck_id} completion: user_allows_sharing={user_allows_sharing}, is_public={update_data['is_public']}")
        
            # SERVER-SIDE METRIC CALCULATION FALLBACK
            # If key metrics are missing or zero, calculate them from GPS data
            distance_missing = not update_data.get('distance_km') or update_data.get('distance_km', 0) == 0
            calories_missing = not update_data.get('calories_burned') or update_data.get('calories_burned', 0) == 0
            elevation_missing = not update_data.get('elevation_gain_m') or update_data.get('elevation_gain_m', 0) == 0
            loss_missing = not update_data.get('elevation_loss_m') or update_data.get('elevation_loss_m', 0) == 0
            pace_missing = not update_data.get('average_pace') or update_data.get('average_pace', 0) == 0
            
            needs_calculation = distance_missing or calories_missing or elevation_missing or loss_missing or pace_missing
            
            logger.info(f"Session {ruck_id} metric check - distance: {update_data.get('distance_km')} (missing: {distance_missing}), calories: {update_data.get('calories_burned')} (missing: {calories_missing}), elevation_gain: {update_data.get('elevation_gain_m')} (missing: {elevation_missing}), elevation_loss: {update_data.get('elevation_loss_m')} (missing: {loss_missing}), pace: {update_data.get('average_pace')} (missing: {pace_missing}), needs_calc: {needs_calculation}")
        
            if needs_calculation:
                logger.info(f"Session {ruck_id}: Missing metrics detected, calculating from GPS data...")
                try:
                    # Fetch GPS location points for this session
                    location_resp = supabase.table('location_point') \
                        .select('latitude,longitude,altitude,timestamp') \
                        .eq('session_id', ruck_id) \
                        .order('timestamp') \
                        .execute()
                
                    if location_resp.data and len(location_resp.data) >= 2:
                        points = location_resp.data
                        logger.info(f"Found {len(points)} GPS points for calculation")
                    
                        # Calculate distance using haversine formula
                        total_distance_km = 0
                        elevation_gain_m = 0
                        elevation_loss_m = 0
                        previous_altitude = None
                    
                        for i in range(1, len(points)):
                            prev_point = points[i-1]
                            curr_point = points[i]
                        
                            # Calculate distance between consecutive points
                            lat1, lon1 = float(prev_point['latitude']), float(prev_point['longitude']) 
                            lat2, lon2 = float(curr_point['latitude']), float(curr_point['longitude'])
                        
                            # Haversine formula
                            R = 6371  # Earth's radius in km
                            dlat = math.radians(lat2 - lat1)
                            dlon = math.radians(lon2 - lon1)
                            a = (math.sin(dlat/2) * math.sin(dlat/2) + 
                                 math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * 
                                 math.sin(dlon/2) * math.sin(dlon/2))
                            c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
                            distance_km = R * c
                            total_distance_km += distance_km
                        
                            # Calculate elevation gain/loss
                            if curr_point.get('altitude') is not None and prev_point.get('altitude') is not None:
                                alt_diff = float(curr_point['altitude']) - float(prev_point['altitude'])
                                if alt_diff > 0:  # Only count positive elevation changes
                                    elevation_gain_m += alt_diff
                                elif alt_diff < 0:  # Count negative elevation changes toward loss
                                    elevation_loss_m += abs(alt_diff)
                    
                        # Calculate missing metrics - use threshold to avoid overwriting small but valid distances
                        if not update_data.get('distance_km') or update_data.get('distance_km', 0) <= 0.001:  # Only override if truly zero or negligible
                            update_data['distance_km'] = round(total_distance_km, 3)
                            logger.info(f"[DISTANCE_DEBUG] Overriding client distance with GPS calculation: {total_distance_km:.3f} km")
                        else:
                            logger.info(f"[DISTANCE_DEBUG] Using client-provided distance: {update_data.get('distance_km')} km")
                    
                        if not update_data.get('elevation_gain_m') or update_data.get('elevation_gain_m', 0) == 0:
                            update_data['elevation_gain_m'] = round(elevation_gain_m, 1)
                            logger.info(f"Calculated elevation gain: {elevation_gain_m:.1f} m")
                        if not update_data.get('elevation_loss_m') or update_data.get('elevation_loss_m', 0) == 0:
                            update_data['elevation_loss_m'] = round(elevation_loss_m, 1)
                            logger.info(f"Calculated elevation loss: {elevation_loss_m:.1f} m")
                    
                        # Calculate average pace if we have distance and duration
                        final_distance = update_data.get('distance_km', 0)
                        logger.info(f"[PACE_DEBUG] Backend pace calculation inputs: duration_seconds={duration_seconds}, final_distance={final_distance}km")
                        if final_distance > 0 and duration_seconds > 0:
                            if not update_data.get('average_pace') or update_data.get('average_pace', 0) == 0:
                                calculated_pace = duration_seconds / final_distance  # seconds per km
                                update_data['average_pace'] = calculated_pace  # Store with full precision like Session 1088
                                logger.info(f"[PACE_DEBUG] Calculated pace: {duration_seconds}s ÷ {final_distance}km = {calculated_pace} sec/km")
                    
                        # Calculate calories if missing (basic estimation)
                        if not update_data.get('calories_burned') or update_data.get('calories_burned', 0) == 0:
                            # Basic calorie estimation: assume 80kg user, ~400 cal/hour base + elevation
                            weight_kg = float(update_data.get('weight_kg', 80))  # Default 80kg if not provided
                            ruck_weight_kg = float(update_data.get('ruck_weight_kg', 0))
                            total_weight_kg = weight_kg + ruck_weight_kg
                        
                            # Base metabolic rate (calories per hour)
                            base_cal_per_hour = 4.5 * total_weight_kg  # METs calculation for rucking
                            duration_hours = duration_seconds / 3600
                            base_calories = base_cal_per_hour * duration_hours
                        
                            # Add elevation bonus (1 cal per 10m elevation gain per kg body weight)
                            elevation_calories = (elevation_gain_m / 10) * weight_kg
                        
                            estimated_calories = round(base_calories + elevation_calories)
                            update_data['calories_burned'] = estimated_calories
                            logger.info(f"Estimated calories: {estimated_calories} (base: {base_calories:.0f}, elevation: {elevation_calories:.0f})")
                    
                        logger.info(f"Server-calculated metrics for session {ruck_id}: distance={update_data.get('distance_km')}km, pace={update_data.get('average_pace')}s/km, calories={update_data.get('calories_burned')}, elevation_gain={update_data.get('elevation_gain_m')}m, elevation_loss={update_data.get('elevation_loss_m')}m")
                    
                    else:
                        logger.warning(f"Session {ruck_id}: Insufficient GPS data for metric calculation ({len(location_resp.data) if location_resp.data else 0} points)")
                    
                except Exception as calc_error:
                    logger.error(f"Error calculating server-side metrics for session {ruck_id}: {calc_error}")
                    # Continue with original data - don't fail the completion
    
            # Continue with update as before
            update_resp = supabase.table('ruck_session') \
                .update(update_data) \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            if not update_resp.data or len(update_resp.data) == 0:
                logger.error(f"Failed to end session {ruck_id}: {update_resp.error}")
                return {'message': 'Failed to end session'}, 500
        
            completed_session = update_resp.data[0]

            # Always check for heart rate samples and aggregate them (they may have been uploaded via chunk endpoints during session)
            try:
                stats_resp = supabase.table('heart_rate_sample') \
                    .select('bpm') \
                    .eq('session_id', ruck_id) \
                    .limit(50000) \
                    .execute()
                logger.info(f"[HR_AGGREGATE] Found {len(stats_resp.data) if stats_resp.data else 0} heart rate samples for session {ruck_id}")
                if stats_resp.data:
                    bpm_values = []
                    for x in stats_resp.data:
                        if x.get('bpm') is None:
                            continue
                        try:
                            bpm_values.append(int(round(float(x['bpm']))))
                        except Exception:
                            continue
                    logger.info(f"[HR_AGGREGATE] Filtered to {len(bpm_values)} valid BPM values")
                    if bpm_values:
                        avg_hr = sum(bpm_values) / len(bpm_values)
                        min_hr = min(bpm_values)
                        max_hr = max(bpm_values)
                        hr_update_resp = supabase.table('ruck_session').update({
                            'avg_heart_rate': round(avg_hr, 1),
                            'min_heart_rate': int(min_hr),
                            'max_heart_rate': int(max_hr)
                        }).eq('id', ruck_id).eq('user_id', g.user.id).execute()
                        logger.info(f"[HR_AGGREGATE] HR update response: {hr_update_resp.data}")
                        # Also reflect into completed_session for response
                        completed_session['avg_heart_rate'] = round(avg_hr, 1)
                        completed_session['min_heart_rate'] = int(min_hr)
                        completed_session['max_heart_rate'] = int(max_hr)
                        logger.info(f"[HR_AGGREGATE] Updated HR stats for session {ruck_id}: avg={avg_hr:.1f}, min={min_hr}, max={max_hr} from {len(bpm_values)} samples")
                    else:
                        logger.warning(f"[HR_AGGREGATE] No valid BPM values found for session {ruck_id}")
                else:
                    logger.info(f"[HR_AGGREGATE] No heart rate samples found for session {ruck_id}")
            except Exception as hr_agg_err:
                logger.error(f"[HR_AGGREGATE] Error aggregating heart rate samples for session {ruck_id}: {hr_agg_err}")

            # Handle heart rate samples if provided in completion payload
            if 'heart_rate_samples' in data and isinstance(data['heart_rate_samples'], list):
                try:
                    samples = data['heart_rate_samples']
                    total_incoming = len(samples)
                    logger.info(f"[HR_DEBUG] Processing {total_incoming} heart rate samples for session {ruck_id} on completion")

                    # Delete existing samples to replace with latest set
                    supabase.table('heart_rate_sample') \
                        .delete() \
                        .eq('session_id', ruck_id) \
                        .execute()

                    # Normalize and coerce
                    def _normalize_ts(ts_val):
                        try:
                            # If numeric -> epoch ms or seconds
                            if isinstance(ts_val, (int, float)):
                                # Assume ms if large
                                sec = ts_val / 1000.0 if ts_val > 1e12 else ts_val
                                return datetime.fromtimestamp(sec, tz=tz.tzutc()).isoformat()
                            if isinstance(ts_val, str):
                                # Pass through if ISO, else attempt parse
                                try:
                                    return datetime.fromisoformat(ts_val.replace('Z', '+00:00')).isoformat()
                                except Exception:
                                    # Fallback: let DB attempt to coerce
                                    return ts_val
                        except Exception:
                            return None

                    def _coerce_bpm(v):
                        try:
                            return int(round(float(v)))
                        except Exception:
                            return None

                    hr_rows = []
                    dropped = 0
                    for s in samples:
                        bpm = s.get('bpm', s.get('heart_rate'))
                        ts = s.get('timestamp')
                        bpm_i = _coerce_bpm(bpm)
                        ts_norm = _normalize_ts(ts)
                        if bpm_i is None or ts_norm is None:
                            dropped += 1
                            continue
                        hr_rows.append({
                            'session_id': int(ruck_id),
                            'timestamp': ts_norm,
                            'bpm': bpm_i,
                        })

                    logger.info(f"[HR_DEBUG] Prepared {len(hr_rows)} rows (dropped {dropped} invalid) for session {ruck_id}")

                    # Chunked insert to avoid payload limits
                    inserted_total = 0
                    CHUNK = 500
                    for i in range(0, len(hr_rows), CHUNK):
                        chunk = hr_rows[i:i+CHUNK]
                        ins = supabase.table('heart_rate_sample').insert(chunk).execute()
                        if ins.error:
                            logger.warning(f"[HR_DEBUG] Insert chunk {i//CHUNK} failed for session {ruck_id}: {ins.error}")
                        else:
                            # Some clients return data=None on bulk insert; rely on count verification after
                            inserted_total += len(chunk)

                    # Verify count from DB
                    count_resp = supabase.table('heart_rate_sample') \
                        .select('id', count='exact') \
                        .eq('session_id', ruck_id) \
                        .execute()
                    db_count = (count_resp.count if hasattr(count_resp, 'count') else None)
                    logger.info(f"[HR_DEBUG] Inserted ~{inserted_total} rows. DB now has {db_count if db_count is not None else 'unknown'} rows for session {ruck_id}")

                    # Compute HR stats from DB and update session
                    stats_resp = supabase.table('heart_rate_sample') \
                        .select('bpm') \
                        .eq('session_id', ruck_id) \
                        .limit(50000) \
                        .execute()
                    if stats_resp.data:
                        # Coerce BPM values robustly to handle cases like "80.0" returned as strings
                        bpm_values = []
                        for x in stats_resp.data:
                            if x.get('bpm') is None:
                                continue
                            try:
                                bpm_values.append(int(round(float(x['bpm']))))
                            except Exception:
                                continue
                        if bpm_values:
                            avg_hr = sum(bpm_values) / len(bpm_values)
                            min_hr = min(bpm_values)
                            max_hr = max(bpm_values)
                            supabase.table('ruck_session').update({
                                'avg_heart_rate': round(avg_hr, 1),
                                'min_heart_rate': int(min_hr),
                                'max_heart_rate': int(max_hr)
                            }).eq('id', ruck_id).eq('user_id', g.user.id).execute()
                            # Also reflect into completed_session for response
                            completed_session['avg_heart_rate'] = round(avg_hr, 1)
                            completed_session['min_heart_rate'] = int(min_hr)
                            completed_session['max_heart_rate'] = int(max_hr)
                            logger.info(f"[HR_DEBUG] Updated HR stats for session {ruck_id}: avg={avg_hr:.1f}, min={min_hr}, max={max_hr}")
                except Exception as hr_err:
                    logger.error(f"[HR_DEBUG] Error handling heart rate samples for session {ruck_id}: {hr_err}")
                    # Do not fail completion on HR errors

            # Handle splits data if provided
            if 'splits' in data and data['splits']:
                splits_data = data['splits']
                logger.info(f"Processing {len(splits_data)} splits for session {ruck_id}")
                
                # Get session location points for elevation calculation
                session_location_points = completed_session.get('location_points', [])
                logger.info(f"Found {len(session_location_points)} location points for elevation calculation")
                
                try:
                    # First, delete existing splits for this session
                    delete_resp = supabase.table('session_splits') \
                        .delete() \
                        .eq('session_id', ruck_id) \
                        .execute()
                    
                    # Insert new splits
                    if splits_data and len(splits_data) > 0:
                        splits_to_insert = []
                        for split in splits_data:
                            # Use elevation gain data from frontend instead of recalculating
                            # The frontend now properly calculates elevation gains for splits
                            split_elevation_gain = split.get('elevation_gain_m', 0.0)
                            
                            logger.debug(f"Split {split.get('split_number')}: using frontend elevation gain: {split_elevation_gain:.1f}m")
                            
                            # Handle the split data format from the Flutter app
                            split_record = {
                                'session_id': int(ruck_id),
                                'split_number': split.get('split_number'),
                                'split_distance_km': split.get('split_distance', 1.0),  # Always 1.0 (1km or 1mi)
                                'split_duration_seconds': split.get('split_duration_seconds'),
                                'total_distance_km': split.get('total_distance', 0),
                                'total_duration_seconds': split.get('total_duration_seconds', 0),
                                'calories_burned': split.get('calories_burned', 0.0),
                                'elevation_gain_m': split_elevation_gain,  # Use calculated elevation gain
                                'split_timestamp': split.get('timestamp') if split.get('timestamp') else datetime.now(tz.tzutc()).isoformat()
                            }
                            splits_to_insert.append(split_record)
                        
                        if splits_to_insert:
                            # Deduplicate by (session_id, split_number) to avoid unique constraint violations
                            unique_map = {}
                            for rec in splits_to_insert:
                                sn = rec.get('split_number')
                                if sn is None:
                                    # Skip invalid split numbers
                                    continue
                                unique_map[(rec['session_id'], sn)] = rec

                            deduped_splits = list(sorted(unique_map.values(), key=lambda r: r['split_number']))

                            insert_resp = supabase.table('session_splits') \
                                .insert(deduped_splits) \
                                .execute()
                            
                            if insert_resp.data:
                                logger.info(f"Successfully inserted {len(insert_resp.data)} splits for session {ruck_id}")
                            else:
                                logger.warning(f"Failed to insert splits for session {ruck_id}: {insert_resp.error}")
                except Exception as splits_error:
                    logger.error(f"Error handling splits for session {ruck_id}: {splits_error}")
                    # Don't fail the session completion if splits insertion fails
        
            # Check if this session is associated with an event and update progress
            if completed_session.get('event_id'):
                try:
                    event_id = completed_session['event_id']
                    logger.info(f"Updating event progress for session {ruck_id} in event {event_id}")
                
                    # Update event participant progress
                    progress_update = {
                        'ruck_session_id': int(ruck_id),  # Convert to int to match database type
                        'distance_km': completed_session.get('distance_km', 0),
                        'duration_minutes': int(duration_seconds / 60) if duration_seconds else 0,
                        'calories_burned': completed_session.get('calories_burned', 0),
                        'elevation_gain_m': completed_session.get('elevation_gain_m', 0),
                        'average_pace_min_per_km': completed_session.get('average_pace', 0) / 60 if completed_session.get('average_pace') else None,
                        'status': 'completed',
                        'completed_at': completed_session['completed_at']
                    }
                
                    # Update the event progress entry
                    progress_resp = supabase.table('event_participant_progress') \
                        .update(progress_update) \
                        .eq('event_id', event_id) \
                        .eq('user_id', g.user.id) \
                        .execute()
                
                    if progress_resp.data:
                        logger.info(f"Successfully updated event progress for user {g.user.id} in event {event_id}")
                    else:
                        logger.warning(f"Failed to update event progress for user {g.user.id} in event {event_id}")
                    
                except Exception as event_error:
                    logger.error(f"Error updating event progress for session {ruck_id}: {event_error}")
                    # Don't fail the session completion if event progress update fails
        
            # Check if this user is in any active duels and update progress automatically
            try:
                logger.info(f"Checking for active duels for user {g.user.id} after completing session {ruck_id}")
                
                # Find active duel participants for this user
                duel_participants_resp = supabase.table('duel_participants') \
                    .select('id, duel_id, current_value') \
                    .eq('user_id', g.user.id) \
                    .eq('status', 'accepted') \
                    .execute()
                
                if duel_participants_resp.data:
                    # For each active duel participation, check if the duel is still active
                    for participant in duel_participants_resp.data:
                        participant_id = participant['id']
                        duel_id = participant['duel_id']
                        
                        # Get duel details
                        duel_resp = supabase.table('duels') \
                            .select('id, status, challenge_type, target_value, ends_at') \
                            .eq('id', duel_id) \
                            .single() \
                            .execute()
                        
                        if not duel_resp.data or duel_resp.data['status'] != 'active':
                            continue
                            
                        duel = duel_resp.data
                        
                        # Check if duel has ended
                        if duel['ends_at']:
                            duel_end_time = datetime.fromisoformat(duel['ends_at'])
                            current_time = datetime.now(duel_end_time.tzinfo) if duel_end_time.tzinfo else datetime.utcnow()
                            if current_time > duel_end_time:
                                continue
                            
                        # Check if session was already counted for this duel
                        existing_session_resp = supabase.table('duel_sessions') \
                            .select('id') \
                            .eq('duel_id', duel_id) \
                            .eq('participant_id', participant_id) \
                            .eq('session_id', ruck_id) \
                            .execute()
                        
                        if existing_session_resp.data:
                            logger.info(f"Session {ruck_id} already counted for duel {duel_id}")
                            continue
                            
                        # Calculate contribution based on challenge type
                        contribution = 0
                        if duel['challenge_type'] == 'distance':
                            contribution = completed_session.get('distance_km', 0)
                        elif duel['challenge_type'] == 'duration':
                            contribution = int(duration_seconds / 60) if duration_seconds else 0
                        elif duel['challenge_type'] == 'time':  # Handle 'time' alias for duration
                            contribution = int(duration_seconds / 60) if duration_seconds else 0
                        elif duel['challenge_type'] == 'elevation':
                            contribution = completed_session.get('elevation_gain_m', 0)
                        elif duel['challenge_type'] == 'power_points':
                            # Power points are automatically calculated by the database computed column
                            # We need to re-fetch the session to get the computed power_points value
                            session_with_power_points = supabase.table('ruck_session') \
                                .select('power_points') \
                                .eq('id', ruck_id) \
                                .single() \
                                .execute()
                            if session_with_power_points.data and session_with_power_points.data.get('power_points'):
                                contribution = float(session_with_power_points.data['power_points'])
                            else:
                                contribution = 0
                        
                        if contribution > 0:
                            # Update participant progress
                            new_value = participant['current_value'] + contribution
                            now = datetime.utcnow()
                            
                            supabase.table('duel_participants').update({
                                'current_value': new_value,
                                'updated_at': now.isoformat()
                            }).eq('id', participant_id).execute()
                            
                            # Record the session contribution
                            supabase.table('duel_sessions').insert([{
                                'duel_id': duel_id,
                                'participant_id': participant_id,
                                'session_id': ruck_id,
                                'contribution_value': contribution,
                                'created_at': now.isoformat()
                            }]).execute()
                            
                            # Notification handled by database trigger
                            # try:
                            #     from api.duel_comments import create_duel_progress_notification
                            #     user_resp = supabase.table('users').select('username').eq('id', g.user.id).single().execute()
                            #     user_name = user_resp.data.get('username', 'Unknown User') if user_resp.data else 'Unknown User'
                            #     create_duel_progress_notification(duel_id, g.user.id, user_name, ruck_id)
                            # except Exception as notif_error:
                            #     logger.error(f"Failed to create duel progress notification: {notif_error}")
                            
                            logger.info(f"Updated duel {duel_id} progress for user {g.user.id}: +{contribution} ({duel['challenge_type']}) = {new_value}")
                            
                            # Check if participant reached target
                            if new_value >= duel['target_value']:
                                supabase.table('duel_participants').update({
                                    'target_reached_at': now.isoformat()
                                }).eq('id', participant_id).execute()
                                logger.info(f"User {g.user.id} reached target in duel {duel_id}")
                        
            except Exception as duel_error:
                logger.error(f"Error updating duel progress for session {ruck_id}: {duel_error}")
                # Don't fail the session completion if duel progress update fails
        
            # Evaluate active custom goals for this user (event-driven hook)
            try:
                logger.info(f"[GOALS] Triggering evaluation of active goals for user {g.user.id} after session {ruck_id}")
                # Fetch active goals for the user
                goals_resp = supabase.table('user_custom_goals').select(
                    'id, user_id, title, metric, target_value, unit, window, constraints_json, '
                    'start_at, end_at, deadline_at, created_at, status'
                ).eq('user_id', g.user.id).eq('status', 'active').limit(200).execute()

                active_goals = goals_resp.data or []
                if not active_goals:
                    logger.info(f"[GOALS] No active goals found for user {g.user.id}")
                else:
                    # For each goal, compute window, aggregate sessions, and upsert progress
                    for goal in active_goals:
                        try:
                            metric = goal.get('metric')
                            target_value = float(goal.get('target_value') or 0)
                            unit = goal.get('unit')

                            supported = {
                                'distance_km_total',
                                'duration_minutes_total',
                                'steps_total',
                                'elevation_gain_m_total',
                                'power_points_total',
                            }
                            if metric not in supported:
                                continue

                            start_iso, end_iso = _compute_window_bounds(goal)

                            # Fetch completed sessions in window
                            select_cols = 'id,distance_km,duration_seconds,steps,elevation_gain_m,power_points,completed_at'
                            s_resp = supabase.table('ruck_session').select(select_cols) \
                                .eq('user_id', g.user.id) \
                                .eq('status', 'completed') \
                                .gte('completed_at', start_iso) \
                                .lte('completed_at', end_iso) \
                                .limit(10000) \
                                .execute()

                            sessions = s_resp.data or []

                            total_distance_km = 0.0
                            total_duration_seconds = 0.0
                            total_steps = 0
                            total_elevation_m = 0.0
                            total_power_points = 0.0

                            for s in sessions:
                                try:
                                    if s.get('distance_km') is not None:
                                        total_distance_km += float(s.get('distance_km') or 0)
                                    if s.get('duration_seconds') is not None:
                                        total_duration_seconds += float(s.get('duration_seconds') or 0)
                                    if s.get('steps') is not None:
                                        total_steps += int(s.get('steps') or 0)
                                    if s.get('elevation_gain_m') is not None:
                                        total_elevation_m += float(s.get('elevation_gain_m') or 0)
                                    if s.get('power_points') is not None:
                                        total_power_points += float(s.get('power_points') or 0)
                                except Exception:
                                    continue

                            current_value = 0.0
                            breakdown_totals = {}

                            if metric == 'distance_km_total':
                                distance_in_goal_unit = _km_to_mi(total_distance_km) if unit == 'mi' else total_distance_km
                                current_value = distance_in_goal_unit
                                breakdown_totals = {
                                    'distance_km': round(total_distance_km, 3),
                                    'distance_mi': round(_km_to_mi(total_distance_km), 3),
                                }
                            elif metric == 'duration_minutes_total':
                                minutes = total_duration_seconds / 60.0
                                current_value = minutes
                                breakdown_totals = {
                                    'duration_seconds': int(total_duration_seconds),
                                    'duration_minutes': round(minutes, 2),
                                }
                            elif metric == 'steps_total':
                                current_value = float(total_steps)
                                breakdown_totals = {
                                    'steps': int(total_steps),
                                }
                            elif metric == 'elevation_gain_m_total':
                                current_value = float(total_elevation_m)
                                breakdown_totals = {
                                    'elevation_gain_m': round(total_elevation_m, 1),
                                }
                            elif metric == 'power_points_total':
                                current_value = float(total_power_points)
                                breakdown_totals = {
                                    'power_points': round(total_power_points, 1),
                                }

                            progress_percent = 0.0
                            if target_value > 0:
                                progress_percent = max(0.0, min(100.0, (current_value / float(target_value)) * 100.0))

                            breakdown = {
                                'metric': metric,
                                'unit': unit,
                                'window': {'start': start_iso, 'end': end_iso, 'source': goal.get('window') or 'custom'},
                                'totals': breakdown_totals,
                                'session_count': len(sessions),
                                'session_ids': [s.get('id') for s in sessions],
                            }

                            # Upsert progress
                            progress_lookup = supabase.table('user_goal_progress').select('id') \
                                .eq('goal_id', goal['id']).eq('user_id', g.user.id).limit(1).execute()

                            now_iso = datetime.now(tz.tzutc()).isoformat()
                            payload = {
                                'goal_id': goal['id'],
                                'user_id': g.user.id,
                                'current_value': float(round(current_value, 3)),
                                'progress_percent': float(round(progress_percent, 2)),
                                'last_evaluated_at': now_iso,
                                'breakdown_json': breakdown,
                            }

                            if progress_lookup.data:
                                progress_id = progress_lookup.data[0]['id']
                                supabase.table('user_goal_progress').update(payload).eq('id', progress_id).execute()
                            else:
                                supabase.table('user_goal_progress').insert(payload).execute()

                        except Exception as goal_err:
                            logger.error(f"[GOALS] Failed to evaluate goal {goal.get('id')} for user {g.user.id}: {goal_err}")
            except Exception as goals_err:
                logger.error(f"[GOALS] Error evaluating active goals for user {g.user.id} after session {ruck_id}: {goals_err}")

            logger.info(f"Session {ruck_id} completion - achievement checking moved to frontend post-navigation")
            completed_session['new_achievements'] = []  # Empty for now, populated by separate API call
        
            cache_delete_pattern(f"ruck_session:{user_id}:*")
            cache_delete_pattern("ruck_buddies:*")
            cache_delete_pattern(f"weekly_stats:{user_id}:*")
            cache_delete_pattern(f"monthly_stats:{user_id}:*")
            cache_delete_pattern(f"yearly_stats:{user_id}:*")
            cache_delete_pattern(f"user_lifetime_stats:{user_id}")
            cache_delete_pattern(f"user_recent_rucks:{user_id}")
            cache_delete_pattern(f'user_profile:{user_id}:*')

            # Fetch and include splits data in the response
            try:
                splits_resp = supabase.table('session_splits') \
                    .select('*') \
                    .eq('session_id', ruck_id) \
                    .order('split_number') \
                    .execute()
                
                if splits_resp.data:
                    completed_session['splits'] = splits_resp.data
                    logger.info(f"Included {len(splits_resp.data)} splits in completion response for session {ruck_id}")
                else:
                    completed_session['splits'] = []
                    logger.info(f"No splits found for session {ruck_id}")
            except Exception as splits_fetch_error:
                logger.error(f"Error fetching splits for completed session {ruck_id}: {splits_fetch_error}")
                completed_session['splits'] = []  # Ensure splits field exists even if fetch fails
            
            return completed_session, 200
        except Exception as e:
            logger.error(f"Error ending ruck session {ruck_id}: {e}")
            return {'message': f"Error ending ruck session: {str(e)}"}, 500

class RuckSessionLocationResource(Resource):
    def post(self, ruck_id):
        """Upload location points to an active ruck session (POST /api/rucks/<ruck_id>/location)"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            
            data = request.get_json()
            
            # Support both single point and batch of points (like heart rate)
            if 'points' in data:
                # Batch mode - array of location points
                if not isinstance(data['points'], list):
                    return {'message': 'Missing or invalid points'}, 400
                location_points = data['points']
            else:
                # Legacy mode - single point (backwards compatibility)
                if 'latitude' not in data or 'longitude' not in data:
                    return {'message': 'Missing location data'}, 400
                location_points = [data]  # Convert to array format
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Check if session exists and belongs to user (like heart rate)
            session_resp = supabase.table('ruck_session') \
                .select('id,status') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            
            if not session_resp.data:
                logger.warning(f"Session {ruck_id} not found or not accessible for user {g.user.id}")
                return {'message': 'Session not found or access denied'}, 404
            
            session_data = session_resp.data[0]
            current_status = session_data['status']
            
            # Auto-start session if it's in 'created' status and receiving first location/HR data
            if current_status == 'created':
                logger.info(f"Auto-starting session {ruck_id} on first data upload")
                try:
                    supabase.table('ruck_session').update({
                        'status': 'in_progress',
                        'started_at': datetime.now(tz.tzutc()).isoformat(),
                    }).eq('id', ruck_id).execute()
                    current_status = 'in_progress'
                except Exception as e:
                    logger.error(f"Failed to auto-start session {ruck_id}: {e}")
                    return {'message': f"Failed to start session: {str(e)}"}, 500
            elif current_status != 'in_progress':
                logger.warning(f"Session {ruck_id} status is '{current_status}', not 'in_progress'")
                return {'message': f"Session not in progress (status: {current_status})"}, 400
            
            # Insert location points (like heart rate samples)
            location_rows = []
            for point in location_points:
                if 'latitude' not in point or 'longitude' not in point:
                    continue  # Skip invalid points
                location_rows.append({
                    'session_id': ruck_id,
                    'latitude': float(point['latitude']),
                    'longitude': float(point['longitude']),
                    'altitude': point.get('elevation') or point.get('elevation_meters'),
                    'timestamp': point.get('timestamp', datetime.now(tz.tzutc()).isoformat())
                })
            
            if not location_rows:
                return {'message': 'No valid location points'}, 400
                
            insert_resp = supabase.table('location_point').insert(location_rows).execute()
            if not insert_resp.data:
                return {'message': 'Failed to insert location points'}, 500
                
            # Note: No need to invalidate session cache for location points
            # Session data (distance, duration, etc.) is calculated separately
            return {'status': 'ok', 'inserted': len(insert_resp.data)}, 201
            
        except Exception as e:
            logger.error(f"Error adding location points for ruck session {ruck_id}: {e}")
            return {'message': f'Error uploading location points: {str(e)}'}, 500

class RuckSessionEditResource(Resource):
    def put(self, ruck_id):
        """Edit a ruck session - trim/crop session by removing data after new end time"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            
            data = request.get_json()
            if not data:
                return {'message': 'No data provided'}, 400
            
            # Validate required fields
            required_fields = ['end_time', 'duration_seconds', 'distance_km', 'elevation_gain_m', 'elevation_loss_m']
            for field in required_fields:
                if field not in data:
                    return {'message': f'Missing required field: {field}'}, 400
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Verify session exists and belongs to user
            session_resp = supabase.table('ruck_session') \
                .select('id,user_id,status,started_at') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            
            if not session_resp.data:
                logger.warning(f"Session {ruck_id} not found or not accessible for user {g.user.id}")
                return {'message': 'Session not found or access denied'}, 404
            
            session_data = session_resp.data[0]
            
            # Parse the new end time
            try:
                new_end_time = datetime.fromisoformat(data['end_time'].replace('Z', '+00:00'))
            except ValueError as e:
                return {'message': f'Invalid end_time format: {str(e)}'}, 400
            
            # Validate end time is after start time
            start_time = datetime.fromisoformat(session_data['started_at'].replace('Z', '+00:00'))
            if new_end_time <= start_time:
                return {'message': 'End time must be after start time'}, 400
            
            logger.info(f"Editing session {ruck_id} - new end time: {new_end_time}")
            
            # Update session with new metrics
            session_updates = {
                'completed_at': data['end_time'],
                'duration_seconds': data['duration_seconds'],
                'distance_km': data['distance_km'],
                'elevation_gain_m': data['elevation_gain_m'],
                'elevation_loss_m': data['elevation_loss_m'],
                'calories_burned': data.get('calories_burned'),
                'average_pace': data.get('average_pace_min_per_km'),
                'avg_heart_rate': data.get('avg_heart_rate'),
                'max_heart_rate': data.get('max_heart_rate'),
                'min_heart_rate': data.get('min_heart_rate')
            }
            
            # Update the session
            update_resp = supabase.table('ruck_session') \
                .update(session_updates) \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            
            if not update_resp.data:
                return {'message': 'Failed to update session'}, 500
            
            # Delete location points after the new end time
            delete_locations_resp = supabase.table('location_point') \
                .delete() \
                .eq('session_id', ruck_id) \
                .gte('timestamp', data['end_time']) \
                .execute()
            
            logger.info(f"Deleted location points after {data['end_time']} for session {ruck_id}: {len(delete_locations_resp.data) if delete_locations_resp.data else 'unknown'} points deleted")
            
            # Delete heart rate samples after the new end time
            delete_hr_resp = supabase.table('heart_rate_sample') \
                .delete() \
                .eq('session_id', ruck_id) \
                .gte('timestamp', data['end_time']) \
                .execute()
            
            logger.info(f"Deleted heart rate samples after {data['end_time']} for session {ruck_id}")
            
            # Delete splits after the new end time
            delete_splits_resp = supabase.table('session_splits') \
                .delete() \
                .eq('session_id', ruck_id) \
                .gte('split_timestamp', data['end_time']) \
                .execute()
            
            logger.info(f"Deleted splits after {data['end_time']} for session {ruck_id}")
            
            # Clear cache for this user's sessions and location data
            cache_delete_pattern(f"ruck_session:{g.user.id}:*")
            cache_delete_pattern(f"location_points:{ruck_id}:*")
            cache_delete_pattern(f"session_details:{ruck_id}:*")
            
            logger.info(f"Successfully completed session {ruck_id}")
            
            return {
                'message': 'Session completed successfully',
                'session_id': ruck_id,
                'distance_km': update_data.get('distance_km', 0),
                'calories_burned': update_data.get('calories_burned', 0),
                'duration_seconds': update_data.get('duration_seconds', 0),
                'average_pace': update_data.get('average_pace', 0)
            }, 200
            
        except Exception as e:
            logger.error(f"Error completing ruck session {ruck_id}: {e}")
            return {'message': f"Error completing ruck session: {str(e)}"}, 500

    def patch(self, ruck_id):
        """PATCH method for session completion - redirects to POST for compatibility"""
        logger.info(f"PATCH /rucks/{ruck_id}/complete received - redirecting to POST method")
        return self.post(ruck_id)


class HeartRateSampleUploadResource(Resource):
    def get(self, ruck_id):
        """Get heart rate samples for a ruck session (GET /api/rucks/<ruck_id>/heart_rate)"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
                
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Check if session exists and belongs to user
            session_resp = supabase.table('ruck_session') \
                .select('id,user_id') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
                
            if not session_resp.data:
                logger.warning(f"Session {ruck_id} not found or not accessible for user {g.user.id}")
                return {'message': 'Session not found or access denied'}, 404
            
            session_data = session_resp.data[0]
            
            # Get heart rate samples for this session with intelligent downsampling
            # First get count to determine if we need downsampling
            count_response = supabase.table('heart_rate_sample') \
                .select('id', count='exact') \
                .eq('session_id', ruck_id) \
                .execute()
                
            total_samples = count_response.count or 0
            logger.info(f"Total heart rate samples for session {ruck_id}: {total_samples}")
            
            # Smart downsampling pattern (same as location points)
            MAX_HR_SAMPLES = 400  # Target number of samples for chart performance
            
            if total_samples <= MAX_HR_SAMPLES:
                # For reasonable sample counts, return all data
                response = supabase.table('heart_rate_sample') \
                    .select('*') \
                    .eq('session_id', ruck_id) \
                    .order('timestamp') \
                    .execute()
            else:
                # For large datasets, use database-level downsampling
                interval = max(1, total_samples // MAX_HR_SAMPLES)
                logger.info(f"Downsampling heart rate data: interval={interval}, target={MAX_HR_SAMPLES} samples")
                
                # Try RPC function for efficient database-level sampling
                try:
                    response = supabase.rpc('get_sampled_heart_rate', {
                        'p_session_id': int(ruck_id),
                        'p_interval': interval,
                        'p_max_samples': MAX_HR_SAMPLES
                    }).execute()
                    
                    # If RPC worked and returned data, use it
                    if response.data:
                        logger.info(f"Successfully used RPC function for heart rate downsampling")
                    else:
                        response = None
                except Exception as rpc_error:
                    logger.info(f"RPC function not available: {rpc_error}")
                    response = None
                
                # Fallback to Python-based downsampling if RPC doesn't exist or failed
                if not response or not response.data:
                    logger.info("RPC function not available, using Python-based downsampling")
                    all_samples_response = supabase.table('heart_rate_sample') \
                        .select('*') \
                        .eq('session_id', ruck_id) \
                        .order('timestamp') \
                        .limit(50000) \
                        .execute()
                    
                    if all_samples_response.data:
                        downsampled = all_samples_response.data[::interval]
                        # Ensure we always include the last sample for accurate end time
                        if len(all_samples_response.data) > 0 and all_samples_response.data[-1] not in downsampled:
                            downsampled.append(all_samples_response.data[-1])
                        
                        # Create a mock response object
                        class MockResponse:
                            def __init__(self, data):
                                self.data = data
                        
                        response = MockResponse(downsampled)
                    else:
                        response = all_samples_response
            
            logger.info(f"Retrieved {len(response.data)} heart rate samples for session {ruck_id} (downsampled from {total_samples})")
            return response.data, 200
            
        except Exception as e:
            logger.error(f"Error fetching heart rate samples for session {ruck_id}: {e}")
            return {'message': f"Error fetching heart rate samples: {str(e)}"}, 500

    def post(self, ruck_id):
        """Upload heart rate samples to a ruck session (POST /api/rucks/<ruck_id>/heart_rate)"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            data = request.get_json()
            if not data or 'samples' not in data or not isinstance(data['samples'], list):
                return {'message': 'Missing or invalid samples'}, 400
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            # Check if session exists and belongs to user
            session_resp = supabase.table('ruck_session') \
                .select('id,status') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            
            if not session_resp.data:
                logger.warning(f"Session {ruck_id} not found or not accessible for user {g.user.id}")
                return {'message': 'Session not found or access denied'}, 404
            
            session_data = session_resp.data[0]
            current_status = session_data['status']
            
            # Auto-start session if it's in 'created' status and receiving first location/HR data
            if current_status == 'created':
                logger.info(f"Auto-starting session {ruck_id} on first data upload")
                try:
                    supabase.table('ruck_session').update({
                        'status': 'in_progress',
                        'started_at': datetime.now(tz.tzutc()).isoformat(),
                    }).eq('id', ruck_id).execute()
                    current_status = 'in_progress'
                except Exception as e:
                    logger.error(f"Failed to auto-start session {ruck_id}: {e}")
                    return {'message': f"Failed to start session: {str(e)}"}, 500
            elif current_status != 'in_progress':
                logger.warning(f"Session {ruck_id} status is '{current_status}', not 'in_progress'")
                return {'message': f"Session not in progress (status: {current_status})"}, 400
            
            # Insert heart rate samples (normalize timestamp and coerce bpm)
            def _normalize_ts(ts_val):
                try:
                    if isinstance(ts_val, (int, float)):
                        # Assume ms if large
                        sec = ts_val / 1000.0 if ts_val > 1e12 else ts_val
                        return datetime.fromtimestamp(sec, tz=tz.tzutc()).isoformat()
                    if isinstance(ts_val, str):
                        try:
                            return datetime.fromisoformat(ts_val.replace('Z', '+00:00')).isoformat()
                        except Exception:
                            return ts_val
                except Exception:
                    return None

            def _coerce_bpm(v):
                try:
                    return int(round(float(v)))
                except Exception:
                    return None

            heart_rate_rows = []
            for sample in data['samples']:
                if 'timestamp' not in sample or 'bpm' not in sample:
                    continue
                ts_norm = _normalize_ts(sample['timestamp'])
                bpm_i = _coerce_bpm(sample['bpm'])
                if ts_norm is None or bpm_i is None:
                    continue
                heart_rate_rows.append({
                    'session_id': int(ruck_id),
                    'timestamp': ts_norm,
                    'bpm': bpm_i
                })
            if not heart_rate_rows:
                return {'message': 'No valid heart rate samples'}, 400
            insert_resp = supabase.table('heart_rate_sample').insert(heart_rate_rows).execute()
            if not insert_resp.data:
                return {'message': 'Failed to insert heart rate samples'}, 500
            cache_delete_pattern(f"ruck_session:{g.user.id}:*")
            return {'status': 'ok', 'inserted': len(insert_resp.data)}, 201
        except Exception as e:
            return {'message': f'Error uploading heart rate samples: {str(e)}'}, 500


class RuckSessionRouteChunkResource(Resource):
    def post(self, ruck_id):
        """Upload route data chunk for completed session (POST /api/rucks/<ruck_id>/route-chunk)"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            
            data = request.get_json()
            if not data or 'route_points' not in data or not isinstance(data['route_points'], list):
                return {'message': 'Missing or invalid route_points'}, 400
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Check if session exists, belongs to user, and is completed
            session_resp = supabase.table('ruck_session') \
                .select('id,status') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            
            if not session_resp.data:
                logger.warning(f"Session {ruck_id} not found or not accessible for user {g.user.id}")
                return {'message': 'Session not found or access denied'}, 404
            
            session_data = session_resp.data[0]
            if session_data['status'] != 'completed':
                logger.warning(f"Session {ruck_id} status is '{session_data['status']}', not 'completed'")
                return {'message': f"Session not completed (status: {session_data['status']}). Route chunks can only be uploaded to completed sessions."}, 400
            
            # Insert location points
            location_rows = []
            for point in data['route_points']:
                if 'timestamp' not in point or 'lat' not in point or 'lng' not in point:
                    continue
                location_rows.append({
                    'session_id': ruck_id,
                    'timestamp': point['timestamp'],
                    'latitude': point['lat'],
                    'longitude': point['lng'],
                    'altitude': point.get('altitude'),
                    'accuracy': point.get('accuracy'),
                    'speed': point.get('speed'),
                    'heading': point.get('heading')
                })
            
            if not location_rows:
                return {'message': 'No valid location points in chunk'}, 400
            
            insert_resp = supabase.table('location_point').insert(location_rows).execute()
            if not insert_resp.data:
                return {'message': 'Failed to insert location points'}, 500
            
            # Clear cache for this user's sessions
            cache_delete_pattern(f"ruck_session:{g.user.id}:*")
            
            logger.info(f"Successfully uploaded route chunk for session {ruck_id}: {len(insert_resp.data)} points")
            return {'status': 'ok', 'inserted': len(insert_resp.data)}, 201
            
        except Exception as e:
            logger.error(f"Error uploading route chunk for session {ruck_id}: {e}")
            return {'message': f'Error uploading route chunk: {str(e)}'}, 500


class RuckSessionHeartRateChunkResource(Resource):
    def post(self, ruck_id):
        """Upload heart rate data chunk for a session (POST /api/rucks/<ruck_id>/heart-rate-chunk)

        Accepted session statuses: 'in_progress', 'completed'.
        """
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            
            # Normalize ruck_id to integer for database operations
            ruck_id = validate_ruck_id(ruck_id)
            if ruck_id is None:
                return {'message': 'Invalid ruck session ID format'}, 400
            
            data = request.get_json()
            if not data or 'heart_rate_samples' not in data or not isinstance(data['heart_rate_samples'], list):
                return {'message': 'Missing or invalid heart_rate_samples'}, 400
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Check if session exists, belongs to user, and is completed
            session_resp = supabase.table('ruck_session') \
                .select('id,status') \
                .eq('id', ruck_id) \
                .eq('user_id', g.user.id) \
                .execute()
            
            if not session_resp.data:
                logger.warning(f"Session {ruck_id} not found or not accessible for user {g.user.id}")
                return {'message': 'Session not found or access denied'}, 404
            
            session_data = session_resp.data[0]
            current_status = session_data['status']
            
            # Auto-start session if it's in 'created' status and receiving first HR data
            if current_status == 'created':
                logger.info(f"Auto-starting session {ruck_id} on first HR data upload")
                try:
                    supabase.table('ruck_session').update({
                        'status': 'in_progress',
                        'started_at': datetime.now(tz.tzutc()).isoformat(),
                    }).eq('id', ruck_id).execute()
                    current_status = 'in_progress'
                except Exception as e:
                    logger.error(f"Failed to auto-start session {ruck_id} for HR: {e}")
                    return {'message': f"Failed to start session for HR: {str(e)}"}, 500
            
            # Allow HR samples for both in-progress and completed sessions
            if current_status not in ('in_progress', 'completed'):
                logger.warning(f"[HR_CHUNK] Session {ruck_id} has invalid status '{current_status}' for HR upload")
                return {'message': f"Invalid session status for HR upload: {current_status}"}, 400
            
            # Insert heart rate samples (accept 'bpm' or 'heart_rate')
            def _normalize_ts(ts_val):
                try:
                    # If numeric -> epoch ms or seconds
                    if isinstance(ts_val, (int, float)):
                        sec = ts_val / 1000.0 if ts_val > 1e12 else ts_val
                        return datetime.fromtimestamp(sec, tz=tz.tzutc()).isoformat()
                    if isinstance(ts_val, str):
                        try:
                            return datetime.fromisoformat(ts_val.replace('Z', '+00:00')).isoformat()
                        except Exception:
                            return ts_val
                except Exception:
                    return None

            def _coerce_bpm(v):
                try:
                    return int(round(float(v)))
                except Exception:
                    return None

            incoming = data['heart_rate_samples']
            heart_rate_rows = []
            dropped = 0
            for sample in incoming:
                ts = sample.get('timestamp')
                bpm_raw = sample.get('bpm', sample.get('heart_rate'))
                ts_norm = _normalize_ts(ts)
                bpm = _coerce_bpm(bpm_raw)
                if ts_norm is None or bpm is None:
                    dropped += 1
                    continue
                heart_rate_rows.append({
                    'session_id': int(ruck_id),
                    'timestamp': ts_norm,
                    'bpm': bpm
                })

            if not heart_rate_rows:
                logger.warning(f"[HR_CHUNK] No valid heart rate samples in chunk (dropped={dropped}) for session {ruck_id}")
                return {'message': 'No valid heart rate samples in chunk'}, 400

            logger.info(f"[HR_CHUNK] Inserting {len(heart_rate_rows)} HR samples (dropped={dropped}) for session {ruck_id}")
            insert_resp = supabase.table('heart_rate_sample').insert(heart_rate_rows).execute()
            if not insert_resp.data and insert_resp.error:
                logger.error(f"[HR_CHUNK] Failed to insert heart rate samples for session {ruck_id}: {insert_resp.error}")
                return {'message': 'Failed to insert heart rate samples'}, 500
            
            # Clear cache for this user's sessions
            cache_delete_pattern(f"ruck_session:{g.user.id}:*")
            
            logger.info(f"Successfully uploaded heart rate chunk for session {ruck_id}: {len(insert_resp.data)} samples")
            return {'status': 'ok', 'inserted': len(insert_resp.data)}, 201
            
        except Exception as e:
            logger.error(f"Error uploading heart rate chunk for session {ruck_id}: {e}")
            return {'message': f'Error uploading heart rate chunk: {str(e)}'}, 500


class RuckSessionAutoEndResource(Resource):
    def post(self):
        """Check for and auto-end inactive sessions (POST /api/rucks/auto-end)"""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            
            data = request.get_json() or {}
            inactivity_threshold_minutes = data.get('inactivity_minutes', 30)  # Default 30 minutes
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Find active sessions that haven't had location updates recently
            cutoff_time = datetime.now(tz.tzutc()) - timedelta(minutes=inactivity_threshold_minutes)
            
            # Get active sessions
            active_sessions = supabase.table('ruck_session') \
                .select('id,started_at,ruck_weight_kg') \
                .eq('user_id', g.user.id) \
                .eq('status', 'in_progress') \
                .execute()
            
            if not active_sessions.data:
                return {'message': 'No active sessions found'}, 200
            
            sessions_to_end = []
            
            for session in active_sessions.data:
                session_id = session['id']
                
                # Check last location update for this session
                last_location = supabase.table('ruck_session_location') \
                    .select('timestamp') \
                    .eq('ruck_session_id', session_id) \
                    .order('timestamp', desc=True) \
                    .limit(1) \
                    .execute()
                
                if last_location.data:
                    last_timestamp = datetime.fromisoformat(last_location.data[0]['timestamp'].replace('Z', '+00:00'))
                    
                    if last_timestamp < cutoff_time:
                        sessions_to_end.append({
                            'id': session_id,
                            'started_at': session['started_at'],
                            'last_activity': last_timestamp.isoformat(),
                            'inactive_minutes': (datetime.now(tz.tzutc()) - last_timestamp).total_seconds() / 60
                        })
                else:
                    # No location data - check if session is old enough to auto-end
                    started_at = datetime.fromisoformat(session['started_at'].replace('Z', '+00:00'))
                    if started_at < cutoff_time:
                        sessions_to_end.append({
                            'id': session_id,
                            'started_at': session['started_at'],
                            'last_activity': None,
                            'inactive_minutes': (datetime.now(tz.tzutc()) - started_at).total_seconds() / 60
                        })
            
            # Auto-end the inactive sessions if requested
            auto_end = data.get('auto_end', False)
            ended_sessions = []
            
            if auto_end and sessions_to_end:
                for session_info in sessions_to_end:
                    try:
                        # Auto-complete the session
                        supabase.table('ruck_session') \
                            .update({
                                'status': 'completed',
                                'completed_at': datetime.now(tz.tzutc()).isoformat(),
                                'notes': f'Auto-completed due to {session_info["inactive_minutes"]:.0f} minutes of inactivity'
                            }) \
                            .eq('id', session_info['id']) \
                            .eq('user_id', g.user.id) \
                            .execute()
                        
                        ended_sessions.append(session_info['id'])
                        logger.info(f"Auto-ended session {session_info['id']} after {session_info['inactive_minutes']:.0f} minutes of inactivity")
                        
                    except Exception as e:
                        logger.error(f"Failed to auto-end session {session_info['id']}: {e}")
            
            # Clear cache if sessions were ended
            if ended_sessions:
                cache_delete_pattern(f"ruck_session:{g.user.id}:*")
                cache_delete_pattern("ruck_buddies:*")
            
            return {
                'inactive_sessions': sessions_to_end,
                'ended_sessions': ended_sessions,
                'threshold_minutes': inactivity_threshold_minutes
            }, 200
            
        except Exception as e:
            logger.error(f"Error in auto-end sessions: {e}")
            return {'message': f'Error checking inactive sessions: {str(e)}'}, 500