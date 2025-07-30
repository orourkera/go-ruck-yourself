"""
Planned Rucks API endpoints for AllTrails integration.
Handles CRUD operations for planned ruck sessions.
"""

from flask import request, g
from flask_restful import Resource
import logging
from typing import Dict, Any, List, Optional
from decimal import Decimal
from datetime import datetime, timedelta

from ..supabase_client import get_supabase_client
from ..models import PlannedRuck
# Removed unused response helper imports to prevent serialization issues
from ..services.route_analytics_service import RouteAnalyticsService

logger = logging.getLogger(__name__)

class PlannedRucksResource(Resource):
    """Handle planned rucks collection operations."""
    
    def get(self):
        """Get user's planned rucks with optional filtering."""
        try:
            # Use same authentication pattern as working endpoints
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            
            logger.info(f"Current user_id: {g.user.id}")
            logger.info(f"Auth header present: {'Authorization' in request.headers}")
            
            # Get query parameters
            status = request.args.get('status', 'planned')  # planned, in_progress, completed, cancelled
            date_from = request.args.get('date_from')  # ISO date string
            date_to = request.args.get('date_to')  # ISO date string
            route_id = request.args.get('route_id')
            include_route = request.args.get('include_route', 'false').lower() == 'true'
            limit = request.args.get('limit', 50, type=int)
            offset = request.args.get('offset', 0, type=int)
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Build query - user can only see their own planned rucks
            query = supabase.table('planned_ruck').select('*').eq('user_id', g.user.id)
            
            # Apply filters
            if status:
                query = query.eq('status', status)
            
            if route_id:
                query = query.eq('route_id', route_id)
            
            if date_from:
                query = query.gte('planned_date', date_from)
            
            if date_to:
                query = query.lte('planned_date', date_to)
            
            # Order by planned date (upcoming first, then overdue)
            query = query.order('planned_date', desc=False)
            query = query.range(offset, offset + limit - 1)
            
            result = query.execute()
            planned_rucks_data = result.data or []
            
            # If empty:
            if not planned_rucks_data:
                return {
                    "success": True,
                    "data": {
                        "planned_rucks": [],
                        "count": 0,
                        "offset": offset,
                        "limit": limit
                    }
                }, 200

            # Collect route_ids:
            route_ids = {pr['route_id'] for pr in planned_rucks_data if pr.get('route_id')}

            # Fetch routes if include_route and route_ids:
            routes_by_id = {}
            if include_route and route_ids:
                routes_result = supabase.table('routes').select('id, name, description, distance_km, elevation_gain_m, trail_difficulty, trail_type, surface_type').in_('id', list(route_ids)).execute()
                routes_by_id = {route['id']: route for route in routes_result.data or []}

            # Add routes to planned_rucks_data:
            for pr in planned_rucks_data:
                if include_route and pr.get('route_id') in routes_by_id:
                    pr['route'] = routes_by_id[pr['route_id']]

            # Return:
            return {
                'success': True,
                'data': {
                    'planned_rucks': planned_rucks_data,
                    'count': len(planned_rucks_data),
                    'offset': offset,
                    'limit': limit
                }
            }, 200
            
        except Exception as e:
            logger.error(f"Error fetching planned rucks: {e}")
            return {"success": False, "error": "Failed to fetch planned rucks"}, 500
    
    def post(self):
        """Create a new planned ruck."""
        try:
            # Use same authentication pattern as working endpoints
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            
            data = request.get_json()
            if not data:
                return {"success": False, "error": "Request body required"}, 400
            
            # Validate required fields
            if not data.get('route_id'):
                return {"success": False, "error": "route_id is required"}, 400
            
            # Set user as owner
            data['user_id'] = g.user.id
            data['created_at'] = datetime.now().isoformat()
            data['updated_at'] = datetime.now().isoformat()
            data['status'] = 'planned'  # Always start as planned
            
            # Create PlannedRuck object for validation  
            planned_ruck = PlannedRuck.from_dict(data)
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Verify route exists and user can access it
            route_result = supabase.table('routes').select('id, name, distance_km, elevation_gain_m, is_public, created_by_user_id').eq('id', planned_ruck.route_id).execute()
            
            if not route_result.data:
                return {"success": False, "error": "Route not found", "status": 404}
            
            route_data = route_result.data[0]
            if not route_data['is_public'] and route_data['created_by_user_id'] != g.user.id:
                return {"success": False, "error": "Route not found", "status": 404}
            
            # Calculate projections if user profile data is available
            try:
                self._calculate_projections(planned_ruck, route_data, g.user.id, supabase)
            except Exception as e:
                logger.warning(f"Failed to calculate projections: {e}")
            
            # Insert planned ruck
            result = supabase.table('planned_ruck').insert(planned_ruck.to_dict()).execute()
            
            if not result.data:
                return {"success": False, "error": "Failed to create planned ruck", "status": 500}
            
            created_planned_ruck = PlannedRuck.from_dict(result.data[0])
            
            # Record analytics event
            try:
                analytics_service = RouteAnalyticsService()
                analytics_service.record_route_planned(planned_ruck.route_id, g.user.id)
            except Exception as e:
                logger.warning(f"Failed to record planned ruck analytics: {e}")
            
            return ({"success": True, "data": {"planned_ruck": created_planned_ruck.to_dict(), "message": "Planned ruck created successfully"}, "status": 201})
            
        except ValueError as e:
            return ({"success": False, "error": f"Validation error: {e}", "status": 400})
        except Exception as e:
            logger.error(f"Error creating planned ruck: {e}")
            return {"success": False, "error": "Failed to create planned ruck", "status": 500}
            
    def _calculate_projections(self, planned_ruck: PlannedRuck, route_data: Dict[str, Any], user_id: str, supabase):
        """Calculate estimated duration, calories, and difficulty for planned ruck."""
        try:
            # Get user profile for calculations
            user_result = supabase.table('user').select('weight_kg, fitness_level').eq('id', user_id).execute()
            
            if not user_result.data:
                return
            
            user_data = user_result.data[0]
            user_weight_kg = Decimal(str(user_data.get('weight_kg', 70)))  # Default 70kg
            fitness_level = user_data.get('fitness_level', 'moderate')  # Default moderate
            
            route_distance_km = Decimal(str(route_data['distance_km']))
            route_elevation_gain_m = Decimal(str(route_data.get('elevation_gain_m', 0)))
            
            # Calculate duration
            planned_ruck.calculate_estimated_duration(route_distance_km, fitness_level)
            
            # Calculate calories
            planned_ruck.calculate_estimated_calories(route_distance_km, user_weight_kg)
            
            # Generate difficulty description
            planned_ruck.generate_difficulty_description(route_elevation_gain_m)
            
        except Exception as e:
            logger.warning(f"Error calculating projections: {e}")

