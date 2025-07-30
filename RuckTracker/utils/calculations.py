import logging

logger = logging.getLogger(__name__)

def calculate_calories(user_weight_kg, ruck_weight_kg, distance_km, elevation_gain_m, duration_seconds=None, elevation_loss_m=0.0, gender=None, terrain_multiplier=1.0):
    """
    Calculate calories burned during a rucking session using the same sophisticated logic as Flutter.
    
    This matches the Flutter MetCalculator.calculateRuckingCalories() method exactly:
    1. Dynamic MET calculation based on actual speed and grade
    2. Complex elevation adjustments for uphill/downhill
    3. Load adjustments based on ruck weight
    4. Terrain multipliers for surface type
    5. Gender-based adjustments
    
    Args:
        user_weight_kg (float): User's weight in kilograms
        ruck_weight_kg (float): Weight of the ruck in kilograms
        distance_km (float): Total distance covered in kilometers
        elevation_gain_m (float): Total elevation gain in meters
        duration_seconds (int, optional): Actual duration in seconds
        elevation_loss_m (float, optional): Total elevation loss in meters
        gender (str, optional): 'male', 'female', or None
        terrain_multiplier (float, optional): Energy cost multiplier for terrain (1.0 = pavement baseline)
        
    Returns:
        float: Estimated calories burned
    """
    import math
    
    try:
        # Validate inputs
        if not all(isinstance(x, (int, float)) for x in [user_weight_kg, ruck_weight_kg, distance_km, elevation_gain_m]):
            logger.warning("Invalid input types for calorie calculation")
            return 0
        
        if user_weight_kg <= 0 or distance_km < 0 or elevation_gain_m < 0:
            logger.warning("Invalid input values for calorie calculation")
            return 0
        
        # Calculate actual speed if duration is provided, otherwise estimate
        if duration_seconds and duration_seconds > 0:
            duration_hours = duration_seconds / 3600.0
            avg_speed_kmh = distance_km / duration_hours if duration_hours > 0 else 0
        else:
            # Fallback: estimate moderate pace of 5 km/h
            avg_speed_kmh = 5.0
            duration_hours = distance_km / avg_speed_kmh if avg_speed_kmh > 0 else 0
        
        # Convert to mph for MET calculation
        avg_speed_mph = avg_speed_kmh * 0.621371
        
        # Calculate average grade from elevation changes
        avg_grade = 0.0
        if distance_km > 0:
            avg_grade = ((elevation_gain_m - elevation_loss_m) / (distance_km * 1000)) * 100
        
        # Convert ruck weight to pounds for MET calculation
        ruck_weight_lbs = ruck_weight_kg * 2.20462
        
        # Calculate MET value using sophisticated Flutter logic
        def calculate_rucking_met_by_grade(speed_mph, grade, ruck_weight_lbs):
            # Base MET value based on speed on flat ground
            if speed_mph < 2.0:
                base_met = 2.5  # Very slow walking
            elif speed_mph < 2.5:
                base_met = 3.0  # Slow walking
            elif speed_mph < 3.0:
                base_met = 3.5  # Moderate walking
            elif speed_mph < 3.5:
                base_met = 4.0  # Average walking
            elif speed_mph < 4.0:
                base_met = 4.5  # Brisk walking
            elif speed_mph < 5.0:
                base_met = 5.0  # Fast walking / power walking
            else:
                base_met = 6.0  # Very fast walking / jogging
            
            # Adjust MET based on grade
            grade_adjustment = 0.0
            if grade > 0:
                # Uphill: MET increases with grade
                grade_adjustment = grade * 0.6 * (speed_mph / 4.0)
            elif grade < 0:
                # Downhill: complex energy patterns
                abs_grade = abs(grade)
                if abs_grade <= 10:
                    # Slight downhill makes walking easier
                    grade_adjustment = -abs_grade * 0.1
                else:
                    # Steep downhill requires braking energy
                    grade_adjustment = (abs_grade - 10) * 0.15
            
            # Adjust for load (ruck weight)
            load_adjustment = 0.0
            if ruck_weight_lbs > 0:
                load_adjustment = min(ruck_weight_lbs * 0.05, 5.0)  # Cap at 5.0 additional METs
            
            # Calculate final MET
            final_met = base_met + grade_adjustment + load_adjustment
            return max(2.0, min(final_met, 15.0))  # Clamp between 2.0 and 15.0
        
        # Calculate MET value
        met_value = calculate_rucking_met_by_grade(avg_speed_mph, avg_grade, ruck_weight_lbs)
        
        # Calculate base calories using MET formula
        duration_minutes = duration_hours * 60 if duration_hours > 0 else (distance_km / avg_speed_kmh) * 60
        base_calories = met_value * (user_weight_kg + ruck_weight_kg) * (duration_minutes / 60.0)
        
        # Apply terrain multiplier for surface type energy cost
        terrain_adjusted_calories = base_calories * terrain_multiplier
        
        # Apply gender-based adjustment for more accurate calculations
        if gender == 'female':
            # Female adjustment: approx. 15% lower calorie burn
            gender_adjusted_calories = terrain_adjusted_calories * 0.85
        elif gender == 'male':
            # Male baseline - no adjustment needed
            gender_adjusted_calories = terrain_adjusted_calories
        else:
            # If gender is not specified, use a middle ground (7.5% reduction)
            gender_adjusted_calories = terrain_adjusted_calories * 0.925
        
        logger.info(f"Calorie calculation: speed={avg_speed_kmh:.2f}km/h, grade={avg_grade:.1f}%, "
                   f"MET={met_value:.2f}, base={base_calories:.0f}, terrain_adj={terrain_adjusted_calories:.0f}, "
                   f"final={gender_adjusted_calories:.0f} calories")
        
        return max(0, gender_adjusted_calories)
        
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
