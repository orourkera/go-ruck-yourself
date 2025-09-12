import 'package:equatable/equatable.dart';
import 'route.dart';

/// Planned ruck model for user-scheduled ruck sessions
/// Represents a user's plan to complete a specific route at a specific time
class PlannedRuck extends Equatable {
  const PlannedRuck({
    this.id,
    required this.userId,
    required this.routeId,
    required this.plannedDate,
    this.plannedStartTime,
    this.targetWeight,
    this.targetPace,
    this.notes,
    this.projectedDurationMinutes,
    this.projectedCalories,
    this.projectedIntensity,
    this.status = PlannedRuckStatus.planned,
    this.actualSessionId,
    this.completedAt,
    this.cancelledAt,
    this.cancelReason,
    this.createdAt,
    this.updatedAt,
    this.route,
  });

  // Core identification
  final String? id;
  final String userId;
  final String routeId;

  // Planning data
  final DateTime plannedDate;
  final DateTime? plannedStartTime; // Specific time if planned
  final double? targetWeight; // Target pack weight in kg
  final double? targetPace; // Target pace in minutes per km
  final String? notes; // User notes and preparation details

  // Projections (calculated based on user profile and route)
  final int? projectedDurationMinutes;
  final int? projectedCalories;
  final String? projectedIntensity; // 'low', 'moderate', 'high', 'extreme'

  // Status tracking
  final PlannedRuckStatus status;
  final String? actualSessionId; // Links to completed RuckSession
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancelReason;

  // Metadata
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Related data (loaded separately)
  final Route? route;

  @override
  List<Object?> get props => [
        id,
        userId,
        routeId,
        plannedDate,
        plannedStartTime,
        targetWeight,
        targetPace,
        notes,
        projectedDurationMinutes,
        projectedCalories,
        projectedIntensity,
        status,
        actualSessionId,
        completedAt,
        cancelledAt,
        cancelReason,
        createdAt,
        updatedAt,
        route,
      ];

