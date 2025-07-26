"""
PlannedRuck model for scheduled ruck sessions.
Links users to routes with specific planning data and projections.
"""

from dataclasses import dataclass
from typing import Optional, Dict, Any
from datetime import datetime
from decimal import Decimal

@dataclass
class PlannedRuck:
    """Planned ruck session linked to a route."""
    
    # Core identification
    id: Optional[str]
    user_id: str
    route_id: str
    
    # User-specific planning data
    name: Optional[str] = None  # Custom name override
    planned_date: Optional[datetime] = None
    planned_ruck_weight_kg: Decimal = None
    planned_difficulty: str = None  # easy, moderate, hard, extreme
    
    # User preferences for this ruck
    safety_tracking_enabled: bool = True
    weather_alerts_enabled: bool = True
    notes: Optional[str] = None
    
    # Calculated projections based on user profile + route
    estimated_duration_hours: Optional[Decimal] = None
    estimated_calories: Optional[int] = None
    estimated_difficulty_description: Optional[str] = None
    
    # Status tracking
    status: str = 'planned'  # planned, in_progress, completed, cancelled
    
    # Metadata
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    
    # Related data (loaded separately)
    route: Optional[Dict[str, Any]] = None  # Route data when needed

    def __post_init__(self):
        """Validate planned ruck data after initialization."""
        if self.planned_difficulty and self.planned_difficulty not in ['easy', 'moderate', 'hard', 'extreme']:
            raise ValueError(f"Invalid planned_difficulty: {self.planned_difficulty}")
        
        if self.status not in ['planned', 'in_progress', 'completed', 'cancelled']:
            raise ValueError(f"Invalid status: {self.status}")
        
        if self.planned_ruck_weight_kg and self.planned_ruck_weight_kg <= 0:
            raise ValueError("Ruck weight must be positive")

    def to_dict(self, include_route: bool = False) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        data = {
            'id': self.id,
            'user_id': self.user_id,
            'route_id': self.route_id,
            'name': self.name,
            'planned_date': self.planned_date.isoformat() if self.planned_date else None,
            'planned_ruck_weight_kg': float(self.planned_ruck_weight_kg) if self.planned_ruck_weight_kg else None,
            'planned_difficulty': self.planned_difficulty,
            'safety_tracking_enabled': self.safety_tracking_enabled,
            'weather_alerts_enabled': self.weather_alerts_enabled,
            'notes': self.notes,
            'estimated_duration_hours': float(self.estimated_duration_hours) if self.estimated_duration_hours else None,
            'estimated_calories': self.estimated_calories,
            'estimated_difficulty_description': self.estimated_difficulty_description,
            'status': self.status,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }
        
        # Optionally include route data
        if include_route and self.route:
            # Ensure route is a dictionary, not a Response object
            if isinstance(self.route, dict):
                data['route'] = self.route
            else:
                # Log warning if route is not a dict (could be Response object)
                import logging
                logger = logging.getLogger(__name__)
                logger.warning(f"PlannedRuck.route is not a dict, type: {type(self.route)}")
        
        return data

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'PlannedRuck':
        """Create PlannedRuck from dictionary (e.g., from database or API)."""
        # Convert string decimals back to Decimal objects for precision
        decimal_fields = ['planned_ruck_weight_kg', 'estimated_duration_hours']
        
        for field in decimal_fields:
            if data.get(field) is not None:
                data[field] = Decimal(str(data[field]))
        
        # Convert ISO datetime strings back to datetime objects
        if data.get('planned_date'):
            data['planned_date'] = datetime.fromisoformat(data['planned_date'])
        if data.get('created_at'):
            data['created_at'] = datetime.fromisoformat(data['created_at'])
        if data.get('updated_at'):
            data['updated_at'] = datetime.fromisoformat(data['updated_at'])
        
        # Extract route data if present
        route_data = data.pop('route', None)
        
        planned_ruck = cls(**data)
        planned_ruck.route = route_data
        
        return planned_ruck

    def is_overdue(self) -> bool:
        """Check if this planned ruck is overdue."""
        if not self.planned_date or self.status != 'planned':
            return False
        return self.planned_date < datetime.now()

    def is_today(self) -> bool:
        """Check if this planned ruck is scheduled for today."""
        if not self.planned_date:
            return False
        today = datetime.now().date()
        return self.planned_date.date() == today

    def is_upcoming(self, days: int = 7) -> bool:
        """Check if this planned ruck is upcoming within specified days."""
        if not self.planned_date or self.status != 'planned':
            return False
        
        now = datetime.now()
        future_date = now.replace(hour=23, minute=59, second=59)
        
        # Add specified days
        from datetime import timedelta
        future_date += timedelta(days=days)
        
        return now <= self.planned_date <= future_date

    def get_difficulty_score(self) -> int:
        """Get numeric difficulty score for calculations (1-4)."""
        difficulty_scores = {
            'easy': 1,
            'moderate': 2,
            'hard': 3,
            'extreme': 4
        }
        return difficulty_scores.get(self.planned_difficulty, 2)  # Default to moderate

    def calculate_estimated_duration(self, route_distance_km: Decimal, user_fitness_level: str = 'moderate') -> Decimal:
        """Calculate estimated duration based on route distance and user fitness."""
        # Base pace in minutes per km for different fitness levels and difficulties
        base_paces = {
            'beginner': {1: 15, 2: 18, 3: 22, 4: 25},      # easy to extreme
            'moderate': {1: 12, 2: 15, 3: 18, 4: 22},      # easy to extreme
            'advanced': {1: 10, 2: 12, 3: 15, 4: 18},      # easy to extreme
            'elite': {1: 8, 2: 10, 3: 12, 4: 15}           # easy to extreme
        }
        
        difficulty_score = self.get_difficulty_score()
        pace_minutes_per_km = base_paces.get(user_fitness_level, base_paces['moderate'])[difficulty_score]
        
        # Adjust for ruck weight (heavier = slower)
        if self.planned_ruck_weight_kg:
            weight_adjustment = 1.0 + (float(self.planned_ruck_weight_kg) - 15) * 0.02  # 2% slower per kg over 15kg
            pace_minutes_per_km *= max(weight_adjustment, 1.0)  # Never faster than base pace
        
        # Calculate total time in hours
        total_minutes = float(route_distance_km) * pace_minutes_per_km
        estimated_hours = Decimal(str(total_minutes / 60))
        
        self.estimated_duration_hours = estimated_hours
        return estimated_hours

    def calculate_estimated_calories(self, route_distance_km: Decimal, user_weight_kg: Decimal) -> int:
        """Calculate estimated calories burned based on distance, weight, and ruck weight."""
        # Base MET value for rucking
        base_met = 8.0
        
        # Adjust MET based on difficulty
        difficulty_multipliers = {1: 0.9, 2: 1.0, 3: 1.2, 4: 1.4}
        met_value = base_met * difficulty_multipliers.get(self.get_difficulty_score(), 1.0)
        
        # Calculate total weight (body + ruck)
        total_weight_kg = user_weight_kg
        if self.planned_ruck_weight_kg:
            total_weight_kg += self.planned_ruck_weight_kg
        
        # Calories = MET × weight(kg) × time(hours)
        if self.estimated_duration_hours:
            calories = met_value * float(total_weight_kg) * float(self.estimated_duration_hours)
            self.estimated_calories = int(calories)
            return self.estimated_calories
        
        # Fallback: estimate based on distance only
        # Approximate 100 calories per km for average person with ruck
        calories_per_km = 100 * (float(total_weight_kg) / 70)  # Normalize to 70kg person
        estimated_calories = int(float(route_distance_km) * calories_per_km)
        
        self.estimated_calories = estimated_calories
        return estimated_calories

    def generate_difficulty_description(self, route_elevation_gain_m: Optional[Decimal] = None) -> str:
        """Generate human-readable difficulty description."""
        descriptions = {
            'easy': "A comfortable ruck suitable for beginners or recovery days.",
            'moderate': "A moderate challenge that will get your heart rate up.",
            'hard': "A challenging ruck that will test your endurance.",
            'extreme': "An intense ruck for experienced ruckers only."
        }
        
        base_description = descriptions.get(self.planned_difficulty, descriptions['moderate'])
        
        # Add context based on route characteristics
        if route_elevation_gain_m and route_elevation_gain_m > 300:
            base_description += " Significant elevation gain will add to the challenge."
        elif route_elevation_gain_m and route_elevation_gain_m > 150:
            base_description += " Some hills will provide variety."
        
        if self.planned_ruck_weight_kg and self.planned_ruck_weight_kg > 20:
            base_description += f" Heavy ruck weight ({self.planned_ruck_weight_kg}kg) will increase intensity."
        
        self.estimated_difficulty_description = base_description
        return base_description

    def mark_as_started(self) -> None:
        """Mark this planned ruck as in progress."""
        self.status = 'in_progress'
        self.updated_at = datetime.now()

    def mark_as_completed(self) -> None:
        """Mark this planned ruck as completed."""
        self.status = 'completed'
        self.updated_at = datetime.now()

    def mark_as_cancelled(self) -> None:
        """Mark this planned ruck as cancelled."""
        self.status = 'cancelled'
        self.updated_at = datetime.now()

    def can_be_started(self) -> bool:
        """Check if this planned ruck can be started (i.e., is in planned status)."""
        return self.status == 'planned'

    def get_display_name(self) -> str:
        """Get display name (custom name or route name)."""
        if self.name:
            return self.name
        elif self.route and 'name' in self.route:
            return self.route['name']
        else:
            return f"Planned Ruck {self.id}"

    def get_status_display(self) -> str:
        """Get human-readable status."""
        status_displays = {
            'planned': 'Planned',
            'in_progress': 'In Progress',
            'completed': 'Completed',
            'cancelled': 'Cancelled'
        }
        return status_displays.get(self.status, self.status.title())
