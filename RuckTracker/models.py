from datetime import datetime
from database import db
from flask_login import UserMixin


class User(UserMixin, db.Model):
    """User model for rucking app"""
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(64), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password_hash = db.Column(db.String(256))
    weight_kg = db.Column(db.Float, nullable=True)  # User's weight in kg
    height_cm = db.Column(db.Float, nullable=True)  # User's height in cm
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationship with RuckSession
    sessions = db.relationship('RuckSession', backref='user', lazy='dynamic')
    
    def to_dict(self):
        """Convert user data to dictionary for API responses"""
        return {
            'id': self.id,
            'username': self.username,
            'email': self.email,
            'weight_kg': self.weight_kg,
            'height_cm': self.height_cm,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }


class RuckSession(db.Model):
    """Model for tracking rucking sessions"""
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    ruck_weight_kg = db.Column(db.Float, nullable=False)  # Weight of the ruck in kg
    user_weight_kg = db.Column(db.Float, nullable=True)  # User's weight in kg
    planned_duration_minutes = db.Column(db.Integer, nullable=True)  # Planned duration
    notes = db.Column(db.Text, nullable=True)  # Session notes
    
    # Session status
    status = db.Column(db.String(20), default='created')  # created, in_progress, paused, completed
    
    # Session time tracking
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    started_at = db.Column(db.DateTime, nullable=True)
    paused_at = db.Column(db.DateTime, nullable=True)
    completed_at = db.Column(db.DateTime, nullable=True)
    
    # Session statistics
    distance_km = db.Column(db.Float, default=0.0)  # Total distance in kilometers
    elevation_gain_meters = db.Column(db.Float, default=0.0)  # Total elevation gain in meters
    elevation_loss_meters = db.Column(db.Float, default=0.0)  # Total elevation loss in meters
    calories_burned = db.Column(db.Float, default=0.0)  # Estimated calories burned
    duration_seconds = db.Column(db.Integer, default=0)  # Total duration in seconds
    average_pace_min_km = db.Column(db.Float, default=0.0)  # Average pace in min/km
    
    # Timestamps
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationship with location data points
    location_points = db.relationship('LocationPoint', backref='session', lazy='dynamic')
    
    # Relationship with session review
    review = db.relationship('SessionReview', uselist=False, back_populates='session')
    
    def to_dict(self, include_points=False):
        """Convert session data to dictionary for API responses"""
        result = {
            'ruck_id': self.id,
            'user_id': self.user_id,
            'status': self.status,
            'ruck_weight_kg': self.ruck_weight_kg,
            'user_weight_kg': self.user_weight_kg,
            'planned_duration_minutes': self.planned_duration_minutes,
            'notes': self.notes,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'started_at': self.started_at.isoformat() if self.started_at else None,
            'paused_at': self.paused_at.isoformat() if self.paused_at else None,
            'completed_at': self.completed_at.isoformat() if self.completed_at else None,
            'stats': {
                'distance_km': self.distance_km or 0.0,
                'elevation_gain_meters': self.elevation_gain_meters or 0.0,
                'elevation_loss_meters': self.elevation_loss_meters or 0.0,
                'calories_burned': self.calories_burned or 0.0,
                'duration_seconds': self.duration_seconds or 0,
                'average_pace_min_km': self.average_pace_min_km or 0.0,
            } if any([self.distance_km, self.duration_seconds]) else None,
            'review': self.review.to_dict() if self.review else None
        }
        
        if include_points:
            result['location_points'] = [point.to_dict() for point in self.location_points]
            
        return result


class LocationPoint(db.Model):
    """Model for storing location data points during a session"""
    id = db.Column(db.Integer, primary_key=True)
    session_id = db.Column(db.Integer, db.ForeignKey('ruck_session.id'), nullable=False)
    
    # Geolocation data
    latitude = db.Column(db.Float, nullable=False)
    longitude = db.Column(db.Float, nullable=False)
    altitude = db.Column(db.Float, nullable=True)  # Elevation in meters
    
    # Timestamp for this location point
    timestamp = db.Column(db.DateTime, default=datetime.utcnow)
    
    def to_dict(self):
        """Convert location point data to dictionary for API responses"""
        return {
            'id': self.id,
            'session_id': self.session_id,
            'latitude': self.latitude,
            'longitude': self.longitude,
            'altitude': self.altitude,
            'timestamp': self.timestamp.isoformat() if self.timestamp else None
        }


class SessionReview(db.Model):
    """Model for storing user reviews of rucking sessions"""
    id = db.Column(db.Integer, primary_key=True)
    session_id = db.Column(db.Integer, db.ForeignKey('ruck_session.id'), nullable=False, unique=True)
    
    # Review data
    rating = db.Column(db.Integer, nullable=False)  # 1-5 star rating
    perceived_exertion = db.Column(db.Integer, nullable=True)  # 1-10 perceived exertion
    notes = db.Column(db.Text, nullable=True)  # User notes about the session
    tags = db.Column(db.JSON, nullable=True)  # Tags as a JSON array of strings
    
    # Timestamps
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationship with session
    session = db.relationship('RuckSession', back_populates='review')
    
    def to_dict(self):
        """Convert review data to dictionary for API responses"""
        return {
            'id': self.id,
            'session_id': self.session_id,
            'rating': self.rating,
            'perceived_exertion': self.perceived_exertion,
            'notes': self.notes,
            'tags': self.tags or [],
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }
