import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/ruck_buddy.dart';
import 'package:rucking_app/features/ruck_buddies/domain/usecases/get_ruck_buddies.dart';

part 'ruck_buddies_event.dart';
part 'ruck_buddies_state.dart';

class RuckBuddiesBloc extends Bloc<RuckBuddiesEvent, RuckBuddiesState> {
  final GetRuckBuddies getRuckBuddies;
  
  RuckBuddiesBloc({required this.getRuckBuddies}) : super(RuckBuddiesInitial()) {
    on<FetchRuckBuddiesEvent>(_onFetchRuckBuddies);
    on<FetchMoreRuckBuddiesEvent>(_onFetchMoreRuckBuddies);
    on<FilterRuckBuddiesEvent>(_onFilterRuckBuddies);
    on<RefreshRuckBuddiesEvent>(_onRefreshRuckBuddies);
  }

  Future<void> _onFetchRuckBuddies(
    FetchRuckBuddiesEvent event, 
    Emitter<RuckBuddiesState> emit
  ) async {
    emit(RuckBuddiesLoading());
    
    final result = await getRuckBuddies(
      RuckBuddiesParams(
        limit: event.limit,
        offset: 0,
        filter: event.filter,
      ),
    );
    
    result.fold(
      (failure) => emit(RuckBuddiesError(message: failure.message)),
      (ruckBuddies) => emit(
        RuckBuddiesLoaded(
          ruckBuddies: ruckBuddies,
          hasReachedMax: ruckBuddies.length < event.limit,
          filter: event.filter,
        ),
      ),
    );
  }

  Future<void> _onFetchMoreRuckBuddies(
    FetchMoreRuckBuddiesEvent event, 
    Emitter<RuckBuddiesState> emit
  ) async {
    if (state is! RuckBuddiesLoaded) return;
    
    final currentState = state as RuckBuddiesLoaded;
    if (currentState.hasReachedMax) return;
    
    emit(
      RuckBuddiesLoaded(
        ruckBuddies: currentState.ruckBuddies,
        hasReachedMax: currentState.hasReachedMax,
        filter: currentState.filter,
        isLoadingMore: true,
      ),
    );
    
    final result = await getRuckBuddies(
      RuckBuddiesParams(
        limit: event.limit,
        offset: currentState.ruckBuddies.length,
        filter: currentState.filter,
      ),
    );
    
    result.fold(
      (failure) => emit(
        RuckBuddiesError(message: failure.message),
      ),
      (newRuckBuddies) => emit(
        RuckBuddiesLoaded(
          ruckBuddies: [...currentState.ruckBuddies, ...newRuckBuddies],
          hasReachedMax: newRuckBuddies.length < event.limit,
          filter: currentState.filter,
          isLoadingMore: false,
        ),
      ),
    );
  }

  Future<void> _onFilterRuckBuddies(
    FilterRuckBuddiesEvent event, 
    Emitter<RuckBuddiesState> emit
  ) async {
    // Reset pagination when filter changes
    add(FetchRuckBuddiesEvent(filter: event.filter));
  }

  Future<void> _onRefreshRuckBuddies(
    RefreshRuckBuddiesEvent event, 
    Emitter<RuckBuddiesState> emit
  ) async {
    // Get current filter
    final String currentFilter = state is RuckBuddiesLoaded 
        ? (state as RuckBuddiesLoaded).filter 
        : 'recent';
    
    // Reset pagination with current filter
    add(FetchRuckBuddiesEvent(filter: currentFilter));
  }
}
