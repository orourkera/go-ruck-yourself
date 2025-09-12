import 'dart:io' show Platform;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class RevenueCatService {
  bool _isInitialized = false;
  bool _forceDebugMode = false; // Fallback debug mode when dotenv fails

  bool get _isDebugMode {
    if (_forceDebugMode) return true;
    try {
      return dotenv.env['REVENUECAT_DEBUG'] == 'true';
    } catch (e) {
      // If dotenv isn't initialized, assume production mode
      return false;
    }
  }

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
    try {
      if (Platform.isIOS) {
        apiKey = dotenv.env['REVENUECAT_API_KEY_IOS'];
        debugPrint('RevenueCatService: Using iOS API key');
      } else if (Platform.isAndroid) {
        apiKey = dotenv.env['REVENUECAT_API_KEY_ANDROID'];
        debugPrint('RevenueCatService: Using Android API key');
      } else {
        apiKey = dotenv.env['REVENUECAT_API_KEY']; // Fallback
      }
    } catch (e) {
      debugPrint('RevenueCat: Could not access dotenv, using debug mode: $e');
      _forceDebugMode = true;
      _isInitialized = true;
      return;
    }

    if (apiKey == null || apiKey.isEmpty) {
      debugPrint(
          'RevenueCat: API key is missing from .env file, using debug mode');
      _forceDebugMode = true;
      _isInitialized = true;
      return;
    }

    try {
      // Disable RevenueCat debug logs for production
      Purchases.setDebugLogsEnabled(false);
      await Purchases.configure(PurchasesConfiguration(apiKey));
      _isInitialized = true;
      debugPrint('RevenueCat initialized successfully');
    } catch (e) {
      debugPrint('RevenueCat initialization failed: $e');
      // Don't throw - gracefully degrade to debug mode behavior
      _isInitialized = false;
      throw Exception('Failed to initialize RevenueCat: $e');
    }
  }

  Future<List<Offering>> getOfferings() async {
    try {
      if (!_isInitialized) await initialize();
      if (_isDebugMode) {
        debugPrint('RevenueCatService: Returning mock offering.');
        return [_createMockOffering()];
      }
      final offerings = await Purchases.getOfferings();
      return offerings.all.values.toList();
    } catch (e) {
      debugPrint('Error getting offerings: $e');
      // Return mock offering as fallback
      return [_createMockOffering()];
    }
  }

  Offering _createMockOffering() {
    final mockStoreProduct = StoreProduct('mock_product',
        'Mock monthly subscription', 'Monthly Premium', 4.99, '\$4.99', 'USD');
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
    try {
      if (!_isInitialized) await initialize();
      if (_isDebugMode) {
        debugPrint(
            'RevenueCatService: Simulating successful purchase in debug mode.');
        _mockUserSubscribed = true; // Set mock subscription to true
        return true;
      }

      final customerInfo = await Purchases.purchasePackage(package);
      final isPurchased = customerInfo.entitlements.active.isNotEmpty;
      debugPrint('Purchase completed successfully: $isPurchased');
      return isPurchased;
    } on PlatformException catch (e) {
      debugPrint('Platform error during purchase: ${e.code} - ${e.message}');
      // Handle specific billing errors
      if (e.code == 'BILLING_UNAVAILABLE' ||
          e.code == 'SERVICE_UNAVAILABLE' ||
          e.message?.contains('PendingIntent') == true) {
        debugPrint(
            'Billing service unavailable or corrupted - graceful fallback');
      }
      return false;
    } catch (e) {
      debugPrint('Unexpected error making purchase: $e');
      return false;
    }
  }

  Future<bool> checkSubscriptionStatus() async {
    if (!_isInitialized) await initialize();
    if (_isDebugMode) {
      debugPrint(
          'RevenueCatService: Returning mock subscription status: $_mockUserSubscribed');
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
      debugPrint(
          'RevenueCatService: Simulating restore purchases in debug mode.');
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
