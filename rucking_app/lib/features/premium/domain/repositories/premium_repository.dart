import 'package:rucking_app/features/premium/domain/models/premium_status.dart';

/// Repository interface for premium feature data access
abstract class PremiumRepository {
  /// Get current premium status for the user
  Future<PremiumStatus> getPremiumStatus();
  
  /// Update premium status (usually from RevenueCat)
  Future<void> updatePremiumStatus(PremiumStatus status);
  
  /// Check if user has access to specific feature
  Future<bool> hasFeatureAccess(String featureId);
  
  /// Get premium features available for current tier
  Future<List<String>> getAvailableFeatures();
  
  /// Refresh premium status from remote source (RevenueCat)
  Future<PremiumStatus> refreshPremiumStatus();
  
  /// Check subscription validity
  Future<bool> isSubscriptionValid();
  
  /// Get subscription details
  Future<Map<String, dynamic>?> getSubscriptionDetails();
  
  /// Track premium feature usage for analytics
  Future<void> trackFeatureUsage(String featureId);
  
  /// Check if user is in test/debug mode for premium bypass
  Future<bool> isDebugModeEnabled();
  
  /// Stream of premium status changes
  Stream<PremiumStatus> watchPremiumStatus();
}
