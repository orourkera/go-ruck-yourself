import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/models/route.dart' as route_model;
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/core/widgets/difficulty_badge.dart';

// Import enums for cleaner code
typedef Route = route_model.Route;
typedef RouteType = route_model.RouteType;
typedef RouteDifficulty = route_model.RouteDifficulty;

/// Card widget for previewing a route before import
class RoutePreviewCard extends StatelessWidget {
  final route_model.Route route;
  final List<String> warnings;
  final VoidCallback? onTap;
  final bool showImportButton;
  final VoidCallback? onImportPressed;

  const RoutePreviewCard({
    super.key,
    required this.route,
    this.warnings = const [],
    this.onTap,
    this.showImportButton = false,
    this.onImportPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with name and difficulty
              Row(
                children: [
                  Expanded(
                    child: Text(
                      route.name,
                      style: AppTextStyles.titleLarge.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (route.trailDifficulty != null) ...[
                    const SizedBox(width: 12),
                    DifficultyBadge(difficulty: route.trailDifficulty!),
                  ],
                ],
              ),

              const SizedBox(height: 8),

              // Source information instead of location
              if (route.source.isNotEmpty) ...[
                Row(
                  children: [
                    Icon(
                      Icons.source,
                      size: 16,
                      color: AppColors.textDarkSecondary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Source: ${route.source}',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textDarkSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              // Route stats
              Row(
                children: [
                  // Distance
                  _buildStatItem(
                    Icons.straighten,
                    _formatDistance(context, route.distanceKm),
                  ),
                  
                  // Elevation gain
                  if (route.elevationGainM != null) ...[
                    const SizedBox(width: 16),
                    _buildStatItem(
                      Icons.trending_up,
                      _formatElevation(context, route.elevationGainM!),
                    ),
                  ],

                ],
              ),

              // Route type
              if (route.trailType != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _getRouteTypeLabel(_parseRouteType(route.trailType!)),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],

              // Description
              if (route.description?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                Text(
                  route.description!,
                  style: AppTextStyles.bodyMedium,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // Ratings and usage info
              if (route.averageRating != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.star,
                      size: 16,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      route.averageRating!.toStringAsFixed(1),
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${route.totalCompletedCount} completed)',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textDarkSecondary,
                      ),
                    ),
                  ],
                ),
              ],

              // Warnings
              if (warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.warning.withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warning,
                            size: 16,
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Warnings',
                            style: AppTextStyles.titleSmall.copyWith(
                              color: AppColors.warning,
                              fontWeight: FontWeight.bold,
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
                            Container(
                              width: 4,
                              height: 4,
                              margin: const EdgeInsets.only(top: 6, right: 8),
                              decoration: BoxDecoration(
                                color: AppColors.warning,
                                shape: BoxShape.circle,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                warning,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.warning.withOpacity(0.8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
              ],

              // Import button
              if (showImportButton) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onImportPressed ?? onTap,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Import Route'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: AppColors.textDarkSecondary,
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textDarkSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // Helper methods to parse string properties to enums
  RouteType _parseRouteType(String type) {
    switch (type.toLowerCase()) {
      case 'loop':
        return RouteType.loop;
      case 'out_and_back':
      case 'out-and-back':
        return RouteType.outAndBack;
      case 'point_to_point':
      case 'point-to-point':
        return RouteType.pointToPoint;
      default:
        return RouteType.loop;
    }
  }

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

  /// Format distance using user's metric preference
  String _formatDistance(BuildContext context, double distanceKm) {
    final authState = context.read<AuthBloc>().state;
    final preferMetric = authState is Authenticated ? authState.user.preferMetric : true;
    return MeasurementUtils.formatDistance(distanceKm, metric: preferMetric);
  }

  /// Format elevation using user's metric preference
  String _formatElevation(BuildContext context, double elevationM) {
    final authState = context.read<AuthBloc>().state;
    final preferMetric = authState is Authenticated ? authState.user.preferMetric : true;
    return MeasurementUtils.formatSingleElevation(elevationM, metric: preferMetric);
  }
}

/// Compact version of route preview card
class CompactRoutePreviewCard extends StatelessWidget {
  final route_model.Route route;
  final VoidCallback? onTap;
  final bool showImportButton;

  const CompactRoutePreviewCard({
    super.key,
    required this.route,
    this.onTap,
    this.showImportButton = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Route info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      route.name,
                      style: AppTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.straighten,
                          size: 14,
                          color: AppColors.textDarkSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDistance(context, route.distanceKm),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textDarkSecondary,
                          ),
                        ),
                        if (route.trailDifficulty != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _getDifficultyColor(_parseDifficulty(route.trailDifficulty!)).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _getDifficultyLabel(_parseDifficulty(route.trailDifficulty!)),
                              style: AppTextStyles.bodySmall.copyWith(
                                color: _getDifficultyColor(_parseDifficulty(route.trailDifficulty!)),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Import button
              if (showImportButton) ...[
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(60, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('Import'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Helper method to parse string difficulty to enum
  RouteDifficulty _parseDifficulty(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'easy':
        return RouteDifficulty.easy;
      case 'moderate':
        return RouteDifficulty.moderate;
      case 'hard':
        return RouteDifficulty.hard;
      case 'extreme':
        return RouteDifficulty.extreme;
      default:
        return RouteDifficulty.easy;
    }
  }

  String _getDifficultyLabel(RouteDifficulty difficulty) {
    switch (difficulty) {
      case RouteDifficulty.easy:
        return 'Easy';
      case RouteDifficulty.moderate:
        return 'Moderate';
      case RouteDifficulty.hard:
        return 'Hard';
      case RouteDifficulty.extreme:
        return 'Extreme';
    }
  }

  Color _getDifficultyColor(RouteDifficulty difficulty) {
    switch (difficulty) {
      case RouteDifficulty.easy:
        return AppColors.success;
      case RouteDifficulty.moderate:
        return AppColors.warning;
      case RouteDifficulty.hard:
        return AppColors.error;
      case RouteDifficulty.extreme:
        return AppColors.error;
    }
  }

  /// Format distance using user's metric preference
  String _formatDistance(BuildContext context, double distanceKm) {
    final authState = context.read<AuthBloc>().state;
    final preferMetric = authState is Authenticated ? authState.user.preferMetric : true;
    return MeasurementUtils.formatDistance(distanceKm, metric: preferMetric);
  }

  /// Format elevation using user's metric preference
  String _formatElevation(BuildContext context, double elevationM) {
    final authState = context.read<AuthBloc>().state;
    final preferMetric = authState is Authenticated ? authState.user.preferMetric : true;
    return MeasurementUtils.formatSingleElevation(elevationM, metric: preferMetric);
  }
}
