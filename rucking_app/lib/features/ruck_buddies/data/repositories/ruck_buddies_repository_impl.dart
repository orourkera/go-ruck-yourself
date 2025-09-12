import 'package:dartz/dartz.dart';
import 'package:rucking_app/core/error/exceptions.dart';
import 'package:rucking_app/core/error/failures.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/services/app_error_handler.dart';
import 'package:rucking_app/features/ruck_buddies/data/datasources/ruck_buddies_remote_datasource.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/ruck_buddy.dart';
import 'package:rucking_app/features/ruck_buddies/domain/repositories/ruck_buddies_repository.dart';

class RuckBuddiesRepositoryImpl implements RuckBuddiesRepository {
  final RuckBuddiesRemoteDataSource remoteDataSource;

  RuckBuddiesRepositoryImpl({
    required this.remoteDataSource,
  });

  // Cache for ruck buddies data
  static Map<String, List<RuckBuddy>>? _ruckBuddiesCache;
  static DateTime? _ruckBuddiesCacheTime;
  static const Duration _ruckBuddiesCacheValidity =
      Duration(minutes: 3); // 3 minute cache

  // Track cache keys for different filter combinations
  static String _createCacheKey({
    required String filter,
    double? latitude,
    double? longitude,
    required int limit,
    required int offset,
  }) {
    final followingStr = filter == 'following' ? 'following' : 'all';
    return '${filter}_${latitude?.toStringAsFixed(3) ?? 'null'}_${longitude?.toStringAsFixed(3) ?? 'null'}_${limit}_${offset}_$followingStr';
  }

  @override
  Future<Either<Failure, List<RuckBuddy>>> getRuckBuddies({
    required int limit,
    required int offset,
    required String filter,
    double? latitude,
    double? longitude,
  }) async {
    try {
      // Create cache key for this specific request
      final cacheKey = _createCacheKey(
        filter: filter,
        latitude: latitude,
        longitude: longitude,
        limit: limit,
        offset: offset,
      );

      // Check if we have cached data that's still valid (only for first page)
      final now = DateTime.now();
      if (offset == 0 && // Only cache first page for simplicity
          _ruckBuddiesCache != null &&
          _ruckBuddiesCacheTime != null &&
          now.difference(_ruckBuddiesCacheTime!) < _ruckBuddiesCacheValidity &&
          _ruckBuddiesCache!.containsKey(cacheKey)) {
        AppLogger.debug(
            '[RUCK_BUDDIES] Using cached data for filter: $filter (${_ruckBuddiesCache![cacheKey]!.length} items)');
        return Right(_ruckBuddiesCache![cacheKey]!);
      }

      AppLogger.info(
          '[RUCK_BUDDIES] Fetching from API - filter: $filter, offset: $offset, limit: $limit');
      final ruckBuddies = await remoteDataSource.getRuckBuddies(
        limit: limit,
        offset: offset,
        filter: filter,
        latitude: latitude,
        longitude: longitude,
      );

      // Cache the results (only for first page to keep it simple)
      if (offset == 0) {
        _ruckBuddiesCache ??= <String, List<RuckBuddy>>{};
        _ruckBuddiesCache![cacheKey] = ruckBuddies;
        _ruckBuddiesCacheTime = now;
        AppLogger.debug(
            '[RUCK_BUDDIES] Cached ${ruckBuddies.length} items for filter: $filter');
      }

      return Right(ruckBuddies);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      // Enhanced error handling with Sentry
      await AppErrorHandler.handleError(
        'ruck_buddies_fetch',
        e,
        context: {
          'filter': filter,
          'limit': limit,
          'offset': offset,
          'has_location': latitude != null && longitude != null,
        },
        sendToBackend: true,
      );
      return Left(
          ServerFailure(message: 'Unexpected error occurred: ${e.toString()}'));
    }
  }

  /// Clear the ruck buddies cache (useful when new data is available)
  static void clearRuckBuddiesCache() {
    _ruckBuddiesCache?.clear();
    _ruckBuddiesCacheTime = null;
    AppLogger.debug('[RUCK_BUDDIES] Cache cleared');
  }

  /// Check if we have valid cached data for the given parameters
  static List<RuckBuddy>? getCachedRuckBuddies({
    required String filter,
    double? latitude,
    double? longitude,
    required int limit,
    required int offset,
  }) {
    // Only check cache for first page
    if (offset != 0) return null;

    final cacheKey = _createCacheKey(
      filter: filter,
      latitude: latitude,
      longitude: longitude,
      limit: limit,
      offset: offset,
    );

    final now = DateTime.now();
    if (_ruckBuddiesCache != null &&
        _ruckBuddiesCacheTime != null &&
        now.difference(_ruckBuddiesCacheTime!) < _ruckBuddiesCacheValidity &&
        _ruckBuddiesCache!.containsKey(cacheKey)) {
      AppLogger.debug(
          '[RUCK_BUDDIES] Found cached data for filter: $filter (${_ruckBuddiesCache![cacheKey]!.length} items)');
      return _ruckBuddiesCache![cacheKey]!;
    }

    return null;
  }
}
