import 'dart:math';
import 'package:rucking_app/core/models/route.dart';
import 'package:rucking_app/core/models/route_elevation_point.dart';

/// 🎯 **Advanced ETA Calculator**
/// 
/// Sophisticated algorithms for calculating estimated time of arrival
/// with multiple calculation methods and confidence indicators.
class ETACalculator {
  static const double _averageWalkingSpeed = 1.4; // m/s (~3.1 mph)
  static const double _averageRuckingSpeed = 1.2; // m/s (~2.7 mph with weight)
  static const double _maxReasonableSpeed = 3.0; // m/s (~6.7 mph)
  static const double _minReasonableSpeed = 0.5; // m/s (~1.1 mph)
  
  /// 🚀 **Calculate ETA with Multiple Methods**
  /// 
  /// Returns comprehensive ETA data with confidence indicators
  ETAResult calculateETA({
    required Route route,
    required double currentLatitude,
    required double currentLongitude,
    required List<double> recentSpeeds, // Last 10-20 speed readings
    double? currentPace, // Current instantaneous pace
    double? averagePace, // Session average pace
    double? targetWeight, // Pack weight for adjusted calculations
    Duration? sessionDuration, // Time elapsed in session
  }) {
    final remainingDistance = _calculateRemainingDistance(
      route, currentLatitude, currentLongitude
    );
    
    if (remainingDistance <= 0) {
      return ETAResult(
        primaryETA: Duration.zero,
        confidence: 1.0,
        alternativeETAs: {},
        remainingDistance: 0,
        estimatedMethods: ['completed'],
      );
    }
    
    final etas = <String, Duration>{};
    final confidences = <String, double>{};
    
    // Method 1: Current Pace ETA
    if (currentPace != null && currentPace > 0) {
      final currentETA = Duration(seconds: (remainingDistance / currentPace).round());
      etas['current_pace'] = currentETA;
      confidences['current_pace'] = _calculatePaceConfidence(currentPace, recentSpeeds);
    }
    
    // Method 2: Average Pace ETA
    if (averagePace != null && averagePace > 0) {
      final averageETA = Duration(seconds: (remainingDistance / averagePace).round());
      etas['average_pace'] = averageETA;
      confidences['average_pace'] = _calculateAverageConfidence(averagePace, sessionDuration);
    }
    
    // Method 3: Moving Average ETA
    if (recentSpeeds.isNotEmpty) {
      final movingAverage = _calculateMovingAverage(recentSpeeds);
      final movingETA = Duration(seconds: (remainingDistance / movingAverage).round());
      etas['moving_average'] = movingETA;
      confidences['moving_average'] = _calculateMovingAverageConfidence(recentSpeeds);
    }
    
    // Method 4: Terrain-Adjusted ETA
    final terrainETA = _calculateTerrainAdjustedETA(
      route, currentLatitude, currentLongitude, targetWeight
    );
    etas['terrain_adjusted'] = terrainETA;
    confidences['terrain_adjusted'] = 0.7; // Moderate confidence for terrain estimates
    
    // Method 5: Adaptive ETA (combines multiple methods)
    final adaptiveETA = _calculateAdaptiveETA(etas, confidences, recentSpeeds);
    etas['adaptive'] = adaptiveETA;
    confidences['adaptive'] = _calculateAdaptiveConfidence(confidences);
    
    // Determine primary ETA (highest confidence or adaptive)
    String primaryMethod = 'adaptive';
    Duration primaryETA = adaptiveETA;
    double primaryConfidence = confidences['adaptive'] ?? 0.5;
    
    // Override with higher confidence method if available
    confidences.forEach((method, confidence) {
      if (confidence > primaryConfidence && method != 'adaptive') {
        primaryMethod = method;
        primaryETA = etas[method]!;
        primaryConfidence = confidence;
      }
    });
    
    return ETAResult(
      primaryETA: primaryETA,
      confidence: primaryConfidence,
      alternativeETAs: Map.from(etas)..remove(primaryMethod),
      remainingDistance: remainingDistance,
      estimatedMethods: etas.keys.toList(),
    );
  }
  
