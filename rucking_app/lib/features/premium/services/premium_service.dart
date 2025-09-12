import 'package:flutter/foundation.dart';
import 'package:rucking_app/core/services/revenue_cat_service.dart';

/// Simple premium service that just checks RevenueCat status
class PremiumService {
  final RevenueCatService _revenueCatService;

  // Cache premium status for 5 minutes to avoid repeated API calls
  bool? _cachedStatus;
  DateTime? _lastCheck;
  static const _cacheDuration = Duration(minutes: 5);

  PremiumService(this._revenueCatService);

  /// Check if user has premium subscription
  Future<bool> isPremium({bool forceRefresh = false}) async {
    // Debug bypass for testing
    if (kDebugMode &&
        const bool.fromEnvironment('PREMIUM_BYPASS', defaultValue: false)) {
      return true;
    }

    // Use cache if valid and not forcing refresh
    if (!forceRefresh &&
        _cachedStatus != null &&
        _lastCheck != null &&
        DateTime.now().difference(_lastCheck!) < _cacheDuration) {
      return _cachedStatus!;
    }

    try {
      final isPremium = await _revenueCatService.checkSubscriptionStatus();
      _cachedStatus = isPremium;
      _lastCheck = DateTime.now();
      debugPrint(
          'Premium status checked: $isPremium (forceRefresh: $forceRefresh)');
      return isPremium;
    } catch (e) {
      debugPrint('Error checking premium status: $e');
      return false; // Default to free on error
    }
  }

  /// Purchase premium subscription
  Future<bool> purchasePremium() async {
    try {
      final offerings = await _revenueCatService.getOfferings();
      if (offerings.isEmpty) return false;

      final package = offerings.first.monthly ??
          offerings.first.annual ??
          offerings.first.availablePackages.firstOrNull;

      if (package == null) return false;

      final success = await _revenueCatService.makePurchase(package);
      if (success) {
        _cachedStatus = true; // Update cache on successful purchase
        _lastCheck = DateTime.now();
      }
      return success;
    } catch (e) {
      debugPrint('Error purchasing premium: $e');
      return false;
    }
  }

  /// Restore previous purchases
  Future<bool> restorePurchases() async {
    try {
      await _revenueCatService.restorePurchases();
      _cachedStatus = null; // Clear cache to force fresh check
      return await isPremium();
    } catch (e) {
      debugPrint('Error restoring purchases: $e');
      return false;
    }
  }

  /// Clear cache (useful for logout or forcing subscription status refresh)
  void clearCache() {
    _cachedStatus = null;
    _lastCheck = null;
    debugPrint('Premium status cache cleared');
  }
}
