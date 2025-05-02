import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';

part 'session_history_event.dart';
part 'session_history_state.dart';

class SessionHistoryBloc extends Bloc<SessionHistoryEvent, SessionHistoryState> {
  final ApiClient _apiClient;
  
  SessionHistoryBloc({required ApiClient apiClient}) 
      : _apiClient = apiClient,
        super(SessionHistoryInitial()) {
    on<LoadSessionHistory>(_onLoadSessionHistory);
    on<FilterSessionHistory>(_onFilterSessionHistory);
  }
  
  Future<void> _onLoadSessionHistory(
    LoadSessionHistory event, 
    Emitter<SessionHistoryState> emit
  ) async {
    emit(SessionHistoryLoading());
    
    try {
      // Build endpoint based on filter
      String endpoint = '/rucks';
      
      if (event.filter != null) {
        switch (event.filter) {
          case SessionFilter.thisWeek:
            final now = DateTime.now();
            final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
            final startDate = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
            endpoint = '/rucks?start_date=${startDate.toIso8601String()}';
            break;
          case SessionFilter.thisMonth:
            final now = DateTime.now();
            final startOfMonth = DateTime(now.year, now.month, 1);
            endpoint = '/rucks?start_date=${startOfMonth.toIso8601String()}';
            break;
          case SessionFilter.lastMonth:
            final now = DateTime.now();
            final startOfLastMonth = DateTime(now.year, now.month - 1, 1);
            final endOfLastMonth = DateTime(now.year, now.month, 0);
            endpoint = '/rucks?start_date=${startOfLastMonth.toIso8601String()}&end_date=${endOfLastMonth.toIso8601String()}';
            break;
          case SessionFilter.custom:
            if (event.customStartDate != null && event.customEndDate != null) {
              endpoint = '/rucks?start_date=${event.customStartDate!.toIso8601String()}&end_date=${event.customEndDate!.toIso8601String()}';
            }
            break;
          case SessionFilter.all:
          default:
            // Default endpoint is all sessions
            break;
        }
      }
      
      AppLogger.info('Fetching sessions with endpoint: $endpoint');
      final response = await _apiClient.get(endpoint);
      
      List<dynamic> sessionsList = [];
      
      // Handle different response formats from the API
      if (response == null) {
        sessionsList = [];
      } else if (response is List) {
        sessionsList = response;
      } else if (response is Map) {
        // Look for common API response patterns
        if (response.containsKey('data')) {
          sessionsList = response['data'] as List;
        } else if (response.containsKey('sessions')) {
          sessionsList = response['sessions'] as List;
        } else if (response.containsKey('items')) {
          sessionsList = response['items'] as List;
        } else if (response.containsKey('results')) {
          sessionsList = response['results'] as List;
        } else {
          // Try to find any List in the response
          for (final key in response.keys) {
            if (response[key] is List) {
              sessionsList = response[key] as List;
              break;
            }
          }
          
          if (sessionsList.isEmpty) {
            AppLogger.warning('Unexpected response format from API');
          }
        }
      } else {
        AppLogger.warning('Unknown response type from API');
      }
      
      // Convert to RuckSession objects
      final sessions = sessionsList
          .map((session) => RuckSession.fromJson(session))
          .toList();
          
      // Sort by date (newest first)
      sessions.sort((a, b) => b.startTime.compareTo(a.startTime));
      
      emit(SessionHistoryLoaded(sessions: sessions));
    } catch (e) {
      AppLogger.error('Error fetching sessions: $e');
      emit(SessionHistoryError(message: e.toString()));
    }
  }
  
  Future<void> _onFilterSessionHistory(
    FilterSessionHistory event, 
    Emitter<SessionHistoryState> emit
  ) async {
    // Simply call LoadSessionHistory with the filter
    add(LoadSessionHistory(filter: event.filter));
  }
}
