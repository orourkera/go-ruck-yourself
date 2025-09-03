"""
GPX Export API endpoints for generating GPX files from routes and ruck sessions.
Handles converting route data and completed sessions to standard GPX format.
"""

from flask import request, jsonify, make_response, g
from flask_restful import Resource
import logging
from typing import Dict, Any, List, Optional
from decimal import Decimal
from datetime import datetime
import xml.etree.ElementTree as ET
from xml.dom import minidom

from ..supabase_client import get_supabase_client
from ..utils.response_helper import success_response, error_response


logger = logging.getLogger(__name__)

class RouteGPXExportResource(Resource):
    """Export routes as GPX files."""
    
    def get(self, route_id: str):
        """Export a route as GPX file."""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return error_response("Authentication required", 401)
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Get route data
            route_result = supabase.table('routes').select('*').eq('id', route_id).execute()
            
            if not route_result.data:
                return error_response("Route not found", 404)
            
            route_data = route_result.data[0]
            
            # Check if user can access this route
            if not route_data['is_public'] and route_data['created_by_user_id'] != g.user.id:
                return error_response("Route not found", 404)
            
            # Get elevation points
            elevation_result = supabase.table('route_elevation_point').select('*').eq('route_id', route_id).order('distance_km').execute()
            
            # Get POIs
            poi_result = supabase.table('route_point_of_interest').select('*').eq('route_id', route_id).order('distance_from_start_km').execute()
            
            # Generate GPX content
            gpx_content = self._generate_route_gpx(
                route_data, 
                elevation_result.data, 
                poi_result.data
            )
            
            # Create response with GPX file
            response = make_response(gpx_content)
            response.headers['Content-Type'] = 'application/gpx+xml'
            response.headers['Content-Disposition'] = f'attachment; filename="{route_data["name"]}.gpx"'
            
            return response
            
        except Exception as e:
            logger.error(f"Error exporting route GPX {route_id}: {e}")
            return error_response("Failed to export route as GPX", 500)
    
    def _generate_route_gpx(self, route_data: Dict[str, Any], elevation_points: List[Dict[str, Any]], pois: List[Dict[str, Any]]) -> str:
        """Generate GPX XML content for a route."""
        # Create root GPX element
        gpx = ET.Element('gpx')
        gpx.set('version', '1.1')
        gpx.set('creator', 'Rucking App - https://getrucky.com')
        gpx.set('xmlns', 'http://www.topografix.com/GPX/1/1')
        gpx.set('xmlns:xsi', 'http://www.w3.org/2001/XMLSchema-instance')
        gpx.set('xsi:schemaLocation', 'http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd')
        
        # Add metadata
        metadata = ET.SubElement(gpx, 'metadata')
        
        name_elem = ET.SubElement(metadata, 'name')
        name_elem.text = route_data['name']
        
        desc_elem = ET.SubElement(metadata, 'desc')
        desc_elem.text = route_data.get('description', 'Route exported from Rucking App')
        
        time_elem = ET.SubElement(metadata, 'time')
        time_elem.text = datetime.now().isoformat() + 'Z'
        
        # Add bounds if available
        if route_data.get('start_latitude') and route_data.get('start_longitude'):
            bounds = ET.SubElement(metadata, 'bounds')
            bounds.set('minlat', str(route_data.get('start_latitude', 0)))
            bounds.set('minlon', str(route_data.get('start_longitude', 0)))
            bounds.set('maxlat', str(route_data.get('end_latitude', route_data.get('start_latitude', 0))))
            bounds.set('maxlon', str(route_data.get('end_longitude', route_data.get('start_longitude', 0))))
        
        # Add waypoints (POIs)
        for poi in pois:
            wpt = ET.SubElement(gpx, 'wpt')
            wpt.set('lat', str(poi['latitude']))
            wpt.set('lon', str(poi['longitude']))
            
            wpt_name = ET.SubElement(wpt, 'name')
            wpt_name.text = poi['name']
            
            if poi.get('description'):
                wpt_desc = ET.SubElement(wpt, 'desc')
                wpt_desc.text = poi['description']
            
            wpt_type = ET.SubElement(wpt, 'type')
            wpt_type.text = poi.get('poi_type', 'waypoint')
        
        # Add track
        if elevation_points or route_data.get('route_polyline'):
            trk = ET.SubElement(gpx, 'trk')
            
            trk_name = ET.SubElement(trk, 'name')
            trk_name.text = route_data['name']
            
            trk_type = ET.SubElement(trk, 'type')
            trk_type.text = 'Rucking'
            
            trkseg = ET.SubElement(trk, 'trkseg')
            
            # Add track points from elevation data
            if elevation_points:
                for point in elevation_points:
                    trkpt = ET.SubElement(trkseg, 'trkpt')
                    trkpt.set('lat', str(point['latitude']))
                    trkpt.set('lon', str(point['longitude']))
                    
                    if point.get('elevation_m'):
                        ele = ET.SubElement(trkpt, 'ele')
                        ele.text = str(point['elevation_m'])
            
            # Fallback: decode polyline if no elevation points
            elif route_data.get('route_polyline'):
                track_points = self._decode_polyline(route_data['route_polyline'])
                for point in track_points:
                    trkpt = ET.SubElement(trkseg, 'trkpt')
                    trkpt.set('lat', str(point['lat']))
                    trkpt.set('lon', str(point['lng']))
        
        # Convert to pretty-printed XML string
        rough_string = ET.tostring(gpx, encoding='unicode')
        reparsed = minidom.parseString(rough_string)
        
        return reparsed.toprettyxml(indent='  ', encoding='UTF-8').decode('utf-8')
    
    def _decode_polyline(self, polyline: str) -> List[Dict[str, float]]:
        """Decode simple polyline format (lat,lng;lat,lng) to points."""
        points = []
        
        try:
            # Handle our simple format: "lat,lng;lat,lng;..."
            if ';' in polyline:
                for point_str in polyline.split(';'):
                    if ',' in point_str:
                        lat_str, lng_str = point_str.split(',', 1)
                        points.append({
                            'lat': float(lat_str.strip()),
                            'lng': float(lng_str.strip())
                        })
        except Exception as e:
            logger.warning(f"Error decoding polyline: {e}")
        
        return points

