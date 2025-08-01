import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/models/route.dart' as route_model;
import 'package:rucking_app/core/repositories/routes_repository.dart';
import 'package:rucking_app/features/planned_rucks/presentation/widgets/my_rucks_app_bar.dart';
import 'package:rucking_app/features/planned_rucks/presentation/screens/route_import_screen.dart';
import 'package:rucking_app/features/planned_rucks/presentation/screens/planned_ruck_detail_screen.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/create_session_screen.dart';
import 'package:rucking_app/core/widgets/error_widget.dart';
import 'package:rucking_app/shared/widgets/loading_indicator.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';


/// Main screen for displaying and managing routes (simplified from planned rucks)
class MyRucksScreen extends StatefulWidget {
  const MyRucksScreen({super.key});

  @override
  State<MyRucksScreen> createState() => _MyRucksScreenState();
}

class _MyRucksScreenState extends State<MyRucksScreen> {
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
    _loadRoutes();
  }

  @override
  void dispose() {
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToImport(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Import Route'),
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
                _buildChip('${route.elevationGainM?.round() ?? 0}m elevation'),
                if (route.trailDifficulty != null) ...[
                  const SizedBox(width: 8),
                  _buildChip(route.trailDifficulty!.toUpperCase()),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _startRuck(route),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('START RUCK'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () => _deleteRoute(route),
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text('DELETE', style: TextStyle(color: Colors.red)),
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

  void _navigateToImport() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const RouteImportScreen(),
      ),
    );
  }

  void _navigateToRouteDetail(route_model.Route route) {
    // For now, use route.id as plannedRuckId - this needs to be updated
    // when PlannedRuckDetailScreen is modified to handle routes directly
    if (route.id != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PlannedRuckDetailScreen(plannedRuckId: route.id!),
        ),
      );
    }
  }

  void _startRuck(route_model.Route route) {
    // Navigate to create session screen with the route data
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const CreateSessionScreen(),
      ),
    );
  }

  void _deleteRoute(route_model.Route route) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Route'),
        content: Text('Are you sure you want to delete "${route.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                if (route.id != null) {
                  await _routesRepository.deleteRoute(route.id!);
                  _loadRoutes(); // Reload routes after deletion
                } else {
                  throw Exception('Route ID is null');
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('"${route.name}" deleted successfully'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete route: $e'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
