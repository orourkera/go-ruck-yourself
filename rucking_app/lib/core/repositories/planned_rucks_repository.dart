import 'package:rucking_app/core/models/planned_ruck.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:get_it/get_it.dart';

/// Repository for managing planned ruck sessions
/// Provides methods to create, manage, and track planned rucks
class PlannedRucksRepository {
  final ApiClient _apiClient;
  
  PlannedRucksRepository({ApiClient? apiClient}) 
      : _apiClient = apiClient ?? GetIt.instance<ApiClient>();

  /// Get all planned rucks for the current user
  /// 
  /// Parameters:
  /// - [limit]: Maximum number of planned rucks to return (default: 20)
  /// - [offset]: Number of planned rucks to skip for pagination (default: 0)
  /// - [status]: Filter by status ('planned', 'in_progress', 'completed', 'cancelled')
  /// - [fromDate]: Get planned rucks from this date onwards
  /// - [toDate]: Get planned rucks until this date
  /// - [includeRoute]: Include full route data (default: true)
  Future<List<PlannedRuck>> getPlannedRucks({
    int limit = 20,
    int offset = 0,
    String? status,
    DateTime? fromDate,
    DateTime? toDate,
    bool includeRoute = true,
  }) async {
    try {
      final queryParams = <String, String>{
        'limit': limit.toString(),
        'offset': offset.toString(),
        'include_route': includeRoute.toString(),
      };
      
      if (status?.isNotEmpty == true) queryParams['status'] = status!;
      if (fromDate != null) queryParams['from_date'] = fromDate.toIso8601String();
      if (toDate != null) queryParams['to_date'] = toDate.toIso8601String();

      final response = await _apiClient.get('/planned-rucks', queryParams: queryParams);
      
      final plannedRucks = (response['data']['planned_rucks'] as List)
          .map((plannedRuckJson) => PlannedRuck.fromJson(plannedRuckJson as Map<String, dynamic>))
          .toList();
      
      AppLogger.info('Retrieved ${plannedRucks.length} planned rucks');
      return plannedRucks;
    } catch (e) {
      AppLogger.error('Error getting planned rucks: $e');
      throw Exception('Error getting planned rucks: $e');
    }
  }

  /// Get a specific planned ruck by ID
  /// 
  /// Parameters:
  /// - [plannedRuckId]: ID of the planned ruck to retrieve
  /// - [includeRoute]: Include full route data (default: true)
  Future<PlannedRuck?> getPlannedRuck(
    String plannedRuckId, {
    bool includeRoute = true,
  }) async {
    try {
      final queryParams = <String, String>{
        'include_route': includeRoute.toString(),
      };

      final response = await _apiClient.get('/planned-rucks/$plannedRuckId', queryParams: queryParams);
      
      final plannedRuck = PlannedRuck.fromJson(response['data']['planned_ruck'] as Map<String, dynamic>);
      AppLogger.info('Retrieved planned ruck: ${plannedRuck.id}');
      return plannedRuck;
    } catch (e) {
      AppLogger.error('Error getting planned ruck $plannedRuckId: $e');
      throw Exception('Error getting planned ruck: $e');
    }
  }

  /// Create a new planned ruck
  /// 
  /// Parameters:
  /// - [plannedRuck]: Planned ruck data to create
  Future<PlannedRuck> createPlannedRuck(PlannedRuck plannedRuck) async {
    try {
      final response = await _apiClient.post('/planned-rucks', plannedRuck.toJson());
      
      final createdPlannedRuck = PlannedRuck.fromJson(response['data']['planned_ruck'] as Map<String, dynamic>);
      AppLogger.info('Created planned ruck: ${createdPlannedRuck.id}');
      return createdPlannedRuck;
    } catch (e) {
      AppLogger.error('Error creating planned ruck: $e');
      throw Exception('Error creating planned ruck: $e');
    }
  }

  /// Update an existing planned ruck
  /// 
  /// Parameters:
  /// - [plannedRuckId]: ID of the planned ruck to update
  /// - [plannedRuck]: Updated planned ruck data
  Future<PlannedRuck> updatePlannedRuck(String plannedRuckId, PlannedRuck plannedRuck) async {
    try {
      final response = await _apiClient.put('/planned-rucks/$plannedRuckId', plannedRuck.toJson());

      final updatedPlannedRuck = PlannedRuck.fromJson(response['data']['planned_ruck'] as Map<String, dynamic>);
      AppLogger.info('Updated planned ruck: ${updatedPlannedRuck.id}');
      return updatedPlannedRuck;
    } catch (e) {
      AppLogger.error('Error updating planned ruck $plannedRuckId: $e');
      throw Exception('Error updating planned ruck: $e');
    }
  }

  /// Delete a planned ruck
  /// 
  /// Parameters:
  /// - [plannedRuckId]: ID of the planned ruck to delete
  Future<bool> deletePlannedRuck(String plannedRuckId) async {
    try {
      await _apiClient.delete('/planned-rucks/$plannedRuckId');
      
      AppLogger.info('Deleted planned ruck: $plannedRuckId');
      return true;
    } catch (e) {
      AppLogger.error('Error deleting planned ruck $plannedRuckId: $e');
      return false;
    }
  }

