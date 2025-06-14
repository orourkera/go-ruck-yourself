import 'package:rucking_app/features/events/domain/models/event.dart';
import 'package:rucking_app/features/events/domain/models/event_comment.dart';
import 'package:rucking_app/features/events/domain/models/event_progress.dart';

abstract class EventsRepository {
  // Event CRUD operations
  Future<List<Event>> getEvents({
    String? search,
    String? clubId,
    String? status,
    bool? includeParticipating,
    DateTime? startDate,
    DateTime? endDate,
  });
  
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
    String? bannerImageUrl,
  });
  
  Future<EventDetails> getEventDetails(String eventId);
  
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
    String? bannerImageUrl,
  });
  
  Future<void> cancelEvent(String eventId);
  
  // Event participation management
  Future<void> joinEvent(String eventId);
  
  Future<void> leaveEvent(String eventId);
  
  Future<List<EventParticipant>> getEventParticipants(String eventId);
  
  Future<void> manageParticipation({
    required String eventId,
    required String userId,
    required String action, // 'approve', 'reject'
  });
  
  // Event comments
  Future<List<EventComment>> getEventComments(String eventId);
  
  Future<EventComment> addEventComment({
    required String eventId,
    required String comment,
  });
  
  Future<EventComment> updateEventComment({
    required String eventId,
    required String commentId,
    required String comment,
  });
  
  Future<void> deleteEventComment({
    required String eventId,
    required String commentId,
  });
  
  // Event progress and leaderboard
  Future<EventLeaderboard> getEventLeaderboard(String eventId);
  
  Future<EventProgress?> getUserEventProgress({
    required String eventId,
    required String userId,
  });
  
  Future<String> startRuckFromEvent(String eventId);
}
