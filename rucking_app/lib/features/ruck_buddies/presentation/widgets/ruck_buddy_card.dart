import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/ruck_buddy.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/user_info.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:provider/provider.dart';

class RuckBuddyCard extends StatelessWidget {
  final RuckBuddy ruckBuddy;

  const RuckBuddyCard({
    Key? key,
    required this.ruckBuddy,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authBloc = Provider.of<AuthBloc>(context, listen: false);
    final bool preferMetric = authBloc.state is Authenticated
        ? (authBloc.state as Authenticated).user.preferMetric
        : false;
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Info Row
            Row(
              children: [
                // Avatar (fallback to circle with first letter if no URL)
                _buildAvatar(ruckBuddy.user),
                const SizedBox(width: 12),
                
                // User Name & Time Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ruckBuddy.user.username,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _formatCompletedDate(ruckBuddy.completedAt),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Weight chip
                Chip(
                  backgroundColor: AppColors.secondary,
                  label: Text(
                    _formatWeight(ruckBuddy.ruckWeightKg, preferMetric),
                    style: AppTextStyles.labelMedium.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            
            const Divider(height: 24),
            
            // Stats Grid (2x2)
            Row(
              children: [
                // Left column
                Expanded(
                  child: Column(
                    children: [
                      _buildStatTile(
                        context: context,
                        icon: Icons.straighten, 
                        label: 'Distance',
                        value: MeasurementUtils.formatDistance(ruckBuddy.distanceKm, metric: preferMetric),
                      ),
                      const SizedBox(height: 16),
                      _buildStatTile(
                        context: context,
                        icon: Icons.local_fire_department, 
                        label: 'Calories',
                        value: '${ruckBuddy.caloriesBurned} kcal',
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(width: 24),
                
                // Right column
                Expanded(
                  child: Column(
                    children: [
                      _buildStatTile(
                        context: context,
                        icon: Icons.timer, 
                        label: 'Duration',
                        value: MeasurementUtils.formatDuration(Duration(seconds: ruckBuddy.durationSeconds)),
                      ),
                      const SizedBox(height: 16),
                      _buildStatTile(
                        context: context,
                        icon: Icons.terrain, 
                        label: 'Elevation',
                        value: '+${ruckBuddy.elevationGainM.toStringAsFixed(0)}/${ruckBuddy.elevationLossM.toStringAsFixed(0)}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAvatar(UserInfo user) {
    if (user.photoUrl != null && user.photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 20,
        backgroundImage: NetworkImage(user.photoUrl!),
      );
    } else {
      final String initial = user.username.isNotEmpty 
        ? user.username[0].toUpperCase() 
        : 'R';
        : 'R';
      
      return CircleAvatar(
        radius: 20,
        backgroundColor: AppColors.primary,
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
  }
  
  String _formatCompletedDate(DateTime? completedAt) {
    if (completedAt == null) return 'Unknown date';
    
    final now = DateTime.now();
    final difference = now.difference(completedAt);
    
    if (difference.inDays == 0) {
      // Today
      return 'Today, ${DateFormat.jm().format(completedAt)}';
    } else if (difference.inDays == 1) {
      // Yesterday
      return 'Yesterday, ${DateFormat.jm().format(completedAt)}';
    } else if (difference.inDays < 7) {
      // Within last week
      return '${difference.inDays} days ago';
    } else {
      // More than a week ago
      return DateFormat.MMMd().format(completedAt);
    }
  }
  
  String _formatWeight(double weightKg, bool preferMetric) {
    if (preferMetric) {
      return '${weightKg.toStringAsFixed(1)} kg';
    } else {
      final double weightLbs = weightKg * 2.20462;
      return '${weightLbs.toStringAsFixed(0)} lb';
    }
  }
  
  Widget _buildStatTile({
    required BuildContext context,
    required IconData icon, 
    required String label, 
    required String value,
  }) {
    return Row(
      children: [
        Icon(
          icon, 
          size: 20, 
          color: AppColors.secondary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              Text(
                value,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
