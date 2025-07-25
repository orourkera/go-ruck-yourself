"""
Models package for RuckTracker.
Exports all data models for use throughout the application.
"""

# Existing models - import from individual files if they exist
# These were previously imported directly from individual files
# Keep this structure to maintain backward compatibility

try:
    from .user import User
except ImportError:
    User = None

try:
    from .ruck_session import RuckSession
except ImportError:
    RuckSession = None

try:
    from .location_point import LocationPoint
except ImportError:
    LocationPoint = None

try:
    from .session_review import SessionReview
except ImportError:
    SessionReview = None

# Route-related models (new)
from .route import Route, RouteElevationPoint, RoutePointOfInterest
from .planned_ruck import PlannedRuck
from .route_analytics import RouteAnalytics, RoutePopularityStats

__all__ = [
    # Existing models (if available)
    'User',
    'RuckSession',
    'LocationPoint',
    'SessionReview',
    
    # Route models (new)
    'Route',
    'RouteElevationPoint', 
    'RoutePointOfInterest',
    
    # Planned ruck models (new)
    'PlannedRuck',
    
    # Analytics models (new)
    'RouteAnalytics',
    'RoutePopularityStats'
]
