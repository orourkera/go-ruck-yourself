import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
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
    
    // Get location if needed for 'closest' filter and not provided in the event
    double? lat = event.latitude;
    double? lon = event.longitude;
    
    if (event.filter == 'closest' && (lat == null || lon == null)) {
      try {
        // Check for permission
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        
        if (permission == LocationPermission.whileInUse || 
            permission == LocationPermission.always) {
          final position = await Geolocator.getCurrentPosition();
          lat = position.latitude;
          lon = position.longitude;
        }
      } catch (e) {
        // Handle error or proceed without location
        print('Error getting location: $e');
      }
    }
    
    debugPrint('[BLOC] Fetching ruck buddies with filter: ${event.filter}, location: ($lat, $lon)');
    final result = await getRuckBuddies(
      RuckBuddiesParams(
        limit: event.limit,
        offset: 0,
        filter: event.filter,
        latitude: lat,
        longitude: lon,
      ),
    );
    
    result.fold(
      (failure) {
        debugPrint('[BLOC] Error fetching ruck buddies: ${failure.message}');
        emit(RuckBuddiesError(message: failure.message));
      },
      (ruckBuddies) {
        debugPrint('[BLOC] Loaded ${ruckBuddies.length} ruck buddies');
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
      },
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
    // Get current filter and location
    String currentFilter = 'closest';
    double? currentLat;
    double? currentLon;
    
    if (state is RuckBuddiesLoaded) {
      final loadedState = state as RuckBuddiesLoaded;
      currentFilter = loadedState.filter;
      currentLat = loadedState.latitude;
      currentLon = loadedState.longitude;
    }
    
    // Reset pagination with current filter and location
    add(FetchRuckBuddiesEvent(
      filter: currentFilter,
      latitude: currentLat,
      longitude: currentLon,
    ));
  }
}
