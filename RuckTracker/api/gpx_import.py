"""
GPX Import API endpoints for processing AllTrails GPX files.
Handles parsing GPX data and creating route records.
"""

from flask import request, jsonify, g
from flask_restful import Resource
import logging
import xml.etree.ElementTree as ET
from typing import Dict, Any, List, Optional
from decimal import Decimal
from datetime import datetime
import re

from ..supabase_client import get_supabase_client
from ..models import Route, RouteElevationPoint, RoutePointOfInterest
from ..utils.auth_helper import get_current_user_id, get_current_user_jwt
from ..services.route_analytics_service import RouteAnalyticsService

logger = logging.getLogger(__name__)

class GPXImportResource(Resource):
    """Handle GPX file import and processing."""
    
    def post(self):
        """Import a GPX file and create route records."""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {
                    "success": False,
                    "message": "Authentication required"
                }, 401
            
            # Get GPX data from JSON payload (same as validation endpoint)
            data = request.get_json()
            if not data:
                return {
                    "success": False,
                    "message": "Request body required"
                }, 400
            
            gpx_content = data.get('gpx_content')
            source_url = data.get('source_url')  # Optional AllTrails URL
            custom_name = data.get('name')  # Optional custom name override
            make_public = data.get('make_public', False)
            
            if not gpx_content:
                return {
                    "success": False,
                    "message": "gpx_content is required"
                }, 400
            
            # Parse GPX content
            try:
                route_data = self._parse_gpx_content(gpx_content, g.user.id, source_url, custom_name)
            except Exception as e:
                logger.error(f"GPX parsing error: {e}")
                return {
                    "success": False,
                    "message": f"Invalid GPX format: {str(e)}"
                }, 400
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Create route record
            route_result = supabase.table('routes').insert(route_data['route']).execute()
            
            if not route_result.data:
                return {
                    "success": False,
                    "message": "Failed to create route"
                }, 500
            
            created_route = route_result.data[0]
            route_id = created_route['id']
            
            # Create elevation points if present
            elevation_points_created = 0
            if route_data.get('elevation_points'):
                for point_data in route_data['elevation_points']:
                    point_data['route_id'] = route_id
                
                elevation_result = supabase.table('route_elevation_point').insert(route_data['elevation_points']).execute()
                elevation_points_created = len(elevation_result.data) if elevation_result.data else 0
            
            # Create POIs if present
            pois_created = 0
            if route_data.get('points_of_interest'):
                for poi_data in route_data['points_of_interest']:
                    poi_data['route_id'] = route_id
                
                poi_result = supabase.table('route_point_of_interest').insert(route_data['points_of_interest']).execute()
                pois_created = len(poi_result.data) if poi_result.data else 0
            
            # Record analytics with authenticated client
            try:
                user_jwt = get_current_user_jwt()
                analytics_service = RouteAnalyticsService(user_jwt=user_jwt)
                analytics_service.record_route_created(route_id, g.user.id)
            except Exception as e:
                logger.warning(f"Failed to record import analytics: {e}")
            
            return {
                "success": True,
                "message": "GPX file imported successfully",
                "data": {
                    'route': created_route,
                    'elevation_points_created': elevation_points_created,
                    'pois_created': pois_created
                }
            }, 201
            
        except Exception as e:
            logger.error(f"Error importing GPX: {e}")
            return {
                "success": False,
                "message": "Failed to import GPX file"
            }, 500
    
    def _parse_gpx_content(self, gpx_content: str, user_id: str, source_url: Optional[str] = None, custom_name: Optional[str] = None) -> Dict[str, Any]:
        """Parse GPX XML content and extract route data."""
        try:
            # Parse XML
            root = ET.fromstring(gpx_content)
            
            # Handle namespace
            ns = {'gpx': 'http://www.topografix.com/GPX/1/1'}
            if not root.tag.startswith('{'):
                ns = {}  # No namespace
            
            # Extract metadata
            metadata = self._extract_metadata(root, ns)
            
            # Extract track data
            tracks = self._extract_tracks(root, ns)
            
            if not tracks:
                raise ValueError("No tracks found in GPX file")
            
            # Use first track for route data
            main_track = tracks[0]
            
            # Generate route polyline from track points
            polyline = self._generate_polyline(main_track['points'])
            
            # Calculate bounds
            bounds = self._calculate_bounds(main_track['points'])
            
            # Determine source
            source = 'alltrails' if source_url and 'alltrails.com' in source_url else 'manual'
            
            # Build route data
            route_data = {
                'name': custom_name or main_track.get('name') or metadata.get('name') or 'Imported Route',
                'description': metadata.get('description') or f"Route imported from GPX file",
                'source': source,
                'external_url': source_url,
                'created_by_user_id': user_id,
                'route_polyline': polyline,
                'start_latitude': bounds['min_lat'],
                'start_longitude': bounds['min_lng'],
                'end_latitude': bounds['max_lat'],
                'end_longitude': bounds['max_lng'],
                'distance_km': main_track['distance_km'],
                'elevation_gain_m': main_track['elevation_gain_m'],
                'elevation_loss_m': main_track['elevation_loss_m'],
                'trail_difficulty': self._estimate_difficulty(main_track['distance_km'], main_track['elevation_gain_m']),
                'trail_type': 'out_and_back',  # Default for GPX imports
                'surface_type': 'mixed',  # Default for GPX imports
                'is_public': False,  # User-imported routes are private by default
                'is_verified': source == 'alltrails',  # AllTrails routes are considered verified
                'created_at': datetime.now().isoformat(),
                'updated_at': datetime.now().isoformat()
            }
            
            # Extract elevation points
            elevation_points = self._extract_elevation_points(main_track['points'])
            
            # Extract POIs (waypoints)
            pois = self._extract_waypoints(root, ns)
            
            return {
                'route': route_data,
                'elevation_points': elevation_points,
                'points_of_interest': pois
            }
            
        except ET.ParseError as e:
            raise ValueError(f"Invalid XML format: {e}")
        except Exception as e:
            raise ValueError(f"GPX parsing error: {e}")
    
    def _extract_metadata(self, root: ET.Element, ns: Dict[str, str]) -> Dict[str, Any]:
        """Extract metadata from GPX file."""
        metadata = {}
        
        # Try to find metadata element
        metadata_elem = root.find('.//gpx:metadata', ns) or root.find('.//metadata')
        
        if metadata_elem is not None:
            name_elem = metadata_elem.find('.//gpx:name', ns) or metadata_elem.find('.//name')
            if name_elem is not None:
                metadata['name'] = name_elem.text
            
            desc_elem = metadata_elem.find('.//gpx:desc', ns) or metadata_elem.find('.//desc')
            if desc_elem is not None:
                metadata['description'] = desc_elem.text
        
        return metadata
    
    def _extract_tracks(self, root: ET.Element, ns: Dict[str, str]) -> List[Dict[str, Any]]:
        """Extract track data from GPX file."""
        tracks = []
        
        # Find all track elements
        track_elements = root.findall('.//gpx:trk', ns) or root.findall('.//trk')
        
        for trk_elem in track_elements:
            track_data = {'points': [], 'distance_km': 0, 'elevation_gain_m': 0, 'elevation_loss_m': 0}
            
            # Get track name
            name_elem = trk_elem.find('.//gpx:name', ns) or trk_elem.find('.//name')
            if name_elem is not None:
                track_data['name'] = name_elem.text
            
            # Get track segments
            trkseg_elements = trk_elem.findall('.//gpx:trkseg', ns) or trk_elem.findall('.//trkseg')
            
            for trkseg in trkseg_elements:
                trkpt_elements = trkseg.findall('.//gpx:trkpt', ns) or trkseg.findall('.//trkpt')
                
                for trkpt in trkpt_elements:
                    lat = float(trkpt.get('lat'))
                    lon = float(trkpt.get('lon'))
                    
                    point = {'lat': lat, 'lon': lon}
                    
                    # Get elevation
                    ele_elem = trkpt.find('.//gpx:ele', ns) or trkpt.find('.//ele')
                    if ele_elem is not None:
                        elevation = float(ele_elem.text)
                        # Filter out obviously corrupted elevation values
                        # Valid elevations should be between -500m (below sea level) and 9000m (highest mountains)
                        if -500 <= elevation <= 9000:
                            point['elevation'] = elevation
                    
                    # Get time
                    time_elem = trkpt.find('.//gpx:time', ns) or trkpt.find('.//time')
                    if time_elem is not None:
                        point['time'] = time_elem.text
                    
                    track_data['points'].append(point)
            
            # Calculate distance and elevation
            if track_data['points']:
                track_data.update(self._calculate_track_metrics(track_data['points']))
                tracks.append(track_data)
        
        return tracks
    
    def _calculate_track_metrics(self, points: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Calculate distance and elevation metrics for track points."""
        total_distance = 0
        elevation_gain = 0
        elevation_loss = 0
        
        for i in range(1, len(points)):
            prev_point = points[i-1]
            curr_point = points[i]
            
            # Calculate distance using Haversine formula
            distance = self._haversine_distance(
                prev_point['lat'], prev_point['lon'],
                curr_point['lat'], curr_point['lon']
            )
            total_distance += distance
            
            # Calculate elevation changes
            if 'elevation' in prev_point and 'elevation' in curr_point:
                elevation_diff = curr_point['elevation'] - prev_point['elevation']
                # Only count reasonable elevation changes (filter out GPS noise and corrupted data)
                # Max reasonable elevation change per segment is ~200m for hiking trails
                if abs(elevation_diff) <= 200:
                    if elevation_diff > 0:
                        elevation_gain += elevation_diff
                    else:
                        elevation_loss += abs(elevation_diff)
        
        return {
            'distance_km': round(total_distance / 1000, 2),  # Convert to km
            'elevation_gain_m': round(elevation_gain, 1),
            'elevation_loss_m': round(elevation_loss, 1)
        }
    
    def _haversine_distance(self, lat1: float, lon1: float, lat2: float, lon2: float) -> float:
        """Calculate distance between two points using Haversine formula (returns meters)."""
        import math
        
        # Convert to radians
        lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
        
        # Haversine formula
        dlat = lat2 - lat1
        dlon = lon2 - lon1
        a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
        c = 2 * math.asin(math.sqrt(a))
        r = 6371000  # Earth's radius in meters
        
        return c * r
    
    def _generate_polyline(self, points: List[Dict[str, Any]]) -> str:
        """Generate a simplified polyline string from track points."""
        # Simplify points (take every 10th point to reduce size)
        simplified_points = points[::10] if len(points) > 100 else points
        
        # Create simple polyline format (lat,lng pairs separated by semicolons)
        polyline_parts = []
        for point in simplified_points:
            polyline_parts.append(f"{point['lat']:.6f},{point['lon']:.6f}")
        
        return ';'.join(polyline_parts)
    
    def _calculate_bounds(self, points: List[Dict[str, Any]]) -> Dict[str, float]:
        """Calculate bounding box for track points."""
        if not points:
            return {'min_lat': 0, 'max_lat': 0, 'min_lng': 0, 'max_lng': 0}
        
        lats = [p['lat'] for p in points]
        lngs = [p['lon'] for p in points]
        
        return {
            'min_lat': min(lats),
            'max_lat': max(lats),
            'min_lng': min(lngs),
            'max_lng': max(lngs)
        }
    
    def _estimate_difficulty(self, distance_km: float, elevation_gain_m: float) -> str:
        """Estimate trail difficulty based on distance and elevation."""
        # Simple difficulty estimation algorithm
        difficulty_score = 0
        
        # Distance factor
        if distance_km > 20:
            difficulty_score += 3
        elif distance_km > 10:
            difficulty_score += 2
        elif distance_km > 5:
            difficulty_score += 1
        
        # Elevation factor
        elevation_per_km = elevation_gain_m / distance_km if distance_km > 0 else 0
        
        if elevation_per_km > 100:
            difficulty_score += 3
        elif elevation_per_km > 50:
            difficulty_score += 2
        elif elevation_per_km > 25:
            difficulty_score += 1
        
        # Map score to difficulty
        if difficulty_score >= 5:
            return 'extreme'
        elif difficulty_score >= 3:
            return 'hard'
        elif difficulty_score >= 1:
            return 'moderate'
        else:
            return 'easy'
    
    def _extract_elevation_points(self, points: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Extract elevation points for detailed elevation profile."""
        elevation_points = []
        cumulative_distance = 0
        
        for i, point in enumerate(points):
            if 'elevation' not in point:
                continue
            
            # Calculate distance from start
            if i > 0:
                distance = self._haversine_distance(
                    points[i-1]['lat'], points[i-1]['lon'],
                    point['lat'], point['lon']
                )
                cumulative_distance += distance
            
            # Calculate grade if possible
            grade_percent = None
            if i > 0 and 'elevation' in points[i-1]:
                distance_m = self._haversine_distance(
                    points[i-1]['lat'], points[i-1]['lon'],
                    point['lat'], point['lon']
                )
                if distance_m > 0:
                    elevation_diff = point['elevation'] - points[i-1]['elevation']
                    grade_percent = (elevation_diff / distance_m) * 100
            
            elevation_point = {
                'distance_km': round(cumulative_distance / 1000, 3),
                'elevation_m': round(point['elevation'], 1),
                'latitude': point['lat'],
                'longitude': point['lon'],
                'grade_percent': round(grade_percent, 1) if grade_percent is not None else None,
                'created_at': datetime.now().isoformat()
            }
            
            elevation_points.append(elevation_point)
        
        # Simplify elevation points (keep every 50th point or so)
        if len(elevation_points) > 200:
            step = len(elevation_points) // 200
            elevation_points = elevation_points[::step]
        
        return elevation_points
    
    def _extract_waypoints(self, root: ET.Element, ns: Dict[str, str]) -> List[Dict[str, Any]]:
        """Extract waypoints as points of interest."""
        pois = []
        
        # Find all waypoint elements
        wpt_elements = root.findall('.//gpx:wpt', ns) or root.findall('.//wpt')
        
        for wpt in wpt_elements:
            lat = float(wpt.get('lat'))
            lon = float(wpt.get('lon'))
            
            # Get waypoint name
            name_elem = wpt.find('.//gpx:name', ns) or wpt.find('.//name')
            name = name_elem.text if name_elem is not None else 'Waypoint'
            
            # Get description
            desc_elem = wpt.find('.//gpx:desc', ns) or wpt.find('.//desc')
            description = desc_elem.text if desc_elem is not None else None
            
            # Get type
            type_elem = wpt.find('.//gpx:type', ns) or wpt.find('.//type')
            poi_type_raw = type_elem.text if type_elem is not None else 'landmark'
            
            # Validate poi_type against allowed values
            allowed_poi_types = ['water', 'rest', 'viewpoint', 'hazard', 'parking', 'landmark', 'shelter']
            poi_type = poi_type_raw if poi_type_raw in allowed_poi_types else 'landmark'
            
            poi = {
                'name': name,
                'description': description,
                'latitude': lat,
                'longitude': lon,
                'poi_type': poi_type,
                'distance_from_start_km': 0,  # Will be calculated later if needed
                'created_at': datetime.now().isoformat()
            }
            
            pois.append(poi)
        
        return pois

class GPXValidateResource(Resource):
    """Validate GPX file content without importing."""
    
    def post(self):
        """Validate GPX content and return parsed metadata."""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {
                    "success": False,
                    "message": "Authentication required"
                }, 401
            
            data = request.get_json()
            if not data or not data.get('gpx_content'):
                return {
                    "success": False,
                    "message": "gpx_content is required"
                }, 400
            
            gpx_content = data['gpx_content']
            
            # Create temporary import instance for parsing
            import_resource = GPXImportResource()
            
            try:
                parsed_data = import_resource._parse_gpx_content(gpx_content, g.user.id)
                
                # Return validation results
                route_data = parsed_data['route']
                
                validation_result = {
                    'valid': True,
                    'route_preview': {
                        'name': route_data['name'],
                        'description': route_data['description'],
                        'distance_km': route_data['distance_km'],
                        'elevation_gain_m': route_data['elevation_gain_m'],
                        'estimated_difficulty': route_data['trail_difficulty'],
                        'start_location': [route_data['start_latitude'], route_data['start_longitude']],
                        'end_location': [route_data['end_latitude'], route_data['end_longitude']]
                    },
                    'elevation_points_count': len(parsed_data.get('elevation_points', [])),
                    'pois_count': len(parsed_data.get('points_of_interest', [])),
                    'source': route_data['source']
                }
                
                return {
                    "success": True,
                    "message": "GPX validation completed",
                    "data": validation_result
                }, 200
                
            except ValueError as e:
                return {
                    "success": True,
                    "message": "GPX validation completed",
                    "data": {
                        'valid': False,
                        'error': str(e),
                        'message': 'Invalid GPX format'
                    }
                }, 200
                
        except Exception as e:
            logger.error(f"Error validating GPX: {e}")
            return {
                "success": False,
                "message": "Failed to validate GPX file"
            }, 500
