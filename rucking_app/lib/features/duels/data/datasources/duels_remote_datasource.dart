import 'dart:convert';
import '../../../../core/services/api_client.dart';
import '../../../../core/error/exceptions.dart';
import '../models/duel_model.dart';
import '../models/duel_participant_model.dart';
import '../models/user_duel_stats_model.dart';
import '../models/duel_invitation_model.dart';

abstract class DuelsRemoteDataSource {
  // Duel management
  Future<List<DuelModel>> getDuels({
    String? status,
    String? challengeType,
    String? location,
    int? limit,
  });

  Future<DuelModel> createDuel({
    required String title,
    required String challengeType,
    required double targetValue,
    required int timeframeHours,
    required int maxParticipants,
    required bool isPublic,
    String? description,
    String? creatorCity,
    String? creatorState,
    List<String>? inviteeEmails,
  });

  Future<DuelModel> getDuel(String duelId);
  Future<DuelModel> updateDuel(String duelId, Map<String, dynamic> updates);
  Future<void> joinDuel(String duelId);

  // Participant management
  Future<void> updateParticipantStatus(String duelId, String participantId, String status);
  Future<void> updateParticipantProgress(String duelId, String participantId, String sessionId, double contributionValue);
  Future<DuelParticipantModel> getParticipantProgress(String duelId, String participantId);
  Future<List<DuelParticipantModel>> getDuelLeaderboard(String duelId);

  // Statistics
  Future<UserDuelStatsModel> getUserDuelStats([String? userId]);
  Future<List<UserDuelStatsModel>> getDuelStatsLeaderboard(String statType, int limit);
  Future<Map<String, dynamic>> getDuelAnalytics(int days);

  // Invitations
  Future<List<DuelInvitationModel>> getDuelInvitations(String status);
  Future<void> respondToInvitation(String invitationId, String action);
  Future<void> cancelInvitation(String invitationId);
  Future<List<DuelInvitationModel>> getSentInvitations();
}

class DuelsRemoteDataSourceImpl implements DuelsRemoteDataSource {
  final ApiClient apiClient;

  DuelsRemoteDataSourceImpl({required this.apiClient});

  @override
  Future<List<DuelModel>> getDuels({
    String? status,
    String? challengeType,
    String? location,
    int? limit,
  }) async {
    final queryParams = <String, String>{};
    if (status != null) queryParams['status'] = status;
    if (challengeType != null) queryParams['challenge_type'] = challengeType;
    if (location != null) queryParams['location'] = location;
    if (limit != null) queryParams['limit'] = limit.toString();

    print('[DEBUG] getDuels() - Making API call with params: $queryParams');
    
    try {
      // ApiClient.get() returns the parsed JSON data directly, not a response object
      final jsonData = await apiClient.get('/duels', queryParams: queryParams);
      
      print('[DEBUG] getDuels() - Received JSON data: $jsonData');
      
      // Extract duels array from the response
      final List<dynamic> duelsData = jsonData['duels'] ?? [];
      print('[DEBUG] getDuels() - Duels array: $duelsData');
      print('[DEBUG] getDuels() - Duels array length: ${duelsData.length}');
      
      final result = duelsData.map((duelJson) {
        print('[DEBUG] getDuels() - Parsing duel: $duelJson');
        return DuelModel.fromJson(duelJson);
      }).toList();
      
      print('[DEBUG] getDuels() - Successfully parsed ${result.length} duels');
      return result;
    } catch (e, stackTrace) {
      print('[ERROR] getDuels() - Error: $e');
      print('[ERROR] getDuels() - Stack trace: $stackTrace');
      throw ServerException(message: 'Failed to fetch duels: $e');
    }
  }

  @override
  Future<DuelModel> createDuel({
    required String title,
    required String challengeType,
    required double targetValue,
    required int timeframeHours,
    required int maxParticipants,
    required bool isPublic,
    String? description,
    String? creatorCity,
    String? creatorState,
    List<String>? inviteeEmails,
  }) async {
    final body = {
      'title': title,
      'challenge_type': challengeType,
      'target_value': targetValue,
      'timeframe_hours': timeframeHours,
      'max_participants': maxParticipants,
      'is_public': isPublic,
      if (description != null) 'description': description,
      if (creatorCity != null) 'creator_city': creatorCity,
      if (creatorState != null) 'creator_state': creatorState,
      if (inviteeEmails != null) 'invitee_emails': inviteeEmails,
    };

    try {
      // ApiClient.post returns the response data directly, not the http.Response
      final response = await apiClient.post('/duels', body);
      
      // The responseData should contain the duel data directly
      return DuelModel.fromJson(response['duel']);
    } catch (e) {
      // ApiClient already handles errors and converts them to appropriate exceptions
      rethrow;
    }
  }

