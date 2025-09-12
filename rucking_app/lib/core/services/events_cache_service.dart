import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for caching events data to improve loading performance
class EventsCacheService {
  static const String _eventsListKey = 'events_list_cache';
  static const String _eventDetailsPrefix = 'event_details_';
  static const String _eventCommentsPrefix = 'event_comments_';
  static const String _eventLeaderboardPrefix = 'event_leaderboard_';
  static const String _timestampKey = 'events_cache_timestamp';
  static const Duration _cacheDuration =
      Duration(minutes: 10); // Cache valid for 10 minutes

  /// Saves events list to local storage
  Future<void> cacheEventsList(List<dynamic> events, {String? cacheKey}) async {
    final prefs = await SharedPreferences.getInstance();

    // Use custom cache key if provided (for filtered results)
    final key = cacheKey ?? _eventsListKey;

    final String jsonData = jsonEncode(events);
    await prefs.setString(key, jsonData);
    await prefs.setInt(_timestampKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Saves individual event details to local storage
  Future<void> cacheEventDetails(
      String eventId, Map<String, dynamic> eventDetails) async {
    final prefs = await SharedPreferences.getInstance();
    final String key = '$_eventDetailsPrefix$eventId';
    final String jsonData = jsonEncode(eventDetails);
    await prefs.setString(key, jsonData);
  }

  /// Saves event comments to local storage
  Future<void> cacheEventComments(
      String eventId, List<dynamic> comments) async {
    final prefs = await SharedPreferences.getInstance();
    final String key = '$_eventCommentsPrefix$eventId';
    final String jsonData = jsonEncode(comments);
    await prefs.setString(key, jsonData);
  }

  /// Saves event leaderboard to local storage
  Future<void> cacheEventLeaderboard(
      String eventId, Map<String, dynamic> leaderboard) async {
    final prefs = await SharedPreferences.getInstance();
    final String key = '$_eventLeaderboardPrefix$eventId';
    final String jsonData = jsonEncode(leaderboard);
    await prefs.setString(key, jsonData);
  }

  /// Retrieves cached events list if it exists and is not expired
  Future<List<dynamic>?> getCachedEventsList({String? cacheKey}) async {
    final prefs = await SharedPreferences.getInstance();

    // Use custom cache key if provided
    final key = cacheKey ?? _eventsListKey;

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

  /// Retrieves cached event details if they exist
  Future<Map<String, dynamic>?> getCachedEventDetails(String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    final String key = '$_eventDetailsPrefix$eventId';

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

  /// Retrieves cached event comments if they exist
  Future<List<dynamic>?> getCachedEventComments(String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    final String key = '$_eventCommentsPrefix$eventId';

    // Check if cache exists
    if (!prefs.containsKey(key)) return null;

    final String? jsonData = prefs.getString(key);
    if (jsonData == null) return null;

    try {
      return jsonDecode(jsonData) as List<dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Retrieves cached event leaderboard if it exists
  Future<Map<String, dynamic>?> getCachedEventLeaderboard(
      String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    final String key = '$_eventLeaderboardPrefix$eventId';

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

  /// Generates cache key for filtered event results
  String _generateCacheKey({
    String? search,
    String? clubId,
    String? status,
    bool? includeParticipating,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final filters = <String>[];
    if (search != null && search.isNotEmpty) filters.add('search:$search');
    if (clubId != null) filters.add('club:$clubId');
    if (status != null) filters.add('status:$status');
    if (includeParticipating != null)
      filters.add('participating:$includeParticipating');
    if (startDate != null)
      filters.add('start:${startDate.millisecondsSinceEpoch}');
    if (endDate != null) filters.add('end:${endDate.millisecondsSinceEpoch}');

    if (filters.isEmpty) return _eventsListKey;
    return '${_eventsListKey}_${filters.join('_')}';
  }

  /// Cache events with filters
  Future<void> cacheFilteredEvents(
    List<dynamic> events, {
    String? search,
    String? clubId,
    String? status,
    bool? includeParticipating,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final cacheKey = _generateCacheKey(
      search: search,
      clubId: clubId,
      status: status,
      includeParticipating: includeParticipating,
      startDate: startDate,
      endDate: endDate,
    );
    await cacheEventsList(events, cacheKey: cacheKey);
  }

  /// Get cached events with filters
  Future<List<dynamic>?> getCachedFilteredEvents({
    String? search,
    String? clubId,
    String? status,
    bool? includeParticipating,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final cacheKey = _generateCacheKey(
      search: search,
      clubId: clubId,
      status: status,
      includeParticipating: includeParticipating,
      startDate: startDate,
      endDate: endDate,
    );
    return getCachedEventsList(cacheKey: cacheKey);
  }

  /// Invalidates cache when events are modified
  Future<void> invalidateCache() async {
    final prefs = await SharedPreferences.getInstance();

    // Get all keys and remove events-related cache entries
    final keys = prefs
        .getKeys()
        .where((key) =>
            key.startsWith(_eventsListKey) ||
            key.startsWith(_eventDetailsPrefix) ||
            key.startsWith(_eventCommentsPrefix) ||
            key.startsWith(_eventLeaderboardPrefix) ||
            key == _timestampKey)
        .toList();

    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  /// Invalidates specific event details cache
  Future<void> invalidateEventDetails(String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    final String key = '$_eventDetailsPrefix$eventId';
    await prefs.remove(key);
  }

  /// Invalidates specific event comments cache
  Future<void> invalidateEventComments(String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    final String key = '$_eventCommentsPrefix$eventId';
    await prefs.remove(key);
  }

  /// Invalidates specific event leaderboard cache
  Future<void> invalidateEventLeaderboard(String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    final String key = '$_eventLeaderboardPrefix$eventId';
    await prefs.remove(key);
  }

  /// Clears all events cache data
  Future<void> clearCache() async {
    await invalidateCache();
  }
}
