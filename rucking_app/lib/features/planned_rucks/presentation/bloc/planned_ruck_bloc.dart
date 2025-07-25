import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/models/planned_ruck.dart';
import 'package:rucking_app/core/repositories/planned_rucks_repository.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'planned_ruck_event.dart';
import 'planned_ruck_state.dart';

/// BLoC for managing planned ruck state and operations
class PlannedRuckBloc extends Bloc<PlannedRuckEvent, PlannedRuckState> {
  final PlannedRucksRepository _plannedRucksRepository;
  
  // Internal state tracking
  final List<PlannedRuck> _allPlannedRucks = [];
  final List<PlannedRuck> _todaysRucks = [];
  final List<PlannedRuck> _upcomingRucks = [];
  final List<PlannedRuck> _overdueRucks = [];
  final List<PlannedRuck> _completedRucks = [];
  
  PlannedRuck? _selectedRuck;
  PlannedRuckStatus? _statusFilter;
  String? _searchQuery;
  bool _hasReachedMax = false;
  int _currentOffset = 0;
  static const int _pageSize = 20;

  PlannedRuckBloc({
    required PlannedRucksRepository plannedRucksRepository,
  })  : _plannedRucksRepository = plannedRucksRepository,
        super(const PlannedRuckInitial()) {
    
    // Register event handlers
    on<LoadPlannedRucks>(_onLoadPlannedRucks);
    on<LoadTodaysPlannedRucks>(_onLoadTodaysPlannedRucks);
    on<LoadUpcomingPlannedRucks>(_onLoadUpcomingPlannedRucks);
    on<LoadOverduePlannedRucks>(_onLoadOverduePlannedRucks);
    on<LoadCompletedPlannedRucks>(_onLoadCompletedPlannedRucks);
    on<LoadPlannedRuckById>(_onLoadPlannedRuckById);
    on<CreatePlannedRuck>(_onCreatePlannedRuck);
    on<UpdatePlannedRuck>(_onUpdatePlannedRuck);
    on<DeletePlannedRuck>(_onDeletePlannedRuck);
    on<StartPlannedRuck>(_onStartPlannedRuck);
    on<CompletePlannedRuck>(_onCompletePlannedRuck);
    on<CancelPlannedRuck>(_onCancelPlannedRuck);
    on<RefreshAllPlannedRucks>(_onRefreshAllPlannedRucks);
    on<ClearPlannedRucks>(_onClearPlannedRucks);
    on<FilterPlannedRucksByStatus>(_onFilterPlannedRucksByStatus);
    on<SearchPlannedRucks>(_onSearchPlannedRucks);
    on<LoadMorePlannedRucks>(_onLoadMorePlannedRucks);
    on<SelectPlannedRuck>(_onSelectPlannedRuck);
    on<UpdatePlannedRuckLocally>(_onUpdatePlannedRuckLocally);
    on<RemovePlannedRuckLocally>(_onRemovePlannedRuckLocally);
    on<AddPlannedRuckLocally>(_onAddPlannedRuckLocally);
    on<SyncPlannedRucks>(_onSyncPlannedRucks);
  }

  /// Load all planned rucks with optional filtering
  Future<void> _onLoadPlannedRucks(
    LoadPlannedRucks event,
    Emitter<PlannedRuckState> emit,
  ) async {
    try {
      if (event.forceRefresh || state is PlannedRuckInitial) {
        emit(const PlannedRuckLoading());
        _currentOffset = 0;
        _hasReachedMax = false;
      } else if (state is PlannedRuckLoaded) {
        emit((state as PlannedRuckLoaded).copyWith(isRefreshing: true));
      }

      final plannedRucks = await _plannedRucksRepository.getPlannedRucks(
        limit: event.limit,
        offset: event.offset,
        status: event.status,
        fromDate: event.fromDate,
        toDate: event.toDate,
        includeRoute: event.includeRoute,
      );

      if (event.forceRefresh || event.offset == 0) {
        _allPlannedRucks.clear();
      }
      
      _allPlannedRucks.addAll(plannedRucks);
      
      // Check if we've reached the end
      if (plannedRucks.length < event.limit) {
        _hasReachedMax = true;
      }

      _currentOffset = event.offset + plannedRucks.length;

      emit(PlannedRuckLoaded(
        plannedRucks: List.from(_allPlannedRucks),
        todaysRucks: List.from(_todaysRucks),
        upcomingRucks: List.from(_upcomingRucks),
        overdueRucks: List.from(_overdueRucks),
        completedRucks: List.from(_completedRucks),
        selectedRuck: _selectedRuck,
        statusFilter: _statusFilter,
        searchQuery: _searchQuery,
        hasReachedMax: _hasReachedMax,
        lastUpdated: DateTime.now(),
      ));

      AppLogger.info('Loaded ${plannedRucks.length} planned rucks');
    } catch (e) {
      AppLogger.error('Error loading planned rucks: $e');
      emit(_handleError(e, 'Failed to load planned rucks'));
    }
  }