  /// Create PlannedRuck from API JSON response
  factory PlannedRuck.fromJson(Map<String, dynamic> json) {
    return PlannedRuck(
      id: json['id'] as String?,
      userId: json['user_id']?.toString() ?? '',
      routeId: json['route_id']?.toString() ?? '',
      plannedDate: DateTime.parse(
          json['planned_date']?.toString() ?? DateTime.now().toIso8601String()),
      plannedStartTime: json['planned_start_time'] != null
          ? DateTime.parse(json['planned_start_time']?.toString() ?? '')
          : null,
      // Map backend field names to model fields
      targetWeight: json['planned_ruck_weight_kg'] != null
          ? (json['planned_ruck_weight_kg'] as num).toDouble()
          : json['target_weight'] != null
              ? (json['target_weight'] as num).toDouble()
              : null,
      targetPace: json['target_pace'] != null
          ? (json['target_pace'] as num).toDouble()
          : null,
      notes: json['notes'] as String?,
      // Convert hours to minutes for duration
      projectedDurationMinutes: json['estimated_duration_hours'] != null
          ? ((json['estimated_duration_hours'] as num) * 60).round()
          : json['projected_duration_minutes'] as int?,
      projectedCalories: (json['estimated_calories'] as int?) ??
          (json['projected_calories'] as int?),
      // Map planned_difficulty to projected_intensity
      projectedIntensity: (json['planned_difficulty'] as String?) ??
          (json['projected_intensity'] as String?),
      status:
          PlannedRuckStatus.fromString(json['status'] as String? ?? 'planned'),
      actualSessionId: json['actual_session_id'] as String?,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at']?.toString() ?? '')
          : null,
      cancelledAt: json['cancelled_at'] != null
          ? DateTime.parse(json['cancelled_at']?.toString() ?? '')
          : null,
      cancelReason: json['cancel_reason'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at']?.toString() ?? '')
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at']?.toString() ?? '')
          : null,
      route: json['route'] != null
          ? Route.fromJson(json['route'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Convert PlannedRuck to JSON for API requests
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'route_id': routeId,
      'planned_date': plannedDate.toIso8601String(),
      if (plannedStartTime != null)
        'planned_start_time': plannedStartTime!.toIso8601String(),
      if (targetWeight != null) 'target_weight': targetWeight,
      if (targetPace != null) 'target_pace': targetPace,
      if (notes != null) 'notes': notes,
      if (projectedDurationMinutes != null)
        'projected_duration_minutes': projectedDurationMinutes,
      if (projectedCalories != null) 'projected_calories': projectedCalories,
      if (projectedIntensity != null) 'projected_intensity': projectedIntensity,
      'status': status.value,
      if (actualSessionId != null) 'actual_session_id': actualSessionId,
      if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
      if (cancelledAt != null) 'cancelled_at': cancelledAt!.toIso8601String(),
      if (cancelReason != null) 'cancel_reason': cancelReason,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      if (route != null) 'route': route!.toJson(),
    };
  }

  /// Create a copy of this PlannedRuck with updated fields
  PlannedRuck copyWith({
    String? id,
    String? userId,
    String? routeId,
    DateTime? plannedDate,
    DateTime? plannedStartTime,
    double? targetWeight,
    double? targetPace,
    String? notes,
    int? projectedDurationMinutes,
    int? projectedCalories,
    String? projectedIntensity,
    PlannedRuckStatus? status,
    String? actualSessionId,
    DateTime? completedAt,
    DateTime? cancelledAt,
    String? cancelReason,
    DateTime? createdAt,
    DateTime? updatedAt,
    Route? route,
  }) {
    return PlannedRuck(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      routeId: routeId ?? this.routeId,
      plannedDate: plannedDate ?? this.plannedDate,
      plannedStartTime: plannedStartTime ?? this.plannedStartTime,
      targetWeight: targetWeight ?? this.targetWeight,
      targetPace: targetPace ?? this.targetPace,
      notes: notes ?? this.notes,
      projectedDurationMinutes:
          projectedDurationMinutes ?? this.projectedDurationMinutes,
      projectedCalories: projectedCalories ?? this.projectedCalories,
      projectedIntensity: projectedIntensity ?? this.projectedIntensity,
      status: status ?? this.status,
      actualSessionId: actualSessionId ?? this.actualSessionId,
      completedAt: completedAt ?? this.completedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancelReason: cancelReason ?? this.cancelReason,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      route: route ?? this.route,
    );
  }

  // Helper methods and computed properties

  /// Get formatted planned date string
  String get formattedPlannedDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final planDate =
        DateTime(plannedDate.year, plannedDate.month, plannedDate.day);

    if (planDate == today) {
      return 'Today';
    } else if (planDate == tomorrow) {
      return 'Tomorrow';
    } else if (planDate.isBefore(today)) {
      final daysAgo = today.difference(planDate).inDays;
      return '$daysAgo days ago';
    } else {
      final daysFromNow = planDate.difference(today).inDays;
      if (daysFromNow <= 7) {
        return _getDayName(planDate.weekday);
      } else {
        return '${planDate.day}/${planDate.month}/${planDate.year}';
      }
    }
  }

  /// Get formatted planned start time
  String get formattedPlannedTime {
    if (plannedStartTime == null) return 'No specific time';

    final hour = plannedStartTime!.hour;
    final minute = plannedStartTime!.minute;
    final amPm = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final displayMinute = minute.toString().padLeft(2, '0');

    return '$displayHour:$displayMinute $amPm';
  }

  /// Get formatted target weight
  String get formattedTargetWeight {
    if (targetWeight == null) return 'No weight target';
    return '${targetWeight!.toStringAsFixed(1)}kg pack weight';
  }

  /// Get formatted target pace
  String get formattedTargetPace {
    if (targetPace == null) return 'No pace target';

    final minutes = targetPace!.floor();
    final seconds = ((targetPace! - minutes) * 60).round();

    return '${minutes}:${seconds.toString().padLeft(2, '0')}/km pace';
  }

  /// Get formatted projected duration
  String get formattedProjectedDuration {
    if (projectedDurationMinutes == null) return 'Unknown duration';

    final minutes = projectedDurationMinutes!;
    if (minutes < 60) {
      return '${minutes}min';
    } else {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;
      if (remainingMinutes == 0) {
        return '${hours}h';
      } else {
        return '${hours}h ${remainingMinutes}min';
      }
    }
  }

  /// Get formatted projected calories
  String get formattedProjectedCalories {
    if (projectedCalories == null) return 'Unknown calories';
    return '~${projectedCalories} calories';
  }

  /// Get projected intensity level
  IntensityLevel get intensityLevel {
    switch (projectedIntensity?.toLowerCase()) {
      case 'low':
        return IntensityLevel.low;
      case 'moderate':
        return IntensityLevel.moderate;
      case 'high':
        return IntensityLevel.high;
      case 'extreme':
        return IntensityLevel.extreme;
      default:
        return IntensityLevel.moderate;
    }
  }

  /// Check if this ruck is planned for today
  bool get isToday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final planDate =
        DateTime(plannedDate.year, plannedDate.month, plannedDate.day);
    return planDate == today;
  }

  /// Check if this ruck is overdue
  bool get isOverdue {
    if (status != PlannedRuckStatus.planned) return false;

    final now = DateTime.now();
    if (plannedStartTime != null) {
      return plannedStartTime!.isBefore(now);
    } else {
      // If no specific time, consider overdue after planned date
      final planDate =
          DateTime(plannedDate.year, plannedDate.month, plannedDate.day);
      final today = DateTime(now.year, now.month, now.day);
      return planDate.isBefore(today);
    }
  }

  /// Check if this ruck is scheduled for the future
  bool get isUpcoming {
    return status == PlannedRuckStatus.planned && !isOverdue;
  }

  /// Check if this ruck can be started
  bool get canStart {
    return status == PlannedRuckStatus.planned;
  }

  /// Check if this ruck can be cancelled
  bool get canCancel {
    return status == PlannedRuckStatus.planned;
  }

  /// Check if this ruck has route information loaded
  bool get hasRouteInfo => route != null;

  /// Get distance from route (if available)
  String get formattedDistance {
    if (route?.distanceKm != null) {
      return route!.formattedDistance;
    }
    return 'Unknown distance';
  }

  /// Get difficulty from route (if available)
  String get formattedDifficulty {
    if (route?.trailDifficulty != null) {
      return route!.difficultyLevel.displayName;
    }
    return 'Unknown difficulty';
  }

  /// Get time until planned start
  String get timeUntilStart {
    if (plannedStartTime == null) return '';

    final now = DateTime.now();
    final difference = plannedStartTime!.difference(now);

    if (difference.isNegative) {
      return 'Overdue';
    }

    if (difference.inDays > 0) {
      return '${difference.inDays}d ${difference.inHours % 24}h';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ${difference.inMinutes % 60}m';
    } else {
      return '${difference.inMinutes}m';
    }
  }

  /// Get day name from weekday number
  String _getDayName(int weekday) {
    switch (weekday) {
      case 1:
        return 'Monday';
      case 2:
        return 'Tuesday';
      case 3:
        return 'Wednesday';
      case 4:
        return 'Thursday';
      case 5:
        return 'Friday';
      case 6:
        return 'Saturday';
      case 7:
        return 'Sunday';
      default:
        return 'Unknown';
    }
  }
}

/// Planned ruck status
enum PlannedRuckStatus {
  planned,
  inProgress,
  completed,
  cancelled;