class SessionGPXExportResource(Resource):
    """Export completed ruck sessions as GPX files."""
    
    def get(self, session_id: int):
        """Export a ruck session as GPX file."""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return error_response("Authentication required", 401)
        
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Get session data
            session_result = supabase.table('ruck_session').select(
                'id, name, start_time, end_time, total_distance_km, ruck_weight_kg, '
                'user_id, route_id, is_guided_session'
            ).eq('id', session_id).eq('user_id', g.user.id).execute()
            
            if not session_result.data:
                return error_response("Session not found", 404)
            
            session_data = session_result.data[0]
            
            # Get location points for the session
            location_result = supabase.table('location_point').select(
                'latitude, longitude, altitude, recorded_at'
            ).eq('session_id', session_id).order('recorded_at').execute()
            
            # Get route data if it's a guided session
            route_data = None
            if session_data.get('route_id'):
                route_result = supabase.table('routes').select('name, description').eq('id', session_data['route_id']).execute()
                if route_result.data:
                    route_data = route_result.data[0]
            
            # Generate GPX content
            gpx_content = self._generate_session_gpx(
                session_data, 
                location_result.data,
                route_data
            )
            
            # Create response with GPX file
            session_name = session_data.get('name', f"Ruck Session {session_id}")
            filename = f"{session_name.replace(' ', '_')}.gpx"
            
            response = make_response(gpx_content)
            response.headers['Content-Type'] = 'application/gpx+xml'
            response.headers['Content-Disposition'] = f'attachment; filename="{filename}"'
            
            return response
            
        except Exception as e:
            logger.error(f"Error exporting session GPX {session_id}: {e}")
            return error_response("Failed to export session as GPX", 500)
    
    def _generate_session_gpx(self, session_data: Dict[str, Any], location_points: List[Dict[str, Any]], route_data: Optional[Dict[str, Any]] = None) -> str:
        """Generate GPX XML content for a completed ruck session."""
        # Create root GPX element
        gpx = ET.Element('gpx')
        gpx.set('version', '1.1')
        gpx.set('creator', 'Rucking App - https://getrucky.com')
        gpx.set('xmlns', 'http://www.topografix.com/GPX/1/1')
        gpx.set('xmlns:xsi', 'http://www.w3.org/2001/XMLSchema-instance')
        gpx.set('xsi:schemaLocation', 'http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd')
        
        # Add metadata
        metadata = ET.SubElement(gpx, 'metadata')
        
        name_elem = ET.SubElement(metadata, 'name')
        session_name = session_data.get('name', f"Ruck Session {session_data['id']}")
        name_elem.text = session_name
        
        desc_elem = ET.SubElement(metadata, 'desc')
        desc_text = f"Rucking session"
        if session_data.get('ruck_weight_kg'):
            desc_text += f" with {session_data['ruck_weight_kg']}kg pack"
        if session_data.get('total_distance_km'):
            desc_text += f", {session_data['total_distance_km']}km total distance"
        if route_data:
            desc_text += f", following route: {route_data['name']}"
        desc_elem.text = desc_text
        
        time_elem = ET.SubElement(metadata, 'time')
        start_time = session_data.get('start_time')
        if start_time:
            if isinstance(start_time, str):
                time_elem.text = start_time
            else:
                time_elem.text = start_time.isoformat() + 'Z'
        else:
            time_elem.text = datetime.now().isoformat() + 'Z'
        
        # Add track if we have location points
        if location_points:
            trk = ET.SubElement(gpx, 'trk')
            
            trk_name = ET.SubElement(trk, 'name')
            trk_name.text = session_name
            
            trk_type = ET.SubElement(trk, 'type')
            trk_type.text = 'Rucking'
            
            # Add track segment
            trkseg = ET.SubElement(trk, 'trkseg')
            
            for point in location_points:
                trkpt = ET.SubElement(trkseg, 'trkpt')
                trkpt.set('lat', str(point['latitude']))
                trkpt.set('lon', str(point['longitude']))
                
                # Add elevation if available
                if point.get('altitude'):
                    ele = ET.SubElement(trkpt, 'ele')
                    ele.text = str(point['altitude'])
                
                # Add timestamp
                if point.get('recorded_at'):
                    time_elem = ET.SubElement(trkpt, 'time')
                    recorded_at = point['recorded_at']
                    if isinstance(recorded_at, str):
                        time_elem.text = recorded_at
                    else:
                        time_elem.text = recorded_at.isoformat() + 'Z'
        
        # Convert to pretty-printed XML string
        rough_string = ET.tostring(gpx, encoding='unicode')
        reparsed = minidom.parseString(rough_string)
        
        return reparsed.toprettyxml(indent='  ', encoding='UTF-8').decode('utf-8')

