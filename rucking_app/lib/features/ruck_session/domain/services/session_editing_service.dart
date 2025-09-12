import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';
import 'package:rucking_app/features/ruck_session/domain/models/session_split.dart';
import 'package:rucking_app/features/ruck_session/domain/repositories/session_repository.dart';

/// Service for handling session editing operations
class SessionEditingService {
  final SessionRepository _sessionRepository;

  SessionEditingService(this._sessionRepository);

  /// Crop a session to a new end time by removing all data after the specified time
  Future<RuckSession> cropSession(
    RuckSession originalSession,
    DateTime newEndTime,
  ) async {
    try {
      AppLogger.info(
          '[SESSION_EDITING] Cropping session ${originalSession.id} to $newEndTime');

      // Validate the new end time
      if (newEndTime.isBefore(originalSession.startTime)) {
        throw ArgumentError('New end time cannot be before session start time');
      }

      if (newEndTime.isAfter(originalSession.endTime)) {
        throw ArgumentError('New end time cannot be after original end time');
      }

      // Calculate new duration
      final newDuration = newEndTime.difference(originalSession.startTime);

      // Filter location points
      final originalLocationPoints = originalSession.locationPoints ?? [];
      final filteredLocationPoints = originalLocationPoints.where((pointData) {
        // Handle both Map and LocationPoint formats
        DateTime pointTime;
        if (pointData is Map<String, dynamic>) {
          pointTime = DateTime.parse(pointData['timestamp'] as String);
        } else if (pointData is LocationPoint) {
          pointTime = pointData.timestamp;
        } else {
          // Skip unknown format
          return false;
        }
        return pointTime.isBefore(newEndTime) ||
            pointTime.isAtSameMomentAs(newEndTime);
      }).toList();

      // Filter heart rate samples
      final filteredHeartRateSamples = (originalSession.heartRateSamples ?? [])
          .where((sample) =>
              sample.timestamp.isBefore(newEndTime) ||
              sample.timestamp.isAtSameMomentAs(newEndTime))
          .toList();

      // Filter splits
      final filteredSplits = (originalSession.splits ?? [])
          .where((split) =>
              split.timestamp.isBefore(newEndTime) ||
              split.timestamp.isAtSameMomentAs(newEndTime))
          .toList();

      // Recalculate session metrics
      final newMetrics = await _recalculateSessionMetrics(
        originalSession: originalSession,
        newEndTime: newEndTime,
        newDuration: newDuration,
        filteredLocationPoints: filteredLocationPoints,
        filteredHeartRateSamples: filteredHeartRateSamples,
        filteredSplits: filteredSplits,
      );

      // Create updated session
      final updatedSession = originalSession.copyWith(
        endTime: newEndTime,
        duration: newDuration,
        distance: newMetrics.distance,
        elevationGain: newMetrics.elevationGain,
        elevationLoss: newMetrics.elevationLoss,
        caloriesBurned: newMetrics.caloriesBurned,
        averagePace: newMetrics.averagePace,
        heartRateSamples: filteredHeartRateSamples,
        avgHeartRate: newMetrics.avgHeartRate,
        maxHeartRate: newMetrics.maxHeartRate,
        minHeartRate: newMetrics.minHeartRate,
        splits: filteredSplits,
        locationPoints: filteredLocationPoints,
      );

      // Save to repository
      await _sessionRepository.updateSession(updatedSession);

      AppLogger.info('[SESSION_EDITING] Session cropped successfully');
      return updatedSession;
    } catch (e) {
      AppLogger.error('[SESSION_EDITING] Error cropping session', exception: e);
      rethrow;
    }
  }

