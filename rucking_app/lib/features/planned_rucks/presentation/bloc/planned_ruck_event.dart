import 'package:equatable/equatable.dart';
import 'package:rucking_app/core/models/planned_ruck.dart';

/// Base class for all planned ruck events
abstract class PlannedRuckEvent extends Equatable {
  const PlannedRuckEvent();

  @override
  List<Object?> get props => [];
}

/// Load all planned rucks for the current user
class LoadPlannedRucks extends PlannedRuckEvent {
  final int limit;
  final int offset;
  final String? status;
  final DateTime? fromDate;
  final DateTime? toDate;
  final bool includeRoute;
  final bool forceRefresh;

  const LoadPlannedRucks({
    this.limit = 20,
    this.offset = 0,
    this.status,
    this.fromDate,
    this.toDate,
    this.includeRoute = true,
    this.forceRefresh = false,
  });

  @override
  List<Object?> get props => [
        limit,
        offset,
        status,
        fromDate,
        toDate,
        includeRoute,
        forceRefresh,
      ];
}

/// Load today's planned rucks
class LoadTodaysPlannedRucks extends PlannedRuckEvent {
  final bool forceRefresh;

  const LoadTodaysPlannedRucks({
    this.forceRefresh = false,
  });

  @override
  List<Object?> get props => [forceRefresh];
}

/// Load upcoming planned rucks (next 7 days)
class LoadUpcomingPlannedRucks extends PlannedRuckEvent {
  final int days;
  final bool forceRefresh;

  const LoadUpcomingPlannedRucks({
    this.days = 7,
    this.forceRefresh = false,
  });

  @override
  List<Object?> get props => [days, forceRefresh];
}

/// Load overdue planned rucks
class LoadOverduePlannedRucks extends PlannedRuckEvent {
  final bool forceRefresh;

  const LoadOverduePlannedRucks({
    this.forceRefresh = false,
  });

  @override
  List<Object?> get props => [forceRefresh];
}

/// Load completed planned rucks
class LoadCompletedPlannedRucks extends PlannedRuckEvent {
  final int limit;
  final int offset;
  final bool forceRefresh;

  const LoadCompletedPlannedRucks({
    this.limit = 20,
    this.offset = 0,
    this.forceRefresh = false,
  });

  @override
  List<Object?> get props => [limit, offset, forceRefresh];
}

/// Load a specific planned ruck by ID
class LoadPlannedRuckById extends PlannedRuckEvent {
  final String plannedRuckId;
  final bool includeRoute;

  const LoadPlannedRuckById({
    required this.plannedRuckId,
    this.includeRoute = true,
  });

  @override
  List<Object?> get props => [plannedRuckId, includeRoute];
}

/// Create a new planned ruck
class CreatePlannedRuck extends PlannedRuckEvent {
  final PlannedRuck plannedRuck;

  const CreatePlannedRuck({
    required this.plannedRuck,
  });

  @override
  List<Object?> get props => [plannedRuck];
}

/// Update an existing planned ruck
class UpdatePlannedRuck extends PlannedRuckEvent {
  final String plannedRuckId;
  final PlannedRuck updatedPlannedRuck;

  const UpdatePlannedRuck({
    required this.plannedRuckId,
    required this.updatedPlannedRuck,
  });

  @override
  List<Object?> get props => [plannedRuckId, updatedPlannedRuck];
}

/// Delete a planned ruck
class DeletePlannedRuck extends PlannedRuckEvent {
  final String plannedRuckId;

  const DeletePlannedRuck({
    required this.plannedRuckId,
  });

  @override
  List<Object?> get props => [plannedRuckId];
}

/// Start a planned ruck (change status to in_progress)
class StartPlannedRuck extends PlannedRuckEvent {
  final String plannedRuckId;

  const StartPlannedRuck({
    required this.plannedRuckId,
  });

  @override
  List<Object?> get props => [plannedRuckId];
}

/// Complete a planned ruck (change status to completed)
class CompletePlannedRuck extends PlannedRuckEvent {
  final String plannedRuckId;
  final String sessionId;

  const CompletePlannedRuck({
    required this.plannedRuckId,
    required this.sessionId,
  });

  @override
  List<Object?> get props => [plannedRuckId, sessionId];
}

/// Cancel a planned ruck
class CancelPlannedRuck extends PlannedRuckEvent {
  final String plannedRuckId;
  final String? reason;

  const CancelPlannedRuck({
    required this.plannedRuckId,
    this.reason,
  });

  @override
  List<Object?> get props => [plannedRuckId, reason];
}

/// Refresh all planned ruck data
class RefreshAllPlannedRucks extends PlannedRuckEvent {
  const RefreshAllPlannedRucks();
}

/// Clear all planned ruck data and error states
class ClearPlannedRucks extends PlannedRuckEvent {
  const ClearPlannedRucks();
}

/// Filter planned rucks by status
class FilterPlannedRucksByStatus extends PlannedRuckEvent {
  final PlannedRuckStatus? status;

  const FilterPlannedRucksByStatus({
    this.status,
  });

  @override
  List<Object?> get props => [status];
}

/// Search planned rucks by route name or notes
class SearchPlannedRucks extends PlannedRuckEvent {
  final String query;

  const SearchPlannedRucks({
    required this.query,
  });

  @override
  List<Object?> get props => [query];
}

/// Load more planned rucks (pagination)
class LoadMorePlannedRucks extends PlannedRuckEvent {
  const LoadMorePlannedRucks();
}

/// Select a planned ruck for detailed view
class SelectPlannedRuck extends PlannedRuckEvent {
  final PlannedRuck? plannedRuck;

  const SelectPlannedRuck({
    this.plannedRuck,
  });

  @override
  List<Object?> get props => [plannedRuck];
}

/// Update planned ruck locally (for optimistic updates)
class UpdatePlannedRuckLocally extends PlannedRuckEvent {
  final PlannedRuck updatedPlannedRuck;

  const UpdatePlannedRuckLocally({
    required this.updatedPlannedRuck,
  });

  @override
  List<Object?> get props => [updatedPlannedRuck];
}

/// Remove planned ruck locally (for optimistic deletes)
class RemovePlannedRuckLocally extends PlannedRuckEvent {
  final String plannedRuckId;

  const RemovePlannedRuckLocally({
    required this.plannedRuckId,
  });

  @override
  List<Object?> get props => [plannedRuckId];
}

/// Add planned ruck locally (for optimistic creates)
class AddPlannedRuckLocally extends PlannedRuckEvent {
  final PlannedRuck plannedRuck;

  const AddPlannedRuckLocally({
    required this.plannedRuck,
  });

  @override
  List<Object?> get props => [plannedRuck];
}

/// Toggle favorite status for a planned ruck
class TogglePlannedRuckFavorite extends PlannedRuckEvent {
  final String plannedRuckId;

  const TogglePlannedRuckFavorite({
    required this.plannedRuckId,
  });

  @override
  List<Object?> get props => [plannedRuckId];
}

/// Sync planned rucks with backend
class SyncPlannedRucks extends PlannedRuckEvent {
  const SyncPlannedRucks();
}

/// Handle network connectivity changes
class PlannedRuckNetworkStatusChanged extends PlannedRuckEvent {
  final bool isConnected;

  const PlannedRuckNetworkStatusChanged({
    required this.isConnected,
  });

  @override
  List<Object?> get props => [isConnected];
}