  /// Load today's planned rucks
  Future<void> _onLoadTodaysPlannedRucks(
    LoadTodaysPlannedRucks event,
    Emitter<PlannedRuckState> emit,
  ) async {
    try {
      final todaysRucks = await _plannedRucksRepository.getTodaysPlannedRucks();
      _todaysRucks.clear();
      _todaysRucks.addAll(todaysRucks);

      if (state is PlannedRuckLoaded) {
        emit((state as PlannedRuckLoaded).copyWith(
          todaysRucks: List.from(_todaysRucks),
          lastUpdated: DateTime.now(),
        ));
      }

      AppLogger.info('Loaded ${todaysRucks.length} today\'s planned rucks');
    } catch (e) {
      AppLogger.error('Error loading today\'s planned rucks: $e');
      // Don't emit error for supplementary data loads
    }
  }

  /// Load upcoming planned rucks
  Future<void> _onLoadUpcomingPlannedRucks(
    LoadUpcomingPlannedRucks event,
    Emitter<PlannedRuckState> emit,
  ) async {
    try {
      final upcomingRucks = await _plannedRucksRepository.getUpcomingPlannedRucks(
        days: event.days,
      );
      _upcomingRucks.clear();
      _upcomingRucks.addAll(upcomingRucks);

      if (state is PlannedRuckLoaded) {
        emit((state as PlannedRuckLoaded).copyWith(
          upcomingRucks: List.from(_upcomingRucks),
          lastUpdated: DateTime.now(),
        ));
      }

      AppLogger.info('Loaded ${upcomingRucks.length} upcoming planned rucks');
    } catch (e) {
      AppLogger.error('Error loading upcoming planned rucks: $e');
    }
  }

  /// Load overdue planned rucks
  Future<void> _onLoadOverduePlannedRucks(
    LoadOverduePlannedRucks event,
    Emitter<PlannedRuckState> emit,
  ) async {
    try {
      final overdueRucks = await _plannedRucksRepository.getOverduePlannedRucks();
      _overdueRucks.clear();
      _overdueRucks.addAll(overdueRucks);

      if (state is PlannedRuckLoaded) {
        emit((state as PlannedRuckLoaded).copyWith(
          overdueRucks: List.from(_overdueRucks),
          lastUpdated: DateTime.now(),
        ));
      }

      AppLogger.info('Loaded ${overdueRucks.length} overdue planned rucks');
    } catch (e) {
      AppLogger.error('Error loading overdue planned rucks: $e');
    }
  }

  /// Load completed planned rucks
  Future<void> _onLoadCompletedPlannedRucks(
    LoadCompletedPlannedRucks event,
    Emitter<PlannedRuckState> emit,
  ) async {
    try {
      final completedRucks = await _plannedRucksRepository.getCompletedPlannedRucks(
        limit: event.limit,
        offset: event.offset,
      );
      
      if (event.offset == 0) {
        _completedRucks.clear();
      }
      _completedRucks.addAll(completedRucks);

      if (state is PlannedRuckLoaded) {
        emit((state as PlannedRuckLoaded).copyWith(
          completedRucks: List.from(_completedRucks),
          lastUpdated: DateTime.now(),
        ));
      }

      AppLogger.info('Loaded ${completedRucks.length} completed planned rucks');
    } catch (e) {
      AppLogger.error('Error loading completed planned rucks: $e');
    }
  }

