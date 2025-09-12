import 'package:flutter/material.dart';

typedef OnSelect = void Function(Map<String, dynamic> item,
    {required bool asWishlist});

class AddGearDialog extends StatefulWidget {
  final Future<List<dynamic>> Function(String query) onSearchCurated;
  final OnSelect onSelectCurated;
  final Future<List<dynamic>> Function(String query)? onSearchAmazon;
  final OnSelect? onSelectAmazon;
  const AddGearDialog(
      {super.key,
      required this.onSearchCurated,
      required this.onSelectCurated,
      this.onSearchAmazon,
      this.onSelectAmazon});

  @override
  State<AddGearDialog> createState() => _AddGearDialogState();
}

class _AddGearDialogState extends State<AddGearDialog> {
  final _controller = TextEditingController();
  List<dynamic> _results = [];
  List<dynamic> _amazon = [];
  bool _loading = false;
  bool _loadingAmazon = false;

  Future<void> _runSearch() async {
    setState(() => _loading = true);
    try {
      final r = await widget.onSearchCurated(_controller.text.trim());
      setState(() => _results = r);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _runAmazonSearch() async {
    if (widget.onSearchAmazon == null) return;
    setState(() => _loadingAmazon = true);
    try {
      final r = await widget.onSearchAmazon!(_controller.text.trim());
      setState(() => _amazon = r);
    } catch (_) {
      setState(() => _amazon = []);
    } finally {
      setState(() => _loadingAmazon = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasAmazon =
        widget.onSearchAmazon != null && widget.onSelectAmazon != null;
    return AlertDialog(
      title: const Text('Add Gear'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            decoration:
                const InputDecoration(hintText: 'Search curated gear...'),
            onSubmitted: (_) {
              _runSearch();
              if (hasAmazon) _runAmazonSearch();
            },
          ),
          const SizedBox(height: 12),
          if (hasAmazon)
            SizedBox(
              height: 260,
              width: 440,
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    const TabBar(
                        tabs: [Tab(text: 'Curated'), Tab(text: 'Amazon')]),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildCuratedList(),
                          _buildAmazonList(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            _buildCuratedList(),
          const SizedBox(height: 8),
          const Divider(),
          if (!hasAmazon) const Text('Amazon integration not enabled.'),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close')),
      ],
    );
  }

  Widget _buildCuratedList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return SizedBox(
      height: 200,
      width: 400,
      child: _results.isEmpty
          ? const Center(child: Text('No curated results'))
          : ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final it = _results[i] as Map<String, dynamic>;
                return ListTile(
                  leading: it['default_image_url'] != null
                      ? Image.network(it['default_image_url'],
                          width: 40, height: 40, fit: BoxFit.cover)
                      : const Icon(Icons.image_not_supported),
                  title: Text(it['name'] ?? 'Unnamed'),
                  subtitle: Text((it['brand'] ?? '') +
                      (it['model'] != null ? ' • ${it['model']}' : '')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () =>
                            widget.onSelectCurated(it, asWishlist: true),
                        child: const Text('Wishlist'),
                      ),
                      ElevatedButton(
                        onPressed: () =>
                            widget.onSelectCurated(it, asWishlist: false),
                        child: const Text('Own it'),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildAmazonList() {
    if (_loadingAmazon) return const Center(child: CircularProgressIndicator());
    if (widget.onSearchAmazon == null || widget.onSelectAmazon == null) {
      return const Center(child: Text('Amazon integration not configured'));
    }
    return SizedBox(
      height: 200,
      width: 400,
      child: _amazon.isEmpty
          ? const Center(child: Text('No Amazon results'))
          : ListView.builder(
              itemCount: _amazon.length,
              itemBuilder: (context, i) {
                final it = _amazon[i] as Map<String, dynamic>;
                return ListTile(
                  leading: it['image_url'] != null
                      ? Image.network(it['image_url'],
                          width: 40, height: 40, fit: BoxFit.cover)
                      : const Icon(Icons.shopping_cart_outlined),
                  title: Text(it['title'] ?? 'Item'),
                  subtitle: Text('ASIN: ${it['asin'] ?? '-'}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () =>
                            widget.onSelectAmazon!(it, asWishlist: true),
                        child: const Text('Wishlist'),
                      ),
                      ElevatedButton(
                        onPressed: () =>
                            widget.onSelectAmazon!(it, asWishlist: false),
                        child: const Text('Own it'),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
