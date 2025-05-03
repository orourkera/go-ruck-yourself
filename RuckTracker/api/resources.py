import logging
from datetime import datetime

from flask import request
from flask_restful import Resource
from sqlalchemy import func, extract

from ..app import db
from ..models import User, RuckSession, LocationPoint, SessionReview
from api.schemas import (
    UserSchema, SessionSchema, LocationPointSchema, 
    SessionReviewSchema, StatisticsSchema, 
    AppleHealthSyncSchema, AppleHealthStatusSchema
)

# Create schema instances
user_schema = UserSchema()
session_schema = SessionSchema()
location_point_schema = LocationPointSchema()
session_review_schema = SessionReviewSchema()
statistics_schema = StatisticsSchema()
apple_health_sync_schema = AppleHealthSyncSchema()
apple_health_status_schema = AppleHealthStatusSchema()
from utils.location import calculate_distance, calculate_elevation_change
from utils.calculations import calculate_calories

logger = logging.getLogger(__name__)


class UserResource(Resource):
    """Resource for managing individual users"""
    
    def get(self, user_id):
        """Get a user by ID"""
        user = User.query.get_or_404(user_id)
        return {"user": user.to_dict()}, 200
    
    def put(self, user_id):
        """Update a user's information"""
        user = User.query.get_or_404(user_id)
        data = request.get_json()
        
        # Validate data
        errors = user_schema.validate(data, partial=True)
        if errors:
            return {"errors": errors}, 400
        
        # Update user fields
        if 'username' in data:
            user.username = data['username']
        if 'email' in data:
            user.email = data['email']
        if 'weight_kg' in data:
            user.weight_kg = data['weight_kg']
        
        db.session.commit()
        return {"user": user.to_dict()}, 200
    
    def delete(self, user_id):
        """Delete a user"""
        user = User.query.get_or_404(user_id)
        db.session.delete(user)
        db.session.commit()
        return {"message": "User deleted successfully"}, 200


class UserListResource(Resource):
    """Resource for creating users and listing all users"""
    
    def get(self):
        """Get all users"""
        users = User.query.all()
        return {"users": [user.to_dict() for user in users]}, 200
    
    def post(self):
        """Create a new user"""
        data = request.get_json()
        
        # Validate data
        errors = user_schema.validate(data)
        if errors:
            return {"errors": errors}, 400
        
        # Check if user with email or username already exists
        if User.query.filter_by(email=data['email']).first():
            return {"message": "User with this email already exists"}, 409
        
        if User.query.filter_by(username=data['username']).first():
            return {"message": "User with this username already exists"}, 409
        
        # Create new user
        user = User(
            username=data['username'],
            email=data['email'],
            weight_kg=data.get('weight_kg')
        )
        
        # Add password hash if provided (in a real app, you'd use werkzeug.security)
        if 'password' in data:
            from werkzeug.security import generate_password_hash
            user.password_hash = generate_password_hash(data['password'])
        
        db.session.add(user)
        db.session.commit()
        
        return {"user": user.to_dict()}, 201


class SessionResource(Resource):
    """Resource for managing individual rucking sessions"""
    
    def get(self, session_id):
        """Get a session by ID"""
        include_points = request.args.get('include_points', 'false').lower() == 'true'
        session = RuckSession.query.get_or_404(session_id)
        return {"session": session.to_dict(include_points=include_points)}, 200
    
    def put(self, session_id):
        """Update a session's information"""
        session = RuckSession.query.get_or_404(session_id)
        data = request.get_json()
        
        # Validate data
        errors = session_schema.validate(data, partial=True)
        if errors:
            return {"errors": errors}, 400
        
        # Update session fields
        if 'ruck_weight_kg' in data:
            session.ruck_weight_kg = data['ruck_weight_kg']
        
        # Handle status changes and timer operations
        if 'status' in data:
            new_status = data['status']
            current_time = datetime.utcnow()
            
            # Start session
            if new_status == 'active' and session.status != 'active':
                if not session.start_time:  # First start
                    session.start_time = current_time
                session.status = 'active'
            
            # Pause session
            elif new_status == 'paused' and session.status == 'active':
                # Record the time when paused
                session.status = 'paused'
                # Logic to track pause time would go here
            
            # Complete session
            elif new_status == 'completed':
                session.end_time = current_time
                session.status = 'completed'
                
                # Calculate duration
                if session.start_time:
                    total_seconds = (current_time - session.start_time).total_seconds()
                    session.duration_seconds = int(total_seconds) - session.paused_duration_seconds
        
        db.session.commit()
        return {"session": session.to_dict()}, 200
    
    def delete(self, session_id):
        """Delete a session"""
        session = RuckSession.query.get_or_404(session_id)
        db.session.delete(session)
        db.session.commit()
        return {"message": "Session deleted successfully"}, 200


