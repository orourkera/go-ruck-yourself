import 'dart:async';
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
      FetchRuckBuddiesEvent event, Emitter<RuckBuddiesState> emit) async {
    double? lat = event.latitude;
    double? lon = event.longitude;
    String filterToUse = event.filter;

    if (filterToUse == 'closest' && (lat == null || lon == null)) {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10), // Prevent infinite wait
        ).timeout(
          const Duration(seconds: 15), // Double timeout protection
          onTimeout: () {
            debugPrint(
                '⏰ Ruck buddies location request timed out after 15 seconds');
            throw TimeoutException(
                'Location request timed out', const Duration(seconds: 15));
          },
        );
        lat = position.latitude;
        lon = position.longitude;
      } catch (e) {
        debugPrint(
            ' [RuckBuddiesBloc] Failed to get current location: $e. Cannot use closest filter.');
        // Location is required for 'closest' filter - show error
        emit(RuckBuddiesError(message: 'Location access is required for "Closest" filter. Please enable location services and try again.'));
        return;
      }
    }

    // Check for cached data first (offset 0 = first page)
    final cachedData = RuckBuddiesRepositoryImpl.getCachedRuckBuddies(
      filter: filterToUse,
      latitude: lat,
      longitude: lon,
      limit: event.limit,
      offset: 0,
    );

    // If we have cached data, emit it immediately
    if (cachedData != null) {
      debugPrint(
          ' [RuckBuddiesBloc] Emitting cached data immediately (${cachedData.length} items)');
      emit(
        RuckBuddiesLoaded(
          ruckBuddies: cachedData,
          hasReachedMax: cachedData.length < event.limit,
          filter: event.filter,
          latitude: lat,
          longitude: lon,
        ),
      );

      // Continue to fetch fresh data in background without showing loading state
      debugPrint(' [RuckBuddiesBloc] Fetching fresh data in background...');
    } else {
      // No cached data, show loading skeleton
      debugPrint(' [RuckBuddiesBloc] No cached data, showing loading skeleton');
      emit(RuckBuddiesLoading());
    }

    final params = RuckBuddiesParams(
      limit: event.limit,
      offset:
          0, // Offset is 0 for a new fetch, managed by FetchMoreRuckBuddiesEvent for pagination
      filter: filterToUse, // Use the potentially updated filter
      latitude: lat,
      longitude: lon,
    );

    try {
      final result = await getRuckBuddies(params);

      result.fold(
        (failure) {
          debugPrint('[BLOC] Error fetching ruck buddies: ${failure.message}');
          // Only emit error if we don't have cached data already showing
          if (cachedData == null) {
            emit(RuckBuddiesError(message: failure.message));
          }
        },
        (ruckBuddies) async {
          if (ruckBuddies.isEmpty) {
            debugPrint('[BLOC] No ruck buddies found in API response');
          } else {
            debugPrint(
                '[BLOC] First buddy: ${ruckBuddies.first.id}, user: ${ruckBuddies.first.user.username}, commentCount: ${ruckBuddies.first.commentCount}');
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
      // Only emit error if we don't have cached data already showing
      if (cachedData == null) {
        emit(RuckBuddiesError(
            message: 'Failed to load ruck buddies: ${e.toString()}'));
      }
    }
  }

  Future<void> _onFetchMoreRuckBuddies(
      FetchMoreRuckBuddiesEvent event, Emitter<RuckBuddiesState> emit) async {
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
        // Deduplicate by creating a Set of existing IDs and filtering out duplicates
        final existingIds =
            currentState.ruckBuddies.map((buddy) => buddy.id).toSet();
        final uniqueNewRuckBuddies = newRuckBuddies
            .where((buddy) => !existingIds.contains(buddy.id))
            .toList();

        debugPrint(
            '[BLOC] Deduplication: ${newRuckBuddies.length} new items, ${uniqueNewRuckBuddies.length} unique items after filtering');

        emit(
          RuckBuddiesLoaded(
            ruckBuddies: [...currentState.ruckBuddies, ...uniqueNewRuckBuddies],
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
            debugPrint(
                '[BLOC] Social data preloading failed for new rucks: $e');
            // Don't emit error state - this is background optimization
          }
        }
      },
    );
  }

  Future<void> _onFilterRuckBuddies(
      FilterRuckBuddiesEvent event, Emitter<RuckBuddiesState> emit) async {
    add(FetchRuckBuddiesEvent(filter: event.filter));
  }

  Future<void> _onRefreshRuckBuddies(
      RefreshRuckBuddiesEvent event, Emitter<RuckBuddiesState> emit) async {
    debugPrint('[BLOC] Refresh triggered - clearing caches');
    RuckBuddiesRepositoryImpl.clearRuckBuddiesCache();

    String currentFilter = 'recent';
    double? currentLat;
    double? currentLon;

    if (state is RuckBuddiesLoaded) {
      final loadedState = state as RuckBuddiesLoaded;
      currentFilter = loadedState.filter;
      currentLat = loadedState.latitude;
      currentLon = loadedState.longitude;
    }

    // If user was on 'closest' filter but no location data, cannot refresh
    if (currentFilter == 'closest' && (currentLat == null || currentLon == null)) {
      debugPrint('[BLOC] Refresh: Cannot refresh closest filter without location data');
      emit(RuckBuddiesError(message: 'Location access is required for "Closest" filter. Please select a different filter or enable location services.'));
      return;
    }

    add(FetchRuckBuddiesEvent(
      filter: currentFilter,
      latitude: currentLat,
      longitude: currentLon,
    ));
  }
}
