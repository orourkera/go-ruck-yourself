import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/models/planned_ruck.dart';
import 'package:rucking_app/core/models/route.dart' as route_model;
import 'package:rucking_app/features/planned_rucks/presentation/bloc/planned_ruck_bloc.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/planned_ruck_event.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/planned_ruck_state.dart';
import 'package:rucking_app/features/planned_rucks/presentation/widgets/route_map_preview.dart';
import 'package:rucking_app/features/planned_rucks/presentation/widgets/elevation_profile_chart.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Detailed view screen for a planned ruck
class PlannedRuckDetailScreen extends StatefulWidget {
  final String plannedRuckId;

  const PlannedRuckDetailScreen({
    super.key,
    required this.plannedRuckId,
  });

  @override
  State<PlannedRuckDetailScreen> createState() => _PlannedRuckDetailScreenState();
}

class _PlannedRuckDetailScreenState extends State<PlannedRuckDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late ScrollController _scrollController;
  bool _showAppBarTitle = false;
  PlannedRuck? _plannedRuck;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _scrollController = ScrollController();
    
    // Load the planned ruck using the ID
    context.read<PlannedRuckBloc>().add(
      LoadPlannedRuckById(plannedRuckId: widget.plannedRuckId),
    );
    
    _scrollController.addListener(() {
      final shouldShow = _scrollController.offset > 200;
      if (shouldShow != _showAppBarTitle) {
        setState(() {
          _showAppBarTitle = shouldShow;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PlannedRuckBloc, PlannedRuckState>(
      listener: (context, state) {
        if (state is PlannedRuckLoading) {
          // Show loading if needed
        } else if (state is PlannedRuckError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppColors.accent,
            ),
          );
        } else if (state is PlannedRuckLoaded) {
          // Use the selectedRuck from the state (loaded by LoadPlannedRuckById)
          final plannedRuck = state.selectedRuck ?? 
              state.plannedRucks
                  .where((ruck) => ruck.id == widget.plannedRuckId)
                  .firstOrNull;
          
          if (plannedRuck != null) {
            setState(() {
              _plannedRuck = plannedRuck;
            });
          }
        }
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: AppColors.backgroundLight,
          body: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // App bar with hero image
              _buildSliverAppBar(_plannedRuck?.route),
              
              // Tab bar
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarDelegate(
                  tabBar: TabBar(
                    controller: _tabController,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.textDarkSecondary,
                    indicatorColor: AppColors.primary,
                    tabs: const [
                      Tab(text: 'Overview'),
                      Tab(text: 'Map & Route'),
                      Tab(text: 'Details'),
                    ],
                  ),
                ),
              ),
              
              // Tab content
              SliverFillRemaining(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOverviewTab(),
                    _buildMapTab(),
                    _buildDetailsTab(),
                  ],
                ),
              ),
            ],
          ),
          
          // Floating action buttons
          floatingActionButton: _buildFloatingActions(),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        );
      },
    );
  }

  Widget _buildSliverAppBar(route_model.Route? route) {
    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      backgroundColor: AppColors.backgroundLight,
      title: _showAppBarTitle 
          ? Text(
              route?.name ?? 'Planned Ruck',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.bold,
              ),
            )
          : null,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Background image or gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.8),
                    AppColors.primary,
                  ],
                ),
              ),
            ),
            
            // Route map preview (if available)
            if (route != null)
              Positioned.fill(
                child: RouteMapPreview(
                  route: route,
                  isHeroImage: true,
                  showOverlay: true,
                ),
              ),
            
            // Overlay content
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Route name
                  Text(
                    route?.name ?? 'Unnamed Route',
                    style: AppTextStyles.headlineMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          color: Colors.grey.shade600.withAlpha(128),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Status and badges
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(26),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _plannedRuck?.status.name.toLowerCase() ?? '',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (route?.trailDifficulty != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.secondary.withAlpha(26),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            route?.trailDifficulty ?? 'Unknown',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.secondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Quick stats
                  if (route != null)
                    Row(
                      children: [
                        _buildQuickStat(Icons.straighten, route.formattedDistance),
                        if (route.elevationGainM != null) ...[
                          const SizedBox(width: 16),
                          _buildQuickStat(Icons.trending_up, route.formattedElevationGain),
                        ],
                        if (route.estimatedDurationMinutes != null) ...[
                          const SizedBox(width: 16),
                          _buildQuickStat(Icons.access_time, route.formattedEstimatedDuration),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStat(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: Colors.white.withValues(alpha: 0.9),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(
            color: Colors.white.withValues(alpha: 0.9),
            fontWeight: FontWeight.w600,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewTab() {
    final route = _plannedRuck?.route;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Planned ruck info card
          _buildInfoCard(
            'Planned Ruck Details',
            Icons.calendar_today,
            [
              _buildInfoRow('Planned Date', _plannedRuck?.formattedPlannedDate ?? ''),
              _buildInfoRow('Status', _plannedRuck?.status.value ?? ''),
              if (_plannedRuck?.notes?.isNotEmpty == true)
                _buildInfoRow('Notes', _plannedRuck?.notes ?? ''),
              if (_plannedRuck?.completedAt != null)
                _buildInfoRow('Completed', '${_plannedRuck?.completedAt?.day ?? 0}/${_plannedRuck?.completedAt?.month ?? 0}/${_plannedRuck?.completedAt?.year ?? 0}'),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Route overview
          if (route != null) ...[
            _buildInfoCard(
              'Route Overview',
              Icons.route,
              [
                _buildInfoRow('Location', '${route.startLatitude.toStringAsFixed(4)}, ${route.startLongitude.toStringAsFixed(4)}'),
                _buildInfoRow('Distance', route.formattedDistance),
                if (route.elevationGainM != null)
                  _buildInfoRow('Elevation Gain', route.formattedElevationGain),
                if (route.estimatedDurationMinutes != null)
                  _buildInfoRow('Estimated Duration', route.formattedEstimatedDuration),
                if (route.routeType != null)
                  _buildInfoRow('Route Type', _getRouteTypeLabel(route.routeType!)),
              ],
            ),
            
            const SizedBox(height: 16),
          ],
          
          // Route description
          if (route?.description?.isNotEmpty == true) ...[
            _buildInfoCard(
              'Description',
              Icons.description,
              [
                Text(
                  route?.description ?? '',
                  style: AppTextStyles.bodyLarge,
                ),
              ],
            ),
            
            const SizedBox(height: 16),
          ],
          
          // Ratings and reviews
          if (route?.averageRating != null || route?.totalCompletedCount != null) ...[
            _buildRatingsCard(route!),
            const SizedBox(height: 16),
          ],
          
          // Weather info (placeholder)
          _buildWeatherCard(),
        ],
      ),
    );
  }

  Widget _buildMapTab() {
    final route = _plannedRuck?.route;
    
    if (route == null) {
      return const Center(
        child: Text('No route data available'),
      );
    }
    
    return Column(
      children: [
        // Interactive map
        Expanded(
          flex: 2,
          child: RouteMapPreview(
            route: route,
            isInteractive: true,
            showControls: true,
          ),
        ),
        
        // Elevation profile
        if (route.elevationPoints.isNotEmpty) ...[
          Container(
            height: 200,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.backgroundLight,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Elevation Profile',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ElevationProfileChart(
                    elevationData: route.elevationPoints,
                    route: route,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDetailsTab() {
    final route = _plannedRuck?.route;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Technical details
          if (route != null) ...[
            _buildInfoCard(
              'Technical Details',
              Icons.analytics,
              [
                if (route.elevationGainM != null)
                  _buildInfoRow('Elevation Gain', '${route.elevationGainM!.toStringAsFixed(0)} m'),
                if (route.elevationLossM != null)
                  _buildInfoRow('Elevation Loss', '${route.elevationLossM!.toStringAsFixed(0)} m'),
                if (route.trailDifficulty != null)
                  _buildInfoRow('Difficulty', route.trailDifficulty!),
                if (route.trailType != null)
                  _buildInfoRow('Trail Type', route.trailType!),
                if (route.surfaceType != null)
                  _buildInfoRow('Surface Type', route.surfaceType!),
              ],
            ),
            
            const SizedBox(height: 16),
          ],
          
          // Points of Interest
          if (route?.pointsOfInterest.isNotEmpty == true) ...[
            _buildPOICard(route!),
            const SizedBox(height: 16),
          ],
          
          // Source information
          _buildInfoCard(
            'Source Information',
            Icons.info,
            [
              if (_plannedRuck?.createdAt != null)
                _buildInfoRow('Created', '${_plannedRuck?.createdAt?.day ?? 0}/${_plannedRuck?.createdAt?.month ?? 0}/${_plannedRuck?.createdAt?.year ?? 0}'),
              if (route?.source?.isNotEmpty == true)
                _buildInfoRow('Route Source', route?.source ?? ''),
              if (route?.id != null)
                _buildInfoRow('Route ID', route?.id ?? ''),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, IconData icon, List<Widget> children) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textDarkSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingsCard(route_model.Route route) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.star, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Ratings & Reviews',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            Row(
              children: [
                // Star rating
                Row(
                  children: List.generate(5, (index) {
                    return Icon(
                      index < route.averageRating!.floor()
                          ? Icons.star
                          : index < route.averageRating!
                              ? Icons.star_half
                              : Icons.star_border,
                      color: Colors.amber,
                      size: 20,
                    );
                  }),
                ),
                const SizedBox(width: 8),
                Text(
                  route.averageRating!.toStringAsFixed(1),
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (route.totalCompletedCount != null) ...[
                  Text(
                    ' (${route.totalCompletedCount} reviews)',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textDarkSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPOICard(route_model.Route route) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.place, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Points of Interest',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            ...route.pointsOfInterest.take(5).map((poi) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      _getPOIIcon(poi.poiType),
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        poi.name,
                        style: AppTextStyles.bodyMedium,
                      ),
                    ),
                    Text(
                        '${poi.distanceFromStartKm.toStringAsFixed(1)} km',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textDarkSecondary,
                        ),
                      ),
                  ],
                ),
              );
            }),
            
            if (route.pointsOfInterest.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '+${route.pointsOfInterest.length - 5} more points of interest',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textDarkSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeatherCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wb_sunny, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Weather Forecast',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            Text(
              'Weather information will be available closer to your planned date.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textDarkSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingActions() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Share button
        FloatingActionButton(
          heroTag: 'share',
          onPressed: _shareRoute,
          backgroundColor: AppColors.backgroundLight,
          foregroundColor: AppColors.primary,
          child: const Icon(Icons.share),
        ),
        
        const SizedBox(height: 16),
        
        // Primary action button
        FloatingActionButton.extended(
          heroTag: 'primary',
          onPressed: _performPrimaryAction,
          backgroundColor: _getPrimaryActionColor(),
          foregroundColor: Colors.white,
          icon: Icon(_getPrimaryActionIcon()),
          label: Text(_getPrimaryActionLabel()),
        ),
      ],
    );
  }

  // Helper methods

  String _getRouteTypeLabel(route_model.RouteType type) {
    switch (type) {
      case route_model.RouteType.loop:
        return 'Loop';
      case route_model.RouteType.outAndBack:
        return 'Out & Back';
      case route_model.RouteType.pointToPoint:
        return 'Point to Point';
    }
  }

  IconData _getPOIIcon(String type) {
    switch (type.toLowerCase()) {
      case 'water':
        return Icons.water_drop;
      case 'restroom':
        return Icons.wc;
      case 'viewpoint':
        return Icons.visibility;
      case 'parking':
        return Icons.local_parking;
      default:
        return Icons.place;
    }
  }

  Color _getPrimaryActionColor() {
    if (_plannedRuck == null) return AppColors.textDarkSecondary;
    
    switch (_plannedRuck!.status) {
      case PlannedRuckStatus.planned:
        return _plannedRuck!.canStart ? AppColors.primary : AppColors.textDarkSecondary;
      case PlannedRuckStatus.inProgress:
        return AppColors.info;
      default:
        return AppColors.textDarkSecondary;
    }
  }

  IconData _getPrimaryActionIcon() {
    if (_plannedRuck == null) return Icons.edit;
    
    switch (_plannedRuck!.status) {
      case PlannedRuckStatus.planned:
        return Icons.play_arrow;
      case PlannedRuckStatus.inProgress:
        return Icons.visibility;
      default:
        return Icons.edit;
    }
  }

  String _getPrimaryActionLabel() {
    if (_plannedRuck == null) return 'Edit';
    
    switch (_plannedRuck!.status) {
      case PlannedRuckStatus.planned:
        return _plannedRuck!.canStart ? 'Start Ruck' : 'Edit';
      case PlannedRuckStatus.inProgress:
        return 'View Session';
      default:
        return 'Edit';
    }
  }

  void _performPrimaryAction() {
    if (_plannedRuck == null) return;
    
    switch (_plannedRuck!.status) {
      case PlannedRuckStatus.planned:
        if (_plannedRuck!.canStart) {
          context.read<PlannedRuckBloc>().add(
            StartPlannedRuck(plannedRuckId: _plannedRuck!.id ?? ''),
          );
        }
        break;
      case PlannedRuckStatus.inProgress:
        // Navigate to active session
        break;
      default:
        // Navigate to edit screen
        break;
    }
  }

  void _shareRoute() {
    // TODO: Implement route sharing
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sharing functionality coming soon!')),
    );
  }
}

// Custom tab bar delegate
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  _TabBarDelegate({required this.tabBar});

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.backgroundLight,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return false;
  }
}
