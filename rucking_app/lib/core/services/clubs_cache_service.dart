import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for caching clubs data to improve loading performance
class ClubsCacheService {
  static const String _clubsListKey = 'clubs_list_cache';
  static const String _clubDetailsPrefix = 'club_details_';
  static const String _timestampKey = 'clubs_cache_timestamp';
  static const Duration _cacheDuration =
      Duration(minutes: 15); // Cache valid for 15 minutes

  /// Saves clubs list to local storage
  Future<void> cacheClubsList(List<dynamic> clubs, {String? cacheKey}) async {
    final prefs = await SharedPreferences.getInstance();

    // Use custom cache key if provided (for filtered results)
    final key = cacheKey ?? _clubsListKey;

    final String jsonData = jsonEncode(clubs);
    await prefs.setString(key, jsonData);
    await prefs.setInt(_timestampKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Saves individual club details to local storage
  Future<void> cacheClubDetails(
      String clubId, Map<String, dynamic> clubDetails) async {
    final prefs = await SharedPreferences.getInstance();
    final String key = '$_clubDetailsPrefix$clubId';
    final String jsonData = jsonEncode(clubDetails);
    await prefs.setString(key, jsonData);
  }

  /// Retrieves cached clubs list if it exists and is not expired
  Future<List<dynamic>?> getCachedClubsList({String? cacheKey}) async {
    final prefs = await SharedPreferences.getInstance();

    // Use custom cache key if provided
    final key = cacheKey ?? _clubsListKey;

    // Check if cache exists
    if (!prefs.containsKey(key)) return null;

    // Check if cache is expired
    final timestamp = prefs.getInt(_timestampKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - timestamp > _cacheDuration.inMilliseconds) return null;

    // Return cached data
    final String? jsonData = prefs.getString(key);
    if (jsonData == null) return null;

    try {
      return jsonDecode(jsonData) as List<dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Retrieves cached club details if they exist
  Future<Map<String, dynamic>?> getCachedClubDetails(String clubId) async {
    final prefs = await SharedPreferences.getInstance();
    final String key = '$_clubDetailsPrefix$clubId';

    // Check if cache exists
    if (!prefs.containsKey(key)) return null;

    final String? jsonData = prefs.getString(key);
    if (jsonData == null) return null;

    try {
      return jsonDecode(jsonData) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Generates cache key for filtered club results
  String _generateCacheKey(
      {String? search, bool? isPublic, String? membershipFilter}) {
    final filters = <String>[];
    if (search != null && search.isNotEmpty) filters.add('search:$search');
    if (isPublic != null) filters.add('public:$isPublic');
    if (membershipFilter != null) filters.add('membership:$membershipFilter');

    if (filters.isEmpty) return _clubsListKey;
    return '${_clubsListKey}_${filters.join('_')}';
  }

  /// Cache clubs with filters
  Future<void> cacheFilteredClubs(
    List<dynamic> clubs, {
    String? search,
    bool? isPublic,
    String? membershipFilter,
  }) async {
    final cacheKey = _generateCacheKey(
      search: search,
      isPublic: isPublic,
      membershipFilter: membershipFilter,
    );
    await cacheClubsList(clubs, cacheKey: cacheKey);
  }

  /// Get cached clubs with filters
  Future<List<dynamic>?> getCachedFilteredClubs({
    String? search,
    bool? isPublic,
    String? membershipFilter,
  }) async {
    final cacheKey = _generateCacheKey(
      search: search,
      isPublic: isPublic,
      membershipFilter: membershipFilter,
    );
    return getCachedClubsList(cacheKey: cacheKey);
  }

  /// Invalidates cache when clubs are modified
  Future<void> invalidateCache() async {
    final prefs = await SharedPreferences.getInstance();

    // Get all keys and remove clubs-related cache entries
    final keys = prefs
        .getKeys()
        .where((key) =>
            key.startsWith(_clubsListKey) ||
            key.startsWith(_clubDetailsPrefix) ||
            key == _timestampKey)
        .toList();

    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  /// Invalidates specific club details cache
  Future<void> invalidateClubDetails(String clubId) async {
    final prefs = await SharedPreferences.getInstance();
    final String key = '$_clubDetailsPrefix$clubId';
    await prefs.remove(key);
  }

  /// Clears all clubs cache data
  Future<void> clearCache() async {
    await invalidateCache();
  }
}