  /// Load a specific planned ruck by ID
  Future<void> _onLoadPlannedRuckById(
    LoadPlannedRuckById event,
    Emitter<PlannedRuckState> emit,
  ) async {
    try {
      final plannedRuck = await _plannedRucksRepository.getPlannedRuck(
        event.plannedRuckId,
        includeRoute: event.includeRoute,
      );

      if (plannedRuck != null) {
        _selectedRuck = plannedRuck;
        
        // Update in the main list if it exists
        final index = _allPlannedRucks.indexWhere((r) => r.id == plannedRuck.id);
        if (index != -1) {
          _allPlannedRucks[index] = plannedRuck;
        }

        if (state is PlannedRuckLoaded) {
          emit((state as PlannedRuckLoaded).copyWith(
            plannedRucks: List.from(_allPlannedRucks),
            selectedRuck: plannedRuck,
            lastUpdated: DateTime.now(),
          ));
        }

        AppLogger.info('Loaded planned ruck: ${plannedRuck.id}');
      } else {
        AppLogger.warning('Planned ruck not found: ${event.plannedRuckId}');
        emit(PlannedRuckError.notFound(message: 'Planned ruck not found'));
      }
    } catch (e) {
      AppLogger.error('Error loading planned ruck ${event.plannedRuckId}: $e');
      emit(_handleError(e, 'Failed to load planned ruck'));
    }
  }

  /// Create a new planned ruck
  Future<void> _onCreatePlannedRuck(
    CreatePlannedRuck event,
    Emitter<PlannedRuckState> emit,
  ) async {
    try {
      emit(PlannedRuckActionInProgress(
        plannedRuckId: 'new',
        action: PlannedRuckAction.create,
        plannedRucks: List.from(_allPlannedRucks),
      ));

      final createdRuck = await _plannedRucksRepository.createPlannedRuck(event.plannedRuck);
      
      _allPlannedRucks.insert(0, createdRuck);
      _selectedRuck = createdRuck;

      emit(PlannedRuckActionSuccess(
        plannedRuckId: createdRuck.id!,
        action: PlannedRuckAction.create,
        updatedRuck: createdRuck,
        message: 'Planned ruck created successfully',
      ));

      // Return to loaded state
      emit(PlannedRuckLoaded(
        plannedRucks: List.from(_allPlannedRucks),
        todaysRucks: List.from(_todaysRucks),
        upcomingRucks: List.from(_upcomingRucks),
        overdueRucks: List.from(_overdueRucks),
        completedRucks: List.from(_completedRucks),
        selectedRuck: createdRuck,
        statusFilter: _statusFilter,
        searchQuery: _searchQuery,
        hasReachedMax: _hasReachedMax,
        lastUpdated: DateTime.now(),
      ));

      AppLogger.info('Created planned ruck: ${createdRuck.id}');
    } catch (e) {
      AppLogger.error('Error creating planned ruck: $e');
      emit(PlannedRuckActionError(
        plannedRuckId: 'new',
        action: PlannedRuckAction.create,
        message: 'Failed to create planned ruck',
      ));
    }
  }

  /// Update an existing planned ruck
  Future<void> _onUpdatePlannedRuck(
    UpdatePlannedRuck event,
    Emitter<PlannedRuckState> emit,
  ) async {
    try {
      emit(PlannedRuckActionInProgress(
        plannedRuckId: event.plannedRuckId,
        action: PlannedRuckAction.update,
        plannedRucks: List.from(_allPlannedRucks),
      ));

      final updatedRuck = await _plannedRucksRepository.updatePlannedRuck(
        event.plannedRuckId,
        event.updatedPlannedRuck,
      );

      _updateRuckInLists(updatedRuck);

      emit(PlannedRuckActionSuccess(
        plannedRuckId: event.plannedRuckId,
        action: PlannedRuckAction.update,
        updatedRuck: updatedRuck,
        message: 'Planned ruck updated successfully',
      ));

      // Return to loaded state
      _emitLoadedState();

      AppLogger.info('Updated planned ruck: ${event.plannedRuckId}');
    } catch (e) {
      AppLogger.error('Error updating planned ruck ${event.plannedRuckId}: $e');
      emit(PlannedRuckActionError(
        plannedRuckId: event.plannedRuckId,
        action: PlannedRuckAction.update,
        message: 'Failed to update planned ruck',
      ));
    }
  }

