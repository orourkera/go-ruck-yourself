import 'dart:convert';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/features/clubs/domain/models/club.dart';
import 'package:rucking_app/features/clubs/domain/repositories/clubs_repository.dart';

class ClubsRepositoryImpl implements ClubsRepository {
  final ApiClient _apiClient;

  ClubsRepositoryImpl(this._apiClient);

  @override
  Future<List<Club>> getClubs({
    String? search,
    bool? isPublic,
    String? membershipFilter,
  }) async {
    final queryParams = <String, String>{};
    
    if (search != null && search.isNotEmpty) {
      queryParams['search'] = search;
    }
    if (isPublic != null) {
      queryParams['is_public'] = isPublic.toString();
    }
    if (membershipFilter != null) {
      queryParams['membership'] = membershipFilter;
    }

    final response = await _apiClient.get('/clubs', queryParams: queryParams);
    
    return response['clubs'].map((json) => Club.fromJson(json as Map<String, dynamic>)).toList();
  }

  @override
  Future<Club> createClub({
    required String name,
    String? description,
    required bool isPublic,
    int? maxMembers,
  }) async {
    final body = {
      'name': name,
      'is_public': isPublic,
      if (description != null) 'description': description,
      if (maxMembers != null) 'max_members': maxMembers,
    };

    final response = await _apiClient.post('/clubs', body);
    
    return Club.fromJson(response['club'] as Map<String, dynamic>);
  }

  @override
  Future<ClubDetails> getClubDetails(String clubId) async {
    final response = await _apiClient.get('/clubs/$clubId');
    
    return ClubDetails.fromJson(response);
  }

  @override
  Future<Club> updateClub({
    required String clubId,
    String? name,
    String? description,
    bool? isPublic,
    int? maxMembers,
  }) async {
    final body = <String, dynamic>{};
    
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (isPublic != null) body['is_public'] = isPublic;
    if (maxMembers != null) body['max_members'] = maxMembers;

    final response = await _apiClient.put('/clubs/$clubId', body);
    
    return Club.fromJson(response['club'] as Map<String, dynamic>);
  }

  @override
  Future<void> deleteClub(String clubId) async {
    await _apiClient.delete('/clubs/$clubId');
  }

  @override
  Future<void> requestMembership(String clubId) async {
    await _apiClient.post('/clubs/$clubId/join', {});
  }

  @override
  Future<void> manageMembership({
    required String clubId,
    required String userId,
    String? action,
    String? role,
  }) async {
    final body = <String, dynamic>{};
    
    if (action != null) body['action'] = action;
    if (role != null) body['role'] = role;

    await _apiClient.put('/clubs/$clubId/members/$userId', body);
  }

  @override
  Future<void> removeMembership(String clubId, String userId) async {
    await _apiClient.delete('/clubs/$clubId/members/$userId');
  }

  @override
  Future<void> leaveClub(String clubId) async {
    // For leaving, we use the current user's ID - this will be handled by the backend
    await _apiClient.delete('/clubs/$clubId/members/me');
  }
}
