import 'dart:convert';
import 'dart:io';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/service_locator.dart';
import 'package:rucking_app/core/services/clubs_cache_service.dart';
import 'package:rucking_app/core/services/avatar_service.dart';
import 'package:rucking_app/features/clubs/domain/models/club.dart';
import 'package:rucking_app/features/clubs/domain/repositories/clubs_repository.dart';

class ClubsRepositoryImpl implements ClubsRepository {
  final ApiClient _apiClient;
  final ClubsCacheService _cacheService = getIt<ClubsCacheService>();
  final AvatarService _avatarService = getIt<AvatarService>();

  ClubsRepositoryImpl(this._apiClient);

  @override
  Future<List<Club>> getClubs({
    String? search,
    bool? isPublic,
    String? membershipFilter,
  }) async {
    // Try to get cached data first
    final cachedData = await _cacheService.getCachedFilteredClubs(
      search: search,
      isPublic: isPublic,
      membershipFilter: membershipFilter,
    );
    
    if (cachedData != null) {
      // Return cached clubs
      return cachedData
          .map((json) => Club.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    
    // No cache or expired, fetch from API
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
    
    final clubsList = (response['clubs'] as List)
        .map((json) => Club.fromJson(json as Map<String, dynamic>))
        .toList();
    
    // Cache the response data
    await _cacheService.cacheFilteredClubs(
      response['clubs'] as List,
      search: search,
      isPublic: isPublic,
      membershipFilter: membershipFilter,
    );
    
    return clubsList;
  }

  @override
  Future<Club> createClub({
    required String name,
    required String description,
    required bool isPublic,
    int? maxMembers,
    String? logoUrl,
    double? latitude,
    double? longitude,
  }) async {
    final body = {
      'name': name,
      'description': description,
      'is_public': isPublic,
      if (maxMembers != null) 'max_members': maxMembers,
      if (logoUrl != null) 'logo_url': logoUrl,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    };

    final response = await _apiClient.post('/clubs', body);
    
    // Invalidate clubs list cache since we created a new club
    await _cacheService.invalidateCache();
    
    return Club.fromJson(response['club'] as Map<String, dynamic>);
  }

  @override
  Future<ClubDetails> getClubDetails(String clubId) async {
    // Try to get cached club details first
    final cachedDetails = await _cacheService.getCachedClubDetails(clubId);
    
    if (cachedDetails != null) {
      return ClubDetails.fromJson(cachedDetails);
    }
    
    // No cache, fetch from API
    final response = await _apiClient.get('/clubs/$clubId');
    
    final clubDetails = ClubDetails.fromJson(response as Map<String, dynamic>);
    
    // Cache the club details
    await _cacheService.cacheClubDetails(clubId, response as Map<String, dynamic>);
    
    return clubDetails;
  }

  @override
  Future<Club> updateClub({
    required String clubId,
    String? name,
    String? description,
    bool? isPublic,
    int? maxMembers,
    File? logo,
    String? location,
    double? latitude,
    double? longitude,
  }) async {
    final body = <String, dynamic>{};
    
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (isPublic != null) body['is_public'] = isPublic;
    if (maxMembers != null) body['max_members'] = maxMembers;
    if (location != null) body['location'] = location;
    if (latitude != null) body['latitude'] = latitude;
    if (longitude != null) body['longitude'] = longitude;
    
    // Handle logo upload
    if (logo != null) {
      try {
        final logoUrl = await _avatarService.uploadClubLogo(logo);
        body['logo_url'] = logoUrl;
      } catch (e) {
        throw Exception('Failed to upload club logo: $e');
      }
    }

    final response = await _apiClient.put('/clubs/$clubId', body);
    
    // Invalidate caches since club was updated
    await _cacheService.invalidateCache();
    await _cacheService.invalidateClubDetails(clubId);
    
    return Club.fromJson(response['club'] as Map<String, dynamic>);
  }

  @override
  Future<void> deleteClub(String clubId) async {
    await _apiClient.delete('/clubs/$clubId');
    
    // Invalidate caches since club was deleted
    await _cacheService.invalidateCache();
    await _cacheService.invalidateClubDetails(clubId);
  }

  @override
  Future<void> requestMembership(String clubId) async {
    await _apiClient.post('/clubs/$clubId/join', {});
    
    // Invalidate club details cache since membership changed
    await _cacheService.invalidateClubDetails(clubId);
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
    
    // Invalidate club details cache since membership changed
    await _cacheService.invalidateClubDetails(clubId);
  }

  @override
  Future<void> removeMembership(String clubId, String userId) async {
    await _apiClient.delete('/clubs/$clubId/members/$userId');
    
    // Invalidate club details cache since membership changed
    await _cacheService.invalidateClubDetails(clubId);
  }

  @override
  Future<void> leaveClub(String clubId) async {
    // For leaving, we use the current user's ID - this will be handled by the backend
    await _apiClient.delete('/clubs/$clubId/members/me');
    
    // Invalidate club details cache since membership changed
    await _cacheService.invalidateClubDetails(clubId);
  }
}