  /// Delete a planned ruck
  Future<void> _onDeletePlannedRuck(
    DeletePlannedRuck event,
    Emitter<PlannedRuckState> emit,
  ) async {
    try {
      emit(PlannedRuckActionInProgress(
        plannedRuckId: event.plannedRuckId,
        action: PlannedRuckAction.delete,
        plannedRucks: List.from(_allPlannedRucks),
      ));

      final success = await _plannedRucksRepository.deletePlannedRuck(event.plannedRuckId);

      if (success) {
        _removeRuckFromLists(event.plannedRuckId);

        if (_selectedRuck?.id == event.plannedRuckId) {
          _selectedRuck = null;
        }

        emit(PlannedRuckActionSuccess(
          plannedRuckId: event.plannedRuckId,
          action: PlannedRuckAction.delete,
          message: 'Planned ruck deleted successfully',
        ));

        // Return to loaded state
        _emitLoadedState();

        AppLogger.info('Deleted planned ruck: ${event.plannedRuckId}');
      } else {
        throw Exception('Delete operation failed');
      }
    } catch (e) {
      AppLogger.error('Error deleting planned ruck ${event.plannedRuckId}: $e');
      emit(PlannedRuckActionError(
        plannedRuckId: event.plannedRuckId,
        action: PlannedRuckAction.delete,
        message: 'Failed to delete planned ruck',
      ));
    }
  }

  /// Start a planned ruck
  Future<void> _onStartPlannedRuck(
    StartPlannedRuck event,
    Emitter<PlannedRuckState> emit,
  ) async {
    try {
      emit(PlannedRuckActionInProgress(
        plannedRuckId: event.plannedRuckId,
        action: PlannedRuckAction.start,
        plannedRucks: List.from(_allPlannedRucks),
      ));

      final updatedRuck = await _plannedRucksRepository.startPlannedRuck(event.plannedRuckId);

      if (updatedRuck != null) {
        _updateRuckInLists(updatedRuck);

        emit(PlannedRuckActionSuccess(
          plannedRuckId: event.plannedRuckId,
          action: PlannedRuckAction.start,
          updatedRuck: updatedRuck,
          message: 'Planned ruck started successfully',
        ));

        // Return to loaded state
        _emitLoadedState();

        AppLogger.info('Started planned ruck: ${event.plannedRuckId}');
      } else {
        throw Exception('Start operation failed');
      }
    } catch (e) {
      AppLogger.error('Error starting planned ruck ${event.plannedRuckId}: $e');
      emit(PlannedRuckActionError(
        plannedRuckId: event.plannedRuckId,
        action: PlannedRuckAction.start,
        message: 'Failed to start planned ruck',
      ));
    }
  }

  /// Complete a planned ruck
  Future<void> _onCompletePlannedRuck(
    CompletePlannedRuck event,
    Emitter<PlannedRuckState> emit,
  ) async {
    try {
      emit(PlannedRuckActionInProgress(
        plannedRuckId: event.plannedRuckId,
        action: PlannedRuckAction.complete,
        plannedRucks: List.from(_allPlannedRucks),
      ));

      final updatedRuck = await _plannedRucksRepository.completePlannedRuck(
        event.plannedRuckId,
        event.sessionId,
      );

      if (updatedRuck != null) {
        _updateRuckInLists(updatedRuck);

        emit(PlannedRuckActionSuccess(
          plannedRuckId: event.plannedRuckId,
          action: PlannedRuckAction.complete,
          updatedRuck: updatedRuck,
          message: 'Planned ruck completed successfully',
        ));

        // Return to loaded state
        _emitLoadedState();

        AppLogger.info('Completed planned ruck: ${event.plannedRuckId}');
      } else {
        throw Exception('Complete operation failed');
      }
    } catch (e) {
      AppLogger.error('Error completing planned ruck ${event.plannedRuckId}: $e');
      emit(PlannedRuckActionError(
        plannedRuckId: event.plannedRuckId,
        action: PlannedRuckAction.complete,
        message: 'Failed to complete planned ruck',
      ));
    }
  }