  /// Detect potentially problematic segments in a session
  Future<List<SuspiciousSegment>> detectSuspiciousSegments(
    RuckSession session,
  ) async {
    try {
      final segments = <SuspiciousSegment>[];
      final locationPoints = session.locationPoints ?? [];

      if (locationPoints.isEmpty) return segments;

      // Analyze location points for suspicious activity
      DateTime? lastPointTime;
      LocationPoint? lastPoint;

      for (final pointData in locationPoints) {
        LocationPoint? point;

        // Handle different point formats
        if (pointData is Map<String, dynamic>) {
          try {
            point = LocationPoint.fromJson(pointData);
          } catch (e) {
            continue; // Skip invalid points
          }
        } else if (pointData is LocationPoint) {
          point = pointData;
        }

        if (point == null) continue;

        // Check for speed-based anomalies
        if (point.speed != null && point.speed! > 0) {
          final speedKmh = point.speed! * 3.6; // Convert m/s to km/h

          // Flag very fast movement (likely vehicular)
          if (speedKmh > 20.0) {
            segments.add(SuspiciousSegment(
              startTime: point.timestamp,
              endTime: point.timestamp,
              reason:
                  'Very fast movement (${speedKmh.toStringAsFixed(1)} km/h)',
              confidence: 0.9,
              speedKmh: speedKmh,
              type: SuspiciousSegmentType.vehicularMovement,
            ));
          }
          // Flag moderately fast movement
          else if (speedKmh > 12.0) {
            segments.add(SuspiciousSegment(
              startTime: point.timestamp,
              endTime: point.timestamp,
              reason: 'Fast movement (${speedKmh.toStringAsFixed(1)} km/h)',
              confidence: 0.6,
              speedKmh: speedKmh,
              type: SuspiciousSegmentType.fastMovement,
            ));
          }
        }

        // Check for long idle periods
        if (lastPointTime != null) {
          final timeDiff = point.timestamp.difference(lastPointTime!);
          if (timeDiff.inMinutes > 10) {
            segments.add(SuspiciousSegment(
              startTime: lastPointTime!,
              endTime: point.timestamp,
              reason: 'Long idle period (${timeDiff.inMinutes} minutes)',
              confidence: 0.7,
              type: SuspiciousSegmentType.longIdle,
            ));
          }
        }

        lastPointTime = point.timestamp;
        lastPoint = point;
      }

      AppLogger.info(
          '[SESSION_EDITING] Detected ${segments.length} suspicious segments');
      return segments;
    } catch (e) {
      AppLogger.error('[SESSION_EDITING] Error detecting suspicious segments',
          exception: e);
      return [];
    }
  }

  /// Suggest optimal end time based on suspicious segments
  DateTime? suggestOptimalEndTime(
    RuckSession session,
    List<SuspiciousSegment> suspiciousSegments,
  ) {
    if (suspiciousSegments.isEmpty) return null;

    // Find the earliest suspicious segment that suggests session should end
    DateTime? suggestedEndTime;

    for (final segment in suspiciousSegments) {
      if (segment.type == SuspiciousSegmentType.vehicularMovement ||
          segment.type == SuspiciousSegmentType.longIdle) {
        if (suggestedEndTime == null ||
            segment.startTime.isBefore(suggestedEndTime)) {
          suggestedEndTime = segment.startTime;
        }
      }
    }

    // Make sure suggested end time is reasonable (at least 5 minutes into session)
    if (suggestedEndTime != null) {
      final minEndTime = session.startTime.add(const Duration(minutes: 5));
      if (suggestedEndTime.isBefore(minEndTime)) {
        suggestedEndTime = minEndTime;
      }
    }

    return suggestedEndTime;
  }

