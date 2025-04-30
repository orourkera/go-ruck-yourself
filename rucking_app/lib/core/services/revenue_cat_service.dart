import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class RevenueCatService {
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    final apiKey = dotenv.env['REVENUECAT_API_KEY'] ?? 'YOUR_REVENUECAT_API_KEY'; // Use environment variable or fallback to placeholder
    await Purchases.configure(PurchasesConfiguration(apiKey));
    _isInitialized = true;
  }

  Future<List<Offering>> getOfferings() async {
    if (!_isInitialized) await initialize();
    final offerings = await Purchases.getOfferings();
    return offerings.all.values.toList();
  }

  Future<bool> makePurchase(Package package) async {
    if (!_isInitialized) await initialize();
    try {
      final purchaserInfo = await Purchases.purchasePackage(package);
      return purchaserInfo.entitlements.all.isNotEmpty;
    } catch (e) {
      print('Purchase error: $e');
      return false;
    }
  }

  Future<bool> checkSubscriptionStatus() async {
    if (!_isInitialized) await initialize();
    final customerInfo = await Purchases.getCustomerInfo();
    return customerInfo.entitlements.active.isNotEmpty;
  }

  Future<void> restorePurchases() async {
    if (!_isInitialized) await initialize();
    await Purchases.restorePurchases();
  }
}
