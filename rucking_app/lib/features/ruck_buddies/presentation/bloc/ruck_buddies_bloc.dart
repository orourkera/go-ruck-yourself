import 'dart:async';
import 'dart:math';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
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

    // For proximity sorting, we need user's location for client-side calculation
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
          // Handle client-side proximity sorting
          List<RuckBuddy> finalResult = ruckBuddies;
          if (filterToUse == 'closest' && lat != null && lon != null) {
            debugPrint('[BLOC] Performing client-side proximity sorting from ($lat, $lon)');
            finalResult = _sortByProximity(ruckBuddies, lat, lon);
          }
          if (finalResult.isEmpty) {
            debugPrint('[BLOC] No ruck buddies found in API response');
          } else {
            debugPrint(
                '[BLOC] First buddy: ${finalResult.first.id}, user: ${finalResult.first.user.username}, commentCount: ${finalResult.first.commentCount}');
          }

          emit(
            RuckBuddiesLoaded(
              ruckBuddies: finalResult,
              hasReachedMax: finalResult.length < event.limit,
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

  /// Sort ruck buddies by proximity to user's location
  List<RuckBuddy> _sortByProximity(List<RuckBuddy> rucks, double userLat, double userLon) {
    debugPrint('[BLOC] Sorting ${rucks.length} rucks by proximity to ($userLat, $userLon)');

    // Calculate distance for each ruck and sort by proximity
    final sortedRucks = rucks.map((ruck) {
      // Use the first route point to calculate distance (or center if no points)
      double distance = double.infinity;

      if (ruck.locationPoints != null && ruck.locationPoints!.isNotEmpty) {
        // Calculate distance to the route center for better proximity representation
        final routePoints = _parseRoutePoints(ruck.locationPoints!);
        if (routePoints.isNotEmpty) {
          distance = _calculateDistanceToRoute(userLat, userLon, routePoints);
        }
      }

      return {'ruck': ruck, 'distance': distance};
    }).toList();

    // Sort by distance (closest first)
    sortedRucks.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

    debugPrint('[BLOC] Proximity sorting complete - closest distance: ${sortedRucks.first['distance']}, farthest: ${sortedRucks.last['distance']}');

    return sortedRucks.map((item) => item['ruck'] as RuckBuddy).toList();
  }

  /// Calculate Haversine distance between two points in kilometers
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // Earth's radius in kilometers

    final double lat1Rad = lat1 * (pi / 180);
    final double lon1Rad = lon1 * (pi / 180);
    final double lat2Rad = lat2 * (pi / 180);
    final double lon2Rad = lon2 * (pi / 180);

    final double dLat = lat2Rad - lat1Rad;
    final double dLon = lon2Rad - lon1Rad;

    final double a = sin(dLat / 2) * sin(dLat / 2) +
                     cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2);

    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  /// Parse coordinate from various formats
  double? _parseCoordinate(Map map, String key) {
    final value = map[key];
    return _parseNum(value);
  }

  /// Parse number from various formats
  double? _parseNum(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Parse route points from various formats into LatLng objects
  List<LatLng> _parseRoutePoints(List<dynamic> rawRoute) {
    final points = <LatLng>[];

    for (final p in rawRoute) {
      double? lat;
      double? lng;

      if (p is Map) {
        lat = _parseCoordinate(p, 'latitude') ?? _parseCoordinate(p, 'lat');
        lng = _parseCoordinate(p, 'longitude') ?? _parseCoordinate(p, 'lng') ?? _parseCoordinate(p, 'lon');
      } else if (p is List && p.length >= 2) {
        lat = _parseNum(p[0]);
        lng = _parseNum(p[1]);
      }

      if (lat != null && lng != null) {
        points.add(LatLng(lat, lng));
      }
    }

    return points;
  }

  /// Calculate distance to the center of a route
  double _calculateDistanceToRoute(double userLat, double userLon, List<LatLng> routePoints) {
    if (routePoints.isEmpty) return double.infinity;

    // For simplicity, calculate distance to the first point
    // In a more advanced implementation, we could calculate distance to the closest point on the route
    final firstPoint = routePoints.first;
    return _calculateDistance(userLat, userLon, firstPoint.latitude, firstPoint.longitude);
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

    // If user was on 'closest' filter but no location data, get location for proximity sorting
    if (currentFilter == 'closest' && (currentLat == null || currentLon == null)) {
      debugPrint('[BLOC] Refresh: Getting location for closest filter proximity sorting');
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        ).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            debugPrint('⏰ Refresh location request timed out after 15 seconds');
            throw TimeoutException('Location request timed out', const Duration(seconds: 15));
          },
        );
        currentLat = position.latitude;
        currentLon = position.longitude;
      } catch (e) {
        debugPrint('[BLOC] Refresh: Failed to get location: $e. Cannot use closest filter.');
        emit(RuckBuddiesError(message: 'Location access is required for "Closest" filter. Please select a different filter or enable location services.'));
        return;
      }
    }

    add(FetchRuckBuddiesEvent(
      filter: currentFilter,
      latitude: currentLat,
      longitude: currentLon,
    ));
  }
}