  /// 📏 **Calculate Remaining Distance**
  double _calculateRemainingDistance(Route route, double currentLat, double currentLon) {
    if (route.coordinatePoints.isEmpty) return 0.0;
    
    // Find closest point on route
    int closestIndex = 0;
    double minDistance = double.infinity;
    
    for (int i = 0; i < route.coordinatePoints.length; i++) {
      final point = route.coordinatePoints[i];
      final distance = _calculateHaversineDistance(
        currentLat, currentLon, point.latitude, point.longitude
      );
      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }
    
    // Calculate remaining distance from closest point
    double remainingDistance = 0.0;
    for (int i = closestIndex; i < route.coordinatePoints.length - 1; i++) {
      final current = route.coordinatePoints[i];
      final next = route.coordinatePoints[i + 1];
      remainingDistance += _calculateHaversineDistance(
        current.latitude, current.longitude, next.latitude, next.longitude
      );
    }
    
    return remainingDistance;
  }
  
  /// 🏔️ **Calculate Terrain-Adjusted ETA**
  Duration _calculateTerrainAdjustedETA(
    Route route, 
    double currentLat, 
    double currentLon,
    double? targetWeight,
  ) {
    final remainingDistance = _calculateRemainingDistance(route, currentLat, currentLon);
    if (remainingDistance <= 0) return Duration.zero;
    
    // Base speed (adjusted for weight)
    double baseSpeed = targetWeight != null && targetWeight > 0
        ? _averageRuckingSpeed * (1 - (targetWeight / 100) * 0.1) // 10% slower per 100lbs
        : _averageWalkingSpeed;
    
    // Calculate elevation changes in remaining route
    final elevationAdjustment = _calculateElevationAdjustment(
      route, currentLat, currentLon
    );
    
    // Terrain difficulty multiplier
    final terrainMultiplier = _calculateTerrainMultiplier(route);
    
    // Adjusted speed
    final adjustedSpeed = baseSpeed * elevationAdjustment * terrainMultiplier;
    final clampedSpeed = math.max(_minReasonableSpeed, 
                         math.min(_maxReasonableSpeed, adjustedSpeed));
    
    return Duration(seconds: (remainingDistance / clampedSpeed).round());
  }
  
  /// ⛰️ **Calculate Elevation Adjustment Factor**
  double _calculateElevationAdjustment(Route route, double currentLat, double currentLon) {
    if (route.elevationProfile.isEmpty) return 1.0;
    
    // Find current position in elevation profile
    int currentIndex = 0;
    double totalElevationGain = 0.0;
    double totalElevationLoss = 0.0;
    
    // Calculate remaining elevation changes
    for (int i = currentIndex; i < route.elevationProfile.length - 1; i++) {
      final current = route.elevationProfile[i];
      final next = route.elevationProfile[i + 1];
      final elevationChange = next.elevation - current.elevation;
      
      if (elevationChange > 0) {
        totalElevationGain += elevationChange;
      } else {
        totalElevationLoss += elevationChange.abs();
      }
    }
    
    // Elevation adjustment factor
    // Uphill: 1 meter = ~10 seconds slower per km
    // Downhill: 1 meter = ~2 seconds faster per km
    final uphillPenalty = totalElevationGain * 0.1; // 10% slower per 100m gain
    final downhillBonus = totalElevationLoss * 0.02; // 2% faster per 100m loss
    
    return math.max(0.5, 1.0 - (uphillPenalty - downhillBonus));
  }
  
