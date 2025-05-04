from datetime import datetime
from .app import db
from flask_login import UserMixin
from sqlalchemy.dialects.postgresql import UUID
import uuid


class User(UserMixin, db.Model):
    """User model for rucking app"""
    id = db.Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    username = db.Column(db.String(64), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password_hash = db.Column(db.String(256))
    weight_kg = db.Column(db.Float, nullable=True)  # User's weight in kg
    prefer_metric = db.Column(db.Boolean, nullable=False, default=True) # User's preference for metric units
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationship with RuckSession
    sessions = db.relationship('RuckSession', backref='user', lazy='dynamic', cascade='all, delete-orphan')
    
    def to_dict(self):
        """Convert user data to dictionary for API responses"""
        return {
            'id': str(self.id),  # Convert UUID to string
            'username': self.username,
            'email': self.email,
            'weight_kg': self.weight_kg,
            'prefer_metric': self.prefer_metric, # Added prefer_metric
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }


class RuckSession(db.Model):
    """Model for tracking rucking sessions"""
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(UUID(as_uuid=True), db.ForeignKey('user.id'), nullable=False)
    ruck_weight_kg = db.Column(db.Float, nullable=False)  # Weight of the ruck in kg
    
    # Session time tracking
    start_time = db.Column(db.DateTime, nullable=True)
    end_time = db.Column(db.DateTime, nullable=True)
    duration_seconds = db.Column(db.Integer, nullable=True)  # Total duration in seconds
    paused_duration_seconds = db.Column(db.Integer, default=0)  # Time spent paused
    
    # Session status
    status = db.Column(db.String(20), default='created')  # created, active, paused, completed
    
    # Session statistics
    distance_km = db.Column(db.Float, default=0.0)  # Total distance in kilometers
    elevation_gain_m = db.Column(db.Float, default=0.0)  # Total elevation gain in meters
    elevation_loss_m = db.Column(db.Float, default=0.0)  # Total elevation loss in meters
    calories_burned = db.Column(db.Float, default=0.0)  # Estimated calories burned
    
    # Timestamps
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationship with location data points
    location_points = db.relationship('LocationPoint', backref='session', lazy='dynamic')
    
    # Relationship with session review
    review = db.relationship('SessionReview', uselist=False, back_populates='session')
    
    def to_dict(self, include_points=False):
        """Convert session data to dictionary for API responses"""
        result = {
            'id': self.id,
            'user_id': self.user_id,
            'ruck_weight_kg': self.ruck_weight_kg,
            'start_time': self.start_time.isoformat() if self.start_time else None,
            'end_time': self.end_time.isoformat() if self.end_time else None,
            'duration_seconds': self.duration_seconds,
            'paused_duration_seconds': self.paused_duration_seconds,
            'status': self.status,
            'distance_km': self.distance_km,
            'elevation_gain_m': self.elevation_gain_m,
            'elevation_loss_m': self.elevation_loss_m,
            'calories_burned': self.calories_burned,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
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
    notes = db.Column(db.Text, nullable=True)  # User notes about the session
    
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
            'notes': self.notes,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }
