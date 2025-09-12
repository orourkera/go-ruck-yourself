import 'package:flutter/material.dart';

typedef OnSelect = void Function(Map<String, dynamic> item, {required bool asWishlist});

class AddGearDialog extends StatefulWidget {
  final Future<List<dynamic>> Function(String query) onSearchCurated;
  final OnSelect onSelectCurated;
  const AddGearDialog({super.key, required this.onSearchCurated, required this.onSelectCurated});

  @override
  State<AddGearDialog> createState() => _AddGearDialogState();
}

class _AddGearDialogState extends State<AddGearDialog> {
  final _controller = TextEditingController();
  List<dynamic> _results = [];
  bool _loading = false;

  Future<void> _runSearch() async {
    setState(() => _loading = true);
    try {
      final r = await widget.onSearchCurated(_controller.text.trim());
      setState(() => _results = r);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Gear'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            decoration: const InputDecoration(hintText: 'Search curated gear...'),
            onSubmitted: (_) => _runSearch(),
          ),
          const SizedBox(height: 12),
          if (_loading) const CircularProgressIndicator(),
          if (!_loading)
            SizedBox(
              height: 200,
              width: 400,
              child: _results.isEmpty
                  ? const Center(child: Text('No results yet'))
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, i) {
                        final it = _results[i] as Map<String, dynamic>;
                        return ListTile(
                          leading: it['default_image_url'] != null
                              ? Image.network(it['default_image_url'], width: 40, height: 40, fit: BoxFit.cover)
                              : const Icon(Icons.image_not_supported),
                          title: Text(it['name'] ?? 'Unnamed'),
                          subtitle: Text((it['brand'] ?? '') + (it['model'] != null ? ' • ${it['model']}' : '')),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () => widget.onSelectCurated(it, asWishlist: true),
                                child: const Text('Wishlist'),
                              ),
                              ElevatedButton(
                                onPressed: () => widget.onSelectCurated(it, asWishlist: false),
                                child: const Text('Own it'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          const SizedBox(height: 8),
          const Divider(),
          const Text('Don\'t see it? We\'ll support Amazon search soon.'),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}

