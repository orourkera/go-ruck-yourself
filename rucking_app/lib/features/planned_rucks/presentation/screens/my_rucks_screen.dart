import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/models/route.dart' as route_model;
import 'package:rucking_app/core/repositories/routes_repository.dart';
import 'package:rucking_app/features/planned_rucks/presentation/widgets/my_rucks_app_bar.dart';
import 'package:rucking_app/features/planned_rucks/presentation/screens/route_import_screen.dart';
import 'package:rucking_app/features/planned_rucks/presentation/screens/planned_ruck_detail_screen.dart';
import 'package:rucking_app/core/widgets/error_widget.dart';
import 'package:rucking_app/shared/widgets/loading_indicator.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';


/// Main screen for displaying and managing routes
class MyRucksScreen extends StatefulWidget {
  const MyRucksScreen({super.key});

  @override
  State<MyRucksScreen> createState() => _MyRucksScreenState();
}

class _MyRucksScreenState extends State<MyRucksScreen> with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final RoutesRepository _routesRepository = GetIt.instance<RoutesRepository>();
  
  List<route_model.Route>? _routes;
  List<route_model.Route> _filteredRoutes = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadRoutes();
  }
  
  @override
  void didUpdateWidget(MyRucksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refresh routes when widget updates
    _loadRoutes();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Refresh when app comes back to foreground
    if (state == AppLifecycleState.resumed && mounted) {
      _loadRoutes();
    }
  }
  
  /// Refresh routes when returning from other screens
  void _onScreenResumed() {
    if (mounted) {
      _loadRoutes();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRoutes() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load user's routes (not planned rucks)
      final routes = await _routesRepository.getMyRoutes(limit: 100);
      setState(() {
        _routes = routes;
        _filteredRoutes = routes;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load routes: $e';
        _isLoading = false;
      });
    }
  }

  void _filterRoutes(String query) {
    if (_routes == null) return;
    
    setState(() {
      if (query.isEmpty) {
        _filteredRoutes = _routes!;
      } else {
        _filteredRoutes = _routes!.where((route) {
          return route.name.toLowerCase().contains(query.toLowerCase()) ||
                 (route.description?.toLowerCase().contains(query.toLowerCase()) ?? false);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: MyRucksAppBar(
        searchController: _searchController,
        onSearchChanged: _filterRoutes,
        onImportPressed: () => _navigateToImport(),
      ),
      body: RefreshIndicator(
        onRefresh: _loadRoutes,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: LoadingIndicator());
    }

    if (_error != null) {
      return Center(
        child: AppErrorWidget(
          message: _error!,
          onRetry: _loadRoutes,
        ),
      );
    }

    if (_filteredRoutes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.route,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              'No Routes Found',
              style: AppTextStyles.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Import your first route to get started!',
              style: AppTextStyles.bodyMedium.copyWith(
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _navigateToImport,
              child: const Text('Import Route'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _filteredRoutes.length,
      itemBuilder: (context, index) {
        final route = _filteredRoutes[index];
        return _buildRouteCard(route);
      },
    );
  }

  Widget _buildRouteCard(route_model.Route route) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _navigateToRouteDetail(route),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              route.name,
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (route.description?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(
                route.description!,
                style: AppTextStyles.bodySmall.copyWith(
                  color: Colors.grey[600],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                _buildChip('${route.distanceKm.toStringAsFixed(1)} km'),
                const SizedBox(width: 8),
                // Only show elevation if it exists and is greater than 0
                if (route.elevationGainM != null && route.elevationGainM! > 0) ...[
                  _buildChip('${route.elevationGainM!.round()}m elevation'),
                  const SizedBox(width: 8),
                ],
                if (route.trailDifficulty != null) ...[
                  _buildChip(route.trailDifficulty!.toUpperCase()),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _navigateToRouteDetail(route),
                  icon: const Icon(Icons.info_outline),
                  label: const Text('Details'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 2,
                  ),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodySmall,
      ),
    );
  }

  // Navigation and Action methods

  void _navigateToImport() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const RouteImportScreen(),
      ),
    );
    // Refresh routes when returning from import screen
    if (mounted) {
      _loadRoutes();
    }
  }

  void _navigateToRouteDetail(route_model.Route route) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PlannedRuckDetailScreen(route: route),
      ),
    );
    // ֿRefresh routes when returning from detail screen
    if (mounted) {
      _loadRoutes();
    }
  }


}