  /// 🌲 **Calculate Terrain Multiplier**
  double _calculateTerrainMultiplier(Route route) {
    // This would ideally use terrain data from the route
    // For now, use route difficulty or default to moderate terrain
    final difficulty = route.difficulty?.toLowerCase() ?? 'moderate';
    
    switch (difficulty) {
      case 'easy':
        return 1.1; // 10% faster on easy terrain
      case 'moderate':
        return 1.0; // Normal speed
      case 'hard':
        return 0.85; // 15% slower on hard terrain
      case 'extreme':
        return 0.7; // 30% slower on extreme terrain
      default:
        return 1.0;
    }
  }
  
  /// 📊 **Calculate Moving Average Speed**
  double _calculateMovingAverage(List<double> recentSpeeds) {
    if (recentSpeeds.isEmpty) return _averageRuckingSpeed;
    
    // Weight recent speeds more heavily
    double weightedSum = 0.0;
    double totalWeight = 0.0;
    
    for (int i = 0; i < recentSpeeds.length; i++) {
      final weight = i / recentSpeeds.length + 0.5; // More recent = higher weight
      weightedSum += recentSpeeds[i] * weight;
      totalWeight += weight;
    }
    
    final average = weightedSum / totalWeight;
    return math.max(_minReasonableSpeed, math.min(_maxReasonableSpeed, average));
  }
  
  /// 🤖 **Calculate Adaptive ETA**
  Duration _calculateAdaptiveETA(
    Map<String, Duration> etas, 
    Map<String, double> confidences,
    List<double> recentSpeeds,
  ) {
    if (etas.isEmpty) return Duration(hours: 1); // Default fallback
    
    // Weight ETAs by their confidence levels
    double weightedSeconds = 0.0;
    double totalWeight = 0.0;
    
    etas.forEach((method, eta) {
      if (method != 'adaptive') { // Don't include adaptive in its own calculation
        final confidence = confidences[method] ?? 0.5;
        final weight = confidence * confidence; // Square for more pronounced weighting
        weightedSeconds += eta.inSeconds * weight;
        totalWeight += weight;
      }
    });
    
    if (totalWeight == 0) return etas.values.first;
    
    return Duration(seconds: (weightedSeconds / totalWeight).round());
  }
  
  /// 🎯 **Calculate Pace Confidence**
  double _calculatePaceConfidence(double currentPace, List<double> recentSpeeds) {
    if (recentSpeeds.isEmpty) return 0.3;
    
    // Check how consistent current pace is with recent speeds
    final average = recentSpeeds.reduce((a, b) => a + b) / recentSpeeds.length;
    final standardDeviation = _calculateStandardDeviation(recentSpeeds);
    final deviation = (currentPace - average).abs();
    
    // Higher confidence if current pace is close to recent average
    final consistencyScore = math.max(0.0, 1.0 - (deviation / (standardDeviation + 0.1)));
    
    // Reasonable speed check
    final speedReasonability = _isReasonableSpeed(currentPace) ? 1.0 : 0.3;
    
    return (consistencyScore * 0.7 + speedReasonability * 0.3).clamp(0.0, 1.0);
  }
  
  /// 📈 **Calculate Average Confidence**
  double _calculateAverageConfidence(double averagePace, Duration? sessionDuration) {
    if (sessionDuration == null) return 0.5;
    
    // More confidence in averages from longer sessions
    final timeFactorMinutes = sessionDuration.inMinutes.toDouble();
    final timeFactor = (timeFactorMinutes / 30).clamp(0.0, 1.0); // Max confidence at 30+ minutes
    
    // Reasonable speed check
    final speedReasonability = _isReasonableSpeed(averagePace) ? 1.0 : 0.3;
    
    return (timeFactor * 0.6 + speedReasonability * 0.4).clamp(0.3, 0.9);
  }
  
  /// 📊 **Calculate Moving Average Confidence**
  double _calculateMovingAverageConfidence(List<double> recentSpeeds) {
    if (recentSpeeds.length < 3) return 0.4;
    
    // More data points = higher confidence
    final dataFactor = (recentSpeeds.length / 20).clamp(0.0, 1.0);
    
    // Consistency of recent speeds
    final standardDeviation = _calculateStandardDeviation(recentSpeeds);
    final consistencyFactor = math.max(0.0, 1.0 - standardDeviation);
    
    return (dataFactor * 0.5 + consistencyFactor * 0.5).clamp(0.3, 0.8);
  }
  
