import 'package:rucking_app/core/services/revenue_cat_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

abstract class PremiumService {
  Future<bool> isPremium();
  Future<bool> purchasePremium();
  Future<bool> restorePurchases();
  Future<List<Offering>> getOfferings();
}

class PremiumServiceImpl implements PremiumService {
  final RevenueCatService _revenueCatService;

  PremiumServiceImpl(this._revenueCatService);

  @override
  Future<bool> isPremium() async {
    return await _revenueCatService.checkSubscriptionStatus();
  }

  @override
  Future<bool> purchasePremium() async {
    try {
      // Get offerings to find the premium package
      final offerings = await _revenueCatService.getOfferings();
      if (offerings.isEmpty) {
        return false;
      }

      // Get the first offering and its monthly package (or available package)
      final offering = offerings.first;
      Package? package;
      
      // Try to get monthly package first, fallback to any available package
      if (offering.monthly != null) {
        package = offering.monthly;
      } else if (offering.annual != null) {
        package = offering.annual;
      } else if (offering.availablePackages.isNotEmpty) {
        package = offering.availablePackages.first;
      }

      if (package == null) {
        return false;
      }

      return await _revenueCatService.makePurchase(package);
    } catch (e) {
      return false;
    }
  }

  @override
  Future<bool> restorePurchases() async {
    try {
      await _revenueCatService.restorePurchases();
      // Check if restore was successful by checking subscription status
      return await _revenueCatService.checkSubscriptionStatus();
    } catch (e) {
      return false;
    }
  }

  @override
  Future<List<Offering>> getOfferings() async {
    return await _revenueCatService.getOfferings();
  }
}