  /// Start a planned ruck (change status to in_progress)
  /// 
  /// Parameters:
  /// - [plannedRuckId]: ID of the planned ruck to start
  Future<PlannedRuck?> startPlannedRuck(String plannedRuckId) async {
    try {
      final response = await _apiClient.post('/planned-rucks/$plannedRuckId/start', {});

      final startedPlannedRuck = PlannedRuck.fromJson(response['data']['planned_ruck'] as Map<String, dynamic>);
      AppLogger.info('Started planned ruck: ${startedPlannedRuck.id}');
      return startedPlannedRuck;
    } catch (e) {
      AppLogger.error('Error starting planned ruck $plannedRuckId: $e');
      throw Exception('Error starting planned ruck: $e');
    }
  }

  /// Complete a planned ruck (change status to completed)
  /// 
  /// Parameters:
  /// - [plannedRuckId]: ID of the planned ruck to complete
  /// - [sessionId]: ID of the completed ruck session
  Future<PlannedRuck?> completePlannedRuck(String plannedRuckId, String sessionId) async {
    try {
      final requestBody = {
        'session_id': sessionId,
      };

      final response = await _apiClient.post('/planned-rucks/$plannedRuckId/complete', requestBody);
      
      final updatedPlannedRuck = PlannedRuck.fromJson(response['data']['planned_ruck'] as Map<String, dynamic>);
      AppLogger.info('Completed planned ruck: $plannedRuckId');
      return updatedPlannedRuck;
    } catch (e) {
      AppLogger.error('Error completing planned ruck $plannedRuckId: $e');
      throw Exception('Error completing planned ruck: $e');
    }
  }

  /// Cancel a planned ruck
  /// 
  /// Parameters:
  /// - [plannedRuckId]: ID of the planned ruck to cancel
  /// - [reason]: Optional reason for cancellation
  Future<PlannedRuck?> cancelPlannedRuck(String plannedRuckId, {String? reason}) async {
    try {
      final requestBody = <String, dynamic>{};
      if (reason?.isNotEmpty == true) {
        requestBody['reason'] = reason;
      }

      final response = await _apiClient.post('/planned-rucks/$plannedRuckId/cancel', requestBody);
      
      final updatedPlannedRuck = PlannedRuck.fromJson(response['data']['planned_ruck'] as Map<String, dynamic>);
      AppLogger.info('Cancelled planned ruck: $plannedRuckId');
      return updatedPlannedRuck;
    } catch (e) {
      AppLogger.error('Error cancelling planned ruck $plannedRuckId: $e');
      throw Exception('Error cancelling planned ruck: $e');
    }
  }

  /// Get planned rucks for today
  /// 
  /// Parameters:
  /// - [includeRoute]: Include full route data (default: true)
  Future<List<PlannedRuck>> getTodaysPlannedRucks({
    bool includeRoute = true,
  }) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));

      return await getPlannedRucks(
        fromDate: today,
        toDate: tomorrow,
        status: 'planned',
        includeRoute: includeRoute,
      );
    } catch (e) {
      AppLogger.error('Error getting today\'s planned rucks: $e');
      throw Exception('Error getting today\'s planned rucks: $e');
    }
  }

  /// Get upcoming planned rucks (next 7 days)
  /// 
  /// Parameters:
  /// - [includeRoute]: Include full route data (default: true)
  /// - [days]: Number of days to look ahead (default: 7)
  Future<List<PlannedRuck>> getUpcomingPlannedRucks({
    bool includeRoute = true,
    int days = 7,
  }) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final futureDate = today.add(Duration(days: days));

      return await getPlannedRucks(
        fromDate: today,
        toDate: futureDate,
        status: 'planned',
        includeRoute: includeRoute,
      );
    } catch (e) {
      AppLogger.error('Error getting upcoming planned rucks: $e');
      throw Exception('Error getting upcoming planned rucks: $e');
    }
  }

  /// Get completed planned rucks with analytics data
  /// 
  /// Parameters:
  /// - [limit]: Maximum number of completed rucks to return (default: 20)
  /// - [offset]: Number of completed rucks to skip for pagination (default: 0)
  /// - [includeRoute]: Include full route data (default: true)
  Future<List<PlannedRuck>> getCompletedPlannedRucks({
    int limit = 20,
    int offset = 0,
    bool includeRoute = true,
  }) async {
    try {
      return await getPlannedRucks(
        limit: limit,
        offset: offset,
        status: 'completed',
        includeRoute: includeRoute,
      );
    } catch (e) {
      AppLogger.error('Error getting completed planned rucks: $e');
      throw Exception('Error getting completed planned rucks: $e');
    }
  }

  /// Get overdue planned rucks
  /// 
  /// Parameters:
  /// - [includeRoute]: Include full route data (default: true)
  Future<List<PlannedRuck>> getOverduePlannedRucks({
    bool includeRoute = true,
  }) async {
    try {
      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));

      final plannedRucks = await getPlannedRucks(
        toDate: yesterday,
        status: 'planned',
        includeRoute: includeRoute,
      );

      // Filter for truly overdue rucks (those with planned times in the past)
      return plannedRucks.where((ruck) => ruck.isOverdue).toList();
    } catch (e) {
      AppLogger.error('Error getting overdue planned rucks: $e');
      throw Exception('Error getting overdue planned rucks: $e');
    }
  }



  /// Dispose of resources
  void dispose() {
    // ApiClient is managed by GetIt, no need to dispose
  }
}
