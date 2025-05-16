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
  List<Map<String, dynamic>> getSplits() => _splits;
  
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
      
      // Set the split distance based on user preference
      final double splitDistanceKm = preferMetric ? 1.0 : 1.609; // 1km or 1mi (in km)
      
      // Calculate current milestone based on total distance
      final int currentMilestoneIndex = (currentDistanceKm / splitDistanceKm).floor();
      final double nextMilestoneDistanceKm = (currentMilestoneIndex + 1) * splitDistanceKm;
      
      // Check if we've passed a new milestone
      if (currentMilestoneIndex > 0 && 
          _lastSplitDistanceKm < (currentMilestoneIndex * splitDistanceKm)) {
        
        AppLogger.info('[SPLITS] Distance milestone reached! ${currentMilestoneIndex * splitDistanceKm} ${preferMetric ? 'km' : 'mi'} completed');
        
        // Calculate split duration (time since last split)
        final DateTime splitEndTime = DateTime.now();
        final DateTime splitStartTime = _lastSplitTime ?? sessionStartTime;
        final Duration splitDuration = splitEndTime.difference(splitStartTime);
        
        // Record this split info
        final splitInfo = {
          'splitNumber': currentMilestoneIndex,
          'splitDistance': preferMetric ? 1.0 : 1.0, // 1km or 1mi as displayed value
          'splitDuration': splitDuration,
          'totalDistance': preferMetric ? currentDistanceKm : currentDistanceKm / 1.609, // Convert to mi if needed
          'totalDuration': Duration(seconds: elapsedSeconds),
          'timestamp': splitEndTime,
        };
        _splits.add(splitInfo);
        
        // Update last split info for next calculation
        _lastSplitDistanceKm = currentMilestoneIndex * splitDistanceKm;
        _lastSplitTime = splitEndTime;
        
        // Send notification to the watch
        await _watchService.sendSplitNotification(
          splitDistance: preferMetric ? 1.0 : 1.0, // Always show as 1.0 (km or mi)
          splitDuration: splitDuration,
          totalDistance: preferMetric ? currentDistanceKm : currentDistanceKm / 1.609, // Convert to mi if needed
          totalDuration: Duration(seconds: elapsedSeconds),
          isMetric: preferMetric,
        );
        
        AppLogger.info('[SPLITS] Split notification sent to watch');
      }
    } catch (e) {
      AppLogger.error('[SPLITS] Error checking for distance milestone: $e');
    }
  }
}