  String get value {
    switch (this) {
      case PlannedRuckStatus.planned:
        return 'planned';
      case PlannedRuckStatus.inProgress:
        return 'in_progress';
      case PlannedRuckStatus.completed:
        return 'completed';
      case PlannedRuckStatus.cancelled:
        return 'cancelled';
    }
  }

  String get displayName {
    switch (this) {
      case PlannedRuckStatus.planned:
        return 'Planned';
      case PlannedRuckStatus.inProgress:
        return 'In Progress';
      case PlannedRuckStatus.completed:
        return 'Completed';
      case PlannedRuckStatus.cancelled:
        return 'Cancelled';
    }
  }

  static PlannedRuckStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'planned':
        return PlannedRuckStatus.planned;
      case 'in_progress':
        return PlannedRuckStatus.inProgress;
      case 'completed':
        return PlannedRuckStatus.completed;
      case 'cancelled':
        return PlannedRuckStatus.cancelled;
      default:
        return PlannedRuckStatus.planned;
    }
  }
}

/// Intensity levels for workout classification
enum IntensityLevel {
  low,
  moderate,
  high,
  extreme;

  String get displayName {
    switch (this) {
      case IntensityLevel.low:
        return 'Low';
      case IntensityLevel.moderate:
        return 'Moderate';
      case IntensityLevel.high:
        return 'High';
      case IntensityLevel.extreme:
        return 'Extreme';
    }
  }

  String get description {
    switch (this) {
      case IntensityLevel.low:
        return 'Light workout, easy pace';
      case IntensityLevel.moderate:
        return 'Moderate effort, good workout';
      case IntensityLevel.high:
        return 'Challenging workout, high effort';
      case IntensityLevel.extreme:
        return 'Very challenging, maximum effort';
    }
  }

  String get colorCode {
    switch (this) {
      case IntensityLevel.low:
        return '#4CAF50'; // Green
      case IntensityLevel.moderate:
        return '#FF9800'; // Orange
      case IntensityLevel.high:
        return '#F44336'; // Red
      case IntensityLevel.extreme:
        return '#9C27B0'; // Purple
    }
  }
}
