"""
Routes API endpoints for AllTrails integration.
Handles CRUD operations for routes and related data.
"""

from flask import request, jsonify, g
from flask_restful import Resource
import logging
from typing import Dict, Any, List, Optional
from decimal import Decimal
from datetime import datetime

from ..supabase_client import get_supabase_client
from ..models import Route, RouteElevationPoint, RoutePointOfInterest
from ..utils.api_response import success_response, error_response
from ..utils.auth_helper import get_current_user_id, get_current_user_jwt
from ..services.route_analytics_service import RouteAnalyticsService

logger = logging.getLogger(__name__)

class RoutesResource(Resource):
    """Handle routes collection operations."""
    
    def get(self):
        """Get list of routes with optional filtering."""
        try:
            # Get query parameters
            source = request.args.get('source')  # alltrails, custom, community
            difficulty = request.args.get('difficulty')  # easy, moderate, hard, extreme
            min_distance = request.args.get('min_distance', type=float)
            max_distance = request.args.get('max_distance', type=float)
            search = request.args.get('search')  # Search in name/description
            created_by_me = request.args.get('created_by_me', 'false').lower() == 'true'
            limit = request.args.get('limit', 20, type=int)
            offset = request.args.get('offset', 0, type=int)
            
            # Get current user for RLS
            user_id = get_current_user_id()
            if not user_id:
                return error_response("Authentication required", 401)
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Build query
            query = supabase.table('routes').select(
                'id, name, description, source, external_id, external_url, '
                'start_latitude, start_longitude, end_latitude, end_longitude, '
                'distance_km, elevation_gain_m, elevation_loss_m, '
                'trail_difficulty, trail_type, surface_type, '
                'total_planned_count, total_completed_count, average_rating, '
                'created_at, updated_at, created_by_user_id, is_verified, is_public'
            )
            
            # Apply filters
            if source:
                query = query.eq('source', source)
            
            if difficulty:
                query = query.eq('trail_difficulty', difficulty)
            
            if min_distance:
                query = query.gte('distance_km', min_distance)
            
            if max_distance:
                query = query.lte('distance_km', max_distance)
            
            if search:
                # Search in name and description
                query = query.or_(f'name.ilike.%{search}%,description.ilike.%{search}%')
            
            # Handle created_by_me filter
            if created_by_me:
                # Filter to user's own routes
                query = query.eq('created_by_user_id', user_id)
            else:
                # Include public routes in addition to user's own routes (RLS handles user's routes)
                query = query.eq('is_public', True)
            
            # Order by popularity and apply pagination
            query = query.order('total_completed_count', desc=True)
            query = query.range(offset, offset + limit - 1)
            
            result = query.execute()
            
            # Convert to Route objects
            routes = []
            for route_data in result.data:
                try:
                    route = Route.from_dict(route_data)
                    routes.append(route.to_dict())
                except Exception as e:
                    logger.warning(f"Error parsing route {route_data.get('id')}: {e}")
                    continue
            
            return success_response({
                'routes': routes,
                'count': len(routes),
                'offset': offset,
                'limit': limit
            })
            
        except Exception as e:
            logger.error(f"Error fetching routes: {e}")
            return error_response("Failed to fetch routes", 500)
    
    def post(self):
        """Create a new route."""
        try:
            # Get current user
            user_id = get_current_user_id()
            if not user_id:
                return error_response("Authentication required", 401)
            
            data = request.get_json()
            if not data:
                return error_response("Request body required", 400)
            
            # Validate required fields
            required_fields = ['name', 'source', 'start_latitude', 'start_longitude', 
                             'route_polyline', 'distance_km']
            for field in required_fields:
                if not data.get(field):
                    return error_response(f"Missing required field: {field}", 400)
            
            # Set user as creator
            data['created_by_user_id'] = user_id
            data['created_at'] = datetime.now().isoformat()
            data['updated_at'] = datetime.now().isoformat()
            
            # Create Route object for validation
            route = Route.from_dict(data)
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Insert route
            result = supabase.table('routes').insert(route.to_dict()).execute()
            
            if not result.data:
                return error_response("Failed to create route", 500)
            
            created_route = Route.from_dict(result.data[0])
            
            # Record analytics event with authenticated client
            try:
                user_jwt = get_current_user_jwt()
                analytics_service = RouteAnalyticsService(user_jwt=user_jwt)
                analytics_service.record_route_created(created_route.id, user_id)
            except Exception as e:
                logger.warning(f"Failed to record route creation analytics: {e}")
            
            return success_response({
                'route': created_route.to_dict(),
                'message': 'Route created successfully'
            }, 201)
            
        except ValueError as e:
            return error_response(f"Validation error: {e}", 400)
        except Exception as e:
            logger.error(f"Error creating route: {e}")
            return error_response("Failed to create route", 500)