  /// 🤖 **Calculate Adaptive Confidence**
  double _calculateAdaptiveConfidence(Map<String, double> confidences) {
    final values = confidences.values.where((c) => c > 0).toList();
    if (values.isEmpty) return 0.5;
    
    // Adaptive confidence is the weighted average of component confidences
    return values.reduce((a, b) => a + b) / values.length;
  }
  
  /// ✅ **Check if Speed is Reasonable**
  bool _isReasonableSpeed(double speed) {
    return speed >= _minReasonableSpeed && speed <= _maxReasonableSpeed;
  }
  
  /// 📐 **Calculate Haversine Distance**
  double _calculateHaversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Earth's radius in meters
    
    final dLat = (lat2 - lat1) * (math.pi / 180);
    final dLon = (lon2 - lon1) * (math.pi / 180);
    
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * (math.pi / 180)) * math.cos(lat2 * (math.pi / 180)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }
  
  /// 📊 **Calculate Standard Deviation**
  double _calculateStandardDeviation(List<double> values) {
    if (values.length < 2) return 0.0;
    
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values
        .map((value) => math.pow(value - mean, 2))
        .reduce((a, b) => a + b) / values.length;
    
    return math.sqrt(variance);
  }
}

/// 🎯 **ETA Calculation Result**
/// 
/// Comprehensive result containing multiple ETA estimates with confidence
class ETAResult {
  final Duration primaryETA;
  final double confidence; // 0.0 to 1.0
  final Map<String, Duration> alternativeETAs;
  final double remainingDistance; // in meters
  final List<String> estimatedMethods;
  
  const ETAResult({
    required this.primaryETA,
    required this.confidence,
    required this.alternativeETAs,
    required this.remainingDistance,
    required this.estimatedMethods,
  });
  
  /// 🎨 **Format ETA for Display**
  String formatPrimaryETA({bool includeConfidence = false}) {
    final hours = primaryETA.inHours;
    final minutes = primaryETA.inMinutes.remainder(60);
    
    String formatted;
    if (hours > 0) {
      formatted = '${hours}h ${minutes}m';
    } else {
      formatted = '${minutes}m';
    }
    
    if (includeConfidence) {
      final confidencePercent = (confidence * 100).round();
      formatted += ' ($confidencePercent% confidence)';
    }
    
    return formatted;
  }
  
  /// 📊 **Get Confidence Level Description**
  String getConfidenceDescription() {
    if (confidence >= 0.8) return 'High';
    if (confidence >= 0.6) return 'Moderate';
    if (confidence >= 0.4) return 'Low';
    return 'Very Low';
  }
  
  /// 🎯 **Get Best Alternative ETA**
  Duration? getBestAlternative() {
    if (alternativeETAs.isEmpty) return null;
    
    // Return the ETA closest to primary ETA (likely most reliable alternative)
    Duration? closest;
    int smallestDifference = double.maxFinite.toInt();
    
    alternativeETAs.values.forEach((eta) {
      final difference = (eta.inSeconds - primaryETA.inSeconds).abs();
      if (difference < smallestDifference) {
        smallestDifference = difference;
        closest = eta;
      }
    });
    
    return closest;
  }
  
  /// 📈 **Get ETA Range**
  String getETARange() {
    if (alternativeETAs.isEmpty) return formatPrimaryETA();
    
    final allETAs = [primaryETA, ...alternativeETAs.values];
    allETAs.sort((a, b) => a.inSeconds.compareTo(b.inSeconds));
    
    final earliest = allETAs.first;
    final latest = allETAs.last;
    
    if (earliest == latest) return formatPrimaryETA();
    
    return '${_formatDuration(earliest)} - ${_formatDuration(latest)}';
  }
  
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }
}
