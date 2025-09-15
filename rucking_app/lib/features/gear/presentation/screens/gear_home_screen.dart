import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/features/gear/data/gear_api.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/features/gear/presentation/widgets/add_gear_dialog.dart';
import 'package:rucking_app/shared/widgets/affiliate_disclosure.dart';

class GearHomeScreen extends StatefulWidget {
  const GearHomeScreen({super.key});

  @override
  State<GearHomeScreen> createState() => _GearHomeScreenState();
}

class _GearHomeScreenState extends State<GearHomeScreen> {
  late final GearApi _api;
  List<dynamic> _curated = [];
  List<dynamic> _topOwned = [];
  List<dynamic> _topSaved = [];
  List<dynamic> _ownedMine = [];
  List<dynamic> _savedMine = [];
  bool _loading = true;

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
      // Read auth-dependent values before any awaits to avoid context-after-await lint
      String? userId;
      try {
        final auth = context.read<AuthBloc>().state;
        if (auth is Authenticated) userId = auth.user.userId;
      } catch (_) {}

      final curated = await _api.searchCurated(q: '');
      final client = GetIt.instance<ApiClient>();
      final topOwned = await client.get('/api/stats/gear/top');
      final topSaved = await client
          .get('/api/stats/gear/top', queryParams: {'relation': 'saved'});

      Map<String, dynamic> profile = {'owned': [], 'saved': []};
      if (userId != null) {
        profile = await client.get('/api/gear/profile/$userId')
            as Map<String, dynamic>;
      }