class RouteResource(Resource):
    """Handle individual route operations."""
    
    def get(self, route_id: str):
        """Get a specific route with detailed data."""
        try:
            user_id = get_current_user_id()
            if not user_id:
                return error_response("Authentication required", 401)
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Get route
            result = supabase.table('routes').select('*').eq('id', route_id).execute()
            
            if not result.data:
                return error_response("Route not found", 404)
            
            route_data = result.data[0]
            
            # Check if user can access this route (public or owned by user)
            if not route_data['is_public'] and route_data['created_by_user_id'] != user_id:
                return error_response("Route not found", 404)
            
            # Get elevation points
            elevation_result = supabase.table('route_elevation_point').select('*').eq('route_id', route_id).order('distance_km').execute()
            
            # Get POIs
            poi_result = supabase.table('route_point_of_interest').select('*').eq('route_id', route_id).order('distance_from_start_km').execute()
            
            # Build Route object with related data
            route_data['elevation_points'] = elevation_result.data
            route_data['points_of_interest'] = poi_result.data
            
            route = Route.from_dict(route_data)
            
            # Record view analytics (if not viewing own route)
            if route.created_by_user_id != user_id:
                try:
                    analytics_service = RouteAnalyticsService()
                    analytics_service.record_route_viewed(route_id, user_id)
                except Exception as e:
                    logger.warning(f"Failed to record route view analytics: {e}")
            
            return success_response({
                'route': route.to_dict(include_elevation_points=True, include_pois=True)
            })
            
        except Exception as e:
            logger.error(f"Error fetching route {route_id}: {e}")
            return error_response("Failed to fetch route", 500)
    
    def put(self, route_id: str):
        """Update a route."""
        try:
            user_id = get_current_user_id()
            if not user_id:
                return error_response("Authentication required", 401)
            
            data = request.get_json()
            if not data:
                return error_response("Request body required", 400)
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Check if route exists and user owns it
            existing_result = supabase.table('routes').select('created_by_user_id').eq('id', route_id).execute()
            
            if not existing_result.data:
                return error_response("Route not found", 404)
            
            if existing_result.data[0]['created_by_user_id'] != user_id:
                return error_response("Permission denied", 403)
            
            # Remove fields that shouldn't be updated
            data.pop('id', None)
            data.pop('created_by_user_id', None)
            data.pop('created_at', None)
            data['updated_at'] = datetime.now().isoformat()
            
            # Update route
            result = supabase.table('routes').update(data).eq('id', route_id).execute()
            
            if not result.data:
                return error_response("Failed to update route", 500)
            
            updated_route = Route.from_dict(result.data[0])
            
            return success_response({
                'route': updated_route.to_dict(),
                'message': 'Route updated successfully'
            })
            
        except Exception as e:
            logger.error(f"Error updating route {route_id}: {e}")
            return error_response("Failed to update route", 500)
    
    def delete(self, route_id: str):
        """Delete a route."""
        try:
            user_id = get_current_user_id()
            if not user_id:
                return error_response("Authentication required", 401)
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Check if route exists and user owns it
            existing_result = supabase.table('routes').select('created_by_user_id').eq('id', route_id).execute()
            
            if not existing_result.data:
                return error_response("Route not found", 404)
            
            if existing_result.data[0]['created_by_user_id'] != user_id:
                return error_response("Permission denied", 403)
            
            # Delete route (cascade will handle related records)
            result = supabase.table('routes').delete().eq('id', route_id).execute()
            
            if not result.data:
                return error_response("Failed to delete route", 500)
            
            return success_response({
                'message': 'Route deleted successfully'
            })
            
        except Exception as e:
            logger.error(f"Error deleting route {route_id}: {e}")
            return error_response("Failed to delete route", 500)

class RouteElevationResource(Resource):
    """Handle route elevation points."""
    
    def get(self, route_id: str):
        """Get elevation profile for a route."""
        try:
            user_id = get_current_user_id()
            if not user_id:
                return error_response("Authentication required", 401)
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Verify route access
            route_result = supabase.table('routes').select('is_public, created_by_user_id').eq('id', route_id).execute()
            
            if not route_result.data:
                return error_response("Route not found", 404)
            
            route_data = route_result.data[0]
            if not route_data['is_public'] and route_data['created_by_user_id'] != user_id:
                return error_response("Route not found", 404)
            
            # Get elevation points
            result = supabase.table('route_elevation_point').select('*').eq('route_id', route_id).order('distance_km').execute()
            
            elevation_points = []
            for point_data in result.data:
                point = RouteElevationPoint(
                    id=point_data['id'],
                    route_id=point_data['route_id'],
                    distance_km=Decimal(str(point_data['distance_km'])),
                    elevation_m=Decimal(str(point_data['elevation_m'])),
                    latitude=Decimal(str(point_data['latitude'])) if point_data.get('latitude') else None,
                    longitude=Decimal(str(point_data['longitude'])) if point_data.get('longitude') else None,
                    terrain_type=point_data.get('terrain_type'),
                    grade_percent=Decimal(str(point_data['grade_percent'])) if point_data.get('grade_percent') else None,
                    created_at=datetime.fromisoformat(point_data['created_at']) if point_data.get('created_at') else None
                )
                elevation_points.append(point.to_dict())
            
            return success_response({
                'elevation_points': elevation_points,
                'count': len(elevation_points)
            })
            
        except Exception as e:
            logger.error(f"Error fetching elevation data for route {route_id}: {e}")
            return error_response("Failed to fetch elevation data", 500)