  /// Cancel a planned ruck
  Future<void> _onCancelPlannedRuck(
    CancelPlannedRuck event,
    Emitter<PlannedRuckState> emit,
  ) async {
    try {
      emit(PlannedRuckActionInProgress(
        plannedRuckId: event.plannedRuckId,
        action: PlannedRuckAction.cancel,
        plannedRucks: List.from(_allPlannedRucks),
      ));

      final updatedRuck = await _plannedRucksRepository.cancelPlannedRuck(
        event.plannedRuckId,
        reason: event.reason,
      );

      if (updatedRuck != null) {
        _updateRuckInLists(updatedRuck);

        emit(PlannedRuckActionSuccess(
          plannedRuckId: event.plannedRuckId,
          action: PlannedRuckAction.cancel,
          updatedRuck: updatedRuck,
          message: 'Planned ruck cancelled successfully',
        ));

        // Return to loaded state
        _emitLoadedState();

        AppLogger.info('Cancelled planned ruck: ${event.plannedRuckId}');
      } else {
        throw Exception('Cancel operation failed');
      }
    } catch (e) {
      AppLogger.error('Error cancelling planned ruck ${event.plannedRuckId}: $e');
      emit(PlannedRuckActionError(
        plannedRuckId: event.plannedRuckId,
        action: PlannedRuckAction.cancel,
        message: 'Failed to cancel planned ruck',
      ));
    }
  }

  /// Refresh all planned ruck data
  Future<void> _onRefreshAllPlannedRucks(
    RefreshAllPlannedRucks event,
    Emitter<PlannedRuckState> emit,
  ) async {
    // Trigger refresh of all data
    add(const LoadPlannedRucks(forceRefresh: true));
    add(const LoadTodaysPlannedRucks(forceRefresh: true));
    add(const LoadUpcomingPlannedRucks(forceRefresh: true));
    add(const LoadOverduePlannedRucks(forceRefresh: true));
  }

  /// Clear all planned ruck data
  void _onClearPlannedRucks(
    ClearPlannedRucks event,
    Emitter<PlannedRuckState> emit,
  ) {
    _allPlannedRucks.clear();
    _todaysRucks.clear();
    _upcomingRucks.clear();
    _overdueRucks.clear();
    _completedRucks.clear();
    _selectedRuck = null;
    _statusFilter = null;
    _searchQuery = null;
    _hasReachedMax = false;
    _currentOffset = 0;

    emit(const PlannedRuckInitial());
  }

  /// Filter planned rucks by status
  void _onFilterPlannedRucksByStatus(
    FilterPlannedRucksByStatus event,
    Emitter<PlannedRuckState> emit,
  ) {
    _statusFilter = event.status;
    
    if (state is PlannedRuckLoaded) {
      emit((state as PlannedRuckLoaded).copyWith(
        statusFilter: _statusFilter,
        lastUpdated: DateTime.now(),
      ));
    }
  }

  /// Search planned rucks
  void _onSearchPlannedRucks(
    SearchPlannedRucks event,
    Emitter<PlannedRuckState> emit,
  ) {
    _searchQuery = event.query.trim().isEmpty ? null : event.query.trim();
    
    if (state is PlannedRuckLoaded) {
      emit((state as PlannedRuckLoaded).copyWith(
        searchQuery: _searchQuery,
        lastUpdated: DateTime.now(),
      ));
    }
  }

  /// Load more planned rucks (pagination)
  Future<void> _onLoadMorePlannedRucks(
    LoadMorePlannedRucks event,
    Emitter<PlannedRuckState> emit,
  ) async {
    if (!_hasReachedMax && state is PlannedRuckLoaded) {
      add(LoadPlannedRucks(
        offset: _currentOffset,
        limit: _pageSize,
        status: _statusFilter?.value,
      ));
    }
  }

  /// Select a planned ruck
  void _onSelectPlannedRuck(
    SelectPlannedRuck event,
    Emitter<PlannedRuckState> emit,
  ) {
    _selectedRuck = event.plannedRuck;
    
    if (state is PlannedRuckLoaded) {
      emit((state as PlannedRuckLoaded).copyWith(
        selectedRuck: _selectedRuck,
      ));
    }
  }

  /// Update planned ruck locally (optimistic update)
  void _onUpdatePlannedRuckLocally(
    UpdatePlannedRuckLocally event,
    Emitter<PlannedRuckState> emit,
  ) {
    _updateRuckInLists(event.updatedPlannedRuck);
    _emitLoadedState();
  }

