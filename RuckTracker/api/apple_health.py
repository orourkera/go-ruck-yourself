import logging
from flask import request, jsonify
from flask_restful import Resource

from ..app import db
from ..models import User, RuckSession, LocationPoint
from .schemas import apple_health_sync_schema, apple_health_status_schema

logger = logging.getLogger(__name__)

class AppleHealthSyncResource(Resource):
    """Resource for syncing data with Apple Health"""
    
    def post(self, user_id):
        """
        Receive workout data from Apple Health and store it in our system
        
        This endpoint accepts data in Apple Health Export format and converts
        it to our internal format for storage.
        """
        user = User.query.get_or_404(user_id)
        data = request.get_json()
        
        # Validate data using schema
        errors = apple_health_sync_schema.validate(data)
        if errors:
            return {"errors": errors}, 400
            
        if not data or 'workouts' not in data:
            return {"message": "Invalid Apple Health data format"}, 400
            
        workouts = data['workouts']
        imported_count = 0
        
        for workout in workouts:
            # Validate workout data has required fields
            if not all(k in workout for k in ['startDate', 'endDate', 'duration', 'distance']):
                continue
                
            # Check if this is a supported workout type (walking, hiking, or other)
            workout_type = workout.get('workoutActivityType', '')
            if not any(t in workout_type.lower() for t in ['walking', 'hiking', 'outdoor']):
                continue
                
            # Check if we already have this session (avoid duplicates)
            start_time = workout['startDate']
            existing = RuckSession.query.filter_by(
                user_id=user_id, 
                start_time=start_time
            ).first()
            
            if existing:
                logger.info(f"Skipping already imported workout from {start_time}")
                continue
                
            # Create new session from Apple Health data
            ruck_weight = workout.get('metadata', {}).get('ruckWeight', 0)
            
            session = RuckSession(
                user_id=user_id,
                ruck_weight_kg=float(ruck_weight),
                start_time=workout['startDate'],
                end_time=workout['endDate'],
                duration_seconds=int(float(workout['duration'])),
                distance_km=float(workout['distance']),
                status='completed'
            )
            
            # Try to get elevation data if available
            if 'elevationAscended' in workout:
                session.elevation_gain_m = float(workout['elevationAscended'])
                
            # Try to get route data if available
            if 'route' in workout:
                for point in workout['route']:
                    location = LocationPoint(
                        session=session,
                        latitude=point['latitude'],
                        longitude=point['longitude'],
                        altitude=point.get('altitude'),
                        timestamp=point['timestamp']
                    )
                    db.session.add(location)
            
            db.session.add(session)
            imported_count += 1
            
        db.session.commit()
        
        return {
            "message": f"Successfully imported {imported_count} workouts from Apple Health",
            "imported_count": imported_count
        }, 201
        
    def get(self, user_id):
        """
        Generate Apple Health compatible workout data for export
        
        This endpoint converts our internal workout data to Apple Health
        format so it can be imported into the Apple Health app.
        """
        user = User.query.get_or_404(user_id)
        
        # Get all completed sessions for user
        sessions = RuckSession.query.filter_by(
            user_id=user_id,
            status='completed'
        ).all()
        
        apple_health_data = {
            "workouts": []
        }
        
        for session in sessions:
            # Only include sessions with complete data
            if not session.start_time or not session.end_time:
                continue
                
            workout = {
                "workoutActivityType": "HKWorkoutActivityTypeWalking",
                "startDate": session.start_time.isoformat(),
                "endDate": session.end_time.isoformat(),
                "duration": float(session.duration_seconds),
                "distance": float(session.distance_km),
                "metadata": {
                    "ruckWeight": float(session.ruck_weight_kg)
                }
            }
            
            # Add elevation data if available
            if session.elevation_gain_m:
                workout["elevationAscended"] = float(session.elevation_gain_m)
                
            # Add route data if available
            location_points = LocationPoint.query.filter_by(session_id=session.id).all()
            if location_points:
                workout["route"] = [
                    {
                        "latitude": point.latitude,
                        "longitude": point.longitude,
                        "altitude": point.altitude,
                        "timestamp": point.timestamp.isoformat()
                    }
                    for point in location_points
                ]
                
            apple_health_data["workouts"].append(workout)
            
        return apple_health_data, 200


class AppleHealthIntegrationStatusResource(Resource):
    """Resource for managing Apple Health integration status"""
    
    def get(self, user_id):
        """Get Apple Health integration status for a user"""
        user = User.query.get_or_404(user_id)
        
        # This would normally check user settings for Apple Health integration
        # For now we'll return a placeholder
        return {
            "integration_enabled": False,
            "last_sync_time": None,
            "metrics_to_sync": ["workouts", "distance", "elevation"]
        }, 200
        
    def put(self, user_id):
        """Update Apple Health integration settings"""
        user = User.query.get_or_404(user_id)
        data = request.get_json()
        
        # Validate data using schema
        errors = apple_health_status_schema.validate(data)
        if errors:
            return {"errors": errors}, 400
        
        # This would normally update user settings
        # For now we'll just return the input
        integration_status = {
            "integration_enabled": data.get('integration_enabled', False),
            "metrics_to_sync": data.get('metrics_to_sync', [])
        }
        
        return integration_status, 200