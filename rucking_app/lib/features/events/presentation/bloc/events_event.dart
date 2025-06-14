import 'package:equatable/equatable.dart';

abstract class EventsEvent extends Equatable {
  const EventsEvent();

  @override
  List<Object?> get props => [];
}

class LoadEvents extends EventsEvent {
  final String? search;
  final String? clubId;
  final String? status;
  final bool? includeParticipating;
  final DateTime? startDate;
  final DateTime? endDate;

  const LoadEvents({
    this.search,
    this.clubId,
    this.status,
    this.includeParticipating,
    this.startDate,
    this.endDate,
  });

  @override
  List<Object?> get props => [search, clubId, status, includeParticipating, startDate, endDate];
}

class RefreshEvents extends EventsEvent {}

class CreateEvent extends EventsEvent {
  final String title;
  final String? description;
  final String? clubId;
  final DateTime scheduledStartTime;
  final int durationMinutes;
  final String? locationName;
  final double? latitude;
  final double? longitude;
  final int? maxParticipants;
  final int? minParticipants;
  final bool? approvalRequired;
  final int? difficultyLevel;
  final double? ruckWeightKg;
  final String? bannerImageUrl;

  const CreateEvent({
    required this.title,
    this.description,
    this.clubId,
    required this.scheduledStartTime,
    required this.durationMinutes,
    this.locationName,
    this.latitude,
    this.longitude,
    this.maxParticipants,
    this.minParticipants,
    this.approvalRequired,
    this.difficultyLevel,
    this.ruckWeightKg,
    this.bannerImageUrl,
  });

  @override
  List<Object?> get props => [
        title,
        description,
        clubId,
        scheduledStartTime,
        durationMinutes,
        locationName,
        latitude,
        longitude,
        maxParticipants,
        minParticipants,
        approvalRequired,
        difficultyLevel,
        ruckWeightKg,
        bannerImageUrl,
      ];
}

class LoadEventDetails extends EventsEvent {
  final String eventId;

  const LoadEventDetails(this.eventId);

  @override
  List<Object?> get props => [eventId];
}

class UpdateEvent extends EventsEvent {
  final String eventId;
  final String? title;
  final String? description;
  final DateTime? scheduledStartTime;
  final int? durationMinutes;
  final String? locationName;
  final double? latitude;
  final double? longitude;
  final int? maxParticipants;
  final int? minParticipants;
  final bool? approvalRequired;
  final int? difficultyLevel;
  final double? ruckWeightKg;
  final String? bannerImageUrl;

  const UpdateEvent({
    required this.eventId,
    this.title,
    this.description,
    this.scheduledStartTime,
    this.durationMinutes,
    this.locationName,
    this.latitude,
    this.longitude,
    this.maxParticipants,
    this.minParticipants,
    this.approvalRequired,
    this.difficultyLevel,
    this.ruckWeightKg,
    this.bannerImageUrl,
  });

  @override
  List<Object?> get props => [
        eventId,
        title,
        description,
        scheduledStartTime,
        durationMinutes,
        locationName,
        latitude,
        longitude,
        maxParticipants,
        minParticipants,
        approvalRequired,
        difficultyLevel,
        ruckWeightKg,
        bannerImageUrl,
      ];
}

class CancelEvent extends EventsEvent {
  final String eventId;

  const CancelEvent(this.eventId);

  @override
  List<Object?> get props => [eventId];
}

class JoinEvent extends EventsEvent {
  final String eventId;

  const JoinEvent(this.eventId);

  @override
  List<Object?> get props => [eventId];
}

class LeaveEvent extends EventsEvent {
  final String eventId;

  const LeaveEvent(this.eventId);

  @override
  List<Object?> get props => [eventId];
}

class LoadEventParticipants extends EventsEvent {
  final String eventId;

  const LoadEventParticipants(this.eventId);

  @override
  List<Object?> get props => [eventId];
}

class ManageEventParticipation extends EventsEvent {
  final String eventId;
  final String userId;
  final String action; // 'approve', 'reject'

  const ManageEventParticipation({
    required this.eventId,
    required this.userId,
    required this.action,
  });

  @override
  List<Object?> get props => [eventId, userId, action];
}

class StartRuckFromEvent extends EventsEvent {
  final String eventId;

  const StartRuckFromEvent(this.eventId);

  @override
  List<Object?> get props => [eventId];
}
