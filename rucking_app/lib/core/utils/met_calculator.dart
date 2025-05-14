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
    required double durationMinutes,
    required double metValue,
  }) {
    // Convert duration to hours
    final double durationHours = durationMinutes / 60.0;
    
    // Apply MET formula
    final calories = metValue * weightKg * durationHours;
    
    // Ensure calories are not negative
    return calories > 0 ? calories : 0.0;
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
  
  /// Calculate calories burned using heart rate-based formula (per sample)
  /// (ACSM/Keytel et al. equations)
  ///
  /// Parameters:
  /// - [samples]: List of heart rate samples (ordered by time)
  /// - [weightKg]: User's weight in kilograms
  /// - [age]: User's age in years (default 30)
  /// - [gender]: 'male' or 'female' (default 'male')
  /// Returns: Total calories burned using HR-based method
  static double calculateCaloriesWithHeartRateSamples({
    required List heartRateSamples,
    required double weightKg,
    int age = 30,
    String gender = 'male',
  }) {
    if (heartRateSamples.length < 2) return 0.0;
    double totalCalories = 0.0;
    for (int i = 1; i < heartRateSamples.length; i++) {
      final prev = heartRateSamples[i - 1];
      final curr = heartRateSamples[i];
      final durationMinutes = curr.timestamp.difference(prev.timestamp).inSeconds / 60.0;
      final hr = curr.bpm;
      double cals;
      if (gender == 'female') {
        cals = ((-20.4022 + (0.4472 * hr) - (0.1263 * weightKg) + (0.074 * age)) / 4.184) * durationMinutes;
      } else {
        cals = ((-55.0969 + (0.6309 * hr) + (0.1988 * weightKg) + (0.2017 * age)) / 4.184) * durationMinutes;
      }
      if (cals > 0) totalCalories += cals;
    }
    return totalCalories;
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

  /// Calculate calories burned for a rucking session using all relevant parameters.
  ///
  /// Parameters:
  /// - [userWeightKg]: User's body weight in kilograms
  /// - [ruckWeightKg]: Weight of the rucksack in kilograms
  /// - [distanceKm]: Total distance covered in kilometers
  /// - [elapsedSeconds]: Total elapsed time in seconds
  /// - [elevationGain]: Total elevation gain in meters
  /// - [elevationLoss]: Total elevation loss in meters
  /// - [gender]: User's gender ('male', 'female', or null) - affects calorie calculations
  ///
  /// Returns: Calories burned as a double
  static double calculateRuckingCalories({
    required double userWeightKg,
    required double ruckWeightKg,
    required double distanceKm,
    required int elapsedSeconds,
    double elevationGain = 0.0,
    double elevationLoss = 0.0,
    String? gender,
  }) {
    // Calculate average speed (km/h)
    double durationHours = elapsedSeconds / 3600.0;
    double avgSpeedKmh = (durationHours > 0) ? (distanceKm / durationHours) : 0.0;
    double avgSpeedMph = kmhToMph(avgSpeedKmh);

    // Estimate average grade (if available)
    double avgGrade = 0.0;
    if (distanceKm > 0) {
      avgGrade = calculateGrade(
        elevationChangeMeters: elevationGain - elevationLoss,
        distanceMeters: distanceKm * 1000,
      );
    }
    double ruckWeightLbs = ruckWeightKg * 2.20462;

    // Calculate MET dynamically
    final metValue = calculateRuckingMetByGrade(
      speedMph: avgSpeedMph,
      grade: avgGrade,
      ruckWeightLbs: ruckWeightLbs,
    );

    double durationMinutes = elapsedSeconds / 60.0;
    
    // Calculate base calories using MET formula
    double baseCalories = calculateCaloriesBurned(
      weightKg: userWeightKg + ruckWeightKg,
      durationMinutes: durationMinutes,
      metValue: metValue,
    );
    
    // Apply gender-based adjustment for more accurate calculations
    // Female and male bodies metabolize calories differently due to body composition differences
    double genderAdjustedCalories = baseCalories;
    if (gender == 'female') {
      // Female adjustment: approx. 15-20% lower calorie burn due to
      // differences in body composition (more fat, less muscle)
      // and lower basal metabolic rate
      genderAdjustedCalories = baseCalories * 0.85; // 15% reduction
      
      debugPrint('Gender-adjusted calories (female): ${genderAdjustedCalories.toStringAsFixed(2)} ' +
                'from base: ${baseCalories.toStringAsFixed(2)}');
    } else if (gender == 'male') {
      // Male baseline - no adjustment needed as the formulas are typically
      // based on male physiological data
      genderAdjustedCalories = baseCalories;
      
      debugPrint('Gender-adjusted calories (male): ${genderAdjustedCalories.toStringAsFixed(2)} ' +
                'from base: ${baseCalories.toStringAsFixed(2)}');
    } else {
      // If gender is not specified, use a middle ground (7.5% reduction)
      genderAdjustedCalories = baseCalories * 0.925;
      
      debugPrint('Gender-adjusted calories (unspecified): ${genderAdjustedCalories.toStringAsFixed(2)} ' +
                'from base: ${baseCalories.toStringAsFixed(2)}');
    }
    
    return genderAdjustedCalories;
  }
}