class SessionListResource(Resource):
    """Resource for creating sessions and listing all sessions"""
    
    def get(self):
        """Get all sessions for a user"""
        user_id = request.args.get('user_id')
        
        if not user_id:
            return {"message": "user_id parameter is required"}, 400
        
        sessions = RuckSession.query.filter_by(user_id=user_id).all()
        return {"sessions": [session.to_dict() for session in sessions]}, 200
    
    def post(self):
        """Create a new session"""
        data = request.get_json()
        
        # Validate data
        errors = session_schema.validate(data)
        if errors:
            return {"errors": errors}, 400
        
        # Verify user exists
        user = User.query.get(data['user_id'])
        if not user:
            return {"message": "User not found"}, 404
        
        # Create new session
        session = RuckSession(
            user_id=data['user_id'],
            ruck_weight_kg=data['ruck_weight_kg'],
            status='created'
        )
        
        db.session.add(session)
        db.session.commit()
        
        return {"session": session.to_dict()}, 201


class SessionStatisticsResource(Resource):
    """Resource for updating session statistics with location data"""
    
    def post(self, session_id):
        """Add location point and update session statistics"""
        session = RuckSession.query.get_or_404(session_id)
        
        # Only accept updates for active sessions
        if session.status != 'active':
            return {"message": f"Session is not active (current status: {session.status})"}, 400
        
        data = request.get_json()
        
        # Validate location data
        errors = location_point_schema.validate(data)
        if errors:
            return {"errors": errors}, 400
        
        # Create new location point
        point = LocationPoint(
            session_id=session_id,
            latitude=data['latitude'],
            longitude=data['longitude'],
            altitude=data.get('altitude'),
            timestamp=datetime.utcnow()
        )
        
        db.session.add(point)
        
        # Get previous location point to calculate incremental changes
        prev_point = (LocationPoint.query
                      .filter_by(session_id=session_id)
                      .order_by(LocationPoint.timestamp.desc())
                      .first())
        
        # If there's a previous point, calculate distance and elevation changes
        if prev_point:
            # Calculate distance increment
            distance_increment = calculate_distance(
                (prev_point.latitude, prev_point.longitude),
                (point.latitude, point.longitude)
            )
            
            # Calculate elevation change if altitude data available
            elevation_gain, elevation_loss = 0, 0
            if prev_point.altitude is not None and point.altitude is not None:
                elevation_gain, elevation_loss = calculate_elevation_change(
                    prev_point.altitude, point.altitude
                )
            
            # Update session statistics
            session.distance_km += distance_increment
            session.elevation_gain_m += elevation_gain
            session.elevation_loss_m += elevation_loss
            
            # Calculate and update calories burned
            user = User.query.get(session.user_id)
            if user and user.weight_kg:
                session.calories_burned = calculate_calories(
                    user.weight_kg,
                    session.ruck_weight_kg,
                    session.distance_km,
                    session.elevation_gain_m
                )
        
        db.session.commit()
        
        return {
            "message": "Location point added and statistics updated",
            "statistics": {
                "distance_km": session.distance_km,
                "elevation_gain_m": session.elevation_gain_m,
                "elevation_loss_m": session.elevation_loss_m,
                "calories_burned": session.calories_burned
            }
        }, 200


class SessionReviewResource(Resource):
    """Resource for managing session reviews"""
    
    def get(self, session_id):
        """Get the review for a session"""
        session = RuckSession.query.get_or_404(session_id)
        
        if not session.review:
            return {"message": "No review found for this session"}, 404
        
        return {"review": session.review.to_dict()}, 200
    
    def post(self, session_id):
        """Create or update a review for a session"""
        session = RuckSession.query.get_or_404(session_id)
        data = request.get_json()
        
        # Validate review data
        errors = session_review_schema.validate(data)
        if errors:
            return {"errors": errors}, 400
        
        # Check if session has a review already
        if session.review:
            # Update existing review
            review = session.review
            review.rating = data['rating']
            review.notes = data.get('notes', '')
        else:
            # Create new review
            review = SessionReview(
                session_id=session_id,
                rating=data['rating'],
                notes=data.get('notes', '')
            )
            db.session.add(review)
        
        db.session.commit()
        
        return {"review": review.to_dict()}, 201


