import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Utility class for calculating calories burned using METs (Metabolic Equivalent of Task)
class MetCalculator {
  /// Calculate calories burned using METs formula
  /// 
  /// The formula is: Calories = MET value × Weight (kg) × Duration (hours)
  /// 
  /// Parameters:
  /// - [weightKg]: User's weight in kilograms (body weight + ruck weight)
  /// - [durationMinutes]: Duration of the activity in minutes
  /// - [metValue]: MET value for the activity
  static double calculateCaloriesBurned({
    required double weightKg,
    required int durationMinutes,
    required double metValue,
  }) {
    // Convert duration to hours
    final durationHours = durationMinutes / 60;
    
    // Apply MET formula
    return metValue * weightKg * durationHours;
  }
  
  /// Calculate MET value for rucking activity based on grade (slope)
  /// 
  /// Parameters:
  /// - [speedMph]: Speed in miles per hour
  /// - [grade]: Grade/slope percentage (elevation change / horizontal distance × 100)
  /// - [ruckWeightLbs]: Weight of the ruck in pounds
  static double calculateRuckingMetByGrade({
    required double speedMph,
    required double grade,
    required double ruckWeightLbs,
  }) {
    // Base MET value based on speed on flat ground
    double baseMet;
    if (speedMph < 2.0) {
      baseMet = 2.5; // Very slow walking
    } else if (speedMph < 2.5) {
      baseMet = 3.0; // Slow walking
    } else if (speedMph < 3.0) {
      baseMet = 3.5; // Moderate walking
    } else if (speedMph < 3.5) {
      baseMet = 4.0; // Average walking
    } else if (speedMph < 4.0) {
      baseMet = 4.5; // Brisk walking
    } else if (speedMph < 5.0) {
      baseMet = 5.0; // Fast walking / power walking
    } else {
      baseMet = 6.0; // Very fast walking / jogging
    }
    
    // Adjust MET based on grade
    double gradeAdjustment = 0.0;
    if (grade > 0) {
      // Uphill: MET increases with grade
      // Formula approximates: For each 1% grade, increase MET by ~0.6 units at 4mph
      gradeAdjustment = grade * 0.6 * (speedMph / 4.0);
    } else if (grade < 0) {
      // Downhill: Negative grades have complex energy patterns
      // Going downhill is easier up to about -10% grade, then becomes harder due to braking
      double absGrade = grade.abs();
      if (absGrade <= 10) {
        // Slight downhill makes walking easier (reduce MET)
        gradeAdjustment = -absGrade * 0.1;
      } else {
        // Steep downhill requires braking energy (increase MET)
        gradeAdjustment = (absGrade - 10) * 0.15;
      }
    }
    
    // Adjust for load (ruck weight)
    double loadAdjustment = 0.0;
    if (ruckWeightLbs > 0) {
      // Simplified formula: ~0.05 MET per pound of weight (more impact at higher weights)
      loadAdjustment = math.min(ruckWeightLbs * 0.05, 5.0); // Cap at 5.0 additional METs
    }
    
    // Calculate final MET
    double finalMet = baseMet + gradeAdjustment + loadAdjustment;
    
    // Ensure MET is reasonable (between 2.0 and 15.0)
    finalMet = finalMet.clamp(2.0, 15.0);
    
    debugPrint('MET Calculation: Speed=${speedMph.toStringAsFixed(2)}mph, ' +
              'Grade=${grade.toStringAsFixed(1)}%, RuckWeight=${ruckWeightLbs.toStringAsFixed(1)}lbs, ' +
              'BaseMET=$baseMet, GradeAdj=${gradeAdjustment.toStringAsFixed(2)}, ' +
              'LoadAdj=${loadAdjustment.toStringAsFixed(2)}, Final=${finalMet.toStringAsFixed(2)}');
    
    return finalMet;
  }
  
  /// Convert km/h to mph
  static double kmhToMph(double kmh) {
    return kmh * 0.621371;
  }
  
  /// Calculate grade percentage from elevation change and distance
  /// 
  /// Parameters:
  /// - [elevationChangeMeters]: Change in elevation (positive for uphill, negative for downhill)
  /// - [distanceMeters]: Horizontal distance covered
  /// Returns: Grade percentage
  static double calculateGrade({
    required double elevationChangeMeters,
    required double distanceMeters,
  }) {
    if (distanceMeters <= 0) return 0;
    
    // Calculate grade percentage
    return (elevationChangeMeters / distanceMeters) * 100;
  }
}