class PlannedRuckResource(Resource):
    """Handle individual planned ruck operations."""
    
    def get(self, planned_ruck_id: str):
        """Get a specific planned ruck."""
        try:
            # Use same authentication pattern as working endpoints
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Get planned ruck (user can only access their own)
            result = supabase.table('planned_ruck').select('*').eq('id', planned_ruck_id).eq('user_id', g.user.id).execute()
            
            if not result.data:
                return {"success": False, "error": "Planned ruck not found", "status": 404}
            
            planned_ruck = PlannedRuck.from_dict(result.data[0])
            
            # Optionally include route data
            include_route = request.args.get('include_route', 'true').lower() == 'true'
            
            if include_route:
                route_result = supabase.table('routes').select('*').eq('id', planned_ruck.route_id).execute()
                if route_result.data:
                    planned_ruck.route = route_result.data[0]
            
            return ({"success": True, "data": {"planned_ruck": planned_ruck.to_dict(include_route=include_route)}})
            
        except Exception as e:
            logger.error(f"Error fetching planned ruck {planned_ruck_id}: {e}")
            return {"success": False, "error": "Failed to fetch planned ruck", "status": 500}
    
    def put(self, planned_ruck_id: str):
        """Update a planned ruck."""
        try:
            # Use same authentication pattern as working endpoints
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            
            data = request.get_json()
            if not data:
                return {"success": False, "error": "Request body required"}, 400
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Check if planned ruck exists and user owns it
            existing_result = supabase.table('planned_ruck').select('*').eq('id', planned_ruck_id).eq('user_id', g.user.id).execute()
            
            if not existing_result.data:
                return {"success": False, "error": "Planned ruck not found", "status": 404}
            
            existing_planned_ruck = PlannedRuck.from_dict(existing_result.data[0])
            
            # Only allow updates if status is 'planned'
            if existing_planned_ruck.status != 'planned':
                return {"success": False, "error": "Cannot modify planned ruck that is not in 'planned' status", "status": 400}
            
            # Remove fields that shouldn't be updated
            data.pop('id', None)
            data.pop('user_id', None)
            data.pop('created_at', None)
            data['updated_at'] = datetime.now().isoformat()
            
            # Recalculate projections if relevant fields changed
            if any(field in data for field in ['planned_ruck_weight_kg', 'planned_difficulty']):
                # Get route data for recalculations
                route_result = supabase.table('routes').select('distance_km, elevation_gain_m').eq('id', existing_planned_ruck.route_id).execute()
                
                if route_result.data:
                    route_data = route_result.data[0]
                    
                    # Merge existing data with updates
                    updated_data = {**existing_planned_ruck.to_dict(), **data}
                    updated_planned_ruck = PlannedRuck.from_dict(updated_data)
                    
                    try:
                        self._calculate_projections(updated_planned_ruck, route_data, g.user.id, supabase)
                        
                        # Update data with new projections
                        data['estimated_duration_hours'] = float(updated_planned_ruck.estimated_duration_hours) if updated_planned_ruck.estimated_duration_hours else None
                        data['estimated_calories'] = updated_planned_ruck.estimated_calories
                        data['estimated_difficulty_description'] = updated_planned_ruck.estimated_difficulty_description
                    except Exception as e:
                        logger.warning(f"Failed to recalculate projections: {e}")
            
            # Update planned ruck
            result = supabase.table('planned_ruck').update(data).eq('id', planned_ruck_id).execute()
            
            if not result.data:
                return {"success": False, "error": "Failed to update planned ruck", "status": 500}
            
            updated_planned_ruck = PlannedRuck.from_dict(result.data[0])
            
            return ({"success": True, "data": {"planned_ruck": updated_planned_ruck.to_dict(), "message": "Planned ruck updated successfully"}})
            
        except ValueError as e:
            return ({"success": False, "error": f"Validation error: {e}", "status": 400})
        except Exception as e:
            logger.error(f"Error updating planned ruck {planned_ruck_id}: {e}")
            return {"success": False, "error": "Failed to update planned ruck", "status": 500}
    
    def delete(self, planned_ruck_id: str):
        """Delete (cancel) a planned ruck."""
        try:
            # Use same authentication pattern as working endpoints
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Check if planned ruck exists and user owns it
            existing_result = supabase.table('planned_ruck').select('status, route_id').eq('id', planned_ruck_id).eq('user_id', g.user.id).execute()
            
            if not existing_result.data:
                return {"success": False, "error": "Planned ruck not found", "status": 404}
            
            existing_data = existing_result.data[0]
            
            # Mark as cancelled instead of deleting (for analytics)
            update_data = {
                'status': 'cancelled',
                'updated_at': datetime.now().isoformat()
            }
            
            result = supabase.table('planned_ruck').update(update_data).eq('id', planned_ruck_id).execute()
            
            if not result.data:
                return {"success": False, "error": "Failed to cancel planned ruck", "status": 500}
            
            # Record analytics event if it was previously planned
            if existing_data['status'] == 'planned':
                try:
                    analytics_service = RouteAnalyticsService()
                    analytics_service.record_route_cancelled(existing_data['route_id'], g.user.id)
                except Exception as e:
                    logger.warning(f"Failed to record cancellation analytics: {e}")
            
            return ({"success": True, "data": {"message": "Planned ruck cancelled successfully"}})
            
        except Exception as e:
            logger.error(f"Error cancelling planned ruck {planned_ruck_id}: {e}")
            return {"success": False, "error": "Failed to cancel planned ruck", "status": 500}

