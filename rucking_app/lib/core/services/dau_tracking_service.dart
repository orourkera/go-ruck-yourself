import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rucking_app/core/services/enhanced_api_client.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/core/models/user.dart';
import 'package:rucking_app/core/api/api_exceptions.dart';
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
    
    WidgetsBinding.instance.addObserver(this);
    
    // Wait for authentication to be fully ready
    await _waitForAuthenticationReady();
    
    AppLogger.debug('DAU tracking - Starting initialization');
    
    // Send any pending updates from previous app sessions
    await _sendPendingUpdate();
    
    // Track initial app open
    await _trackAppOpen();
    
    AppLogger.debug('DAU tracking - Initialization complete');
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
      // Double-check authentication state before making API calls
      final user = await _getValidatedUser();
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
      // Validate authentication before making API call
      final user = await _getValidatedUser();
      if (user == null) {
        AppLogger.debug('DAU tracking - No authenticated user, skipping update');
        return false;
      }
      
      // Additional validation - check if user has valid userId
      if (user.userId.isEmpty) {
        AppLogger.warning('DAU tracking - User has empty userId, skipping update');
        return false;
      }
      
      AppLogger.debug('DAU tracking - Sending update for user: ${user.userId}');
      
      await _apiClient.patch(
        '/users/${user.userId}',
        {'last_active_at': DateTime.now().toUtc().toIso8601String()},
        operationName: 'update_last_active',
      );
      
      AppLogger.info('✅ DAU tracking - last_active_at updated successfully');
      return true;
      
    } catch (e) {
      return await _handleApiError(e);
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
  
  /// Wait for authentication to be fully ready before making API calls
  Future<void> _waitForAuthenticationReady() async {
    final authBloc = GetIt.instance<AuthBloc>();
    
    // Wait up to 10 seconds for authentication to complete
    for (int i = 0; i < 40; i++) {
      final currentState = authBloc.state;
      
      if (currentState is Authenticated) {
        AppLogger.debug('DAU tracking - Authentication confirmed ready');
        return;
      } else if (currentState is Unauthenticated || currentState is AuthError) {
        AppLogger.debug('DAU tracking - User not authenticated, skipping');
        return;
      }
      
      // AuthInitial or AuthLoading - wait a bit more
      await Future.delayed(const Duration(milliseconds: 250));
    }
    
    AppLogger.warning('DAU tracking - Timeout waiting for authentication state');
  }
  
  /// Get validated user ensuring authentication state is consistent
  Future<User?> _getValidatedUser() async {
    try {
      final authBloc = GetIt.instance<AuthBloc>();
      final currentState = authBloc.state;
      
      // First check: Ensure AuthBloc shows user as authenticated
      if (currentState is! Authenticated) {
        AppLogger.debug('DAU tracking - AuthBloc state is not Authenticated: ${currentState.runtimeType}');
        return null;
      }
      
      // Second check: Verify AuthService agrees
      final user = await _authService.getCurrentUser();
      if (user == null) {
        AppLogger.warning('DAU tracking - AuthBloc shows authenticated but AuthService returned null');
        return null;
      }
      
      // Third check: Ensure user data is consistent
      if (user.userId != currentState.user.userId) {
        AppLogger.warning('DAU tracking - User ID mismatch between AuthBloc and AuthService');
        return null;
      }
      
      return user;
    } catch (e) {
      AppLogger.error('DAU tracking - Error validating user: $e');
      return null;
    }
  }
  
  /// Handle API errors with proper authentication recovery
  Future<bool> _handleApiError(dynamic error) async {
    if (error is UnauthorizedException || 
        error.toString().contains('Not authenticated') ||
        error.toString().contains('UnauthorizedException')) {
      
      AppLogger.warning('DAU tracking - Authentication error detected: $error');
      
      // Try to refresh the token
      try {
        final refreshedToken = await _authService.refreshToken();
        if (refreshedToken != null) {
          AppLogger.info('DAU tracking - Token refreshed successfully, retrying operation');
          // Token refreshed, let the retry happen on next app cycle
          return false;
        }
      } catch (refreshError) {
        AppLogger.error('DAU tracking - Token refresh failed: $refreshError');
      }
      
      // If token refresh failed, trigger re-authentication
      try {
        final authBloc = GetIt.instance<AuthBloc>();
        AppLogger.info('DAU tracking - Triggering authentication check due to auth error');
        authBloc.add(AuthCheckRequested());
      } catch (e) {
        AppLogger.error('DAU tracking - Failed to trigger auth check: $e');
      }
      
      return false;
    }
    
    // Handle other types of errors
    if (error.toString().contains('ServerException')) {
      AppLogger.error('DAU tracking - Server error (likely auth/permissions): $error');
    } else if (error.toString().contains('TimeoutException')) {
      AppLogger.warning('DAU tracking - Request timeout: $error');
    } else {
      AppLogger.warning('DAU tracking - Failed to update last_active_at: $error');
    }
    
    return false;
  }
}
