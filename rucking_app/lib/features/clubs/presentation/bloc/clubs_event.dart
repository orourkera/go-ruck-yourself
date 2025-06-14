import 'package:equatable/equatable.dart';

abstract class ClubsEvent extends Equatable {
  const ClubsEvent();

  @override
  List<Object?> get props => [];
}

class LoadClubs extends ClubsEvent {
  final String? search;
  final bool? isPublic;
  final String? membershipFilter;

  const LoadClubs({
    this.search,
    this.isPublic,
    this.membershipFilter,
  });

  @override
  List<Object?> get props => [search, isPublic, membershipFilter];
}

class RefreshClubs extends ClubsEvent {}

class CreateClub extends ClubsEvent {
  final String name;
  final String description;
  final bool isPublic;
  final int? maxMembers;
  final File? logo;
  final String? location;
  final double? latitude;
  final double? longitude;

  const CreateClub({
    required this.name,
    required this.description,
    required this.isPublic,
    this.maxMembers,
    this.logo,
    this.location,
    this.latitude,
    this.longitude,
  });

  @override
  List<Object?> get props => [name, description, isPublic, maxMembers, logo, location, latitude, longitude];
}

class LoadClubDetails extends ClubsEvent {
  final String clubId;

  const LoadClubDetails(this.clubId);

  @override
  List<Object?> get props => [clubId];
}

class UpdateClub extends ClubsEvent {
  final String clubId;
  final String? name;
  final String? description;
  final bool? isPublic;
  final int? maxMembers;

  const UpdateClub({
    required this.clubId,
    this.name,
    this.description,
    this.isPublic,
    this.maxMembers,
  });

  @override
  List<Object?> get props => [clubId, name, description, isPublic, maxMembers];
}

class DeleteClub extends ClubsEvent {
  final String clubId;

  const DeleteClub(this.clubId);

  @override
  List<Object?> get props => [clubId];
}

class RequestMembership extends ClubsEvent {
  final String clubId;

  const RequestMembership(this.clubId);

  @override
  List<Object?> get props => [clubId];
}

class ManageMembership extends ClubsEvent {
  final String clubId;
  final String userId;
  final String? action; // 'approve', 'reject'
  final String? role; // 'admin', 'member'

  const ManageMembership({
    required this.clubId,
    required this.userId,
    this.action,
    this.role,
  });

  @override
  List<Object?> get props => [clubId, userId, action, role];
}

class RemoveMembership extends ClubsEvent {
  final String clubId;
  final String userId;

  const RemoveMembership({
    required this.clubId,
    required this.userId,
  });

  @override
  List<Object?> get props => [clubId, userId];
}

class LeaveClub extends ClubsEvent {
  final String clubId;

  const LeaveClub(this.clubId);

  @override
  List<Object?> get props => [clubId];
}