  /// Recalculate session metrics for a cropped session
  Future<SessionMetrics> _recalculateSessionMetrics({
    required RuckSession originalSession,
    required DateTime newEndTime,
    required Duration newDuration,
    required List<dynamic> filteredLocationPoints,
    required List<HeartRateSample> filteredHeartRateSamples,
    required List<SessionSplit> filteredSplits,
  }) async {
    try {
      // Calculate distance from location points
      double distance = 0.0;
      double elevationGain = 0.0;
      double elevationLoss = 0.0;

      if (filteredLocationPoints.length >= 2) {
        LocationPoint? previousPoint;

        for (final pointData in filteredLocationPoints) {
          LocationPoint? point;

          if (pointData is Map<String, dynamic>) {
            try {
              point = LocationPoint.fromJson(pointData);
            } catch (e) {
              continue;
            }
          } else if (pointData is LocationPoint) {
            point = pointData;
          }

          if (point == null) continue;

          if (previousPoint != null) {
            // Calculate distance
            distance += _calculateDistance(previousPoint, point);

            // Calculate elevation changes
            final elevationDiff = point.elevation - previousPoint.elevation;
            if (elevationDiff > 0) {
              elevationGain += elevationDiff;
            } else {
              elevationLoss += elevationDiff.abs();
            }
          }

          previousPoint = point;
        }
      }

      // Convert distance from meters to kilometers
      distance = distance / 1000.0;

      // Calculate calories (basic estimation)
      const double baseCaloriesPerHour = 400.0;
      final double weightFactor = originalSession.ruckWeightKg / 20.0;
      final double durationHours =
          newDuration.inMilliseconds / (1000 * 60 * 60);
      final int caloriesBurned =
          ((baseCaloriesPerHour + (weightFactor * 50)) * durationHours).round();

      // Calculate average pace
      final double averagePace =
          distance > 0 ? (newDuration.inSeconds / 60) / distance : 0.0;

      // Calculate heart rate statistics
      int? avgHeartRate;
      int? maxHeartRate;
      int? minHeartRate;

      if (filteredHeartRateSamples.isNotEmpty) {
        final heartRates =
            filteredHeartRateSamples.map((s) => s.heartRate).toList();
        avgHeartRate =
            (heartRates.reduce((a, b) => a + b) / heartRates.length).round();
        maxHeartRate = heartRates.reduce((a, b) => a > b ? a : b);
        minHeartRate = heartRates.reduce((a, b) => a < b ? a : b);
      }

      return SessionMetrics(
        distance: distance,
        elevationGain: elevationGain,
        elevationLoss: elevationLoss,
        caloriesBurned: caloriesBurned,
        averagePace: averagePace,
        avgHeartRate: avgHeartRate,
        maxHeartRate: maxHeartRate,
        minHeartRate: minHeartRate,
      );
    } catch (e) {
      AppLogger.error('[SESSION_EDITING] Error recalculating metrics',
          exception: e);
      rethrow;
    }
  }

  /// Calculate distance between two location points using Haversine formula
  double _calculateDistance(LocationPoint p1, LocationPoint p2) {
    const double earthRadius = 6371000; // Earth's radius in meters

    final double lat1Rad = p1.latitude * (3.14159265359 / 180);
    final double lat2Rad = p2.latitude * (3.14159265359 / 180);
    final double deltaLatRad =
        (p2.latitude - p1.latitude) * (3.14159265359 / 180);
    final double deltaLonRad =
        (p2.longitude - p1.longitude) * (3.14159265359 / 180);

    final double a = (deltaLatRad / 2) * (deltaLatRad / 2) +
        lat1Rad * lat2Rad * (deltaLonRad / 2) * (deltaLonRad / 2);
    final double c = 2 * (a / (1 - a));

    return earthRadius * c;
  }
}

/// Represents a suspicious segment in a session
class SuspiciousSegment {
  final DateTime startTime;
  final DateTime endTime;
  final String reason;
  final double confidence; // 0.0 to 1.0
  final double? speedKmh;
  final SuspiciousSegmentType type;

  SuspiciousSegment({
    required this.startTime,
    required this.endTime,
    required this.reason,
    required this.confidence,
    this.speedKmh,
    required this.type,
  });
}

/// Types of suspicious segments
enum SuspiciousSegmentType {
  vehicularMovement,
  fastMovement,
  longIdle,
  gpsAnomaly,
}

/// Recalculated session metrics
class SessionMetrics {
  final double distance;
  final double elevationGain;
  final double elevationLoss;
  final int caloriesBurned;
  final double averagePace;
  final int? avgHeartRate;
  final int? maxHeartRate;
  final int? minHeartRate;

  SessionMetrics({
    required this.distance,
    required this.elevationGain,
    required this.elevationLoss,
    required this.caloriesBurned,
    required this.averagePace,
    this.avgHeartRate,
    this.maxHeartRate,
    this.minHeartRate,
  });
}
