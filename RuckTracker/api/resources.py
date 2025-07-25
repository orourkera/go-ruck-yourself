import logging
from datetime import datetime

from flask import request, g
from flask_restful import Resource
from sqlalchemy import func, extract

from ..extensions import db
from ..models import User, RuckSession, LocationPoint, SessionReview
from .schemas import (
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
from ..utils.location import calculate_distance, calculate_elevation_change
from ..utils.calculations import calculate_calories
from ..supabase_client import get_supabase_admin_client

logger = logging.getLogger(__name__)


class UserResource(Resource):
    """Resource for managing individual users"""
    
    def get(self, user_id):
        """Get a user by ID"""
        # Debug logging for User model
        if User is None:
            logger.error("User model is None - database initialization failed!")
            return {"error": "Database initialization error"}, 500
            
        if not hasattr(User, 'query'):
            logger.error("User.query is None - SQLAlchemy not properly initialized!")
            return {"error": "Database query interface not available"}, 500
            
        try:
            user = User.query.get_or_404(user_id)
            return {"user": user.to_dict()}, 200
        except Exception as e:
            logger.error(f"Error querying user {user_id}: {str(e)}")
            return {"error": "Database query failed"}, 500
    
    def put(self, user_id):
        """Update a user's information"""
        user = User.query.get_or_404(user_id)
        data = request.get_json() or {}
        # Map common camelCase keys from the Flutter app to snake_case expected by the backend
        camel_to_snake = {
            'weightKg': 'weight_kg',
            'isMetric': 'prefer_metric',
            'heightCm': 'height_cm',
            'avatarUrl': 'avatar_url'
        }
        data = {camel_to_snake.get(k, k): v for k, v in data.items()}
        
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
        if 'prefer_metric' in data:
            user.prefer_metric = data['prefer_metric']
        if 'height_cm' in data:
            user.height_cm = data['height_cm']
        if 'avatar_url' in data:
            user.avatar_url = data['avatar_url']
        if 'is_profile_private' in data:
            user.is_profile_private = data['is_profile_private']
        
        db.session.commit()
        return {"user": user.to_dict()}, 200
    
    def patch(self, user_id):
        """Partially update user fields. Primarily used for `last_active_at` pings from the mobile app.

        Currently the mobile app sends
        {
          "last_active_at": "2025-07-17T08:06:12.123Z"
        }
        via PATCH /users/{id} to record that the user opened the app. Historically this triggered a
        405 (Method Not Allowed) because the backend only implemented GET, PUT and DELETE.  

        We purposefully keep the implementation extremely lightweight: if `last_active_at` is
        provided we simply update the built-in `updated_at` column for the user (no need for a
        dedicated column) which is already indexed and available for analytics.  
        Any other recognised user fields will also be mapped and updated using the same camel →
        snake conversion used in `put()`.
        """
        try:
            # Use Supabase instead of SQLAlchemy to avoid 504 timeouts
            # Import here to avoid circular imports
            from ..supabase_client import get_supabase_client
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # First check if user exists
            user_check = supabase.table('user').select('id, username, email').eq('id', str(user_id)).execute()
            if not user_check.data:
                return {'error': 'User not found'}, 404
                
            data = request.get_json() or {}
            logger.info(f"PATCH /users/{user_id} - Received data: {data}")

            # Map camelCase keys coming from Flutter to snake_case columns
            camel_to_snake = {
                'weightKg': 'weight_kg',
                'isMetric': 'prefer_metric',
                'heightCm': 'height_cm',
                'avatarUrl': 'avatar_url',
                'lastActiveAt': 'last_active_at',  # not a real column but accepted in payload
            }
            data = {camel_to_snake.get(k, k): v for k, v in data.items()}

            # Prepare update data
            update_data = {}
            
            # Handle last_active_at specially – we just bump updated_at for now
            if 'last_active_at' in data:
                try:
                    # Parse ISO8601 – datetime.fromisoformat handles microseconds & timezone info
                    ts = datetime.fromisoformat(data['last_active_at'].replace('Z', '+00:00'))
                    update_data['updated_at'] = ts.isoformat()
                    logger.info(f"Updated last_active_at for user {user_id} to {ts}")
                except Exception as e:
                    # If parsing fails just use current UTC time (fail-safe)
                    update_data['updated_at'] = datetime.utcnow().isoformat()
                    logger.warning(f"Failed to parse last_active_at, using current time: {e}")

            # For any other provided fields reuse the same logic as PUT but without validation
            allowed_simple_fields = {
                'username', 'email', 'weight_kg', 'prefer_metric', 'height_cm',
                'avatar_url', 'is_profile_private'
            }
            for key in allowed_simple_fields:
                if key in data:
                    update_data[key] = data[key]

            # Update user in Supabase
            if update_data:
                result = supabase.table('user').update(update_data).eq('id', str(user_id)).execute()
                if result.data:
                    user_data = result.data[0]
                    logger.info(f"Successfully updated user {user_id}")
                    return {"user": {
                        'id': user_data.get('id'),
                        'username': user_data.get('username'),
                        'email': user_data.get('email'),
                        'weight_kg': user_data.get('weight_kg'),
                        'height_cm': user_data.get('height_cm'),
                        'gender': user_data.get('gender'),
                        'prefer_metric': user_data.get('prefer_metric', True),
                        'avatarUrl': user_data.get('avatar_url'),
                        'isPrivateProfile': user_data.get('is_profile_private', False),
                        'updated_at': user_data.get('updated_at')
                    }}, 200
                else:
                    logger.error(f"No data returned from user update for {user_id}")
                    return {'error': 'Update failed'}, 400
            else:
                logger.info(f"No valid update data provided for user {user_id}")
                return {'error': 'No valid update data provided'}, 400
                
        except Exception as e:
            logger.error(f"Error updating user {user_id}: {str(e)}", exc_info=True)
            return {'error': f'Internal server error: {str(e)}'}, 500

    def delete(self, user_id):
        """Delete a user and all associated data from Supabase and local DB"""
        # Authorization check: Ensure the authenticated user matches the user_id being deleted
        if not g.user or g.user.id != user_id:
            logger.warning(f"Unauthorized delete attempt: auth_user='{g.user.id if g.user else None}' target_user='{user_id}'")
            return {'message': 'Forbidden: You can only delete your own account'}, 403

        try:
            supabase = get_supabase_admin_client()
            # Delete all related data from Supabase tables
            # First, get all ruck sessions for the user
            sessions_resp = supabase.table('ruck_session').select('id').eq('user_id', user_id).execute()
            if hasattr(sessions_resp, 'data') and sessions_resp.data:
                session_ids = [session['id'] for session in sessions_resp.data]
                if session_ids:
                    # Delete location points associated with these sessions
                    supabase.table('location_point').delete().in_('ruck_session_id', session_ids).execute()
                # Delete the ruck sessions
                supabase.table('ruck_session').delete().eq('user_id', user_id).execute()
            # Delete the user's profile from the user table
            supabase.table('user').delete().eq('id', user_id).execute()
            # Finally, delete the user from Supabase auth
            delete_user_resp = supabase.auth.admin.delete_user(user_id)
            if hasattr(delete_user_resp, 'error') and delete_user_resp.error:
                logger.error(f"Failed to delete user {user_id} from Supabase auth: {delete_user_resp.error}")
                return {'message': 'Failed to delete user from authentication system'}, 500
            logger.info(f"User {user_id} deleted successfully from Supabase auth.")
        except Exception as e:
            logger.error(f"Error deleting user {user_id} from Supabase: {str(e)}", exc_info=True)
            return {'message': f'Error deleting user from Supabase: {str(e)}'}, 500

        # Delete from local DB (SQLAlchemy ORM)
        logger.debug(f"Attempting to find user {user_id} in local DB for deletion.")
        user = User.query.filter_by(id=user_id).first()
        if not user:
            logger.warning(f"User {user_id} not found in local DB.")
            # Since Supabase deletion was successful, we can still return success
            return {"message": "User deleted successfully from Supabase, but not found in local DB"}, 200
        try:
            # Merge the user object into the current session to avoid session conflicts
            user = db.session.merge(user)
            db.session.delete(user)
            db.session.commit()
            logger.info(f"User {user_id} deleted successfully from local DB.")
            return {"message": "User and all associated data deleted successfully"}, 200
        except RuntimeError as re:
            logger.error(f"Flask-SQLAlchemy initialization error for user {user_id}: {str(re)}")
            logger.error(f"Rolling back local DB session for user {user_id} due to error.")
            # Since Supabase deletion was successful, return success despite local DB issue
            return {"message": "User deleted successfully from Supabase, but local DB deletion failed due to configuration issue"}, 200
        except Exception as e:
            logger.error(f"Rolling back local DB session for user {user_id} due to error.")
            db.session.rollback()
            logger.error(f"Error during user deletion process for {user_id}: {str(e)}", exc_info=True)
            return {'message': 'An error occurred during deletion'}, 500


class UserListResource(Resource):
    """Resource for creating users and listing all users"""
    
    def get(self):
        """Get all users"""
        users = User.query.all()
        return {"users": [user.to_dict() for user in users]}, 200
    
    def post(self):
        """Create a new user"""
        data = request.get_json() or {}
        # Map common camelCase keys from the Flutter app to snake_case expected by the backend
        camel_to_snake = {
            'weightKg': 'weight_kg',
            'isMetric': 'prefer_metric',
            'heightCm': 'height_cm',
            'avatarUrl': 'avatar_url'
        }
        data = {camel_to_snake.get(k, k): v for k, v in data.items()}
        
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
        data = request.get_json() or {}
        # Map common camelCase keys from the Flutter app to snake_case expected by the backend
        camel_to_snake = {
            'weightKg': 'weight_kg',
            'isMetric': 'prefer_metric',
            'heightCm': 'height_cm',
            'avatarUrl': 'avatar_url'
        }
        data = {camel_to_snake.get(k, k): v for k, v in data.items()}
        
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
        data = request.get_json() or {}
        # Map common camelCase keys from the Flutter app to snake_case expected by the backend
        camel_to_snake = {
            'weightKg': 'weight_kg',
            'isMetric': 'prefer_metric',
            'heightCm': 'height_cm',
            'avatarUrl': 'avatar_url'
        }
        data = {camel_to_snake.get(k, k): v for k, v in data.items()}
        
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
        
        data = request.get_json() or {}
        # Map common camelCase keys from the Flutter app to snake_case expected by the backend
        camel_to_snake = {
            'weightKg': 'weight_kg',
            'isMetric': 'prefer_metric',
            'heightCm': 'height_cm',
            'avatarUrl': 'avatar_url'
        }
        data = {camel_to_snake.get(k, k): v for k, v in data.items()}
        
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
            
            # Resolve altitude for both points – fetch from external service if missing
            from RuckTracker.utils.elevation_service import get_elevation
            prev_alt = prev_point.altitude if prev_point.altitude is not None else get_elevation(prev_point.latitude, prev_point.longitude)
            curr_alt = point.altitude if point.altitude is not None else get_elevation(point.latitude, point.longitude)

            elevation_gain, elevation_loss = 0, 0
            if prev_alt is not None and curr_alt is not None:
                elevation_gain, elevation_loss = calculate_elevation_change(prev_alt, curr_alt)
            
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
        data = request.get_json() or {}
        # Map common camelCase keys from the Flutter app to snake_case expected by the backend
        camel_to_snake = {
            'weightKg': 'weight_kg',
            'isMetric': 'prefer_metric',
            'heightCm': 'height_cm',
            'avatarUrl': 'avatar_url'
        }
        data = {camel_to_snake.get(k, k): v for k, v in data.items()}
        
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


class UserProfileResource(Resource):
    """Resource for user profile management (Google auth and general profile ops)"""
    
    def get(self):
        """Get current user's profile"""
        if not g.user:
            return {'message': 'Authentication required'}, 401
            
        return {"user": g.user.to_dict()}, 200
    
    def post(self):
        """Create or update user profile (primarily for Google auth users)"""
        if not g.user:
            return {'message': 'Authentication required'}, 401
        
        try:
            data = request.get_json() or {}
            # Map common camelCase keys from the Flutter app to snake_case expected by the backend
            camel_to_snake = {
                'weightKg': 'weight_kg',
                'isMetric': 'prefer_metric',
                'heightCm': 'height_cm',
                'avatarUrl': 'avatar_url'
            }
            data = {camel_to_snake.get(k, k): v for k, v in data.items()}
            
            # Check if user record already exists
            existing_user = User.query.filter_by(id=g.user.id).first()
            
            if existing_user:
                # Update existing user
                if 'username' in data:
                    existing_user.username = data['username']
                if 'email' in data:
                    existing_user.email = data['email']
                if 'prefer_metric' in data:
                    existing_user.prefer_metric = data['prefer_metric']
                if 'weight_kg' in data:
                    existing_user.weight_kg = data['weight_kg']
                if 'height_cm' in data:
                    existing_user.height_cm = data['height_cm']
                if 'gender' in data:
                    existing_user.gender = data['gender']
                
                db.session.commit()
                logger.info(f"Updated user profile for {existing_user.id}")
                return {"user": existing_user.to_dict()}, 200
            else:
                # Create new user record (for Google auth users)
                new_user = User(
                    id=g.user.id,  # Use Supabase user ID
                    username=data.get('username', ''),
                    email=data.get('email', ''),
                    prefer_metric=data.get('is_metric', True),
                    weight_kg=data.get('weight_kg'),
                    height_cm=data.get('height_cm'),
                    gender=data.get('gender'),
                )
                
                db.session.add(new_user)
                db.session.commit()
                
                logger.info(f"Created new user profile for Google auth user: {new_user.id}")
                return {"user": new_user.to_dict()}, 201
                
        except Exception as e:
            logger.error(f"Error creating/updating user profile: {str(e)}", exc_info=True)
            db.session.rollback()
            return {'message': f'Failed to create/update profile: {str(e)}'}, 500