class RouteSearchResource(Resource):
    """Handle route search with advanced filtering."""
    
    def post(self):
        """Advanced route search with multiple criteria."""
        try:
            user_id = get_current_user_id()
            if not user_id:
                return error_response("Authentication required", 401)
            
            data = request.get_json() or {}
            
            # Extract search criteria
            search_text = data.get('search')
            center_lat = data.get('center_latitude')
            center_lng = data.get('center_longitude')
            radius_km = data.get('radius_km', 50)  # Default 50km radius
            difficulty_levels = data.get('difficulty_levels', [])  # List of difficulties
            distance_range = data.get('distance_range', {})  # {min: x, max: y}
            elevation_range = data.get('elevation_range', {})  # {min: x, max: y}
            sources = data.get('sources', [])  # List of sources
            limit = data.get('limit', 20)
            offset = data.get('offset', 0)
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Start with base query
            query = supabase.table('routes').select(
                'id, name, description, source, external_url, '
                'start_latitude, start_longitude, distance_km, elevation_gain_m, '
                'trail_difficulty, trail_type, surface_type, '
                'total_completed_count, average_rating, is_verified'
            )
            
            # Only public routes or user's own routes
            query = query.or_('is_public.eq.true,created_by_user_id.eq.' + user_id)
            
            # Apply filters
            if search_text:
                query = query.or_(f'name.ilike.%{search_text}%,description.ilike.%{search_text}%')
            
            if difficulty_levels:
                difficulty_filter = ','.join([f'trail_difficulty.eq.{d}' for d in difficulty_levels])
                query = query.or_(difficulty_filter)
            
            if distance_range.get('min'):
                query = query.gte('distance_km', distance_range['min'])
            
            if distance_range.get('max'):
                query = query.lte('distance_km', distance_range['max'])
            
            if elevation_range.get('min'):
                query = query.gte('elevation_gain_m', elevation_range['min'])
            
            if elevation_range.get('max'):
                query = query.lte('elevation_gain_m', elevation_range['max'])
            
            if sources:
                source_filter = ','.join([f'source.eq.{s}' for s in sources])
                query = query.or_(source_filter)
            
            # Geographic filtering would require PostGIS functions
            # For now, we'll skip it and do client-side filtering if needed
            
            # Order by relevance (completion count, rating, verified status)
            query = query.order('is_verified', desc=True)
            query = query.order('total_completed_count', desc=True)
            query = query.range(offset, offset + limit - 1)
            
            result = query.execute()
            
            # Convert and potentially filter by location
            routes = []
            for route_data in result.data:
                try:
                    route = Route.from_dict(route_data)
                    route_dict = route.to_dict()
                    
                    # Client-side distance filtering if center provided
                    if center_lat and center_lng and route.start_latitude and route.start_longitude:
                        distance = self._calculate_distance(
                            center_lat, center_lng,
                            float(route.start_latitude), float(route.start_longitude)
                        )
                        if distance > radius_km:
                            continue
                        route_dict['distance_from_center_km'] = round(distance, 1)
                    
                    routes.append(route_dict)
                except Exception as e:
                    logger.warning(f"Error parsing route {route_data.get('id')}: {e}")
                    continue
            
            return success_response({
                'routes': routes,
                'count': len(routes),
                'offset': offset,
                'limit': limit,
                'search_criteria': data
            })
            
        except Exception as e:
            logger.error(f"Error in route search: {e}")
            return error_response("Search failed", 500)
    
    def _calculate_distance(self, lat1: float, lng1: float, lat2: float, lng2: float) -> float:
        """Calculate distance between two points using Haversine formula."""
        import math
        
        # Convert to radians
        lat1, lng1, lat2, lng2 = map(math.radians, [lat1, lng1, lat2, lng2])
        
        # Haversine formula
        dlat = lat2 - lat1
        dlng = lng2 - lng1
        a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlng/2)**2
        c = 2 * math.asin(math.sqrt(a))
        r = 6371  # Earth's radius in kilometers
        
        return c * r
