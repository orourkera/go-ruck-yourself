import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/services/api_client.dart';

class ProfileGearSections extends StatefulWidget {
  final String userId;
  const ProfileGearSections({super.key, required this.userId});

  @override
  State<ProfileGearSections> createState() => _ProfileGearSectionsState();
}

class _ProfileGearSectionsState extends State<ProfileGearSections> {
  List<dynamic> _owned = [];
  List<dynamic> _saved = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final client = GetIt.instance<ApiClient>();
      final data = await client.get('/api/gear/profile/${widget.userId}')
          as Map<String, dynamic>;
      setState(() {
        _owned = (data['owned'] as List?) ?? [];
        _saved = (data['saved'] as List?) ?? [];
      });
    } catch (_) {
      // no-op; keep empty
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_owned.isNotEmpty) ...[
          Text('Owned Gear', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _owned.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final it = _owned[i] as Map<String, dynamic>;
                return _GearChip(title: it['title'], imageUrl: it['image_url']);
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_saved.isNotEmpty) ...[
          Text('Wishlist', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _saved.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final it = _saved[i] as Map<String, dynamic>;
                return _GearChip(title: it['title'], imageUrl: it['image_url']);
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _GearChip extends StatelessWidget {
  final String? title;
  final String? imageUrl;
  const _GearChip({required this.title, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
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
          if (imageUrl != null)
            Image.network(imageUrl!, height: 80, width: 140, fit: BoxFit.cover)
          else
            Container(height: 80, width: 140, color: Colors.grey[300]),
          Padding(
            padding: const EdgeInsets.all(6.0),
            child: Text(title ?? 'Unknown',
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
