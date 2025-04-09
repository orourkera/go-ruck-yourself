import logging

logger = logging.getLogger(__name__)

def calculate_calories(user_weight_kg, ruck_weight_kg, distance_km, elevation_gain_m):
    """
    Calculate calories burned during a rucking session.
    
    This uses a formula based on:
    1. Basic MET (Metabolic Equivalent of Task) for walking/hiking
    2. Additional load from the ruck
    3. Additional effort for elevation gain
    
    Args:
        user_weight_kg (float): User's weight in kilograms
        ruck_weight_kg (float): Weight of the ruck in kilograms
        distance_km (float): Total distance covered in kilometers
        elevation_gain_m (float): Total elevation gain in meters
        
    Returns:
        float: Estimated calories burned
    """
    try:
        # Validate inputs
        if not all(isinstance(x, (int, float)) for x in [user_weight_kg, ruck_weight_kg, distance_km, elevation_gain_m]):
            logger.warning("Invalid input types for calorie calculation")
            return 0
        
        if user_weight_kg <= 0 or distance_km < 0 or elevation_gain_m < 0:
            logger.warning("Invalid input values for calorie calculation")
            return 0
        
        # Base MET for walking at moderate pace
        base_met = 3.5
        
        # Additional MET for carrying weight (approximately 0.5 MET per 10% of body weight)
        weight_percentage = (ruck_weight_kg / user_weight_kg) * 100
        additional_met_for_weight = (weight_percentage / 10) * 0.5
        
        # MET for elevation gain (approximately 0.2 MET per 1% grade)
        # Convert elevation gain to grade percentage (rise/run * 100)
        if distance_km > 0:
            grade_percentage = (elevation_gain_m / (distance_km * 1000)) * 100
            additional_met_for_elevation = grade_percentage * 0.2
        else:
            additional_met_for_elevation = 0
        
        # Total MET
        total_met = base_met + additional_met_for_weight + additional_met_for_elevation
        
        # Calorie calculation: MET * weight in kg * hours
        # 1 MET = 1 kcal/kg/hour
        total_weight_kg = user_weight_kg + ruck_weight_kg
        
        # Estimate time in hours (assuming moderate pace of 5 km/h)
        hours = distance_km / 5
        
        # Calculate calories
        calories = total_met * total_weight_kg * hours
        
        return calories
    except Exception as e:
        logger.error(f"Error calculating calories: {str(e)}")
        return 0


def calculate_pace(distance_km, duration_seconds):
    """
    Calculate pace in minutes per kilometer.
    
    Args:
        distance_km (float): Distance covered in kilometers
        duration_seconds (int): Duration in seconds
        
    Returns:
        float: Pace in minutes per kilometer
    """
    if distance_km <= 0 or duration_seconds <= 0:
        return 0
    
    # Convert duration to minutes
    duration_minutes = duration_seconds / 60
    
    # Calculate pace
    pace = duration_minutes / distance_km
    
    return pace


def calculate_average_speed(distance_km, duration_seconds):
    """
    Calculate average speed in kilometers per hour.
    
    Args:
        distance_km (float): Distance covered in kilometers
        duration_seconds (int): Duration in seconds
        
    Returns:
        float: Average speed in km/h
    """
    if distance_km <= 0 or duration_seconds <= 0:
        return 0
    
    # Convert duration to hours
    duration_hours = duration_seconds / 3600
    
    # Calculate speed
    speed = distance_km / duration_hours
    
    return speed


def calculate_energy_expenditure_per_kg(ruck_weight_kg, distance_km, elevation_gain_m):
    """
    Calculate energy expenditure per kilogram of body weight.
    
    This is useful for comparing workouts across individuals of different weights.
    
    Args:
        ruck_weight_kg (float): Weight of the ruck in kilograms
        distance_km (float): Distance covered in kilometers
        elevation_gain_m (float): Elevation gain in meters
        
    Returns:
        float: Energy expenditure per kilogram (in kcal/kg)
    """
    # Base cost of walking (kcal/kg/km)
    base_cost = 0.75
    
    # Additional cost for carrying weight (approximately 0.01 kcal/kg/km per kg of ruck)
    additional_cost_for_weight = 0.01 * ruck_weight_kg
    
    # Additional cost for elevation gain (approximately 0.002 kcal/kg/m)
    additional_cost_for_elevation = 0.002 * elevation_gain_m
    
    # Total energy expenditure per kg
    energy_per_kg = (base_cost + additional_cost_for_weight) * distance_km + additional_cost_for_elevation
    
    return energy_per_kg
