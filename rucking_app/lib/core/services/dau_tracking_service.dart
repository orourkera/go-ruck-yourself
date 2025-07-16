import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rucking_app/core/services/enhanced_api_client.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:get_it/get_it.dart';

/// Service for tracking Daily Active Users (DAU) via app foreground detection
class DauTrackingService with WidgetsBindingObserver {
  static const String _lastActiveKey = 'last_active_update';
  static const String _pendingUpdateKey = 'pending_active_update';
  static const Duration _updateCooldown = Duration(hours: 23);
  
  final EnhancedApiClient _apiClient = GetIt.instance<EnhancedApiClient>();
  final AuthService _authService = GetIt.instance<AuthService>();
  
  static DauTrackingService? _instance;
  
  /// Singleton instance
  static DauTrackingService get instance {
    _instance ??= DauTrackingService._internal();
    return _instance!;
  }
  
  DauTrackingService._internal();
  
  /// Initialize the service and start listening for app lifecycle changes
  Future<void> initialize() async {
    AppLogger.info('Initializing DAU tracking service');
    
    // Register as lifecycle observer
    WidgetsBinding.instance.addObserver(this);
    
    // Send any pending updates from previous app sessions
    await _sendPendingUpdate();
    
    // Track initial app open
    await _trackAppOpen();
  }
  
  /// Clean up resources
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      AppLogger.info('App resumed - checking DAU tracking');
      _trackAppOpen();
    }
  }
  
  /// Track app open and update last_active_at if needed
  Future<void> _trackAppOpen() async {
    try {
      final user = await _authService.getCurrentUser();
      if (user == null) {
        AppLogger.debug('No authenticated user - skipping DAU tracking');
        return;
      }
      
      final prefs = await SharedPreferences.getInstance();
      final lastUpdateStr = prefs.getString(_lastActiveKey);
      
      DateTime? lastUpdate;
      if (lastUpdateStr != null) {
        lastUpdate = DateTime.tryParse(lastUpdateStr);
      }
      
      final now = DateTime.now();
      
      // Check if we need to update (first time or > 23 hours since last update)
      if (lastUpdate == null || now.difference(lastUpdate) > _updateCooldown) {
        AppLogger.info('Updating last_active_at (last update: ${lastUpdate?.toIso8601String() ?? 'never'})');
        
        // Try to send update immediately
        final success = await _sendLastActiveUpdate();
        
        if (success) {
          // Update local timestamp on success
          await prefs.setString(_lastActiveKey, now.toIso8601String());
          await prefs.remove(_pendingUpdateKey);
        } else {
          // Store pending update for later
          await prefs.setString(_pendingUpdateKey, now.toIso8601String());
        }
      } else {
        AppLogger.debug('DAU tracking cooldown active - skipping update');
      }
    } catch (e) {
      AppLogger.error('Error in DAU tracking', exception: e);
    }
  }
  
  /// Send last_active_at update to the backend
  Future<bool> _sendLastActiveUpdate() async {
    try {
      final user = await _authService.getCurrentUser();
      if (user == null) return false;
      
      await _apiClient.put(
        '/users/${user.userId}',
        {'last_active_at': DateTime.now().toUtc().toIso8601String()},
        operationName: 'update_last_active',
      );
      
      AppLogger.info('✅ DAU tracking - last_active_at updated successfully');
      return true;
      
    } catch (e) {
      AppLogger.warning('Failed to update last_active_at: $e');
      return false;
    }
  }
  
  /// Send any pending updates from previous app sessions
  Future<void> _sendPendingUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingUpdateStr = prefs.getString(_pendingUpdateKey);
      
      if (pendingUpdateStr != null) {
        AppLogger.info('Found pending DAU update - attempting to send');
        
        final success = await _sendLastActiveUpdate();
        
        if (success) {
          await prefs.setString(_lastActiveKey, pendingUpdateStr);
          await prefs.remove(_pendingUpdateKey);
          AppLogger.info('✅ Pending DAU update sent successfully');
        } else {
          AppLogger.warning('Failed to send pending DAU update - will retry later');
        }
      }
    } catch (e) {
      AppLogger.error('Error sending pending DAU update', exception: e);
    }
  }
  
  /// Force update last_active_at (for testing or manual triggers)
  Future<bool> forceUpdate() async {
    AppLogger.info('Force updating DAU tracking');
    
    final success = await _sendLastActiveUpdate();
    
    if (success) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastActiveKey, DateTime.now().toIso8601String());
      await prefs.remove(_pendingUpdateKey);
    }
    
    return success;
  }
}