class GPXExportBatchResource(Resource):
    """Export multiple sessions or routes as a single GPX file."""
    
    def post(self):
        """Export multiple items as a batch GPX file."""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return error_response("Authentication required", 401)
            
            data = request.get_json()
            if not data:
                return error_response("Request body required", 400)
            
            session_ids = data.get('session_ids', [])
            route_ids = data.get('route_ids', [])
            export_name = data.get('name', 'Batch Export')
            
            if not session_ids and not route_ids:
                return error_response("At least one session_id or route_id is required", 400)
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Create root GPX element
            gpx = ET.Element('gpx')
            gpx.set('version', '1.1')
            gpx.set('creator', 'Rucking App - https://getrucky.com')
            gpx.set('xmlns', 'http://www.topografix.com/GPX/1/1')
            gpx.set('xmlns:xsi', 'http://www.w3.org/2001/XMLSchema-instance')
            gpx.set('xsi:schemaLocation', 'http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd')
            
            # Add metadata
            metadata = ET.SubElement(gpx, 'metadata')
            
            name_elem = ET.SubElement(metadata, 'name')
            name_elem.text = export_name
            
            desc_elem = ET.SubElement(metadata, 'desc')
            desc_elem.text = f"Batch export of {len(session_ids)} sessions and {len(route_ids)} routes from Rucking App"
            
            time_elem = ET.SubElement(metadata, 'time')
            time_elem.text = datetime.now().isoformat() + 'Z'
            
            # Export sessions
            for session_id in session_ids:
                try:
                    self._add_session_to_gpx(gpx, session_id, g.user.id, supabase)
                except Exception as e:
                    logger.warning(f"Failed to add session {session_id} to batch GPX: {e}")
            
            # Export routes
            for route_id in route_ids:
                try:
                    self._add_route_to_gpx(gpx, route_id, g.user.id, supabase)
                except Exception as e:
                    logger.warning(f"Failed to add route {route_id} to batch GPX: {e}")
            
            # Convert to pretty-printed XML string
            rough_string = ET.tostring(gpx, encoding='unicode')
            reparsed = minidom.parseString(rough_string)
            gpx_content = reparsed.toprettyxml(indent='  ', encoding='UTF-8').decode('utf-8')
            
            # Create response
            filename = f"{export_name.replace(' ', '_')}.gpx"
            response = make_response(gpx_content)
            response.headers['Content-Type'] = 'application/gpx+xml'
            response.headers['Content-Disposition'] = f'attachment; filename="{filename}"'
            
            return response
            
        except Exception as e:
            logger.error(f"Error in batch GPX export: {e}")
            return error_response("Failed to export batch GPX", 500)
    
    def _add_session_to_gpx(self, gpx: ET.Element, session_id: int, user_id: str, supabase):
        """Add a session track to the GPX document."""
        # Get session data
        session_result = supabase.table('ruck_session').select(
            'id, name, start_time, end_time, ruck_weight_kg'
        ).eq('id', session_id).eq('user_id', user_id).execute()
        
        if not session_result.data:
            return
        
        session_data = session_result.data[0]
        
        # Get location points
        location_result = supabase.table('location_point').select(
            'latitude, longitude, altitude, recorded_at'
        ).eq('session_id', session_id).order('recorded_at').execute()
        
        if not location_result.data:
            return
        
        # Create track
        trk = ET.SubElement(gpx, 'trk')
        
        trk_name = ET.SubElement(trk, 'name')
        trk_name.text = session_data.get('name', f"Session {session_id}")
        
        trk_type = ET.SubElement(trk, 'type')
        trk_type.text = 'Rucking'
        
        # Add track segment
        trkseg = ET.SubElement(trk, 'trkseg')
        
        for point in location_result.data:
            trkpt = ET.SubElement(trkseg, 'trkpt')
            trkpt.set('lat', str(point['latitude']))
            trkpt.set('lon', str(point['longitude']))
            
            if point.get('altitude'):
                ele = ET.SubElement(trkpt, 'ele')
                ele.text = str(point['altitude'])
            
            if point.get('recorded_at'):
                time_elem = ET.SubElement(trkpt, 'time')
                time_elem.text = point['recorded_at']
    
    def _add_route_to_gpx(self, gpx: ET.Element, route_id: str, user_id: str, supabase):
        """Add a route track to the GPX document."""
        # Get route data
        route_result = supabase.table('routes').select('*').eq('id', route_id).execute()
        
        if not route_result.data:
            return
        
        route_data = route_result.data[0]
        
        # Check access permissions
        if not route_data['is_public'] and route_data['created_by_user_id'] != user_id:
            return
        
        # Get elevation points
        elevation_result = supabase.table('route_elevation_point').select('*').eq('route_id', route_id).order('distance_km').execute()
        
        # Get POIs
        poi_result = supabase.table('route_point_of_interest').select('*').eq('route_id', route_id).execute()
        
        # Add waypoints (POIs)
        for poi in poi_result.data:
            wpt = ET.SubElement(gpx, 'wpt')
            wpt.set('lat', str(poi['latitude']))
            wpt.set('lon', str(poi['longitude']))
            
            wpt_name = ET.SubElement(wpt, 'name')
            wpt_name.text = poi['name']
            
            if poi.get('description'):
                wpt_desc = ET.SubElement(wpt, 'desc')
                wpt_desc.text = poi['description']
        
        # Add track if we have elevation points
        if elevation_result.data:
            trk = ET.SubElement(gpx, 'trk')
            
            trk_name = ET.SubElement(trk, 'name')
            trk_name.text = route_data['name']
            
            trk_type = ET.SubElement(trk, 'type')
            trk_type.text = 'Route'
            
            trkseg = ET.SubElement(trk, 'trkseg')
            
            for point in elevation_result.data:
                trkpt = ET.SubElement(trkseg, 'trkpt')
                trkpt.set('lat', str(point['latitude']))
                trkpt.set('lon', str(point['longitude']))
                
                if point.get('elevation_m'):
                    ele = ET.SubElement(trkpt, 'ele')
                    ele.text = str(point['elevation_m'])
