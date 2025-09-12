import 'dart:convert';
import 'dart:io';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/service_locator.dart';
import 'package:rucking_app/core/services/events_cache_service.dart';
import 'package:rucking_app/core/services/avatar_service.dart';
import 'package:rucking_app/features/events/domain/models/event.dart';
import 'package:rucking_app/features/events/domain/models/event_comment.dart';
import 'package:rucking_app/features/events/domain/models/event_progress.dart';
import 'package:rucking_app/features/events/domain/repositories/events_repository.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

class EventsRepositoryImpl implements EventsRepository {
  final ApiClient _apiClient;
  final AvatarService _avatarService;
  final EventsCacheService _cacheService = getIt<EventsCacheService>();

  EventsRepositoryImpl(this._apiClient, this._avatarService);

  @override
  Future<List<Event>> getEvents({
    String? search,
    String? clubId,
    String? status,
    bool? includeParticipating,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // Try to get cached data first
    final cachedData = await _cacheService.getCachedFilteredEvents(
      search: search,
      clubId: clubId,
      status: status,
      includeParticipating: includeParticipating,
      startDate: startDate,
      endDate: endDate,
    );

    if (cachedData != null) {
      // Return cached events
      return cachedData
          .map((json) => Event.fromJson(json as Map<String, dynamic>))
          .toList();
    }

    // No cache or expired, fetch from API
    final queryParams = <String, String>{};

    if (search != null && search.isNotEmpty) {
      queryParams['search'] = search;
    }
    if (clubId != null) {
      if (clubId == 'club_events') {
        // Special case: filter for events that have any club association
        queryParams['has_club'] = 'true';
      } else {
        // Specific club ID filter
        queryParams['club_id'] = clubId;
      }
    }
    if (status != null) {
      if (status == 'completed') {
        // Special case: filter for events that ended at least a day ago
        final dayAgo = DateTime.now().subtract(const Duration(days: 1));
        queryParams['end_before'] = dayAgo.toIso8601String();
      } else {
        // Regular status filter
        queryParams['status'] = status;
      }
    }
    if (includeParticipating != null) {
      queryParams['participating'] = includeParticipating.toString();
    }
    if (startDate != null) {
      queryParams['start_date'] = startDate.toIso8601String();
    }
    if (endDate != null) {
      queryParams['end_date'] = endDate.toIso8601String();
    }

    final response = await _apiClient.get('/events', queryParams: queryParams);

    AppLogger.info('Events API Response: ${jsonEncode(response)}');

    final eventsList = (response['events'] as List).map((json) {
      AppLogger.info('Processing event JSON: ${jsonEncode(json)}');
      AppLogger.info('Event club_id: ${json['club_id']}');
      AppLogger.info('Event hosting_club: ${json['hosting_club']}');
      return Event.fromJson(json as Map<String, dynamic>);
    }).toList();

    // Cache the response data
    await _cacheService.cacheFilteredEvents(
      response['events'] as List,
      search: search,
      clubId: clubId,
      status: status,
      includeParticipating: includeParticipating,
      startDate: startDate,
      endDate: endDate,
    );

    return eventsList;
  }

  @override
  Future<Event> createEvent({
    required String title,
    String? description,
    String? clubId,
    required DateTime scheduledStartTime,
    required int durationMinutes,
    String? locationName,
    double? latitude,
    double? longitude,
    int? maxParticipants,
    int? minParticipants,
    bool? approvalRequired,
    int? difficultyLevel,
    double? ruckWeightKg,
    File? bannerImageFile,
  }) async {
    // Upload banner image if provided
    String? bannerImageUrl;
    if (bannerImageFile != null) {
      bannerImageUrl = await _avatarService.uploadEventBanner(bannerImageFile);
    }

    final body = {
      'title': title,
      'scheduled_start_time': scheduledStartTime.toIso8601String(),
      'duration_minutes': durationMinutes,
      if (description != null) 'description': description,
      if (clubId != null) 'club_id': clubId,
      if (locationName != null) 'location_name': locationName,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (maxParticipants != null) 'max_participants': maxParticipants,
      if (minParticipants != null) 'min_participants': minParticipants,
      if (approvalRequired != null) 'approval_required': approvalRequired,
      if (difficultyLevel != null) 'difficulty_level': difficultyLevel,
      if (ruckWeightKg != null) 'ruck_weight_kg': ruckWeightKg,
      if (bannerImageUrl != null) 'banner_image_url': bannerImageUrl,
    };

    final response = await _apiClient.post('/events', body);

    // Invalidate events list cache since we created a new event
    await _cacheService.invalidateCache();

    return Event.fromJson(response['event'] as Map<String, dynamic>);
  }

  @override
  Future<EventDetails> getEventDetails(String eventId) async {
    // Invalidate cache first to ensure fresh data
    await _cacheService.invalidateEventDetails(eventId);

    // Try to get cached event details first
    final cachedDetails = await _cacheService.getCachedEventDetails(eventId);

    if (cachedDetails != null) {
      return EventDetails.fromJson(cachedDetails);
    }

    // No cache, fetch from API
    final response = await _apiClient.get('/events/$eventId');

    final eventDetails = EventDetails.fromJson(response);

    // Cache the event details
    await _cacheService.cacheEventDetails(eventId, response);

    return eventDetails;
  }

  @override
  Future<Event> updateEvent({
    required String eventId,
    String? title,
    String? description,
    DateTime? scheduledStartTime,
    int? durationMinutes,
    String? locationName,
    double? latitude,
    double? longitude,
    int? maxParticipants,
    int? minParticipants,
    bool? approvalRequired,
    int? difficultyLevel,
    double? ruckWeightKg,
    File? bannerImageFile,
  }) async {
    // Upload banner image if provided
    String? bannerImageUrl;
    if (bannerImageFile != null) {
      bannerImageUrl = await _avatarService.uploadEventBanner(bannerImageFile);
    }

    final body = <String, dynamic>{};

    if (title != null) body['title'] = title;
    if (description != null) body['description'] = description;
    if (scheduledStartTime != null)
      body['scheduled_start_time'] = scheduledStartTime.toIso8601String();
    if (durationMinutes != null) body['duration_minutes'] = durationMinutes;
    if (locationName != null) body['location_name'] = locationName;
    if (latitude != null) body['latitude'] = latitude;
    if (longitude != null) body['longitude'] = longitude;
    if (maxParticipants != null) body['max_participants'] = maxParticipants;
    if (minParticipants != null) body['min_participants'] = minParticipants;
    if (approvalRequired != null) body['approval_required'] = approvalRequired;
    if (difficultyLevel != null) body['difficulty_level'] = difficultyLevel;
    if (ruckWeightKg != null) body['ruck_weight_kg'] = ruckWeightKg;
    if (bannerImageUrl != null) body['banner_image_url'] = bannerImageUrl;

    final response = await _apiClient.put('/events/$eventId', body);

    // Invalidate caches since event was updated
    await _cacheService.invalidateCache();
    await _cacheService.invalidateEventDetails(eventId);

    return Event.fromJson(response['event'] as Map<String, dynamic>);
  }

  @override
  Future<void> cancelEvent(String eventId) async {
    await _apiClient.delete('/events/$eventId');

    // Invalidate caches since event was cancelled
    await _cacheService.invalidateCache();
    await _cacheService.invalidateEventDetails(eventId);
  }

  @override
  Future<void> joinEvent(String eventId) async {
    await _apiClient.post('/events/$eventId/participation', {});

    // Invalidate event details cache since participation changed
    await _cacheService.invalidateEventDetails(eventId);
    await _cacheService.invalidateCache(); // Also invalidate list cache
  }

  @override
  Future<void> leaveEvent(String eventId) async {
    await _apiClient.delete('/events/$eventId/participation');

    // Invalidate event details cache since participation changed
    await _cacheService.invalidateEventDetails(eventId);
    await _cacheService.invalidateCache(); // Also invalidate list cache
  }

  @override
  Future<List<EventParticipant>> getEventParticipants(String eventId) async {
    final response = await _apiClient.get('/events/$eventId/participants');

    return (response['participants'] as List<dynamic>)
        .map((participant) =>
            EventParticipant.fromJson(participant as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> manageParticipation({
    required String eventId,
    required String userId,
    required String action,
  }) async {
    final body = {
      'user_id': userId,
      'action': action,
    };

    await _apiClient.put('/events/$eventId/participation', body);

    // Invalidate event details cache since participation was managed
    await _cacheService.invalidateEventDetails(eventId);
  }

  @override
  Future<List<EventComment>> getEventComments(String eventId) async {
    // Try to get cached comments first
    final cachedComments = await _cacheService.getCachedEventComments(eventId);

    if (cachedComments != null) {
      return cachedComments
          .map((json) => EventComment.fromJson(json as Map<String, dynamic>))
          .toList();
    }

    // No cache, fetch from API
    final response = await _apiClient.get('/events/$eventId/comments');

    final comments = (response['comments'] as List<dynamic>)
        .map(
            (comment) => EventComment.fromJson(comment as Map<String, dynamic>))
        .toList();

    // Cache the comments
    await _cacheService.cacheEventComments(
        eventId, response['comments'] as List);

    return comments;
  }

  @override
  Future<EventComment> addEventComment({
    required String eventId,
    required String comment,
  }) async {
    final body = {
      'comment': comment,
    };

    final response = await _apiClient.post('/events/$eventId/comments', body);

    // Invalidate comments cache since we added a new comment
    await _cacheService.invalidateEventComments(eventId);

    return EventComment.fromJson(response['comment'] as Map<String, dynamic>);
  }

  @override
  Future<EventComment> updateEventComment({
    required String eventId,
    required String commentId,
    required String comment,
  }) async {
    final body = {
      'comment': comment,
    };

    final response =
        await _apiClient.put('/events/$eventId/comments/$commentId', body);

    // Invalidate comments cache since we updated a comment
    await _cacheService.invalidateEventComments(eventId);

    return EventComment.fromJson(response['comment'] as Map<String, dynamic>);
  }

  @override
  Future<void> deleteEventComment({
    required String eventId,
    required String commentId,
  }) async {
    await _apiClient.delete('/events/$eventId/comments/$commentId');

    // Invalidate comments cache since we deleted a comment
    await _cacheService.invalidateEventComments(eventId);
  }

  @override
  Future<EventLeaderboard> getEventLeaderboard(String eventId) async {
    // Try to get cached leaderboard first
    final cachedLeaderboard =
        await _cacheService.getCachedEventLeaderboard(eventId);

    if (cachedLeaderboard != null) {
      final parsed = EventLeaderboard.fromJson(cachedLeaderboard);
      // If any entry is missing user data, treat cache as stale and refetch
      final hasMissingUser = parsed.entries.any((entry) => entry.user == null);
      if (!hasMissingUser) {
        return parsed;
      }
      // Otherwise fall through to fetch fresh data
    }

    // No cache, fetch from API
    final response = await _apiClient.get('/events/$eventId/progress');

    // Transform API response to match EventLeaderboard model
    final transformedResponse = {
      'event_id': eventId,
      'entries': response['progress'] ?? [], // Map 'progress' to 'entries'
      'last_updated': DateTime.now().toIso8601String(),
    };

    final leaderboard = EventLeaderboard.fromJson(transformedResponse);

    // Cache the transformed response
    await _cacheService.cacheEventLeaderboard(eventId, transformedResponse);

    return leaderboard;
  }

  @override
  Future<EventProgress?> getUserEventProgress({
    required String eventId,
    required String userId,
  }) async {
    try {
      final response = await _apiClient
          .get('/events/$eventId/progress', queryParams: {'user_id': userId});

      if (response['progress'] != null) {
        return EventProgress.fromJson(
            response['progress'] as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      // Return null if user has no progress yet
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>> startRuckFromEvent(String eventId) async {
    final response = await _apiClient.post('/events/$eventId/start-ruck', {});

    // Invalidate leaderboard cache since progress may change
    await _cacheService.invalidateEventLeaderboard(eventId);

    return {
      'event_id': response['event_id'] as String,
      'event_title': response['event_title'] as String,
      'status': response['status'] as String,
    };
  }
}
