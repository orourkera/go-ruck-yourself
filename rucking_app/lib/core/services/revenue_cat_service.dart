import 'dart:io' show Platform;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

class RevenueCatService {
  bool _isInitialized = false;
  bool get _isDebugMode => dotenv.env['REVENUECAT_DEBUG'] == 'true';

  // New flag for managing mock subscription state in debug mode
  bool _mockUserSubscribed = false;

  RevenueCatService();

  Future<void> initialize() async {
    if (_isInitialized) return;
    if (_isDebugMode) {
      debugPrint('RevenueCatService: Debug mode enabled.');
      // In a more advanced scenario, you might load _mockUserSubscribed from prefs
      _isInitialized = true;
      return;
    }
    String? apiKey;
    if (Platform.isIOS) {
      apiKey = dotenv.env['REVENUECAT_API_KEY_IOS'];
      debugPrint('RevenueCatService: Using iOS API key');
    } else if (Platform.isAndroid) {
      apiKey = dotenv.env['REVENUECAT_API_KEY_ANDROID'];
      debugPrint('RevenueCatService: Using Android API key');
    } else {
      apiKey = dotenv.env['REVENUECAT_API_KEY']; // Fallback
    }
    
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('RevenueCat API key is missing from .env file for this platform');
    }
    
    // Disable RevenueCat debug logs for production
    Purchases.setDebugLogsEnabled(false);
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
      _mockUserSubscribed = true; // Set mock subscription to true
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
      debugPrint('RevenueCatService: Returning mock subscription status: $_mockUserSubscribed');
      return _mockUserSubscribed; // Return the state of the mock subscription
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
      _mockUserSubscribed = true; // Assume restore finds a subscription
      return;
    }
    try {
      await Purchases.restorePurchases();
    } catch (e) {
      debugPrint('Error restoring purchases: $e');
    }
  }

  // Optional: A helper to reset mock status for testing different scenarios without app restart
  void resetMockSubscriptionStatusForDebug() {
    if (_isDebugMode) {
      _mockUserSubscribed = false;
      debugPrint('RevenueCatService: Mock subscription status reset.');
    }
  }
}
