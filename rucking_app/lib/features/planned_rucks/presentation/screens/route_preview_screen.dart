import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/models/route.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/route_import_bloc.dart';
import 'package:rucking_app/shared/widgets/buttons/primary_button.dart';
import 'package:rucking_app/shared/widgets/buttons/secondary_button.dart';
import 'package:rucking_app/shared/widgets/loading_states/loading_overlay.dart';
import 'package:rucking_app/features/planned_rucks/presentation/widgets/route_map_preview.dart';
import 'package:rucking_app/features/planned_rucks/presentation/widgets/elevation_profile_chart.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// 🗺️ **Route Preview Screen**
/// 
/// Detailed preview of a route before importing or planning a ruck
class RoutePreviewScreen extends StatelessWidget {
  final String routeId;
  
  const RoutePreviewScreen({
    Key? key,
    required this.routeId,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Route Preview'),
        backgroundColor: AppColors.backgroundLight,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _shareRoute(context),
          ),
          IconButton(
            icon: const Icon(Icons.favorite_border),
            onPressed: () => _saveRoute(context),
          ),
        ],
      ),
      body: BlocBuilder<RouteImportBloc, RouteImportState>(
        builder: (context, state) {
          if (state is RouteImportLoading) {
            return const LoadingOverlay();
          }
          
          if (state is RouteImportError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: AppColors.white,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to load route preview',
                    style: AppTextStyles.headlineMedium.copyWith(
                      color: AppColors.getTextColor(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please check your connection and try again.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.getSecondaryTextColor(context),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    onPressed: () => Navigator.of(context).pop(),
                    text: 'Go Back',
                  ),
                ],
              ),
            );
          }
          
          // For now, create a mock route for preview
          final mockRoute = Route(
            id: routeId,
            name: 'Preview Route',
            description: 'This is a route preview placeholder',
            coordinatePoints: [],
            elevationProfile: [],
            pointsOfInterest: [],
            distance: 5000,
            totalAscent: 200,
            totalDescent: 150,
            difficulty: 'Moderate',
            tags: ['hiking', 'scenic'],
            source: 'preview',
            isPublic: true,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Route Header
                _buildRouteHeader(context, mockRoute),
                const SizedBox(height: 24),
                
                // Route Map
                _buildRouteMap(context, mockRoute),
                const SizedBox(height: 24),
                
                // Route Stats
                _buildRouteStats(context, mockRoute),
                const SizedBox(height: 24),
                
                // Elevation Profile
                _buildElevationProfile(context, mockRoute),
                const SizedBox(height: 24),
                
                // Route Details
                _buildRouteDetails(context, mockRoute),
                const SizedBox(height: 24),
                
                // Action Buttons
                _buildActionButtons(context, mockRoute),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildRouteHeader(BuildContext context, Route route) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          route.name,
          style: AppTextStyles.headlineMedium.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (route.description?.isNotEmpty == true)
          Text(
            route.description!,
            style: AppTextStyles.bodyLarge.copyWith(
              color: AppColors.getTextColor(context),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: route.tags.map((tag) => Chip(
            label: Text(tag),
            backgroundColor: AppColors.primary.withOpacity(0.1),
          )).toList(),
        ),
      ],
    );
  }
  
  Widget _buildRouteMap(BuildContext context, Route route) {
    return Card(
      elevation: 4,
      child: Container(
        height: 300,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Route Map',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    'Interactive map will be displayed here\nonce route data is loaded',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.grey),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildRouteStats(BuildContext context, Route route) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Route Statistics',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    context,
                    'Distance',
                    '${(route.distance / 1000).toStringAsFixed(1)} km',
                    Icons.straighten,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    context,
                    'Ascent',
                    '${route.totalAscent.toInt()} m',
                    Icons.trending_up,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    context,
                    'Difficulty',
                    route.difficulty ?? 'Unknown',
                    Icons.bar_chart,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatItem(BuildContext context, String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primary),
        const SizedBox(height: 8),
        Text(
          value,
          style: AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.getSecondaryTextColor(context),
          ),
        ),
      ],
    );
  }
  
  Widget _buildElevationProfile(BuildContext context, Route route) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Elevation Profile',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  'Elevation chart will be displayed here\nonce route elevation data is loaded',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.grey),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildRouteDetails(BuildContext context, Route route) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Route Details',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildDetailRow('Source', route.source),
            _buildDetailRow('Created', _formatDate(route.createdAt)),
            if (route.pointsOfInterest.isNotEmpty)
              _buildDetailRow('Points of Interest', '${route.pointsOfInterest.length} locations'),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.getTextColor(context),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
  
  Widget _buildActionButtons(BuildContext context, Route route) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _planRuckWithRoute(context, route),
            icon: const Icon(Icons.add_task),
            label: const Text('Plan Ruck with This Route'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _downloadGPX(context, route),
                icon: const Icon(Icons.download),
                label: const Text('Download GPX'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _shareRoute(context),
                icon: const Icon(Icons.share),
                label: const Text('Share Route'),
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
  
  void _shareRoute(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Route sharing coming soon!')),
    );
  }
  
  void _saveRoute(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Route saved to favorites!')),
    );
  }
  
  void _planRuckWithRoute(BuildContext context, Route route) {
    // Navigate to planned ruck creation with this route
    Navigator.of(context).pop(); // Go back with result
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Planning ruck with this route...')),
    );
  }
  
  void _downloadGPX(BuildContext context, Route route) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('GPX download starting...')),
    );
  }
}