class PlannedRuckActionsResource(Resource):
    """Handle planned ruck actions like starting a session."""
    
    def post(self, planned_ruck_id: str, action: str):
        """Perform actions on planned rucks (start, complete, etc.)."""
        try:
            # Use same authentication pattern as working endpoints
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Get planned ruck
            planned_ruck_result = supabase.table('planned_ruck').select('*').eq('id', planned_ruck_id).eq('user_id', g.user.id).execute()
            
            if not planned_ruck_result.data:
                return {"success": False, "error": "Planned ruck not found", "status": 404}
            
            planned_ruck = PlannedRuck.from_dict(planned_ruck_result.data[0])
            
            if action == 'start':
                return self._start_planned_ruck(planned_ruck, supabase)
            elif action == 'complete':
                return self._complete_planned_ruck(planned_ruck, supabase)
            else:
                return ({"success": False, "error": f"Unknown action: {action}", "status": 400})
                
        except Exception as e:
            logger.error(f"Error performing action {action} on planned ruck {planned_ruck_id}: {e}")
            return ({"success": False, "error": f"Failed to {action} planned ruck", "status": 500})
    
    def _start_planned_ruck(self, planned_ruck: PlannedRuck, supabase) -> Dict[str, Any]:
        """Start a planned ruck session."""
        if not planned_ruck.can_be_started():
            return {"success": False, "error": "Planned ruck cannot be started", "status": 400}
        
        # Mark as in progress
        planned_ruck.mark_as_started()
        
        # Update in database
        update_data = {
            'status': 'in_progress',
            'updated_at': planned_ruck.updated_at.isoformat()
        }
        
        result = supabase.table('planned_ruck').update(update_data).eq('id', planned_ruck.id).execute()
        
        if not result.data:
            return {"success": False, "error": "Failed to start planned ruck", "status": 500}
        
        # Record analytics event
        try:
            analytics_service = RouteAnalyticsService()
            analytics_service.record_route_started(planned_ruck.route_id, planned_ruck.user_id, planned_ruck.planned_ruck_weight_kg)
        except Exception as e:
            logger.warning(f"Failed to record start analytics: {e}")
        
        return ({"success": True, "data": {"planned_ruck": planned_ruck.to_dict(), "message": "Planned ruck started successfully"}})
    
    def _complete_planned_ruck(self, planned_ruck: PlannedRuck, supabase) -> Dict[str, Any]:
        """Mark a planned ruck as completed."""
        if planned_ruck.status != 'in_progress':
            return {"success": False, "error": "Planned ruck must be in progress to complete", "status": 400}
        
        data = request.get_json() or {}
        
        # Mark as completed
        planned_ruck.mark_as_completed()
        
        # Update in database
        update_data = {
            'status': 'completed',
            'updated_at': planned_ruck.updated_at.isoformat()
        }
        
        result = supabase.table('planned_ruck').update(update_data).eq('id', planned_ruck.id).execute()
        
        if not result.data:
            return {"success": False, "error": "Failed to complete planned ruck", "status": 500}
        
        # Record analytics event with optional feedback
        try:
            analytics_service = RouteAnalyticsService()
            
            duration_hours = data.get('duration_hours')
            rating = data.get('rating')
            feedback = data.get('feedback')
            
            if duration_hours:
                duration_decimal = Decimal(str(duration_hours))
                analytics_service.record_route_completed(
                    planned_ruck.route_id, 
                    planned_ruck.user_id,
                    duration_decimal,
                    planned_ruck.planned_ruck_weight_kg,
                    rating,
                    feedback
                )
            
        except Exception as e:
            logger.warning(f"Failed to record completion analytics: {e}")
        
        return ({"success": True, "data": {"planned_ruck": planned_ruck.to_dict(), "message": "Planned ruck completed successfully"}})

