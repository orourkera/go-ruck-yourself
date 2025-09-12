import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:rucking_app/features/gear/data/gear_api.dart';
import 'package:rucking_app/shared/widgets/affiliate_disclosure.dart';

class GearDetailScreen extends StatefulWidget {
  final Map<String, dynamic> item;
  const GearDetailScreen({super.key, required this.item});

  @override
  State<GearDetailScreen> createState() => _GearDetailScreenState();
}

class _GearDetailScreenState extends State<GearDetailScreen> {
  late final GearApi _api;
  List<dynamic> _comments = [];
  bool _loading = true;
  Map<String, dynamic>? _detail;

  @override
  void initState() {
    super.initState();
    final client = GetIt.instance<ApiClient>();
    _api = GearApi.fromClient(client);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final itemId = widget.item['id'].toString();
      final detail = await _api.getItemDetail(itemId);
      final comments = await _api.getCuratedComments(itemId);
      setState(() {
        _detail = detail;
        _comments = comments;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatMinor(dynamic minor, {String currency = 'USD'}) {
    if (minor == null) return '';
    final cents = (minor as num).toInt();
    final dollars = cents / 100.0;
    final symbol = currency == 'USD' ? r'\$' : '';
    return symbol + dollars.toStringAsFixed(2);
  }

  Future<void> _buy(dynamic sku) async {
    final skuId = sku['sku_id']?.toString();
    final retailer = (sku['retailer'] ?? '').toString();
    if (skuId == null || skuId.isEmpty || retailer.isEmpty) return;
    final code =
        (sku['coupon_code'] ?? sku['referral_code'] ?? 'none').toString();
    final url =
        '${AppConfig.apiBaseUrl}/gear/ref/$retailer/$code?sku_id=$skuId';
    await launchUrlString(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _showAddCommentDialog() async {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    int? rating;
    bool ownership = false;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Comment'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration:
                      const InputDecoration(labelText: 'Title (optional)'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: rating,
                  decoration:
                      const InputDecoration(labelText: 'Rating (optional)'),
                  items: [1, 2, 3, 4, 5]
                      .map((e) => DropdownMenuItem(value: e, child: Text('$e')))
                      .toList(),
                  onChanged: (v) => rating = v,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: bodyController,
                  maxLines: 4,
                  decoration:
                      const InputDecoration(hintText: 'Write your thoughts...'),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('I own this'),
                  value: ownership,
                  onChanged: (v) {
                    ownership = v ?? false;
                    setState(() {});
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                )
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Post')),
          ],
        );
      },
    );
    if (ok == true) {
      final body = bodyController.text.trim();
      if (body.isEmpty) return;
      try {
        await _api.postCuratedComment(
          itemId: widget.item['id'].toString(),
          rating: rating,
          title: titleController.text.trim(),
          body: body,
          ownershipClaimed: ownership,
        );
        messenger
            ?.showSnackBar(const SnackBar(content: Text('Comment posted')));
        _load();
      } catch (_) {
        messenger?.showSnackBar(
            const SnackBar(content: Text('Failed to post comment')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Scaffold(
      appBar: AppBar(title: Text(item['name'] ?? 'Gear')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (item['default_image_url'] != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(item['default_image_url'],
                          height: 220, fit: BoxFit.cover),
                    )
                  else
                    Container(
                        height: 200,
                        decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(12))),
                  const SizedBox(height: 12),
                  Text(item['name'] ?? '',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(
                      [
                        if ((item['brand'] ?? '').toString().isNotEmpty)
                          item['brand'],
                        if ((item['model'] ?? '').toString().isNotEmpty)
                          item['model'],
                      ].join(' • '),
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  const AffiliateDisclosure(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.maybeOf(context);
                          try {
                            await _api.claimCurated(
                                gearItemId: item['id'].toString(),
                                relation: 'owned');
                            messenger?.showSnackBar(const SnackBar(
                                content: Text('Marked as owned')));
                          } catch (_) {
                            messenger?.showSnackBar(const SnackBar(
                                content: Text('Failed to claim')));
                          }
                        },
                        child: const Text('Own'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.maybeOf(context);
                          try {
                            await _api.claimCurated(
                                gearItemId: item['id'].toString(),
                                relation: 'saved');
                            messenger?.showSnackBar(const SnackBar(
                                content: Text('Added to wishlist')));
                          } catch (_) {
                            messenger?.showSnackBar(
                                const SnackBar(content: Text('Failed to add')));
                          }
                        },
                        child: const Text('Wishlist'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_detail != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Prices',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        ...((_detail!['skus'] as List? ?? [])).map((s) {
                          final sku = s as Map<String, dynamic>;
                          final base = _formatMinor(sku['base_minor']);
                          final eff = _formatMinor(sku['effective_minor']);
                          final hasDiscount = sku['discount_id'] != null &&
                              eff.isNotEmpty &&
                              base.isNotEmpty &&
                              eff != base;
                          return Card(
                            child: ListTile(
                              title: Text(
                                  (sku['retailer'] ?? 'Retailer').toString()),
                              subtitle: hasDiscount
                                  ? Row(children: [
                                      Text(base,
                                          style: const TextStyle(
                                              decoration:
                                                  TextDecoration.lineThrough)),
                                      const SizedBox(width: 6),
                                      Text(eff,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ])
                                  : Text(base.isNotEmpty ? base : '—'),
                              trailing: ElevatedButton(
                                onPressed: () => _buy(sku),
                                child: const Text('Buy'),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  const SizedBox(height: 16),
                  Text('Comments',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_comments.isEmpty)
                    const Text('No comments yet.')
                  else
                    ..._comments.map((c) {
                      final m = c as Map<String, dynamic>;
                      final rating = m['rating'] as int?;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(m['title']?.toString().isNotEmpty == true
                              ? m['title']
                              : 'Comment'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (rating != null) Text('Rating: $rating/5'),
                              Text(m['body'] ?? ''),
                            ],
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      onPressed: _showAddCommentDialog,
                      icon: const Icon(Icons.add_comment),
                      label: const Text('Add Comment'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
