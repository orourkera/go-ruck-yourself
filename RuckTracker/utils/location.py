import logging
from math import radians, sin, cos, sqrt, atan2
from geopy.distance import geodesic

logger = logging.getLogger(__name__)

def calculate_distance(point1, point2):
    """
    Calculate the distance between two geographical points.
    
    Args:
        point1 (tuple): (latitude, longitude) of first point
        point2 (tuple): (latitude, longitude) of second point
        
    Returns:
        float: Distance in kilometers
    """
    try:
        # Use geopy's geodesic calculation for accurate distance
        distance = geodesic(point1, point2).kilometers
        return distance
    except Exception as e:
        logger.error(f"Error calculating distance: {str(e)}")
        # Fallback to haversine formula if geopy fails
        return haversine_distance(point1, point2)


def haversine_distance(point1, point2):
    """
    Calculate the great circle distance between two points 
    on the earth using the haversine formula.
    
    Args:
        point1 (tuple): (latitude, longitude) of first point
        point2 (tuple): (latitude, longitude) of second point
        
    Returns:
        float: Distance in kilometers
    """
    # Earth radius in kilometers
    R = 6371.0
    
    lat1, lon1 = point1
    lat2, lon2 = point2
    
    # Convert latitude and longitude from degrees to radians
    lat1, lon1, lat2, lon2 = map(radians, [lat1, lon1, lat2, lon2])
    
    # Haversine formula
    dlon = lon2 - lon1
    dlat = lat2 - lat1
    a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlon/2)**2
    c = 2 * atan2(sqrt(a), sqrt(1-a))
    distance = R * c
    
    return distance


def calculate_elevation_change(altitude1, altitude2):
    """
    Calculate elevation gain and loss between two altitude points.
    
    Args:
        altitude1 (float): Altitude of first point in meters
        altitude2 (float): Altitude of second point in meters
        
    Returns:
        tuple: (elevation_gain, elevation_loss) in meters
    """
    if altitude1 is None or altitude2 is None:
        return 0, 0
    
    elevation_difference = altitude2 - altitude1
    
    if elevation_difference > 0:
        return elevation_difference, 0  # Gain
    else:
        return 0, abs(elevation_difference)  # Loss


def filter_inaccurate_points(points, accuracy_threshold=10):
    """
    Filter out inaccurate GPS points.
    
    Args:
        points (list): List of location points
        accuracy_threshold (float): Threshold for accuracy in meters
        
    Returns:
        list: Filtered list of points
    """
    filtered_points = []
    
    for point in points:
        # Assuming point has an 'accuracy' attribute
        if hasattr(point, 'accuracy') and point.accuracy <= accuracy_threshold:
            filtered_points.append(point)
        elif not hasattr(point, 'accuracy'):
            # If no accuracy data, include the point
            filtered_points.append(point)
    
    return filtered_points
