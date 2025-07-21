import 'package:flutter/material.dart';
import '../../data/models/leaderboard_user_model.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../../core/utils/measurement_utils.dart';

/// Well I'll be hornswoggled! This row shows each rucker prettier than a prize pig
class LeaderboardRow extends StatelessWidget {
  final LeaderboardUserModel user;
  final int rank;
  final bool isUpdating;

  const LeaderboardRow({
    Key? key,
    required this.user,
    required this.rank,
    this.isUpdating = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _getRowColor(context),
        borderRadius: BorderRadius.circular(8),
        border: user.isCurrentUser 
            ? Border.all(
                color: Theme.of(context).primaryColor,
                width: 2,
              )
            : null,
        boxShadow: user.isCurrentUser
            ? [
                BoxShadow(
                  color: Theme.of(context).primaryColor.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _navigateToProfile(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                // Main row with stats
                Row(
                  children: [
                    // Rank with medal
                    _buildRankColumn(),
                    
                    // User info
                    _buildUserColumn(context),
                    
                    // Stats columns
                    _buildStatColumn(
                      user.stats.totalRucks.toString(),
                      flex: 1,
                    ),
                    _buildStatColumn(
                      MeasurementUtils.formatDistance(user.stats.distanceKm, metric: true),
                      flex: 2,
                    ),
                    _buildStatColumn(
                      MeasurementUtils.formatElevation(user.stats.elevationGainMeters, 0.0, metric: true),
                      flex: 2,
                    ),
                    _buildStatColumn(
                      MeasurementUtils.formatCalories(user.stats.caloriesBurned.round()),
                      flex: 2,
                    ),
                    _buildStatColumn(
                      _formatPowerPoints(user.stats.powerPoints),
                      flex: 2,
                      isPowerPoints: true,
                    ),
                  ],
                ),
                
                // Location row (if available)
                if (user.lastRuckLocation != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const SizedBox(width: 40), // Align with rank
                      const SizedBox(width: 8),
                      Icon(
                        Icons.location_on,
                        size: 12,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        user.lastRuckLocation!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build rank column with fancy medals for top 3
  Widget _buildRankColumn() {
    return SizedBox(
      width: 40,
      child: Column(
        children: [
          if (rank <= 3) ...[
            Text(
              _getRankEmoji(),
              style: const TextStyle(fontSize: 20),
            ),
          ] else ...[
            Text(
              rank.toString(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  /// Build user column with avatar and name
  Widget _buildUserColumn(BuildContext context) {
    return SizedBox(
      width: 140, // Fixed width for user column
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Row(
          children: [
            // Avatar
            Stack(
              children: [
                UserAvatar(
                  avatarUrl: user.avatarUrl,
                  username: user.username,
                  size: 36,
                ),
                // Live indicator for currently rucking
                if (user.isCurrentlyRucking)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            
            // Username and live status
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '@${user.username}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (user.isCurrentlyRucking) ...[
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Colors.green.withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        'LIVE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build stat column
  Widget _buildStatColumn(
    String value, {
    int flex = 1,
    bool isPowerPoints = false,
  }) {
    double width = flex == 1 ? 50.0 : 80.0; // Base width and wider for multi-flex columns
    return SizedBox(
      width: width,
      child: Text(
        value,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: isPowerPoints ? Colors.amber.shade700 : null,
        ),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Get row background color
  Color _getRowColor(BuildContext context) {
    if (user.isCurrentUser) {
      return Theme.of(context).primaryColor.withOpacity(0.05);
    } else if (rank <= 3) {
      return _getMedalColor().withOpacity(0.05);
    } else if (isUpdating) {
      return Colors.green.withOpacity(0.05);
    }
    return Theme.of(context).cardColor;
  }

  /// Get rank emoji for top 3
  String _getRankEmoji() {
    switch (rank) {
      case 1:
        return '🥇';
      case 2:
        return '🥈';
      case 3:
        return '🥉';
      default:
        return '';
    }
  }

  /// Get medal color for top 3
  Color _getMedalColor() {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700); // Gold
      case 2:
        return const Color(0xFFC0C0C0); // Silver
      case 3:
        return const Color(0xFFCD7F32); // Bronze
      default:
        return Colors.grey;
    }
  }

  /// Navigate to user's public profile
  void _navigateToProfile(BuildContext context) {
    Navigator.pushNamed(
      context,
      '/profile/${user.id}',
    );
  }

  /// Format power points with nice abbreviations
  String _formatPowerPoints(double points) {
    if (points >= 1000000) {
      return '${(points / 1000000).toStringAsFixed(1)}M';
    } else if (points >= 1000) {
      return '${(points / 1000).toStringAsFixed(1)}k';
    } else {
      return points.toStringAsFixed(0);
    }
  }
}
