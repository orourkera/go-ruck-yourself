"""
RouteAnalytics model for tracking route usage and user interactions.
Used for popularity metrics, user feedback, and route recommendations.
"""

from dataclasses import dataclass
from typing import Optional, Dict, Any
from datetime import datetime
from decimal import Decimal

@dataclass
class RouteAnalytics:
    """Analytics record for route usage and user interactions."""
    
    # Core identification
    route_id: str
    user_id: str
    event_type: str  # planned, started, completed, cancelled, viewed
    id: Optional[str] = None
    
    # Session-specific data (when applicable)
    actual_duration_hours: Optional[Decimal] = None
    actual_ruck_weight_kg: Optional[Decimal] = None
    user_rating: Optional[int] = None  # 1-5 stars
    user_feedback: Optional[str] = None
    
    # Metadata
    created_at: Optional[datetime] = None

    def __post_init__(self):
        """Validate analytics data after initialization."""
        valid_event_types = ['planned', 'started', 'completed', 'cancelled', 'viewed']
        if self.event_type not in valid_event_types:
            raise ValueError(f"Invalid event_type: {self.event_type}. Must be one of {valid_event_types}")
        
        if self.user_rating is not None and not (1 <= self.user_rating <= 5):
            raise ValueError("User rating must be between 1 and 5")
        
        if self.actual_duration_hours is not None and self.actual_duration_hours <= 0:
            raise ValueError("Actual duration must be positive")
        
        if self.actual_ruck_weight_kg is not None and self.actual_ruck_weight_kg <= 0:
            raise ValueError("Ruck weight must be positive")

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        result = {
            'route_id': self.route_id,
            'user_id': self.user_id,
            'event_type': self.event_type,
            'actual_duration_hours': float(self.actual_duration_hours) if self.actual_duration_hours else None,
            'actual_ruck_weight_kg': float(self.actual_ruck_weight_kg) if self.actual_ruck_weight_kg else None,
            'user_rating': self.user_rating,
            'user_feedback': self.user_feedback,
            'created_at': self.created_at.isoformat() if self.created_at else None
        }
        
        # Only include id if it's not None (let database auto-generate UUID if None)
        if self.id is not None:
            result['id'] = self.id
            
        return result

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'RouteAnalytics':
        """Create RouteAnalytics from dictionary (e.g., from database or API)."""
        # Convert string decimals back to Decimal objects for precision
        decimal_fields = ['actual_duration_hours', 'actual_ruck_weight_kg']
        
        for field in decimal_fields:
            if data.get(field) is not None:
                data[field] = Decimal(str(data[field]))
        
        # Convert ISO datetime string back to datetime object
        if data.get('created_at'):
            data['created_at'] = datetime.fromisoformat(data['created_at'])
        
        return cls(**data)

    def is_completion_event(self) -> bool:
        """Check if this is a completion event with session data."""
        return self.event_type == 'completed'

    def has_rating(self) -> bool:
        """Check if this analytics record includes a user rating."""
        return self.user_rating is not None

    def has_feedback(self) -> bool:
        """Check if this analytics record includes user feedback."""
        return bool(self.user_feedback and self.user_feedback.strip())

    def get_rating_stars(self) -> str:
        """Get star representation of rating."""
        if not self.user_rating:
            return "No rating"
        return "★" * self.user_rating + "☆" * (5 - self.user_rating)

    @classmethod
    def create_view_event(cls, route_id: str, user_id: str) -> 'RouteAnalytics':
        """Create a route view analytics event."""
        return cls(
            route_id=route_id,
            user_id=user_id,
            event_type='viewed',
            created_at=datetime.now()
        )

    @classmethod
    def create_planned_event(cls, route_id: str, user_id: str) -> 'RouteAnalytics':
        """Create a route planned analytics event."""
        return cls(
            route_id=route_id,
            user_id=user_id,
            event_type='planned',
            created_at=datetime.now()
        )

    @classmethod
    def create_started_event(cls, route_id: str, user_id: str, ruck_weight_kg: Optional[Decimal] = None) -> 'RouteAnalytics':
        """Create a route started analytics event."""
        return cls(
            route_id=route_id,
            user_id=user_id,
            event_type='started',
            actual_ruck_weight_kg=ruck_weight_kg,
            created_at=datetime.now()
        )

    @classmethod
    def create_completed_event(
        cls,
        route_id: str,
        user_id: str,
        duration_hours: Decimal,
        ruck_weight_kg: Optional[Decimal] = None,
        rating: Optional[int] = None,
        feedback: Optional[str] = None
    ) -> 'RouteAnalytics':
        """Create a route completed analytics event with session data."""
        return cls(
            route_id=route_id,
            user_id=user_id,
            event_type='completed',
            actual_duration_hours=duration_hours,
            actual_ruck_weight_kg=ruck_weight_kg,
            user_rating=rating,
            user_feedback=feedback,
            created_at=datetime.now()
        )

    @classmethod
    def create_cancelled_event(cls, route_id: str, user_id: str, reason: Optional[str] = None) -> 'RouteAnalytics':
        """Create a route cancelled analytics event."""
        return cls(
            route_id=route_id,
            user_id=user_id,
            event_type='cancelled',
            user_feedback=reason,  # Use feedback field for cancellation reason
            created_at=datetime.now()
        )

