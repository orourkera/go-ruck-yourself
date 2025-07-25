import 'package:equatable/equatable.dart';
import 'package:rucking_app/core/models/planned_ruck.dart';

/// Base class for all planned ruck states
abstract class PlannedRuckState extends Equatable {
  const PlannedRuckState();

  @override
  List<Object?> get props => [];
}

/// Initial state when BLoC is first created
class PlannedRuckInitial extends PlannedRuckState {
  const PlannedRuckInitial();
}

/// State when loading planned rucks
class PlannedRuckLoading extends PlannedRuckState {
  final bool isRefreshing;
  final bool isLoadingMore;

  const PlannedRuckLoading({
    this.isRefreshing = false,
    this.isLoadingMore = false,
  });

  @override
  List<Object?> get props => [isRefreshing, isLoadingMore];
}

/// State when planned rucks are successfully loaded
class PlannedRuckLoaded extends PlannedRuckState {
  final List<PlannedRuck> plannedRucks;
  final List<PlannedRuck> todaysRucks;
  final List<PlannedRuck> upcomingRucks;
  final List<PlannedRuck> overdueRucks;
  final List<PlannedRuck> completedRucks;
  final PlannedRuck? selectedRuck;
  final PlannedRuckStatus? statusFilter;
  final String? searchQuery;
  final bool hasReachedMax;
  final bool isRefreshing;
  final DateTime lastUpdated;

  const PlannedRuckLoaded({
    required this.plannedRucks,
    this.todaysRucks = const [],
    this.upcomingRucks = const [],
    this.overdueRucks = const [],
    this.completedRucks = const [],
    this.selectedRuck,
    this.statusFilter,
    this.searchQuery,
    this.hasReachedMax = false,
    this.isRefreshing = false,
    required this.lastUpdated,
  });

  @override
  List<Object?> get props => [
        plannedRucks,
        todaysRucks,
        upcomingRucks,
        overdueRucks,
        completedRucks,
        selectedRuck,
        statusFilter,
        searchQuery,
        hasReachedMax,
        isRefreshing,
        lastUpdated,
      ];