class WeeklyStatisticsResource(Resource):
    """Resource for weekly statistics aggregation"""
    
    def get(self):
        """Get weekly statistics for a user"""
        user_id = request.args.get('user_id')
        if not user_id:
            return {"message": "user_id parameter is required"}, 400
        
        # Get week number and year from request or use current
        week = request.args.get('week')
        year = request.args.get('year')
        
        query = RuckSession.query.filter_by(user_id=user_id, status='completed')
        
        if week and year:
            # Filter by specific week and year
            query = query.filter(
                extract('week', RuckSession.end_time) == week,
                extract('year', RuckSession.end_time) == year
            )
        
        # Aggregate statistics
        stats = self._aggregate_statistics(query)
        
        return {"statistics": stats}, 200
    
    def _aggregate_statistics(self, query):
        """Aggregate statistics from query results"""
        results = query.with_entities(
            func.sum(RuckSession.distance_km).label('total_distance'),
            func.sum(RuckSession.elevation_gain_m).label('total_elevation_gain'),
            func.sum(RuckSession.calories_burned).label('total_calories'),
            func.avg(RuckSession.distance_km).label('avg_distance'),
            func.count(RuckSession.id).label('session_count'),
            func.sum(RuckSession.duration_seconds).label('total_duration')
        ).first()
        
        # Convert to dictionary
        if results:
            stats = {
                'total_distance_km': float(results.total_distance) if results.total_distance else 0,
                'total_elevation_gain_m': float(results.total_elevation_gain) if results.total_elevation_gain else 0,
                'total_calories_burned': float(results.total_calories) if results.total_calories else 0,
                'average_distance_km': float(results.avg_distance) if results.avg_distance else 0,
                'session_count': results.session_count,
                'total_duration_seconds': results.total_duration if results.total_duration else 0
            }
        else:
            stats = {
                'total_distance_km': 0,
                'total_elevation_gain_m': 0,
                'total_calories_burned': 0,
                'average_distance_km': 0,
                'session_count': 0,
                'total_duration_seconds': 0
            }
        
        return stats


class MonthlyStatisticsResource(Resource):
    """Resource for monthly statistics aggregation"""
    
    def get(self):
        """Get monthly statistics for a user"""
        user_id = request.args.get('user_id')
        if not user_id:
            return {"message": "user_id parameter is required"}, 400
        
        # Get month and year from request or use current
        month = request.args.get('month')
        year = request.args.get('year')
        
        query = RuckSession.query.filter_by(user_id=user_id, status='completed')
        
        if month and year:
            # Filter by specific month and year
            query = query.filter(
                extract('month', RuckSession.end_time) == month,
                extract('year', RuckSession.end_time) == year
            )
        
        # Use the same aggregation method as weekly
        weekly_resource = WeeklyStatisticsResource()
        stats = weekly_resource._aggregate_statistics(query)
        
        return {"statistics": stats}, 200


class YearlyStatisticsResource(Resource):
    """Resource for yearly statistics aggregation"""
    
    def get(self):
        """Get yearly statistics for a user"""
        user_id = request.args.get('user_id')
        if not user_id:
            return {"message": "user_id parameter is required"}, 400
        
        # Get year from request or use current
        year = request.args.get('year')
        
        query = RuckSession.query.filter_by(user_id=user_id, status='completed')
        
        if year:
            # Filter by specific year
            query = query.filter(extract('year', RuckSession.end_time) == year)
        
        # Use the same aggregation method as weekly
        weekly_resource = WeeklyStatisticsResource()
        stats = weekly_resource._aggregate_statistics(query)
        
        # Add monthly breakdown for the year
        monthly_breakdown = []
        if year:
            for month in range(1, 13):
                month_query = query.filter(extract('month', RuckSession.end_time) == month)
                month_stats = weekly_resource._aggregate_statistics(month_query)
                month_stats['month'] = month
                monthly_breakdown.append(month_stats)
            
            stats['monthly_breakdown'] = monthly_breakdown
        
        return {"statistics": stats}, 200
