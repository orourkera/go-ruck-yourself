import 'package:flutter/material.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/network/api_endpoints.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RuckerRatingWidget extends StatefulWidget {
  final Function(Map<String, dynamic>)? onInsightsLoaded;

  const RuckerRatingWidget({
    Key? key,
    this.onInsightsLoaded,
  }) : super(key: key);

  @override
  State<RuckerRatingWidget> createState() => _RuckerRatingWidgetState();
}

class _RuckerRatingWidgetState extends State<RuckerRatingWidget> {
  final ApiClient _apiClient = GetIt.instance<ApiClient>();
  Map<String, dynamic>? _userInsights;
  bool _isLoading = true;
  bool _useMetric = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      // Load metric preference
      final prefs = await SharedPreferences.getInstance();
      _useMetric = prefs.getBool('prefer_metric') ??
          prefs.getBool('preferMetric') ??
          true;

      // Fetch user insights
      final response = await _apiClient.get(
        ApiEndpoints.userInsights,
        queryParams: {'fresh': 1},
      );

      bool? preferMetricFromServer;
      if (response is Map<String, dynamic>) {
        final insights = response['insights'];
        if (insights is Map<String, dynamic>) {
          final facts = insights['facts'];
          if (facts is Map<String, dynamic>) {
            final preferMetricValue = facts['prefer_metric'];
            if (preferMetricValue is bool) {
              preferMetricFromServer = preferMetricValue;
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          if (preferMetricFromServer != null) {
            _useMetric = preferMetricFromServer!;
          }
          _userInsights = response;
          _isLoading = false;
        });

        // Call the callback with the insights data
        if (widget.onInsightsLoaded != null && response != null) {
          widget.onInsightsLoaded!(_extractRatingData());
        }
      }
    } catch (e) {
      AppLogger.error('Failed to load rucker rating data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Map<String, dynamic> _extractRatingData() {
    if (_userInsights == null) return {};

    final insights =
        Map<String, dynamic>.from(_userInsights!['insights'] ?? {});
    final facts = Map<String, dynamic>.from(insights['facts'] ?? {});

    // Extract key metrics
    final totals30d = Map<String, dynamic>.from(facts['totals_30d'] ?? {});
    final allTime = Map<String, dynamic>.from(facts['all_time'] ?? {});
    final demographics = Map<String, dynamic>.from(facts['demographics'] ?? {});
    final user = Map<String, dynamic>.from(facts['user'] ?? {});
    final recency = Map<String, dynamic>.from(facts['recency'] ?? {});
    final splits = facts['recent_splits'] as List? ?? [];
    final preferMetric = facts['prefer_metric'] as bool?;
    final averageRuckWeightKg =
        (facts['average_ruck_weight_kg'] as num?)?.toDouble();

    // Calculate average pace from recent splits
    double avgPaceMinPerKm = 0;
    if (splits.isNotEmpty) {
      double totalPace = 0;
      int validSplits = 0;
      for (var session in splits) {
        final sessionSplits = session['splits'] as List? ?? [];
        for (var split in sessionSplits) {
          final paceSeconds = split['pace_s_per_km'];
          if (paceSeconds != null && paceSeconds > 0) {
            totalPace += paceSeconds / 60.0; // Convert to minutes
            validSplits++;
          }
        }
      }
      if (validSplits > 0) {
        avgPaceMinPerKm = totalPace / validSplits;
      }
    }

    // Get sessions and distance
    final sessions30d = totals30d['sessions'] as int? ?? 0;
    final distance30d = (totals30d['distance_km'] as num?)?.toDouble() ?? 0.0;
    final avgSessionDistance =
        sessions30d > 0 ? distance30d / sessions30d : 0.0;

    // Get weight data
    final userWeight = (user['weight'] as num?)?.toDouble() ??
        (demographics['weight'] as num?)?.toDouble();

    // Get usual ruck weight (from recent sessions or equipment settings)
    double? ruckWeight = (recency['last_ruck_weight_kg'] as num?)?.toDouble();
    if (ruckWeight != null && ruckWeight <= 0) {
      ruckWeight = null;
    }
    final equipmentWeight = (user['equipment_weight_kg'] as num?)?.toDouble();
    if ((ruckWeight == null || ruckWeight <= 0) &&
        averageRuckWeightKg != null &&
        averageRuckWeightKg > 0) {
      ruckWeight = averageRuckWeightKg;
    }
    if ((ruckWeight == null || ruckWeight <= 0) &&
        equipmentWeight != null &&
        equipmentWeight > 0) {
      ruckWeight = equipmentWeight;
    }
    if (ruckWeight == null || ruckWeight <= 0) {
      final insightsWeight = (insights['ruck_weight'] as num?)?.toDouble() ??
          (facts['average_ruck_weight'] as num?)?.toDouble();
      if (insightsWeight != null && insightsWeight > 0) {
        ruckWeight = insightsWeight;
      }
    }

    // Calculate experience level
    final allTimeSessions = allTime['sessions'] as int? ?? 0;
    String experienceLevel;
    if (allTimeSessions >= 50) {
      experienceLevel = 'Advanced';
    } else if (allTimeSessions >= 20) {
      experienceLevel = 'Intermediate';
    } else {
      experienceLevel = 'Beginner';
    }

    // Calculate weekly average
    final weeklyAvg = sessions30d / 4.3; // ~4.3 weeks in 30 days

    return {
      'experience_level': experienceLevel,
      'total_sessions': allTimeSessions,
      'sessions_30d': sessions30d,
      'weekly_avg': weeklyAvg,
      'avg_distance': avgSessionDistance,
      'avg_pace': avgPaceMinPerKm,
      'user_weight': userWeight,
      'ruck_weight': ruckWeight,
      'total_distance': (allTime['distance_km'] as num?)?.toDouble() ?? 0.0,
      'average_ruck_weight': averageRuckWeightKg,
      'prefer_metric': preferMetric ?? _useMetric,
    };
  }

  String _formatPace(double paceMinPerKm) {
    if (paceMinPerKm <= 0) return '--:--';
    var paceValue = paceMinPerKm;
    if (!_useMetric) {
      paceValue = paceMinPerKm / 0.621371; // Convert to min/mi
    }
    final minutes = paceValue.floor();
    final seconds = ((paceValue - minutes) * 60).round();
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDistance(double km) {
    if (!_useMetric) {
      final miles = km * 0.621371;
      return '${miles.toStringAsFixed(1)} mi';
    }
    return '${km.toStringAsFixed(1)} km';
  }

  String _formatWeight(double? kg) {
    if (kg == null || kg <= 0) return '--';
    if (!_useMetric) {
      final lbs = kg * 2.20462;
      return '${lbs.round()} lbs';
    }
    return '${kg.round()} kg';
  }

  Color _getRatingColor(String level) {
    switch (level) {
      case 'Advanced':
        return AppColors.success;
      case 'Intermediate':
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withOpacity(0.05),
              AppColors.primary.withOpacity(0.02),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.1),
          ),
        ),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final ratingData = _extractRatingData();
    if (ratingData.isEmpty || ratingData['total_sessions'] == 0) {
      // New user - no rating yet
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withOpacity(0.05),
              AppColors.primary.withOpacity(0.02),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.1),
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.trending_up,
              size: 48,
              color: AppColors.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'Build Your Rucker Rating',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Complete a few rucks to unlock personalized insights and recommendations',
              style: AppTextStyles.bodySmall.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withOpacity(0.08),
            AppColors.primary.withOpacity(0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.1),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.assessment,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Rucker Rating',
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                      Text(
                        ratingData['experience_level'],
                        style: AppTextStyles.bodySmall.copyWith(
                          color:
                              _getRatingColor(ratingData['experience_level']),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getRatingColor(ratingData['experience_level'])
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${ratingData['total_sessions']} rucks',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: _getRatingColor(ratingData['experience_level']),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Stats Grid
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // First Row - Frequency & Distance
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.calendar_today,
                        label: 'Weekly Avg',
                        value:
                            '${ratingData['weekly_avg'].toStringAsFixed(1)}x',
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.route,
                        label: 'Avg Distance',
                        value: _formatDistance(ratingData['avg_distance']),
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Second Row - Pace & Weight
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.speed,
                        label: 'Avg Pace',
                        value:
                            '${_formatPace(ratingData['avg_pace'])}/${_useMetric ? "km" : "mi"}',
                        color: AppColors.success,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.fitness_center,
                        label: 'Ruck Weight',
                        value: _formatWeight(ratingData['ruck_weight']),
                        color: AppColors.warning,
                      ),
                    ),
                  ],
                ),

                // User weight if available
                if (ratingData['user_weight'] != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.person,
                          size: 18,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Body Weight: ${_formatWeight(ratingData['user_weight'])}',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Load: ${((ratingData['ruck_weight'] ?? 0) / (ratingData['user_weight'] ?? 1) * 100).round()}%',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: AppTextStyles.labelSmall.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
