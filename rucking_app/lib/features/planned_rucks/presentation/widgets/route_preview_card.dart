import 'package:flutter/material.dart';
import 'package:rucking_app/core/models/route.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/core/widgets/difficulty_badge.dart';

/// Card widget for previewing a route before import
class RoutePreviewCard extends StatelessWidget {
  final Route route;
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
                      style: AppTextStyles.headline6.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (route.difficulty != null) ...[
                    const SizedBox(width: 12),
                    DifficultyBadge(difficulty: route.difficulty!),
                  ],
                ],
              ),

              const SizedBox(height: 8),

              // Location
              if (route.location?.isNotEmpty == true) ...[
                Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        route.location!,
                        style: AppTextStyles.body2.copyWith(
                          color: AppColors.textSecondary,
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
                    route.formattedDistance,
                  ),
                  
                  // Elevation gain
                  if (route.elevationGain != null) ...[
                    const SizedBox(width: 16),
                    _buildStatItem(
                      Icons.trending_up,
                      route.formattedElevationGain,
                    ),
                  ],
                  
                  // Duration
                  if (route.duration != null) ...[
                    const SizedBox(width: 16),
                    _buildStatItem(
                      Icons.access_time,
                      route.formattedDuration,
                    ),
                  ],
                ],
              ),

              // Route type
              if (route.routeType != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _getRouteTypeLabel(route.routeType!),
                    style: AppTextStyles.caption.copyWith(
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
                  style: AppTextStyles.body2,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // Ratings and popularity
              if (route.averageRating != null || route.totalReviews != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (route.averageRating != null) ...[
                      Icon(
                        Icons.star,
                        size: 16,
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        route.averageRating!.toStringAsFixed(1),
                        style: AppTextStyles.body2.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (route.totalReviews != null) ...[
                      if (route.averageRating != null) const SizedBox(width: 8),
                      Text(
                        '(${route.totalReviews} reviews)',
                        style: AppTextStyles.body2.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
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
                            style: AppTextStyles.subtitle2.copyWith(
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
                                style: AppTextStyles.body2.copyWith(
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
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: AppTextStyles.body2.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
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
}

/// Compact version of route preview card
class CompactRoutePreviewCard extends StatelessWidget {
  final Route route;
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
                      style: AppTextStyles.subtitle2.copyWith(
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
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          route.formattedDistance,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (route.difficulty != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _getDifficultyColor(route.difficulty!).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _getDifficultyLabel(route.difficulty!),
                              style: AppTextStyles.caption.copyWith(
                                color: _getDifficultyColor(route.difficulty!),
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

  String _getDifficultyLabel(RouteDifficulty difficulty) {
    switch (difficulty) {
      case RouteDifficulty.easy:
        return 'Easy';
      case RouteDifficulty.moderate:
        return 'Moderate';
      case RouteDifficulty.hard:
        return 'Hard';
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
    }
  }
}