class TodayPlannedRucksResource(Resource):
    """Get today's planned rucks for quick access."""
    
    def get(self):
        """Get planned rucks scheduled for today."""
        try:
            # Use same authentication pattern as working endpoints
            if not hasattr(g, 'user') or g.user is None:
                return {'message': 'User not authenticated'}, 401
            
            # Get today's date range
            today = datetime.now().date()
            today_start = today.isoformat()
            today_end = (today + timedelta(days=1)).isoformat()
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Get today's planned rucks
            result = supabase.table('planned_ruck').select('*').eq('user_id', g.user.id).eq('status', 'planned').gte('planned_date', today_start).lt('planned_date', today_end).order('planned_date').execute()
            
            planned_rucks = []
            route_ids = set()
            
            for planned_ruck_data in result.data:
                planned_ruck = PlannedRuck.from_dict(planned_ruck_data)
                planned_rucks.append(planned_ruck)
                route_ids.add(planned_ruck.route_id)
            
            # Get route data
            routes_by_id = {}
            if route_ids:
                routes_result = supabase.table('routes').select('id, name, distance_km, elevation_gain_m, trail_difficulty').in_('id', list(route_ids)).execute()
                routes_by_id = {route['id']: route for route in routes_result.data}
            
            # Build response with route data
            planned_rucks_data = []
            for planned_ruck in planned_rucks:
                planned_ruck_dict = planned_ruck.to_dict()
                if planned_ruck.route_id in routes_by_id:
                    planned_ruck_dict['route'] = routes_by_id[planned_ruck.route_id]
                planned_rucks_data.append(planned_ruck_dict)
            
            return ({"success": True, "data": {"planned_rucks": planned_rucks_data, "count": len(planned_rucks_data), "date": today.isoformat()}})
            
        except Exception as e:
            logger.error(f"Error fetching today's planned rucks: {e}")
            return {"success": False, "error": "Failed to fetch today's planned rucks", "status": 500}