  /// Remove planned ruck locally (optimistic delete)
  void _onRemovePlannedRuckLocally(
    RemovePlannedRuckLocally event,
    Emitter<PlannedRuckState> emit,
  ) {
    _removeRuckFromLists(event.plannedRuckId);
    
    if (_selectedRuck?.id == event.plannedRuckId) {
      _selectedRuck = null;
    }
    
    _emitLoadedState();
  }

  /// Add planned ruck locally (optimistic create)
  void _onAddPlannedRuckLocally(
    AddPlannedRuckLocally event,
    Emitter<PlannedRuckState> emit,
  ) {
    _allPlannedRucks.insert(0, event.plannedRuck);
    _emitLoadedState();
  }

  /// Sync planned rucks with backend
  Future<void> _onSyncPlannedRucks(
    SyncPlannedRucks event,
    Emitter<PlannedRuckState> emit,
  ) async {
    // This would handle syncing any offline changes
    // For now, just refresh
    add(const RefreshAllPlannedRucks());
  }

  // Helper methods

  /// Update a ruck in all relevant lists
  void _updateRuckInLists(PlannedRuck updatedRuck) {
    // Update in main list
    final mainIndex = _allPlannedRucks.indexWhere((r) => r.id == updatedRuck.id);
    if (mainIndex != -1) {
      _allPlannedRucks[mainIndex] = updatedRuck;
    }

    // Update selected ruck if it's the same
    if (_selectedRuck?.id == updatedRuck.id) {
      _selectedRuck = updatedRuck;
    }

    // Update in specialized lists based on status
    _updateInSpecializedLists(updatedRuck);
  }

  /// Update ruck in specialized lists (today's, upcoming, etc.)
  void _updateInSpecializedLists(PlannedRuck ruck) {
    // Remove from all specialized lists first
    _todaysRucks.removeWhere((r) => r.id == ruck.id);
    _upcomingRucks.removeWhere((r) => r.id == ruck.id);
    _overdueRucks.removeWhere((r) => r.id == ruck.id);
    _completedRucks.removeWhere((r) => r.id == ruck.id);

    // Add to appropriate list based on current status and date
    if (ruck.status == PlannedRuckStatus.completed) {
      _completedRucks.insert(0, ruck);
    } else if (ruck.isToday) {
      _todaysRucks.add(ruck);
    } else if (ruck.isUpcoming) {
      _upcomingRucks.add(ruck);
    } else if (ruck.isOverdue) {
      _overdueRucks.add(ruck);
    }
  }

  /// Remove a ruck from all lists
  void _removeRuckFromLists(String ruckId) {
    _allPlannedRucks.removeWhere((r) => r.id == ruckId);
    _todaysRucks.removeWhere((r) => r.id == ruckId);
    _upcomingRucks.removeWhere((r) => r.id == ruckId);
    _overdueRucks.removeWhere((r) => r.id == ruckId);
    _completedRucks.removeWhere((r) => r.id == ruckId);
  }

  /// Emit current loaded state
  void _emitLoadedState() {
    emit(PlannedRuckLoaded(
      plannedRucks: List.from(_allPlannedRucks),
      todaysRucks: List.from(_todaysRucks),
      upcomingRucks: List.from(_upcomingRucks),
      overdueRucks: List.from(_overdueRucks),
      completedRucks: List.from(_completedRucks),
      selectedRuck: _selectedRuck,
      statusFilter: _statusFilter,
      searchQuery: _searchQuery,
      hasReachedMax: _hasReachedMax,
      lastUpdated: DateTime.now(),
    ));
  }

  /// Handle errors and return appropriate error state
  PlannedRuckError _handleError(dynamic error, String defaultMessage) {
    if (error.toString().contains('network') || error.toString().contains('connection')) {
      return PlannedRuckError.network();
    } else if (error.toString().contains('401') || error.toString().contains('unauthorized')) {
      return PlannedRuckError.authentication();
    } else if (error.toString().contains('404') || error.toString().contains('not found')) {
      return PlannedRuckError.notFound();
    } else if (error.toString().contains('400') || error.toString().contains('validation')) {
      return PlannedRuckError.validation(message: error.toString());
    } else {
      return PlannedRuckError(message: defaultMessage, originalError: error);
    }
  }

  @override
  Future<void> close() {
    _plannedRucksRepository.dispose();
    return super.close();
  }
}
