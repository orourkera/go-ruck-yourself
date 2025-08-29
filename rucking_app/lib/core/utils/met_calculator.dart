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
  /// - [terrainMultiplier]: Energy cost multiplier for terrain type (1.0 = pavement baseline)
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
    double terrainMultiplier = 1.0, // Default to pavement baseline
    String calorieMethod = 'fusion', // 'mechanical' | 'hr' | 'fusion'
    List<dynamic>? heartRateSamples, // expects objects with bpm:int and timestamp:DateTime
    int age = 30,
    bool activeOnly = false,
    double? temperatureCelsius,
    double? windSpeedKmh,
    double? humidity,
    bool isRaining = false,
  }) {
    // If no movement and no significant elevation change, return minimal calories (resting metabolic rate)
    if (distanceKm <= 0.01 && (elevationGain + elevationLoss) <= 10.0) {
      // Resting metabolic rate: ~1.2 MET * weight * time (not including ruck weight when stationary)
      final restingCalories = 1.2 * userWeightKg * (elapsedSeconds / 3600.0);
      
      // If activeOnly is enabled, subtract resting energy to get only active calories
      if (activeOnly && elapsedSeconds > 0) {
        final durationHours = elapsedSeconds / 3600.0;
        final bmrPerHour = _estimateBmrKcalPerDay(weightKg: userWeightKg, age: age, gender: gender ?? 'male') / 24.0;
        final restingKcal = bmrPerHour * durationHours;
        final activeCalories = (restingCalories - restingKcal).clamp(0.0, double.infinity);
        return activeCalories;
      }
      
      return restingCalories;
    }
    
    // Calculate average speed (km/h)
    double durationHours = elapsedSeconds / 3600.0;
    double avgSpeedKmh = (durationHours > 0) ? (distanceKm / durationHours) : 0.0;
    double avgSpeedMph = kmhToMph(avgSpeedKmh);

    // Estimate an effective grade using uphill-only elevation gain to avoid
    // net-zero cancellation on out-and-back routes. This better reflects
    // the metabolic cost of climbing without averaging away the effort.
    double effectiveUphillGradePct = 0.0;
    if (distanceKm > 0) {
      effectiveUphillGradePct = calculateGrade(
        elevationChangeMeters: math.max(0.0, elevationGain),
        distanceMeters: distanceKm * 1000,
      );
    }
    double ruckWeightLbs = ruckWeightKg * 2.20462;

    // Calculate weather adjustment multiplier
    final weatherMultiplier = _calculateWeatherMultiplier(
      temperatureCelsius: temperatureCelsius,
      windSpeedKmh: windSpeedKmh,
      humidity: humidity,
      isRaining: isRaining,
      speedKmh: avgSpeedKmh,
    );

    // Mechanical model (Pandolf/Givoni–Goldman inspired)
    final mechanicalCalories = _calculateMechanicalCaloriesPandolf(
      userWeightKg: userWeightKg,
      ruckWeightKg: ruckWeightKg,
      speedKmh: avgSpeedKmh,
      gradePct: effectiveUphillGradePct,
      terrainMultiplier: 1.0, // Pure Pandolf uses no terrain adjustment
      elapsedSeconds: elapsedSeconds,
    );

    // HR-based calories if samples present
    double hrCalories = 0.0;
    if (heartRateSamples != null && heartRateSamples.isNotEmpty) {
      hrCalories = calculateCaloriesWithHeartRateSamples(
        heartRateSamples: heartRateSamples,
        weightKg: userWeightKg,
        age: age,
        gender: (gender == 'female') ? 'female' : 'male',
      );
    }

    // MET path retained (for comparison and fallback)
    final metValue = calculateRuckingMetByGrade(
      speedMph: avgSpeedMph,
      grade: effectiveUphillGradePct,
      ruckWeightLbs: ruckWeightLbs,
    );
    // Important: MET already includes load via ruckWeightLbs adjustment above.
    // To avoid double-counting, use BODY WEIGHT ONLY here.
    final baseCalories = calculateCaloriesBurned(
      weightKg: userWeightKg,
      durationMinutes: elapsedSeconds / 60.0,
      metValue: metValue,
    ) * terrainMultiplier;

    // Choose method - only Fusion gets weather adjustments
    if (calorieMethod == 'mechanical') {
      // Pure Pandolf with GORUCK load-ratio adjustment only
      return mechanicalCalories;
    } else if (calorieMethod == 'hr') {
      // HR-based method deprecated for rucking - fallback to fusion
      // (Keytel equation not appropriate for load carriage activities)
      // Fall through to fusion method below
    }

    // Fusion (recommended): confidence-weighted blend of HR and mechanical WITH weather
    double fusion = mechanicalCalories;
    if (hrCalories > 0) {
      // Estimate HR coverage: assume downsample ~20s between saved samples
      final expectedSamples = (elapsedSeconds / 20.0).clamp(1.0, 1e9);
      final coverage = (heartRateSamples!.length / expectedSamples).clamp(0.0, 1.0);
      // Reduce HR dominance for load carriage activities to avoid inflation
      // HR weight range: 0.3 → 0.6 based on coverage
      final wHr = (0.3 + 0.3 * coverage).clamp(0.3, 0.6);
      final wMech = 1.0 - wHr; // 0.4 → 0.7
      fusion = wHr * hrCalories + wMech * mechanicalCalories;
    }

    // Apply weather and terrain adjustments to both for apples-to-apples capping
    final mechAdjusted = mechanicalCalories * weatherMultiplier * terrainMultiplier;
    fusion *= weatherMultiplier * terrainMultiplier;

    // Cap fusion within ±15% of adjusted mechanical to prevent runaway inflation/deflation
    final lowerCap = mechAdjusted * 0.85;
    final upperCap = mechAdjusted * 1.15;
    fusion = fusion.clamp(lowerCap, upperCap);

    // Apply a small sex adjustment post‑fusion (only if unspecified)
    if (gender == null) fusion *= 0.925; // mid‑way when sex unknown

    // Subtract resting energy if activeOnly enabled
    if (activeOnly && elapsedSeconds > 0) {
      final durationHours = elapsedSeconds / 3600.0;
      final bmrPerHour = _estimateBmrKcalPerDay(weightKg: userWeightKg, age: age, gender: gender ?? 'male') / 24.0;
      final restingKcal = bmrPerHour * durationHours;
      fusion = (fusion - restingKcal).clamp(0.0, double.infinity);
    }

    return fusion;
  }

  /// Calculate weather adjustment multiplier based on environmental conditions
  /// Research-based adjustments for temperature, wind, humidity, and precipitation
  static double _calculateWeatherMultiplier({
    double? temperatureCelsius,
    double? windSpeedKmh,
    double? humidity,
    bool isRaining = false,
    double speedKmh = 0.0,
  }) {
    double multiplier = 1.0;

    // Temperature adjustments (conservative)
    if (temperatureCelsius != null) {
      final temp = temperatureCelsius;
      if (temp > 30) {
        // Hot weather: modest increase due to thermoregulation
        multiplier *= 1.06; // 6%
      } else if (temp > 25) {
        // Warm weather
        multiplier *= 1.03; // 3%
      } else if (temp < 0) {
        // Very cold (assuming clothing mitigates most extra cost)
        multiplier *= 1.05; // 5%
      } else if (temp < 5) {
        // Cold weather
        multiplier *= 1.03; // 3%
      }
      // Optimal range (5-25°C) has no adjustment (multiplier stays 1.0)
    }

    // Wind resistance adjustments (speed-dependent, conservative at walking speeds)
    if (windSpeedKmh != null && windSpeedKmh > 10 && speedKmh > 3.0) {
      // Keep small at typical ruck speeds
      final windFactor = (windSpeedKmh - 10) / 40.0; // 0-1 for 10-50 km/h
      final speedFactor = (speedKmh / 6.0).clamp(0.0, 1.0); // normalize to ~6 km/h
      final windAdjustment = windFactor * speedFactor * 0.04; // Up to 4%
      multiplier *= (1.0 + windAdjustment.clamp(0.0, 0.04));
    }

    // Humidity adjustments (affects cooling efficiency; mild)
    if (humidity != null && temperatureCelsius != null && temperatureCelsius > 20) {
      if (humidity > 80) {
        multiplier *= 1.02; // 2%
      } else if (humidity > 70) {
        multiplier *= 1.01; // 1%
      }
    }

    // Precipitation adjustments (affects footing and muscle stabilization; mild)
    if (isRaining) {
      multiplier *= 1.02; // 2%
    }

    // Cap total weather adjustment at reasonable bounds (more conservative)
    return multiplier.clamp(1.0, 1.10); // Max 10% increase from weather
  }

  /// Enhanced Pandolf equation with GORUCK load-ratio corrections (pure - no terrain/weather)
  static double _calculateMechanicalCaloriesPandolf({
    required double userWeightKg,
    required double ruckWeightKg,
    required double speedKmh,
    required double gradePct,
    double terrainMultiplier = 1.0, // Default to 1.0 for pure Pandolf
    required int elapsedSeconds,
  }) {
    // Convert units
    final v = (speedKmh / 3.6).clamp(0.0, 3.0); // m/s typical walking speeds up to ~3 m/s
    final W = userWeightKg;
    final L = ruckWeightKg;
    final G = gradePct; // percent
    final eta = terrainMultiplier.clamp(0.8, 1.3); // surface factor

    // Pandolf (1977) baseline (approximation; coefficients tuned for walking):
    // M (W) = 1.5W + 2.0(W+L)(L/W)^2 + eta*(W+L)*(1.5 v^2 + 0.35 v G)
    // Ensure safe division
    final lw = (W > 0) ? (L / W) : 0.0;
    final termLoad = 2.0 * (W + L) * (lw * lw);
    final termSpeedGrade = eta * (W + L) * (1.5 * v * v + 0.35 * v * G.clamp(-20.0, 30.0));
    double M = 1.5 * W + termLoad + termSpeedGrade; // Watts

    // GORUCK-inspired load ratio adjustment to address Pandolf underestimation
    // Research shows 12-33% underestimation, but need to be more conservative for civilian rucking
    final loadRatio = lw; // L/W ratio (0.0 to ~0.33 for reasonable loads)
    final speedMph = speedKmh * 0.621371;
    
    // Calculate adjustment factor based on load ratio and speed
    // Reduced from military research values to better match civilian rucking reality
    double adjustmentFactor = 1.0;
    if (loadRatio > 0 && speedMph > 2.0) {
      // Base adjustment scales with load ratio (0-15% at max, reduced from 27%)
      final baseAdjustment = math.min(loadRatio * 0.45, 0.15); // Cap at 15% instead of 27%
      // Speed factor: more adjustment at higher speeds (research shows this)
      final speedFactor = math.min((speedMph - 2.0) / 2.0, 1.0); // 0-1 factor for 2-4mph+
      adjustmentFactor = 1.0 + (baseAdjustment * speedFactor);
    }
    
    // Apply the research-based adjustment
    M = M * adjustmentFactor;

    // Clamp to reasonable range (walking with load)
    M = M.clamp(50.0, 800.0);

    // Convert W→kcal
    final kcalPerSec = (M / 4186.0); // 1 kcal ≈ 4186 J; per second
    double kcal = kcalPerSec * elapsedSeconds;

    // Safety: if speed is near zero but distance > 0 (GPS noise), scale by distance fraction
    if (speedKmh < 0.5 && elapsedSeconds > 0) {
      final minRate = 0.2; // prevent total collapse
      kcal *= minRate;
    }

    return kcal;
  }

  /// Rough BMR estimate (kcal/day) using Mifflin–St Jeor with height fallback
  static double _estimateBmrKcalPerDay({
    required double weightKg,
    required int age,
    String gender = 'male',
    double? heightCm,
  }) {
    // If height unknown, use average 175 cm male / 162 cm female
    final h = heightCm ?? (gender == 'female' ? 162.0 : 175.0);
    final w = weightKg;
    final a = age.clamp(10, 100);
    final s = (gender == 'female') ? -161.0 : 5.0;
    final bmr = (10.0 * w) + (6.25 * h) - (5.0 * a) + s; // kcal/day
    return bmr.clamp(900.0, 3000.0);
  }
}