  /// Create a copy of this state with updated fields
  PlannedRuckLoaded copyWith({
    List<PlannedRuck>? plannedRucks,
    List<PlannedRuck>? todaysRucks,
    List<PlannedRuck>? upcomingRucks,
    List<PlannedRuck>? overdueRucks,
    List<PlannedRuck>? completedRucks,
    PlannedRuck? selectedRuck,
    PlannedRuckStatus? statusFilter,
    String? searchQuery,
    bool? hasReachedMax,
    bool? isRefreshing,
    DateTime? lastUpdated,
    bool clearSelectedRuck = false,
    bool clearStatusFilter = false,
    bool clearSearchQuery = false,
  }) {
    return PlannedRuckLoaded(
      plannedRucks: plannedRucks ?? this.plannedRucks,
      todaysRucks: todaysRucks ?? this.todaysRucks,
      upcomingRucks: upcomingRucks ?? this.upcomingRucks,
      overdueRucks: overdueRucks ?? this.overdueRucks,
      completedRucks: completedRucks ?? this.completedRucks,
      selectedRuck: clearSelectedRuck ? null : (selectedRuck ?? this.selectedRuck),
      statusFilter: clearStatusFilter ? null : (statusFilter ?? this.statusFilter),
      searchQuery: clearSearchQuery ? null : (searchQuery ?? this.searchQuery),
      hasReachedMax: hasReachedMax ?? this.hasReachedMax,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  /// Get filtered planned rucks based on current filters
  List<PlannedRuck> get filteredPlannedRucks {
    var filtered = plannedRucks;

    // Apply status filter
    if (statusFilter != null) {
      filtered = filtered.where((ruck) => ruck.status == statusFilter).toList();
    }

    // Apply search query
    if (searchQuery?.isNotEmpty == true) {
      final query = searchQuery!.toLowerCase();
      filtered = filtered.where((ruck) {
        final nameMatch = ruck.route?.name.toLowerCase().contains(query) ?? false;
        final notesMatch = ruck.notes?.toLowerCase().contains(query) ?? false;
        return nameMatch || notesMatch;
      }).toList();
    }

    return filtered;
  }

  /// Get planned rucks grouped by status
  Map<PlannedRuckStatus, List<PlannedRuck>> get plannedRucksByStatus {
    final grouped = <PlannedRuckStatus, List<PlannedRuck>>{};
    
    for (final status in PlannedRuckStatus.values) {
      grouped[status] = plannedRucks.where((ruck) => ruck.status == status).toList();
    }
    
    return grouped;
  }

  /// Get planned rucks for the current week
  List<PlannedRuck> get thisWeeksRucks {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    
    return plannedRucks.where((ruck) {
      final ruckDate = DateTime(ruck.plannedDate.year, ruck.plannedDate.month, ruck.plannedDate.day);
      return ruckDate.isAfter(startOfWeek.subtract(const Duration(days: 1))) &&
             ruckDate.isBefore(endOfWeek.add(const Duration(days: 1)));
    }).toList();
  }

  /// Get completion rate for completed rucks
  double get completionRate {
    if (plannedRucks.isEmpty) return 0.0;
    
    final completedCount = plannedRucks.where((ruck) => ruck.status == PlannedRuckStatus.completed).length;
    return completedCount / plannedRucks.length;
  }

  /// Check if there are any urgent/overdue rucks
  bool get hasUrgentRucks {
    return overdueRucks.isNotEmpty || 
           plannedRucks.any((ruck) => ruck.isToday && ruck.status == PlannedRuckStatus.planned);
  }
}

/// State when an error occurs
class PlannedRuckError extends PlannedRuckState {
  final String message;
  final String? errorCode;
  final dynamic originalError;
  final bool isNetworkError;
  final bool canRetry;

  const PlannedRuckError({
    required this.message,
    this.errorCode,
    this.originalError,
    this.isNetworkError = false,
    this.canRetry = true,
  });

  @override
  List<Object?> get props => [
        message,
        errorCode,
        originalError,
        isNetworkError,
        canRetry,
      ];

  /// Create a network error
  factory PlannedRuckError.network({String? message}) {
    return PlannedRuckError(
      message: message ?? 'Network connection failed',
      errorCode: 'NETWORK_ERROR',
      isNetworkError: true,
      canRetry: true,
    );
  }

  /// Create a server error
  factory PlannedRuckError.server({String? message, int? statusCode}) {
    return PlannedRuckError(
      message: message ?? 'Server error occurred',
      errorCode: 'SERVER_ERROR_$statusCode',
      canRetry: statusCode != 400, // Don't retry client errors
    );
  }

  /// Create a validation error
  factory PlannedRuckError.validation({required String message}) {
    return PlannedRuckError(
      message: message,
      errorCode: 'VALIDATION_ERROR',
      canRetry: false,
    );
  }

  /// Create an authentication error
  factory PlannedRuckError.authentication({String? message}) {
    return PlannedRuckError(
      message: message ?? 'Authentication required',
      errorCode: 'AUTH_ERROR',
      canRetry: false,
    );
  }

  /// Create a not found error
  factory PlannedRuckError.notFound({String? message}) {
    return PlannedRuckError(
      message: message ?? 'Planned ruck not found',
      errorCode: 'NOT_FOUND',
      canRetry: false,
    );
  }
}

/// State when performing an action on a specific planned ruck
class PlannedRuckActionInProgress extends PlannedRuckState {
  final String plannedRuckId;
  final PlannedRuckAction action;
  final List<PlannedRuck> plannedRucks; // Keep current data during action

  const PlannedRuckActionInProgress({
    required this.plannedRuckId,
    required this.action,
    required this.plannedRucks,
  });

  @override
  List<Object?> get props => [plannedRuckId, action, plannedRucks];
}

/// State when an action on a planned ruck is successful
class PlannedRuckActionSuccess extends PlannedRuckState {
  final String plannedRuckId;
  final PlannedRuckAction action;
  final PlannedRuck? updatedRuck;
  final String? message;

  const PlannedRuckActionSuccess({
    required this.plannedRuckId,
    required this.action,
    this.updatedRuck,
    this.message,
  });

  @override
  List<Object?> get props => [plannedRuckId, action, updatedRuck, message];
}

/// State when an action on a planned ruck fails
class PlannedRuckActionError extends PlannedRuckState {
  final String plannedRuckId;
  final PlannedRuckAction action;
  final String message;
  final bool canRetry;

  const PlannedRuckActionError({
    required this.plannedRuckId,
    required this.action,
    required this.message,
    this.canRetry = true,
  });

  @override
  List<Object?> get props => [plannedRuckId, action, message, canRetry];
}

/// State when the app is offline
class PlannedRuckOffline extends PlannedRuckState {
  final List<PlannedRuck> cachedPlannedRucks;
  final List<PlannedRuckPendingAction> pendingActions;

  const PlannedRuckOffline({
    required this.cachedPlannedRucks,
    required this.pendingActions,
  });

  @override
  List<Object?> get props => [cachedPlannedRucks, pendingActions];
}

/// Enum for different actions that can be performed on planned rucks
enum PlannedRuckAction {
  create,
  update,
  delete,
  start,
  complete,
  cancel,
  toggleFavorite,
}

/// Helper class for pending actions when offline
class PlannedRuckPendingAction extends Equatable {
  final String id;
  final PlannedRuckAction action;
  final String plannedRuckId;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  const PlannedRuckPendingAction({
    required this.id,
    required this.action,
    required this.plannedRuckId,
    this.data,
    required this.timestamp,
  });

  @override
  List<Object?> get props => [id, action, plannedRuckId, data, timestamp];

  /// Create a pending action
  factory PlannedRuckPendingAction.create({
    required PlannedRuckAction action,
    required String plannedRuckId,
    Map<String, dynamic>? data,
  }) {
    return PlannedRuckPendingAction(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      action: action,
      plannedRuckId: plannedRuckId,
      data: data,
      timestamp: DateTime.now(),
    );
  }
}

/// Extension to get display name for actions
extension PlannedRuckActionExtension on PlannedRuckAction {
  String get displayName {
    switch (this) {
      case PlannedRuckAction.create:
        return 'Creating';
      case PlannedRuckAction.update:
        return 'Updating';
      case PlannedRuckAction.delete:
        return 'Deleting';
      case PlannedRuckAction.start:
        return 'Starting';
      case PlannedRuckAction.complete:
        return 'Completing';
      case PlannedRuckAction.cancel:
        return 'Cancelling';
      case PlannedRuckAction.toggleFavorite:
        return 'Updating favorite';
    }
  }

  String get pastTense {
    switch (this) {
      case PlannedRuckAction.create:
        return 'created';
      case PlannedRuckAction.update:
        return 'updated';
      case PlannedRuckAction.delete:
        return 'deleted';
      case PlannedRuckAction.start:
        return 'started';
      case PlannedRuckAction.complete:
        return 'completed';
      case PlannedRuckAction.cancel:
        return 'cancelled';
      case PlannedRuckAction.toggleFavorite:
        return 'updated';
    }
  }
}
