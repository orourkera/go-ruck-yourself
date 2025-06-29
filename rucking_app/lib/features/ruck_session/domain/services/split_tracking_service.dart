import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/models/user.dart';
import 'package:rucking_app/core/services/watch_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';

/// Service for tracking distance milestones (splits) during ruck sessions
/// and sending notifications to the watch when milestones are reached
class SplitTrackingService {
  final WatchService _watchService;
  
  // Split tracking variables
  double _lastSplitDistanceKm = 0.0; // Last completed split distance in km
  DateTime? _lastSplitTime; // Time when last split was recorded
  List<Map<String, dynamic>> _splits = []; // History of all splits
  
  SplitTrackingService({required WatchService watchService}) 
      : _watchService = watchService;
  
  /// Reset all split tracking variables (called when starting a new session)
  void reset() {
    _lastSplitDistanceKm = 0.0;
    _lastSplitTime = null;
    _splits = [];
    AppLogger.info('[SPLITS] Split tracking service reset');
  }
  
  /// Get all recorded splits
  List<Map<String, dynamic>> getSplits() {
    print('[DEBUG] SplitTrackingService.getSplits() called');
    print('[DEBUG] Current splits count: ${_splits.length}');
    if (_splits.isNotEmpty) {
      print('[DEBUG] Splits data: $_splits');
    }
    return _splits;
  }
  
  /// Check if a distance milestone has been reached and send a notification to the watch
  Future<void> checkForMilestone({
    required double currentDistanceKm,
    required DateTime sessionStartTime,
    required int elapsedSeconds,
    required bool isPaused,
  }) async {
    if (isPaused) return; // Don't check for milestones during pauses
    
    // Get user preference for metric vs imperial
    try {
      final authBloc = GetIt.instance<AuthBloc>();
      final bool preferMetric = authBloc.state is Authenticated ? 
          (authBloc.state as Authenticated).user.preferMetric : true;
      
      AppLogger.debug('[SPLITS] User preferMetric preference: $preferMetric');
      
      // Set the split distance based on user preference
      // TEMPORARY: Using 0.01km (10 meters) for testing instead of 1km/1mi
      final double splitDistanceKm = 0.01; // 10 meters for testing
      // final double splitDistanceKm = preferMetric ? 1.0 : 1.609; // 1km or 1mi (in km)
      
      AppLogger.debug('[SPLITS] Split distance in km: $splitDistanceKm (${preferMetric ? "1km" : "1mi"})');
      
      // Calculate current milestone based on total distance
      final int currentMilestoneIndex = (currentDistanceKm / splitDistanceKm).floor();
      final double nextMilestoneDistanceKm = (currentMilestoneIndex + 1) * splitDistanceKm;
      
      // Debug logging for split detection
      AppLogger.sessionCompletion('Split milestone check', context: {
        'current_distance_km': currentDistanceKm,
        'split_distance_km': splitDistanceKm,
        'current_milestone_index': currentMilestoneIndex,
        'last_split_distance_km': _lastSplitDistanceKm,
        'milestone_threshold': currentMilestoneIndex * splitDistanceKm,
        'splits_count': _splits.length,
      });
      
      // Check if we've passed a new milestone
      if (currentMilestoneIndex > 0 && 
          _lastSplitDistanceKm < (currentMilestoneIndex * splitDistanceKm)) {
        
        AppLogger.sessionCompletion('Distance milestone reached!', context: {
          'milestone_km': currentMilestoneIndex * splitDistanceKm,
          'unit': preferMetric ? 'km' : 'mi',
          'splits_before': _splits.length,
        });
        
        // Calculate split duration (time since last split)
        final DateTime splitEndTime = DateTime.now();
        final DateTime splitStartTime = _lastSplitTime ?? sessionStartTime;
        final Duration splitDuration = splitEndTime.difference(splitStartTime);
        
        // Record this split info
        final splitInfo = {
          'splitNumber': currentMilestoneIndex,
          'splitDistance': 1.0, // Always 1.0 as it represents 1km or 1mi
          'splitDurationSeconds': splitDuration.inSeconds, // Convert Duration to seconds
          'totalDistance': preferMetric ? currentDistanceKm : currentDistanceKm / 1.609, // Convert to mi if needed
          'totalDurationSeconds': elapsedSeconds, // Use seconds instead of Duration
          'timestamp': splitEndTime.toIso8601String(), // Convert DateTime to string
        };
        _splits.add(splitInfo);
        
        AppLogger.sessionCompletion('Split recorded', context: {
          'split_info': splitInfo,
          'total_splits': _splits.length,
        });
        
        // Update last split info for next calculation
        _lastSplitDistanceKm = currentMilestoneIndex * splitDistanceKm;
        _lastSplitTime = splitEndTime;
        
        // Send notification to the watch
        await _watchService.sendSplitNotification(
          splitDistance: 1.0, // Always show as 1.0 (represents 1km or 1mi based on isMetric flag)
          splitDuration: splitDuration,
          totalDistance: preferMetric ? currentDistanceKm : currentDistanceKm / 1.609, // Convert to mi if needed
          totalDuration: Duration(seconds: elapsedSeconds),
          isMetric: preferMetric,
        );
        
        AppLogger.sessionCompletion('Split notification sent to watch', context: {
          'split_number': currentMilestoneIndex,
        });
      }
    } catch (e) {
      AppLogger.sessionCompletion('Error checking for distance milestone', context: {
        'error': e.toString(),
        'current_distance_km': currentDistanceKm,
      });
    }
  }
}