@dataclass 
class RoutePopularityStats:
    """Aggregated popularity statistics for a route."""
    
    route_id: str
    total_views: int = 0
    total_planned: int = 0
    total_started: int = 0
    total_completed: int = 0
    total_cancelled: int = 0
    
    # Rating statistics
    average_rating: Optional[Decimal] = None
    total_ratings: int = 0
    rating_distribution: Optional[Dict[int, int]] = None  # {1: count, 2: count, ...}
    
    # Performance statistics
    average_duration_hours: Optional[Decimal] = None
    fastest_duration_hours: Optional[Decimal] = None
    slowest_duration_hours: Optional[Decimal] = None
    
    # Completion rate
    completion_rate: Optional[Decimal] = None  # completed / started
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            'route_id': self.route_id,
            'total_views': self.total_views,
            'total_planned': self.total_planned,
            'total_started': self.total_started,
            'total_completed': self.total_completed,
            'total_cancelled': self.total_cancelled,
            'average_rating': float(self.average_rating) if self.average_rating else None,
            'total_ratings': self.total_ratings,
            'rating_distribution': self.rating_distribution,
            'average_duration_hours': float(self.average_duration_hours) if self.average_duration_hours else None,
            'fastest_duration_hours': float(self.fastest_duration_hours) if self.fastest_duration_hours else None,
            'slowest_duration_hours': float(self.slowest_duration_hours) if self.slowest_duration_hours else None,
            'completion_rate': float(self.completion_rate) if self.completion_rate else None
        }

    def calculate_completion_rate(self) -> Optional[Decimal]:
        """Calculate and set completion rate."""
        if self.total_started == 0:
            self.completion_rate = None
            return None
        
        rate = Decimal(self.total_completed) / Decimal(self.total_started)
        self.completion_rate = rate
        return rate

    def get_popularity_score(self) -> int:
        """Calculate overall popularity score (0-100)."""
        # Weight different engagement types
        score = (
            self.total_views * 1 +
            self.total_planned * 3 +
            self.total_started * 5 +
            self.total_completed * 10
        )
        
        # Bonus for high ratings
        if self.average_rating and self.total_ratings >= 3:
            rating_bonus = int(float(self.average_rating) * 10)
            score += rating_bonus
        
        # Bonus for high completion rate
        if self.completion_rate and self.total_started >= 5:
            completion_bonus = int(float(self.completion_rate) * 20)
            score += completion_bonus
        
        # Cap at 100
        return min(score, 100)

    def is_trending(self, days_threshold: int = 30) -> bool:
        """Check if route is trending (high recent activity)."""
        # This would need recent analytics data to implement properly
        # For now, use completion rate and rating as proxy
        if not self.completion_rate or not self.average_rating:
            return False
        
        return (
            float(self.completion_rate) > 0.7 and 
            float(self.average_rating) >= 4.0 and 
            self.total_completed >= 5
        )

    def get_difficulty_feedback(self) -> Optional[str]:
        """Get aggregated difficulty feedback from completion rates and ratings."""
        if self.total_started < 3:
            return None
        
        completion_rate = float(self.completion_rate) if self.completion_rate else 0
        avg_rating = float(self.average_rating) if self.average_rating else 0
        
        if completion_rate < 0.5:
            return "Many ruckers find this route challenging - consider the difficulty level"
        elif completion_rate > 0.9 and avg_rating >= 4.0:
            return "Highly rated route with excellent completion rate"
        elif avg_rating >= 4.5:
            return "Excellent route - highly recommended by ruckers"
        elif avg_rating <= 2.5:
            return "Mixed reviews - check recent feedback before planning"
        else:
            return "Popular route with good completion rate"
