import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:rucking_app/features/premium/domain/models/premium_status.dart';
import 'package:rucking_app/features/premium/domain/repositories/premium_repository.dart';
import 'package:rucking_app/core/services/revenue_cat_service.dart';

/// Implementation of premium repository using RevenueCat
class PremiumRepositoryImpl implements PremiumRepository {
  final RevenueCatService _revenueCatService;
  final StreamController<PremiumStatus> _statusController = StreamController.broadcast();
  
  PremiumStatus? _cachedStatus;

  PremiumRepositoryImpl(this._revenueCatService);

  @override
  Future<PremiumStatus> getPremiumStatus() async {
    if (_cachedStatus != null) {
      return _cachedStatus!;
    }
    
    return await refreshPremiumStatus();
  }

  @override
  Future<PremiumStatus> refreshPremiumStatus() async {
    try {
      // Check debug mode first
      if (await isDebugModeEnabled()) {
        _cachedStatus = PremiumStatus.pro();
        _statusController.add(_cachedStatus!);
        return _cachedStatus!;
      }

      // Get status from RevenueCat
      final isActive = await _revenueCatService.isSubscriptionActive();
      final customerInfo = await _revenueCatService.getCustomerInfo();
      
      if (isActive) {
        _cachedStatus = PremiumStatus.pro(
          subscriptionId: customerInfo?['originalAppUserId'] as String?,
          expiryDate: _parseExpiryDate(customerInfo),
        );
      } else {
        _cachedStatus = PremiumStatus.free();
      }
      
      _statusController.add(_cachedStatus!);
      return _cachedStatus!;
    } catch (e) {
      // Default to free on error
      _cachedStatus = PremiumStatus.free();
      _statusController.add(_cachedStatus!);
      return _cachedStatus!;
    }
  }

  @override
  Future<void> updatePremiumStatus(PremiumStatus status) async {
    _cachedStatus = status;
    _statusController.add(status);
  }

  @override
  Future<bool> hasFeatureAccess(String featureId) async {
    final status = await getPremiumStatus();
    return status.canAccessFeature(featureId);
  }

  @override
  Future<List<String>> getAvailableFeatures() async {
    final status = await getPremiumStatus();
    return status.unlockedFeatures;
  }

  @override
  Future<bool> isSubscriptionValid() async {
    try {
      return await _revenueCatService.isSubscriptionActive();
    } catch (e) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>?> getSubscriptionDetails() async {
    try {
      return await _revenueCatService.getCustomerInfo();
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> trackFeatureUsage(String featureId) async {
    // Track premium feature usage for analytics
    // This could be sent to analytics service
    debugPrint('Premium feature used: $featureId');
  }

  @override
  Future<bool> isDebugModeEnabled() async {
    // Check for debug mode premium bypass
    return kDebugMode && const bool.fromEnvironment('PREMIUM_DEBUG', defaultValue: false);
  }

  @override
  Stream<PremiumStatus> watchPremiumStatus() {
    return _statusController.stream;
  }

  DateTime? _parseExpiryDate(Map<String, dynamic>? customerInfo) {
    if (customerInfo == null) return null;
    
    try {
      final expiryString = customerInfo['expirationDate'] as String?;
      if (expiryString != null) {
        return DateTime.parse(expiryString);
      }
    } catch (e) {
      debugPrint('Error parsing expiry date: $e');
    }
    
    return null;
  }

  void dispose() {
    _statusController.close();
  }
}
