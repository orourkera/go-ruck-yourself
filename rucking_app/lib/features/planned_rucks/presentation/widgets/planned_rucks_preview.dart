import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:rucking_app/core/di/injection_container.dart';
import 'package:rucking_app/core/models/planned_ruck.dart';
import 'package:rucking_app/core/theme/app_colors.dart';
import 'package:rucking_app/core/theme/app_text_styles.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/planned_ruck_bloc.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/planned_ruck_event.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/planned_ruck_state.dart';
import 'package:rucking_app/core/navigation/alltrails_router.dart';

/// Preview widget for planned rucks on the home screen
class PlannedRucksPreview extends StatelessWidget {
  const PlannedRucksPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<PlannedRuckBloc>()..add(LoadPlannedRucks()),
      child: BlocBuilder<PlannedRuckBloc, PlannedRuckState>(
        builder: (context, state) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.backgroundLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.greyLight,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with title and action button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Planned Rucks',
                      style: AppTextStyles.titleMedium.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _navigateToMyRucks(context),
                      child: Text(
                        'View All',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Content based on state
                if (state is PlannedRuckLoading)
                  _buildLoadingState()
                else if (state is PlannedRuckError)
                  _buildErrorState(context, state.message)
                else if (state is PlannedRuckLoaded)
                  _buildLoadedState(context, state.plannedRucks)
                else
                  _buildEmptyState(context),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Icon(
              Icons.error_outline,
              color: AppColors.error,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              'Failed to load planned rucks',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textDarkSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                context.read<PlannedRuckBloc>().add(LoadPlannedRucks());
              },
              child: Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadedState(BuildContext context, List<PlannedRuck> plannedRucks) {
    if (plannedRucks.isEmpty) {
      return _buildEmptyState(context);
    }

    // Show up to 2 planned rucks
    final previewRucks = plannedRucks.take(2).toList();
    
    return Column(
      children: [
        ...previewRucks.map((ruck) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildPlannedRuckPreviewItem(context, ruck),
        )),
        
        if (plannedRucks.length > 2) ...[
          const SizedBox(height: 8),
          Text(
            '+${plannedRucks.length - 2} more planned rucks',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textDarkSecondary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Column(
      children: [
        Icon(
          Icons.route_outlined,
          color: AppColors.textDarkSecondary,
          size: 32,
        ),
        const SizedBox(height: 8),
        Text(
          'No planned rucks yet',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textDarkSecondary,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _navigateToRouteImport(context),
            icon: const Icon(Icons.add),
            label: const Text('Plan Your First Ruck'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlannedRuckPreviewItem(BuildContext context, PlannedRuck ruck) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.greyLight,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          // Status indicator
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: _getStatusColor(ruck.status),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          
          // Ruck details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ruck.route?.name ?? ruck.notes ?? 'Planned Ruck',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                if (ruck.route != null) ...[
                  Text(
                    '${(ruck.route!.distanceKm).toStringAsFixed(1)} km',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textDarkSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getStatusColor(ruck.status).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _getStatusText(ruck.status),
              style: AppTextStyles.bodySmall.copyWith(
                color: _getStatusColor(ruck.status),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(PlannedRuckStatus status) {
    switch (status) {
      case PlannedRuckStatus.planned:
        return AppColors.primary;
      case PlannedRuckStatus.inProgress:
        return AppColors.secondary;
      case PlannedRuckStatus.completed:
        return AppColors.accent;
      case PlannedRuckStatus.cancelled:
        return AppColors.textDarkSecondary;
    }
  }

  String _getStatusText(PlannedRuckStatus status) {
    switch (status) {
      case PlannedRuckStatus.planned:
        return 'Planned';
      case PlannedRuckStatus.inProgress:
        return 'Active';
      case PlannedRuckStatus.completed:
        return 'Done';
      case PlannedRuckStatus.cancelled:
        return 'Cancelled';
    }
  }

  void _navigateToMyRucks(BuildContext context) {
    context.go(AllTrailsRouter.myRucks);
  }

  void _navigateToRouteImport(BuildContext context) {
    context.go('${AllTrailsRouter.myRucks}/import');
  }
}