      setState(() {
        _curated = curated;
        _topOwned = (topOwned['items'] as List?) ?? [];
        _topSaved = (topSaved['items'] as List?) ?? [];
        _ownedMine = (profile['owned'] as List?) ?? [];
        _savedMine = (profile['saved'] as List?) ?? [];
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  void _openAddDialog() {
    showDialog(
      context: context,
      builder: (_) => AddGearDialog(
        onSearchCurated: (q) => _api.searchCurated(q: q),
        onSelectCurated: (item, {required bool asWishlist}) async {
          Navigator.pop(context);
          final messenger = ScaffoldMessenger.maybeOf(context);
          await _api.claimCurated(
            gearItemId: item['id'].toString(),
            relation: asWishlist ? 'saved' : 'owned',
          );
          messenger?.showSnackBar(
            SnackBar(
                content:
                    Text(asWishlist ? 'Added to wishlist' : 'Marked as owned')),
          );
          _load();
        },
        onSearchAmazon:
            AppConfig.enableAmazonGear ? (q) => _api.searchAmazon(q: q) : null,
        onSelectAmazon: AppConfig.enableAmazonGear
            ? (it, {required bool asWishlist}) async {
                Navigator.pop(context);
                final messenger = ScaffoldMessenger.maybeOf(context);
                await _api.claimExternal(
                  source: 'amazon',
                  externalId: (it['asin'] ?? '').toString(),
                  relation: asWishlist ? 'saved' : 'owned',
                  title: it['title']?.toString(),
                  imageUrl: it['image_url']?.toString(),
                );
                messenger?.showSnackBar(SnackBar(
                    content: Text(
                        asWishlist ? 'Added to wishlist' : 'Marked as owned')));
                _load();
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gear'),
        actions: [
          IconButton(onPressed: _openAddDialog, icon: const Icon(Icons.add)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const AffiliateDisclosure(),
                  const SizedBox(height: 16),
                  Text('Curated For Rucking',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _curated.isEmpty
                      ? const Text('No curated items yet')
                      : SizedBox(
                          height: 140,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _curated.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, i) {
                              final it = _curated[i] as Map<String, dynamic>;
                              return _CuratedCard(
                                  item: it,
                                  onOwn: () async {
                                    await _api.claimCurated(
                                        gearItemId: it['id'].toString(),
                                        relation: 'owned');
                                    _load();
                                  },
                                  onWishlist: () async {
                                    await _api.claimCurated(
                                        gearItemId: it['id'].toString(),
                                        relation: 'saved');
                                    _load();
                                  });
                            },
                          ),
                        ),
                  const SizedBox(height: 24),
                  Text('Community-Owned Gear',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ..._topOwned.map((e) => ListTile(
                        leading: (e['image_url'] != null)
                            ? Image.network(e['image_url'],
                                width: 48, height: 48, fit: BoxFit.cover)
                            : const Icon(Icons.image),
                        title: Text(e['title'] ?? 'Unknown'),
                        subtitle: Text(
                            '${e['sessions_count'] ?? 0} sessions • ${e['total_distance_km'] ?? 0} km'),
                        trailing: TextButton(
                          onPressed: () async {
                            // owning external/community item requires lookup; for now just open add dialog
                            _openAddDialog();
                          },
                          child: const Text('I own this'),
                        ),
                      )),
                  const SizedBox(height: 24),
                  Text('Most Wishlisted',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ..._topSaved.map((e) => ListTile(
                        leading: (e['image_url'] != null)
                            ? Image.network(e['image_url'],
                                width: 48, height: 48, fit: BoxFit.cover)
                            : const Icon(Icons.image),
                        title: Text(e['title'] ?? 'Unknown'),
                        subtitle: Text('${e['saved_count'] ?? 0} wishlists'),
                        trailing: TextButton(
                          onPressed: _openAddDialog,
                          child: const Text('Add to wishlist'),
                        ),
                      )),
                  const SizedBox(height: 24),
                  Text('Your Owned',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_ownedMine.isEmpty) const Text('Nothing claimed yet'),
                  ..._ownedMine.map((e) => ListTile(
                        leading: (e['image_url'] != null)
                            ? Image.network(e['image_url'],
                                width: 40, height: 40, fit: BoxFit.cover)
                            : const Icon(Icons.check_circle_outline),
                        title: Text(e['title'] ?? 'Unknown'),
                        trailing: TextButton(
                          onPressed: () async {
                            final messenger =
                                ScaffoldMessenger.maybeOf(context);
                            try {
                              await _api.unclaim(
                                gearItemId:
                                    (e['gear_item_id']?.toString()) != 'null'
                                        ? e['gear_item_id']?.toString()
                                        : null,
                                externalProductId:
                                    (e['external_product_id']?.toString()) !=
                                            'null'
                                        ? e['external_product_id']?.toString()
                                        : null,
                                relation: 'owned',
                              );
                              messenger?.showSnackBar(const SnackBar(
                                  content: Text('Removed from owned')));
                              _load();
                            } catch (_) {
                              messenger?.showSnackBar(const SnackBar(
                                  content: Text('Failed to remove')));
                            }
                          },
                          child: const Text('Remove'),
                        ),
                      )),
                  const SizedBox(height: 16),
                  Text('Your Wishlist',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_savedMine.isEmpty) const Text('Wishlist is empty'),
                  ..._savedMine.map((e) => ListTile(
                        leading: (e['image_url'] != null)
                            ? Image.network(e['image_url'],
                                width: 40, height: 40, fit: BoxFit.cover)
                            : const Icon(Icons.favorite_border),
                        title: Text(e['title'] ?? 'Unknown'),
                        trailing: TextButton(
                          onPressed: () async {
                            final messenger =
                                ScaffoldMessenger.maybeOf(context);
                            try {
                              await _api.unclaim(
                                gearItemId:
                                    (e['gear_item_id']?.toString()) != 'null'
                                        ? e['gear_item_id']?.toString()
                                        : null,
                                externalProductId:
                                    (e['external_product_id']?.toString()) !=
                                            'null'
                                        ? e['external_product_id']?.toString()
                                        : null,
                                relation: 'saved',
                              );
                              messenger?.showSnackBar(const SnackBar(
                                  content: Text('Removed from wishlist')));
                              _load();
                            } catch (_) {
                              messenger?.showSnackBar(const SnackBar(
                                  content: Text('Failed to remove')));
                            }
                          },
                          child: const Text('Remove'),
                        ),
                      )),
                ],
              ),
            ),
    );
  }
}

class _CuratedCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onOwn;
  final VoidCallback onWishlist;
  const _CuratedCard(
      {required this.item, required this.onOwn, required this.onWishlist});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.pushNamed(context, '/gear/detail', arguments: item);
      },
      child: Container(
        width: 220,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item['default_image_url'] != null)
              Image.network(item['default_image_url'],
                  height: 90, width: 220, fit: BoxFit.cover)
            else
              Container(height: 90, width: 220, color: Colors.grey[300]),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(item['name'] ?? 'Unnamed',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                children: [
                  TextButton(
                      onPressed: onWishlist, child: const Text('Wishlist')),
                  const Spacer(),
                  ElevatedButton(onPressed: onOwn, child: const Text('Own')),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
