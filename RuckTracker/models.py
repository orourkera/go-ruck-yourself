from datetime import datetime
from .extensions import db
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
    gender = db.Column(db.String(10), nullable=True)  # User's gender (male/female)
    height_cm = db.Column(db.Float, nullable=True)  # User's height in cm
    allow_ruck_sharing = db.Column(db.Boolean, nullable=False, default=True)  # User's preference for sharing ruck data
    avatar_url = db.Column(db.String(255), nullable=True)  # User's avatar URL
    is_profile_private = db.Column(db.Boolean, nullable=False, default=False)  # User's profile privacy setting
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationship with RuckSession
    sessions = db.relationship('RuckSession', backref='user', lazy='dynamic', cascade='all, delete-orphan')
    
    # Non-persistent token attribute for JWT storage
    _token = None
    
    @property
    def token(self):
        return self._token
        
    @token.setter
    def token(self, value):
        self._token = value
    
    def to_dict(self):
        """Convert user data to dictionary for API responses"""
        return {
            'id': str(self.id),  # Convert UUID to string
            'username': self.username,
            'email': self.email,
            'weight_kg': self.weight_kg,
            'height_cm': self.height_cm,
            'gender': self.gender,
            'allow_ruck_sharing': self.allow_ruck_sharing,
            'prefer_metric': self.prefer_metric, # Added prefer_metric
            'avatarUrl': self.avatar_url,  # camelCase for frontend
            'isPrivateProfile': self.is_profile_private,  # camelCase for frontend
            'isFollowing': False,  # TODO: implement following logic
            'isFollowedBy': False,  # TODO: implement following logic
            'createdAt': self.created_at.isoformat() if self.created_at else None,
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
    paused_duration_seconds = db.Column(db.Integer, nullable=True)  # Time spent paused
    planned_duration_minutes = db.Column(db.Integer, nullable=True)
    started_at = db.Column(db.DateTime(timezone=True), nullable=True)
    ended_at = db.Column(db.DateTime(timezone=True), nullable=True)
    completed_at = db.Column(db.DateTime(timezone=True), nullable=True)

    # Session status
    status = db.Column(db.String(20), default='created')  # created, active, paused, completed

    # Session statistics
    distance_km = db.Column(db.Float, nullable=True)  # Total distance in kilometers
    distance_meters = db.Column(db.Numeric, nullable=True)
    elevation_gain_m = db.Column(db.Float, nullable=True)  # Total elevation gain in meters
    elevation_loss_m = db.Column(db.Float, nullable=True)  # Total elevation loss in meters
    calories_burned = db.Column(db.Float, nullable=True)  # Estimated calories burned
    avg_heart_rate = db.Column(db.Integer, nullable=True)
    final_average_pace = db.Column(db.Numeric, nullable=True)
    final_distance_km = db.Column(db.Numeric, nullable=True)
    final_calories_burned = db.Column(db.Integer, nullable=True)
    final_elevation_gain = db.Column(db.Numeric, nullable=True)
    final_elevation_loss = db.Column(db.Numeric, nullable=True)
    weight_kg = db.Column(db.Numeric, nullable=True)

    # User feedback
    rating = db.Column(db.Integer, nullable=True)
    perceived_exertion = db.Column(db.Integer, nullable=True)
    notes = db.Column(db.Text, nullable=True)
    tags = db.Column(db.ARRAY(db.String), nullable=True)

    # Timestamps
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationship with location data points
    location_points = db.relationship('LocationPoint', backref='session', lazy='dynamic')

    # Relationship with session review
    review = db.relationship('SessionReview', uselist=False, back_populates='session')

    # Relationship with heart rate samples
    heart_rate_samples = db.relationship('HeartRateSample', backref='session', lazy='dynamic', cascade='all, delete-orphan')

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
            'planned_duration_minutes': self.planned_duration_minutes,
            'started_at': self.started_at.isoformat() if self.started_at else None,
            'ended_at': self.ended_at.isoformat() if self.ended_at else None,
            'completed_at': self.completed_at.isoformat() if self.completed_at else None,
            'status': self.status,
            'distance_km': self.distance_km,
            'distance_meters': float(self.distance_meters) if self.distance_meters is not None else None,
            'elevation_gain_m': self.elevation_gain_m,
            'elevation_loss_m': self.elevation_loss_m,
            'calories_burned': self.calories_burned,
            'avg_heart_rate': self.avg_heart_rate,
            'final_average_pace': float(self.final_average_pace) if self.final_average_pace is not None else None,
            'final_distance_km': float(self.final_distance_km) if self.final_distance_km is not None else None,
            'final_calories_burned': self.final_calories_burned,
            'final_elevation_gain': float(self.final_elevation_gain) if self.final_elevation_gain is not None else None,
            'final_elevation_loss': float(self.final_elevation_loss) if self.final_elevation_loss is not None else None,
            'weight_kg': float(self.weight_kg) if self.weight_kg is not None else None,
            'rating': self.rating,
            'perceived_exertion': self.perceived_exertion,
            'notes': self.notes,
            'tags': self.tags,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
            'review': self.review.to_dict() if self.review else None
        }
        if include_points:
            result['location_points'] = [point.to_dict() for point in self.location_points]
        
        # Always include heart rate samples for heart rate widget functionality
        result['heart_rate_samples'] = [sample.to_dict() for sample in self.heart_rate_samples]
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


class HeartRateSample(db.Model):
    """Model for storing heart rate samples for a rucking session"""
    id = db.Column(db.Integer, primary_key=True)
    session_id = db.Column(db.Integer, db.ForeignKey('ruck_session.id', ondelete='CASCADE'), nullable=False)
    timestamp = db.Column(db.DateTime, nullable=False)
    bpm = db.Column(db.Integer, nullable=False)

    def to_dict(self):
        return {
            'id': self.id,
            'session_id': self.session_id,
            'timestamp': self.timestamp.isoformat() if self.timestamp else None,
            'bpm': self.bpm,
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
