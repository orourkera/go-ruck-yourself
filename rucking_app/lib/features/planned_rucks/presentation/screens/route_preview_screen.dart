import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/models/route.dart' as route_model;
import 'package:rucking_app/features/planned_rucks/presentation/bloc/route_import_bloc.dart';
import 'package:rucking_app/shared/widgets/buttons/primary_button.dart';
import 'package:rucking_app/shared/widgets/buttons/secondary_button.dart';
import 'package:rucking_app/shared/widgets/loading_states/loading_overlay.dart';
import 'package:rucking_app/features/planned_rucks/presentation/widgets/route_map_preview.dart';
import 'package:rucking_app/features/planned_rucks/presentation/widgets/elevation_profile_chart.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// String extension for capitalizing first letter
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1).toLowerCase();
  }
}

/// 🗺️ **Route Preview Screen**
/// 
/// Detailed preview of a route before importing or planning a ruck
class RoutePreviewScreen extends StatefulWidget {
  final String routeId;
  
  const RoutePreviewScreen({
    Key? key,
    required this.routeId,
  }) : super(key: key);

  @override
  State<RoutePreviewScreen> createState() => _RoutePreviewScreenState();
}

class _RoutePreviewScreenState extends State<RoutePreviewScreen> {
  late TextEditingController _titleController;
  
  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
  }
  
  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Route Preview',
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark 
                ? AppColors.textLight 
                : Colors.white,
          ),
        ),
        backgroundColor: Theme.of(context).brightness == Brightness.dark 
            ? AppColors.surfaceDark 
            : AppColors.primary,
        foregroundColor: Theme.of(context).brightness == Brightness.dark 
            ? AppColors.textLight 
            : Colors.white,
        elevation: 2,
        // No actions needed for import preview
      ),
      body: BlocBuilder<RouteImportBloc, RouteImportState>(
        builder: (context, state) {
          if (state is RouteImportInProgress) {
            return LoadingOverlay(
              isVisible: true,
              message: 'Loading route preview...',
              child: Container(),
            );
          }
          
          if (state is RouteImportError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
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
          
          // Get the actual route data from the BLoC state
          route_model.Route? route;
          List<String> warnings = [];
          
          if (state is RouteImportPreview) {
            route = state.route;
            warnings = state.warnings;
          } else if (state is RouteImportValidated) {
            route = state.route;
            warnings = state.warnings;
          } else if (state is RouteImportSuccess) {
            route = state.importedRoute;
          }
          
          if (route == null) {
            return const Center(
              child: Text('No route data available'),
            );
          }
          
          // Update the title controller when route data changes
          if (_titleController.text.isEmpty && route.name.isNotEmpty) {
            _titleController.text = route.name;
          }
          
          // Update the title controller when route data changes
          if (_titleController.text.isEmpty && route.name.isNotEmpty) {
            _titleController.text = route.name;
          }
          
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Show warnings if any
                if (warnings.isNotEmpty) ...[
                  _buildWarningsSection(warnings),
                  const SizedBox(height: 16),
                ],
                
                // Route Header
                _buildRouteHeader(context, route),
                const SizedBox(height: 24),
                
                // Route Map
                _buildRouteMap(context, route),
                const SizedBox(height: 24),
                
                // Route Stats
                _buildRouteStats(context, route),
                const SizedBox(height: 24),
                
                // Elevation Profile
                _buildElevationProfile(context, route),
                const SizedBox(height: 24),
                
                // Route Details
                _buildRouteDetails(context, route),
                const SizedBox(height: 24),
                
                // Action Buttons
                _buildActionButtons(context, route),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildWarningsSection(List<String> warnings) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.warning.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber,
                color: AppColors.warning,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Import Warnings',
                style: AppTextStyles.titleSmall.copyWith(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...warnings.map((warning) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '• ',
                  style: TextStyle(color: AppColors.warning),
                ),
                Expanded(
                  child: Text(
                    warning,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textDark,
                    ),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
  
  Widget _buildRouteHeader(BuildContext context, route_model.Route route) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _titleController,
          style: AppTextStyles.headlineMedium.copyWith(
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            hintText: 'Enter route name...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.primary),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.primary.withOpacity(0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
      ],
    );
  }
  
  Widget _buildRouteMap(BuildContext context, route_model.Route route) {
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: RouteMapPreview(
                  route: route,
                  isInteractive: true,
                  showOverlay: false,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildRouteStats(BuildContext context, route_model.Route route) {
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
                    '${route.distanceKm.toStringAsFixed(1)} km',
                    Icons.straighten,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    context,
                    'Ascent',
                    '+${route.elevationGainM?.toStringAsFixed(0) ?? '0'}m',
                    Icons.trending_up,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    context,
                    'Difficulty',
                    route.trailDifficulty?.toString().replaceAll('TrailDifficulty.', '').capitalize() ?? 'Unknown',
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
  
  Widget _buildElevationProfile(BuildContext context, route_model.Route route) {
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
            // Show elevation chart if we have elevation data, otherwise show placeholder
            route.elevationPoints.isNotEmpty
                ? ElevationProfileChart(
                    elevationData: route.elevationPoints,
                    route: route,
                    height: 200,
                    showDetailedTooltips: true,
                    showGradientAreas: true,
                    isInteractive: true,
                  )
                : Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: AppColors.backgroundLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.show_chart,
                            size: 48,
                            color: AppColors.getSecondaryTextColor(context),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No elevation data available',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.getSecondaryTextColor(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildRouteDetails(BuildContext context, route_model.Route route) {
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
            _buildDetailRow(context, 'Source', route.source ?? 'GPX Import'),
            _buildDetailRow(context, 'Created', _formatTodaysDate()),
            if (route.pointsOfInterest.isNotEmpty)
              _buildDetailRow(context, 'Points of Interest', '${route.pointsOfInterest.length} locations'),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDetailRow(BuildContext context, String label, String value) {
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
  
  Widget _buildActionButtons(BuildContext context, route_model.Route route) {
    return Column(
      children: [
        // Save Route button (primary action)
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _saveRouteWithCustomName(context, route),
            icon: const Icon(Icons.save),
            label: const Text('Save Route'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(16),
            ),
          ),
        ),
        // No secondary actions needed for import preview
      ],
    );
  }
  
  String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown';
    return '${date.day}/${date.month}/${date.year}';
  }
  
  String _formatTodaysDate() {
    final now = DateTime.now();
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    
    String getDayWithSuffix(int day) {
      if (day >= 11 && day <= 13) {
        return '${day}th';
      }
      switch (day % 10) {
        case 1: return '${day}st';
        case 2: return '${day}nd';
        case 3: return '${day}rd';
        default: return '${day}th';
      }
    }
    
    return '${months[now.month - 1]} ${getDayWithSuffix(now.day)}, ${now.year}';
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
  
  void _saveRouteWithCustomName(BuildContext context, route_model.Route route) {
    // Create updated route with custom name
    final updatedRoute = route.copyWith(
      name: _titleController.text.trim().isNotEmpty ? _titleController.text.trim() : route.name,
    );
    
    // Trigger the import action in the bloc
    context.read<RouteImportBloc>().add(ConfirmImport(
      route: updatedRoute,
    ));
    
    // Navigate back to routes list
    Navigator.of(context).pop();
    Navigator.of(context).pop();
  }
  
  void _importRoute(BuildContext context, route_model.Route route) {
    // Trigger the import action in the bloc
    context.read<RouteImportBloc>().add(ConfirmImport(
      route: route,
    ));
    
    // Navigate back to routes list
    Navigator.of(context).pop();
    Navigator.of(context).pop();
  }
  
  void _planRuckWithRoute(BuildContext context, route_model.Route route) {
    // Navigate to planned ruck creation with this route
    Navigator.of(context).pop(); // Go back with result
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Planning ruck with this route...')),
    );
  }
  
  void _downloadGPX(BuildContext context, route_model.Route route) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('GPX download starting...')),
    );
  }
}
