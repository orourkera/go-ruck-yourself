import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

class RevenueCatService {
  bool _isInitialized = false;
  bool get _isDebugMode => dotenv.env['REVENUECAT_DEBUG'] == 'true';

  RevenueCatService();

  Future<void> initialize() async {
    if (_isInitialized) return;
    if (_isDebugMode) {
      debugPrint('RevenueCatService: Debug mode enabled. Using mock offerings.');
      _isInitialized = true;
      return;
    }
    final apiKey = dotenv.env['REVENUECAT_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('REVENUECAT_API_KEY is missing from .env file');
    }
    await Purchases.configure(PurchasesConfiguration(apiKey));
    _isInitialized = true;
  }

  Future<List<Offering>> getOfferings() async {
    if (!_isInitialized) await initialize();
    if (_isDebugMode) {
      debugPrint('RevenueCatService: Returning mock offering.');
      return [_createMockOffering()];
    }
    final offerings = await Purchases.getOfferings();
    return offerings.all.values.toList();
  }

  Offering _createMockOffering() {
    final mockStoreProduct = StoreProduct(
      'mock_product',
      'Mock monthly subscription',
      'Monthly Premium',
      4.99,
      '\$4.99',
      'USD'
    );
    final mockPackage = Package(
      'mock_monthly',
      PackageType.monthly,
      mockStoreProduct,
      PresentedOfferingContext(
        'mock_offering',
        null,
        null,
      ),
    );
    return Offering(
      'mock_offering',
      'Mock Offering for Development',
      {
        'monthly': mockPackage,
      },
      [mockPackage],
    );
  }

  Future<bool> makePurchase(Package package) async {
    if (!_isInitialized) await initialize();
    if (_isDebugMode) {
      debugPrint('RevenueCatService: Simulating successful purchase in debug mode.');
      return true;
    }
    try {
      final customerInfo = await Purchases.purchasePackage(package);
      final isPurchased = customerInfo.entitlements.active.isNotEmpty;
      return isPurchased;
    } catch (e) {
      debugPrint('Error making purchase: $e');
      return false;
    }
  }

  Future<bool> checkSubscriptionStatus() async {
    if (!_isInitialized) await initialize();
    if (_isDebugMode) {
      debugPrint('RevenueCatService: Always returning false for subscription status in debug mode.');
      return false;
    }
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      return customerInfo.entitlements.active.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking subscription status: $e');
      return false;
    }
  }

  Future<void> restorePurchases() async {
    if (!_isInitialized) await initialize();
    if (_isDebugMode) {
      debugPrint('RevenueCatService: Simulating restore purchases in debug mode.');
      return;
    }
    try {
      await Purchases.restorePurchases();
    } catch (e) {
      debugPrint('Error restoring purchases: $e');
    }
  }
}
