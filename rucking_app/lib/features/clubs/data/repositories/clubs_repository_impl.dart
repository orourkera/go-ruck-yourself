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

    final response = await _apiClient.get('/api/clubs', queryParams: queryParams);
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> clubsJson = data['clubs'] as List<dynamic>;
      return clubsJson.map((json) => Club.fromJson(json as Map<String, dynamic>)).toList();
    } else {
      throw Exception('Failed to load clubs: ${response.body}');
    }
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

    final response = await _apiClient.post('/api/clubs', body: json.encode(body));
    
    if (response.statusCode == 201) {
      final data = json.decode(response.body);
      return Club.fromJson(data['club'] as Map<String, dynamic>);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to create club');
    }
  }

  @override
  Future<ClubDetails> getClubDetails(String clubId) async {
    final response = await _apiClient.get('/api/clubs/$clubId');
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return ClubDetails.fromJson(data);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to load club details');
    }
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

    final response = await _apiClient.put('/api/clubs/$clubId', body: json.encode(body));
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return Club.fromJson(data['club'] as Map<String, dynamic>);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to update club');
    }
  }

  @override
  Future<void> deleteClub(String clubId) async {
    final response = await _apiClient.delete('/api/clubs/$clubId');
    
    if (response.statusCode != 200) {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to delete club');
    }
  }

  @override
  Future<void> requestMembership(String clubId) async {
    final response = await _apiClient.post('/api/clubs/$clubId/join');
    
    if (response.statusCode != 200) {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to request membership');
    }
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

    final response = await _apiClient.put('/api/clubs/$clubId/members/$userId', body: json.encode(body));
    
    if (response.statusCode != 200) {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to manage membership');
    }
  }

  @override
  Future<void> removeMembership(String clubId, String userId) async {
    final response = await _apiClient.delete('/api/clubs/$clubId/members/$userId');
    
    if (response.statusCode != 200) {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to remove membership');
    }
  }

  @override
  Future<void> leaveClub(String clubId) async {
    // For leaving, we use the current user's ID - this will be handled by the backend
    final response = await _apiClient.delete('/api/clubs/$clubId/members/me');
    
    if (response.statusCode != 200) {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to leave club');
    }
  }
}