  @override
  Future<DuelModel> getDuel(String duelId) async {
    try {
      final responseData = await apiClient.get('/duels/$duelId', queryParams: {});
      return DuelModel.fromJson(responseData);
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<DuelModel> updateDuel(String duelId, Map<String, dynamic> updates) async {
    try {
      final responseData = await apiClient.put('/duels/$duelId', updates);
      return DuelModel.fromJson(responseData['duel']);
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> joinDuel(String duelId) async {
    try {
      // Second parameter is body, pass an empty map if no body needed
      await apiClient.post('/duels/$duelId/join', {});
      // Successfully joined if no exception is thrown
      return;
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> updateParticipantStatus(String duelId, String participantId, String status) async {
    try {
      final body = {'status': status};
      await apiClient.put('/duels/$duelId/participants/$participantId/status', body);
      return;
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> updateParticipantProgress(String duelId, String participantId, String sessionId, double contributionValue) async {
    final body = {
      'session_id': sessionId,
      'contribution_value': contributionValue,
    };
    final response = await apiClient.post('/duels/$duelId/participants/$participantId/progress', body);
    
    if (response.statusCode != 200) {
      final errorData = json.decode(response.body);
      throw ServerException(message: errorData['error'] ?? 'Failed to update progress');
    }
  }

  @override
  Future<DuelParticipantModel> getParticipantProgress(String duelId, String participantId) async {
    try {
      final responseData = await apiClient.get('/duels/$duelId/participants/$participantId/progress', queryParams: {});
      return DuelParticipantModel.fromJson(responseData);
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<List<DuelParticipantModel>> getDuelLeaderboard(String duelId) async {
    try {
      final responseData = await apiClient.get('/duels/$duelId/leaderboard', queryParams: {});
      final List<dynamic> leaderboardData = responseData['leaderboard'] ?? [];
      return leaderboardData
          .map((data) => DuelParticipantModel.fromJson(data))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<UserDuelStatsModel> getUserDuelStats([String? userId]) async {
    try {
      final endpoint = userId != null ? '/duel-stats/$userId' : '/duel-stats';
      final responseData = await apiClient.get(endpoint, queryParams: {});
      return UserDuelStatsModel.fromJson(responseData);
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<List<UserDuelStatsModel>> getDuelStatsLeaderboard(String statType, int limit) async {
    try {
      final queryParams = {
        'type': statType,
        'limit': limit.toString(),
      };
      final responseData = await apiClient.get('/duel-stats/leaderboard', queryParams: queryParams);
      final List<dynamic> leaderboardData = responseData['leaderboard'] ?? [];
      return leaderboardData.map((statsJson) => UserDuelStatsModel.fromJson(statsJson)).toList();
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> getDuelAnalytics(int days) async {
    try {
      final queryParams = {'days': days.toString()};
      // ApiClient.get returns the response data directly
      return await apiClient.get('/duel-stats/analytics', queryParams: queryParams);
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<List<DuelInvitationModel>> getDuelInvitations(String status) async {
    try {
      final queryParams = {'status': status};
      final responseData = await apiClient.get('/duel-invitations', queryParams: queryParams);
      final List<dynamic> invitationsData = responseData['invitations'] ?? [];
      return invitationsData.map((invitationJson) => DuelInvitationModel.fromJson(invitationJson)).toList();
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> respondToInvitation(String invitationId, String action) async {
    try {
      final body = {'action': action};
      await apiClient.put('/duel-invitations/$invitationId', body);
      // Successfully responded if no exception is thrown
      return;
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> cancelInvitation(String invitationId) async {
    final response = await apiClient.delete('/duel-invitations/$invitationId');
    
    if (response.statusCode != 200) {
      final errorData = json.decode(response.body);
      throw ServerException(message: errorData['error'] ?? 'Failed to cancel invitation');
    }
  }

  @override
  Future<List<DuelInvitationModel>> getSentInvitations() async {
    final response = await apiClient.get('/duel-invitations/sent', queryParams: {});
    
    if (response.statusCode == 200) {
      final jsonData = json.decode(response.body);
      final List<dynamic> invitationsData = jsonData['sent_invitations'] ?? [];
      return invitationsData.map((invitationJson) => DuelInvitationModel.fromJson(invitationJson)).toList();
    } else {
      throw ServerException(message: 'Failed to fetch sent invitations');
    }
  }
}
