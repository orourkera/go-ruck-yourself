import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rucking_app/features/ruck_buddies/data/repositories/ruck_buddies_repository_impl.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/ruck_buddy.dart';
import 'package:rucking_app/features/ruck_buddies/domain/usecases/get_ruck_buddies.dart';
import 'package:rucking_app/features/social/data/repositories/social_repository.dart';

part 'ruck_buddies_event.dart';
part 'ruck_buddies_state.dart';

class RuckBuddiesBloc extends Bloc<RuckBuddiesEvent, RuckBuddiesState> {
  final GetRuckBuddies getRuckBuddies;
  final SocialRepository socialRepository;

  RuckBuddiesBloc({
    required this.getRuckBuddies,
    required this.socialRepository,
  }) : super(RuckBuddiesInitial()) {
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

    double? lat = event.latitude;
    double? lon = event.longitude;
    String filterToUse = event.filter;

    if (filterToUse == 'closest' && (lat == null || lon == null)) {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          // Consider adding a timeLimit if not already handled by Geolocator defaults
        );
        lat = position.latitude;
        lon = position.longitude;
      } catch (e) {
        debugPrint(' [RuckBuddiesBloc] Failed to get current location: $e. Proceeding without it.');
        // Optionally, change filter if location is essential for 'closest'
        // filterToUse = 'most_recent'; // Example fallback, if desired
        // emit(RuckBuddiesError('Could not get location for "closest" rucks. Showing most recent instead.'));
      }
    }
    
    final params = RuckBuddiesParams(
      limit: event.limit,
      offset: 0, // Offset is 0 for a new fetch, managed by FetchMoreRuckBuddiesEvent for pagination
      filter: filterToUse, // Use the potentially updated filter
      latitude: lat,
      longitude: lon,
    );

    try {
      final result = await getRuckBuddies(params);
      
      result.fold(
        (failure) {
          debugPrint('[BLOC] Error fetching ruck buddies: ${failure.message}');
          emit(RuckBuddiesError(message: failure.message));
        },
        (ruckBuddies) async {
          if (ruckBuddies.isEmpty) {
            debugPrint('[BLOC] No ruck buddies found in API response');
          } else {
            debugPrint('[BLOC] First buddy: ${ruckBuddies.first.id}, user: ${ruckBuddies.first.user.username}, commentCount: ${ruckBuddies.first.commentCount}');
          }
          
          emit(
            RuckBuddiesLoaded(
              ruckBuddies: ruckBuddies,
              hasReachedMax: ruckBuddies.length < event.limit,
              filter: event.filter,
              latitude: lat,
              longitude: lon,
            ),
          );
          
          if (ruckBuddies.isNotEmpty) {
            final ruckIds = ruckBuddies
                .map((buddy) => int.tryParse(buddy.id))
                .where((id) => id != null)
                .cast<int>()
                .toList();
            try {
              await socialRepository.preloadSocialDataForRucks(ruckIds);
            } catch (e) {
              debugPrint('[BLOC] Social data preloading failed: $e');
              // Don't emit error state - this is background optimization
            }
          }
        },
      );
    } catch (e) {
      emit(RuckBuddiesError(message: 'Failed to load ruck buddies: ${e.toString()}'));
    }
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
        latitude: currentState.latitude,
        longitude: currentState.longitude,
        isLoadingMore: true,
      ),
    );
    
    final result = await getRuckBuddies(
      RuckBuddiesParams(
        limit: event.limit,
        offset: currentState.ruckBuddies.length,
        filter: currentState.filter,
        latitude: currentState.latitude,
        longitude: currentState.longitude,
      ),
    );
    
    result.fold(
      (failure) => emit(
        RuckBuddiesError(message: failure.message),
      ),
      (newRuckBuddies) async {
        emit(
          RuckBuddiesLoaded(
            ruckBuddies: [...currentState.ruckBuddies, ...newRuckBuddies],
            hasReachedMax: newRuckBuddies.length < event.limit,
            filter: currentState.filter,
            isLoadingMore: false,
          ),
        );
        
        if (newRuckBuddies.isNotEmpty) {
          final newRuckIds = newRuckBuddies
              .map((buddy) => int.tryParse(buddy.id))
              .where((id) => id != null)
              .cast<int>()
              .toList();
          try {
            await socialRepository.preloadSocialDataForRucks(newRuckIds);
          } catch (e) {
            debugPrint('[BLOC] Social data preloading failed for new rucks: $e');
            // Don't emit error state - this is background optimization
          }
        }
      },
    );
  }

  Future<void> _onFilterRuckBuddies(
    FilterRuckBuddiesEvent event, 
    Emitter<RuckBuddiesState> emit
  ) async {
    add(FetchRuckBuddiesEvent(filter: event.filter));
  }

  Future<void> _onRefreshRuckBuddies(
    RefreshRuckBuddiesEvent event, 
    Emitter<RuckBuddiesState> emit
  ) async {
    debugPrint('[BLOC] Refresh triggered - clearing caches');
    RuckBuddiesRepositoryImpl.clearRuckBuddiesCache();
    
    String currentFilter = 'closest';
    double? currentLat;
    double? currentLon;
    
    if (state is RuckBuddiesLoaded) {
      final loadedState = state as RuckBuddiesLoaded;
      currentFilter = loadedState.filter;
      currentLat = loadedState.latitude;
      currentLon = loadedState.longitude;
    }
    
    add(FetchRuckBuddiesEvent(
      filter: currentFilter,
      latitude: currentLat,
      longitude: currentLon,
    ));
  }
}
