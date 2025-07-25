"""
Route model for AllTrails integration.
Represents shareable route data from various sources (AllTrails, custom, community).
"""

from dataclasses import dataclass
from typing import Optional, List, Dict, Any
from datetime import datetime
from decimal import Decimal

@dataclass
class RouteElevationPoint:
    """Individual elevation point along a route."""
    id: Optional[str]
    route_id: str
    distance_km: Decimal
    elevation_m: Decimal
    latitude: Optional[Decimal] = None
    longitude: Optional[Decimal] = None
    terrain_type: Optional[str] = None
    grade_percent: Optional[Decimal] = None
    created_at: Optional[datetime] = None

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            'id': self.id,
            'route_id': self.route_id,
            'distance_km': float(self.distance_km),
            'elevation_m': float(self.elevation_m),
            'latitude': float(self.latitude) if self.latitude else None,
            'longitude': float(self.longitude) if self.longitude else None,
            'terrain_type': self.terrain_type,
            'grade_percent': float(self.grade_percent) if self.grade_percent else None,
            'created_at': self.created_at.isoformat() if self.created_at else None
        }

@dataclass
class RoutePointOfInterest:
    """Point of interest along a route (water, rest, viewpoint, etc.)."""
    id: Optional[str]
    route_id: str
    name: str
    description: Optional[str]
    poi_type: str  # water, rest, viewpoint, hazard, parking, landmark, shelter
    latitude: Decimal
    longitude: Decimal
    distance_from_start_km: Optional[Decimal] = None
    created_at: Optional[datetime] = None

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            'id': self.id,
            'route_id': self.route_id,
            'name': self.name,
            'description': self.description,
            'poi_type': self.poi_type,
            'latitude': float(self.latitude),
            'longitude': float(self.longitude),
            'distance_from_start_km': float(self.distance_from_start_km) if self.distance_from_start_km else None,
            'created_at': self.created_at.isoformat() if self.created_at else None
        }

