import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/models/planned_ruck.dart';
import 'package:rucking_app/core/models/route.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/planned_ruck_bloc.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/planned_ruck_event.dart';
import 'package:rucking_app/features/planned_rucks/presentation/widgets/route_map_preview.dart';
import 'package:rucking_app/features/planned_rucks/presentation/widgets/elevation_profile_chart.dart';
import 'package:rucking_app/core/widgets/difficulty_badge.dart';
import 'package:rucking_app/core/widgets/status_badge.dart';
import 'package:rucking_app/core/theme/app_colors.dart';
import 'package:rucking_app/core/theme/app_text_styles.dart';

/// Detailed view screen for a planned ruck
class PlannedRuckDetailScreen extends StatefulWidget {
  final PlannedRuck plannedRuck;

  const PlannedRuckDetailScreen({
    super.key,
    required this.plannedRuck,
  });

  @override
  State<PlannedRuckDetailScreen> createState() => _PlannedRuckDetailScreenState();
}

class _PlannedRuckDetailScreenState extends State<PlannedRuckDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late ScrollController _scrollController;
  bool _showAppBarTitle = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _scrollController = ScrollController();
    
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
    final route = widget.plannedRuck.route;
    
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // App bar with hero image
          _buildSliverAppBar(route),
          
          // Tab bar
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              tabBar: TabBar(
                controller: _tabController,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
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
  }

  Widget _buildSliverAppBar(Route? route) {
    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      backgroundColor: AppColors.surface,
      title: _showAppBarTitle 
          ? Text(
              route?.name ?? 'Planned Ruck',
              style: AppTextStyles.headline6.copyWith(
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
                    AppColors.primary.withOpacity(0.8),
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
                    style: AppTextStyles.headline4.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          color: Colors.black.withOpacity(0.5),
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
                      StatusBadge(
                        status: widget.plannedRuck.status,
                        backgroundColor: Colors.white.withOpacity(0.9),
                      ),
                      if (route?.difficulty != null) ...[
                        const SizedBox(width: 8),
                        DifficultyBadge(
                          difficulty: route!.difficulty!,
                          backgroundColor: Colors.white.withOpacity(0.9),
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
                        if (route.elevationGain != null) ...[
                          const SizedBox(width: 16),
                          _buildQuickStat(Icons.trending_up, route.formattedElevationGain),
                        ],
                        if (route.duration != null) ...[
                          const SizedBox(width: 16),
                          _buildQuickStat(Icons.access_time, route.formattedDuration),
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
          color: Colors.white.withOpacity(0.9),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: AppTextStyles.body2.copyWith(
            color: Colors.white.withOpacity(0.9),
            fontWeight: FontWeight.w600,
            shadows: [
              Shadow(
                color: Colors.black.withOpacity(0.3),
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
    final route = widget.plannedRuck.route;
    
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
              _buildInfoRow('Planned Date', widget.plannedRuck.formattedPlannedDate),
              _buildInfoRow('Status', widget.plannedRuck.status.value),
              if (widget.plannedRuck.notes?.isNotEmpty == true)
                _buildInfoRow('Notes', widget.plannedRuck.notes!),
              if (widget.plannedRuck.completedAt != null)
                _buildInfoRow('Completed', widget.plannedRuck.formattedCompletedAt!),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Route overview
          if (route != null) ...[
            _buildInfoCard(
              'Route Overview',
              Icons.route,
              [
                if (route.location?.isNotEmpty == true)
                  _buildInfoRow('Location', route.location!),
                _buildInfoRow('Distance', route.formattedDistance),
                if (route.elevationGain != null)
                  _buildInfoRow('Elevation Gain', route.formattedElevationGain),
                if (route.duration != null)
                  _buildInfoRow('Estimated Duration', route.formattedDuration),
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
                  route!.description!,
                  style: AppTextStyles.body1,
                ),
              ],
            ),
            
            const SizedBox(height: 16),
          ],
          
          // Ratings and reviews
          if (route?.averageRating != null || route?.totalReviews != null) ...[
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
    final route = widget.plannedRuck.route;
    
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
        if (route.elevationProfile.isNotEmpty) ...[
          Container(
            height: 200,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
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
                  style: AppTextStyles.subtitle1.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ElevationProfileChart(
                    elevationData: route.elevationProfile,
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
    final route = widget.plannedRuck.route;
    
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
                if (route.maxElevation != null)
                  _buildInfoRow('Max Elevation', '${route.maxElevation!.toInt()} ft'),
                if (route.minElevation != null)
                  _buildInfoRow('Min Elevation', '${route.minElevation!.toInt()} ft'),
                if (route.averageGrade != null)
                  _buildInfoRow('Average Grade', '${route.averageGrade!.toStringAsFixed(1)}%'),
                if (route.maxGrade != null)
                  _buildInfoRow('Max Grade', '${route.maxGrade!.toStringAsFixed(1)}%'),
                if (route.estimatedCalories != null)
                  _buildInfoRow('Estimated Calories', '${route.estimatedCalories} cal'),
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
              _buildInfoRow('Created', widget.plannedRuck.formattedCreatedAt),
              if (route?.source?.isNotEmpty == true)
                _buildInfoRow('Route Source', route!.source!),
              if (route?.id != null)
                _buildInfoRow('Route ID', route!.id!),
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
                  style: AppTextStyles.subtitle1.copyWith(
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
              style: AppTextStyles.body2.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.body2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingsCard(Route route) {
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
                  style: AppTextStyles.subtitle1.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            if (route.averageRating != null) ...[
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
                    style: AppTextStyles.subtitle1.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (route.totalReviews != null) ...[
                    Text(
                      ' (${route.totalReviews} reviews)',
                      style: AppTextStyles.body2.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPOICard(Route route) {
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
                  style: AppTextStyles.subtitle1.copyWith(
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
                      _getPOIIcon(poi.type),
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        poi.name,
                        style: AppTextStyles.body2,
                      ),
                    ),
                    if (poi.distance != null)
                      Text(
                        '${poi.distance!.toStringAsFixed(1)} mi',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
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
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
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
                  style: AppTextStyles.subtitle1.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            Text(
              'Weather information will be available closer to your planned date.',
              style: AppTextStyles.body2.copyWith(
                color: AppColors.textSecondary,
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
          backgroundColor: AppColors.surface,
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

  String _getRouteTypeLabel(RouteType type) {
    switch (type) {
      case RouteType.loop:
        return 'Loop';
      case RouteType.outAndBack:
        return 'Out & Back';
      case RouteType.pointToPoint:
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
    switch (widget.plannedRuck.status) {
      case PlannedRuckStatus.planned:
        return widget.plannedRuck.canStart ? AppColors.primary : AppColors.textSecondary;
      case PlannedRuckStatus.inProgress:
        return AppColors.info;
      case PlannedRuckStatus.paused:
        return AppColors.primary;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _getPrimaryActionIcon() {
    switch (widget.plannedRuck.status) {
      case PlannedRuckStatus.planned:
        return Icons.play_arrow;
      case PlannedRuckStatus.inProgress:
        return Icons.visibility;
      case PlannedRuckStatus.paused:
        return Icons.play_arrow;
      default:
        return Icons.edit;
    }
  }

  String _getPrimaryActionLabel() {
    switch (widget.plannedRuck.status) {
      case PlannedRuckStatus.planned:
        return widget.plannedRuck.canStart ? 'Start Ruck' : 'Edit';
      case PlannedRuckStatus.inProgress:
        return 'View Session';
      case PlannedRuckStatus.paused:
        return 'Resume';
      default:
        return 'Edit';
    }
  }

  void _performPrimaryAction() {
    switch (widget.plannedRuck.status) {
      case PlannedRuckStatus.planned:
        if (widget.plannedRuck.canStart) {
          context.read<PlannedRuckBloc>().add(
            StartPlannedRuck(plannedRuckId: widget.plannedRuck.id!),
          );
        }
        break;
      case PlannedRuckStatus.inProgress:
      case PlannedRuckStatus.paused:
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
      color: AppColors.surface,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return false;
  }
}
