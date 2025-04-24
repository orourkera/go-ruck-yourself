import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class PaywallScreen extends StatefulWidget {
  final VoidCallback onSubscribed;
  const PaywallScreen({Key? key, required this.onSubscribed}) : super(key: key);

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  Offerings? _offerings;
  bool _loading = true;
  String? _error;
  bool _purchasing = false;

  @override
  void initState() {
    super.initState();
    _fetchOfferings();
  }

  Future<void> _fetchOfferings() async {
    setState(() { _loading = true; _error = null; });
    try {
      // final offerings = await Purchases.getOfferings();
      // setState(() {
      //   _offerings = offerings;
      //   _loading = false;
      // });
      setState(() {
        _offerings = null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load plans. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _purchase(Package package) async {
    setState(() { _purchasing = true; _error = null; });
    try {
      await Purchases.purchasePackage(package);
      widget.onSubscribed();
    } catch (e) {
      setState(() {
        _error = 'Purchase failed or cancelled.';
      });
    } finally {
      setState(() { _purchasing = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : _error != null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchOfferings,
                          child: const Text('Retry'),
                        ),
                      ],
                    )
                  : _offerings?.current == null || _offerings!.current!.availablePackages.isEmpty
                      ? const Text('No subscriptions available.')
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Get Full Access',
                              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            ..._offerings!.current!.availablePackages.map((pkg) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                                  child: ElevatedButton(
                                    onPressed: _purchasing ? null : () => _purchase(pkg),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                      textStyle: const TextStyle(fontSize: 18),
                                    ),
                                    child: Column(
                                      children: [
                                        Text(pkg.storeProduct.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        Text(pkg.storeProduct.priceString),
                                        if (pkg.storeProduct.introductoryPrice != null)
                                          Text('7-day free trial', style: TextStyle(color: Colors.green[700])),
                                      ],
                                    ),
                                  ),
                                )),
                            if (_purchasing) const Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(),
                            ),
                          ],
                        ),
        ),
      ),
    );
  }
}
