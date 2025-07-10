import 'package:flutter/foundation.dart';
import '../utils/app_logger.dart';
import 'storage_service.dart';

/// Feature flags for controlling feature rollout
class FeatureFlags {
  static const String _storageKeyPrefix = 'feature_flag_';
  
  // Feature flag keys
  static const String useRefactoredActiveSessionBloc = 'use_refactored_active_session_bloc';
  
  final StorageService _storageService;
  final Map<String, bool> _defaultValues = {
    useRefactoredActiveSessionBloc: true, // Enable new implementation for testing
  };
  
  // Cache for performance
  final Map<String, bool> _cache = {};
  
  FeatureFlags(this._storageService);
  
  /// Initialize feature flags from storage
  Future<void> initialize() async {
    AppLogger.info('[FEATURE_FLAGS] Initializing feature flags');
    
    for (final key in _defaultValues.keys) {
      final storedValue = await _storageService.getBool('$_storageKeyPrefix$key');
      _cache[key] = storedValue ?? _defaultValues[key]!;
      AppLogger.info('[FEATURE_FLAGS] $key: ${_cache[key]}');
    }
  }
  
  /// Check if a feature is enabled
  bool isEnabled(String featureKey) {
    final value = _cache[featureKey] ?? _defaultValues[featureKey] ?? false;
    return value;
  }
  
  /// Set a feature flag value
  Future<void> setFeatureFlag(String featureKey, bool value) async {
    AppLogger.info('[FEATURE_FLAGS] Setting $featureKey to $value');
    
    _cache[featureKey] = value;
    await _storageService.setBool('$_storageKeyPrefix$featureKey', value);
  }
  
  /// Get all feature flags
  Map<String, bool> getAllFlags() {
    return Map.from(_cache);
  }
  
  /// Reset all feature flags to default values
  Future<void> resetAllFlags() async {
    AppLogger.info('[FEATURE_FLAGS] Resetting all feature flags to defaults');
    
    for (final entry in _defaultValues.entries) {
      await setFeatureFlag(entry.key, entry.value);
    }
  }
  
  /// Enable refactored ActiveSessionBloc for testing
  Future<void> enableRefactoredActiveSessionBloc() async {
    await setFeatureFlag(useRefactoredActiveSessionBloc, true);
  }
  
  /// Disable refactored ActiveSessionBloc (use old implementation)
  Future<void> disableRefactoredActiveSessionBloc() async {
    await setFeatureFlag(useRefactoredActiveSessionBloc, false);
  }
  
  /// Check if we should use the refactored ActiveSessionBloc
  bool get shouldUseRefactoredActiveSessionBloc {
    // Force new implementation in debug mode for testing
    if (kDebugMode && const bool.fromEnvironment('FORCE_NEW_BLOC', defaultValue: false)) {
      print('[FEATURE_FLAGS] FORCE_NEW_BLOC environment variable is true');
      return true;
    }
    
    // Temporarily force enable for debugging session completion
    if (kDebugMode) {
      print('[FEATURE_FLAGS] Debug mode detected, forcing refactored bloc to true');
      return true;
    }
    
    final result = isEnabled(useRefactoredActiveSessionBloc);
    print('[FEATURE_FLAGS] shouldUseRefactoredActiveSessionBloc result: $result');
    return result;
  }
}
