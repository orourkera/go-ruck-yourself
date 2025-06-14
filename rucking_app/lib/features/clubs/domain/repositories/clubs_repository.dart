import 'package:rucking_app/features/clubs/domain/models/club.dart';

abstract class ClubsRepository {
  Future<List<Club>> getClubs({
    String? search,
    bool? isPublic,
    String? membershipFilter,
  });
  
  Future<Club> createClub({
    required String name,
    required String description,
    required bool isPublic,
    int? maxMembers,
    String? logoUrl,
    double? latitude,
    double? longitude,
  });
  
  Future<ClubDetails> getClubDetails(String clubId);
  
  Future<Club> updateClub({
    required String clubId,
    String? name,
    String? description,
    bool? isPublic,
    int? maxMembers,
  });
  
  Future<void> deleteClub(String clubId);
  
  Future<void> requestMembership(String clubId);
  
  Future<void> manageMembership({
    required String clubId,
    required String userId,
    String? action, // 'approve', 'reject'
    String? role, // 'admin', 'member'
  });
  
  Future<void> removeMembership(String clubId, String userId);
  
  Future<void> leaveClub(String clubId);
}