@dataclass
class Route:
    """Core route model for AllTrails integration."""
    
    # Core identification
    id: Optional[str]
    name: str
    description: Optional[str]
    source: str  # alltrails, custom, community
    external_id: Optional[str] = None  # AllTrails trail ID, etc.
    external_url: Optional[str] = None  # Link back to original source
    
    # Geographic data
    start_latitude: Decimal = None
    start_longitude: Decimal = None
    end_latitude: Optional[Decimal] = None
    end_longitude: Optional[Decimal] = None
    route_polyline: str = None  # Encoded polyline or GeoJSON
    
    # Route metrics
    distance_km: Decimal = None
    elevation_gain_m: Decimal = Decimal('0')
    elevation_loss_m: Optional[Decimal] = None
    min_elevation_m: Optional[Decimal] = None
    max_elevation_m: Optional[Decimal] = None
    
    # Difficulty and characteristics
    trail_difficulty: Optional[str] = None  # easy, moderate, hard, extreme
    trail_type: Optional[str] = None  # loop, out_and_back, point_to_point
    surface_type: Optional[str] = None  # trail, paved, gravel, mixed, rocky, technical
    
    # Popularity metrics
    total_planned_count: int = 0
    total_completed_count: int = 0
    average_rating: Optional[Decimal] = None
    
    # Metadata
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    created_by_user_id: Optional[str] = None
    is_verified: bool = False
    is_public: bool = True
    
    # Related data (loaded separately)
    elevation_points: Optional[List[RouteElevationPoint]] = None
    points_of_interest: Optional[List[RoutePointOfInterest]] = None

    def __post_init__(self):
        """Validate route data after initialization."""
        if self.source not in ['alltrails', 'custom', 'community']:
            raise ValueError(f"Invalid source: {self.source}")
        
        if self.trail_difficulty and self.trail_difficulty not in ['easy', 'moderate', 'hard', 'extreme']:
            raise ValueError(f"Invalid trail_difficulty: {self.trail_difficulty}")
        
        if self.trail_type and self.trail_type not in ['loop', 'out_and_back', 'point_to_point']:
            raise ValueError(f"Invalid trail_type: {self.trail_type}")
        
        if self.surface_type and self.surface_type not in ['trail', 'paved', 'gravel', 'mixed', 'rocky', 'technical']:
            raise ValueError(f"Invalid surface_type: {self.surface_type}")

    def to_dict(self, include_elevation_points: bool = False, include_pois: bool = False) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        data = {
            'id': self.id,
            'name': self.name,
            'description': self.description,
            'source': self.source,
            'external_id': self.external_id,
            'external_url': self.external_url,
            'start_latitude': float(self.start_latitude) if self.start_latitude else None,
            'start_longitude': float(self.start_longitude) if self.start_longitude else None,
            'end_latitude': float(self.end_latitude) if self.end_latitude else None,
            'end_longitude': float(self.end_longitude) if self.end_longitude else None,
            'route_polyline': self.route_polyline,
            'distance_km': float(self.distance_km) if self.distance_km else None,
            'elevation_gain_m': float(self.elevation_gain_m) if self.elevation_gain_m else None,
            'elevation_loss_m': float(self.elevation_loss_m) if self.elevation_loss_m else None,
            'min_elevation_m': float(self.min_elevation_m) if self.min_elevation_m else None,
            'max_elevation_m': float(self.max_elevation_m) if self.max_elevation_m else None,
            'trail_difficulty': self.trail_difficulty,
            'trail_type': self.trail_type,
            'surface_type': self.surface_type,
            'total_planned_count': self.total_planned_count,
            'total_completed_count': self.total_completed_count,
            'average_rating': float(self.average_rating) if self.average_rating else None,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
            'created_by_user_id': self.created_by_user_id,
            'is_verified': self.is_verified,
            'is_public': self.is_public
        }
        
        # Optionally include related data
        if include_elevation_points and self.elevation_points:
            data['elevation_points'] = [point.to_dict() for point in self.elevation_points]
        
        if include_pois and self.points_of_interest:
            data['points_of_interest'] = [poi.to_dict() for poi in self.points_of_interest]
        
        return data

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'Route':
        """Create Route from dictionary (e.g., from database or API)."""
        # Convert string decimals back to Decimal objects for precision
        decimal_fields = [
            'start_latitude', 'start_longitude', 'end_latitude', 'end_longitude',
            'distance_km', 'elevation_gain_m', 'elevation_loss_m', 
            'min_elevation_m', 'max_elevation_m', 'average_rating'
        ]
        
        for field in decimal_fields:
            if data.get(field) is not None:
                data[field] = Decimal(str(data[field]))
        
        # Convert ISO datetime strings back to datetime objects
        if data.get('created_at'):
            data['created_at'] = datetime.fromisoformat(data['created_at'])
        if data.get('updated_at'):
            data['updated_at'] = datetime.fromisoformat(data['updated_at'])
        
        # Handle elevation points
        elevation_points = None
        if data.get('elevation_points'):
            elevation_points = [
                RouteElevationPoint(
                    id=point.get('id'),
                    route_id=point['route_id'],
                    distance_km=Decimal(str(point['distance_km'])),
                    elevation_m=Decimal(str(point['elevation_m'])),
                    latitude=Decimal(str(point['latitude'])) if point.get('latitude') else None,
                    longitude=Decimal(str(point['longitude'])) if point.get('longitude') else None,
                    terrain_type=point.get('terrain_type'),
                    grade_percent=Decimal(str(point['grade_percent'])) if point.get('grade_percent') else None,
                    created_at=datetime.fromisoformat(point['created_at']) if point.get('created_at') else None
                )
                for point in data['elevation_points']
            ]
        
        # Handle POIs
        points_of_interest = None
        if data.get('points_of_interest'):
            points_of_interest = [
                RoutePointOfInterest(
                    id=poi.get('id'),
                    route_id=poi['route_id'],
                    name=poi['name'],
                    description=poi.get('description'),
                    poi_type=poi['poi_type'],
                    latitude=Decimal(str(poi['latitude'])),
                    longitude=Decimal(str(poi['longitude'])),
                    distance_from_start_km=Decimal(str(poi['distance_from_start_km'])) if poi.get('distance_from_start_km') else None,
                    created_at=datetime.fromisoformat(poi['created_at']) if poi.get('created_at') else None
                )
                for poi in data['points_of_interest']
            ]
        
        # Remove nested data for main Route construction
        route_data = {k: v for k, v in data.items() if k not in ['elevation_points', 'points_of_interest']}
        
        route = cls(**route_data)
        route.elevation_points = elevation_points
        route.points_of_interest = points_of_interest
        
        return route

    def get_bounds(self) -> Optional[Dict[str, float]]:
        """Calculate geographic bounds for the route."""
        if not self.start_latitude or not self.start_longitude:
            return None
            
        # If we have elevation points with coordinates, use those for more accurate bounds
        if self.elevation_points:
            lats = [float(p.latitude) for p in self.elevation_points if p.latitude]
            lngs = [float(p.longitude) for p in self.elevation_points if p.longitude]
            
            if lats and lngs:
                return {
                    'north': max(lats),
                    'south': min(lats),
                    'east': max(lngs),
                    'west': min(lngs)
                }
        
        # Fallback to start/end points
        lats = [float(self.start_latitude)]
        lngs = [float(self.start_longitude)]
        
        if self.end_latitude and self.end_longitude:
            lats.append(float(self.end_latitude))
            lngs.append(float(self.end_longitude))
        
        return {
            'north': max(lats),
            'south': min(lats),
            'east': max(lngs),
            'west': min(lngs)
        }

    def is_loop_route(self) -> bool:
        """Check if this is a loop route based on start/end proximity."""
        if not all([self.start_latitude, self.start_longitude, self.end_latitude, self.end_longitude]):
            return self.trail_type == 'loop'
        
        # Calculate distance between start and end points (rough approximation)
        lat_diff = abs(float(self.start_latitude) - float(self.end_latitude))
        lng_diff = abs(float(self.start_longitude) - float(self.end_longitude))
        
        # If start and end are within ~100 meters, consider it a loop
        return lat_diff < 0.001 and lng_diff < 0.001

    def get_difficulty_score(self) -> int:
        """Get numeric difficulty score for calculations (1-4)."""
        difficulty_scores = {
            'easy': 1,
            'moderate': 2,
            'hard': 3,
            'extreme': 4
        }
        return difficulty_scores.get(self.trail_difficulty, 2)  # Default to moderate
