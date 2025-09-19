import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/features/coaching/data/services/coaching_service.dart';
import 'package:rucking_app/features/coaching/presentation/screens/coaching_plan_details_screen.dart';
import 'package:rucking_app/features/coaching/presentation/screens/plan_creation_screen.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

class CoachingPlanCard extends StatefulWidget {
  const CoachingPlanCard({Key? key}) : super(key: key);

  @override
  State<CoachingPlanCard> createState() => _CoachingPlanCardState();
}

class _CoachingPlanCardState extends State<CoachingPlanCard> {
  final CoachingService _coachingService = GetIt.instance<CoachingService>();
  Map<String, dynamic>? _planData;
  Map<String, dynamic>? _progressData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlanData();
  }

  Future<void> _loadPlanData() async {
    try {
      final plan = await _coachingService.getActiveCoachingPlan();
      AppLogger.info('[COACHING_CARD] Loaded plan data: ${plan != null ? "HAS PLAN" : "NO PLAN"}');

      Map<String, dynamic>? progress;
      if (plan != null) {
        try {
          progress = await _coachingService.getCoachingPlanProgress();
        } catch (e) {
          AppLogger.error('Failed to load progress: $e');
        }
      }

      if (mounted) {
        setState(() {
          _planData = plan;
          _progressData = progress;
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.error('Failed to load coaching plan for home screen: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLogger.info('[COACHING_CARD] Building widget - isLoading: $_isLoading, planData: ${_planData != null ? "EXISTS" : "NULL"}');

    if (_isLoading) {
      return const SizedBox.shrink();
    }

    // ONLY show the "Start Your Coaching Journey" card if user has NO plan
    if (_planData == null) {
      AppLogger.info('[COACHING_CARD] Showing NO PLAN card');
      return _buildNoPlanCard();
    }

    // User HAS a plan - don't show anything on homepage
    AppLogger.info('[COACHING_CARD] User has plan - hiding card');
    return const SizedBox.shrink();
  }

  Widget _buildNoPlanCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const PlanCreationScreen(),
              ),
            ).then((_) {
              if (mounted) {
                _loadPlanData();
              }
            });
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withOpacity(0.05),
                  AppColors.primary.withOpacity(0.02),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.add_chart,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Start Your Coaching Journey',
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Get a personalized training plan',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textDarkSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: AppColors.primary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSessionDetail(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: AppColors.textDarkSecondary,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textDarkSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildActivePlanCard() {
    final planName = _planData!['plan_name'] ?? 'Training Plan';
    final currentWeek = _planData!['current_week'] ?? 1;
    final totalWeeks = _planData!['duration_weeks'] ?? 8;
    final coachingPersonality = _planData!['coaching_personality'] ?? 'Coach';

    // Progress data
    final adherence = _progressData?['adherence_percentage'] ?? 0;
    final completedSessions = _progressData?['completed_sessions'] ?? 0;
    final totalSessions = _progressData?['total_sessions'] ?? 0;

    // Next session details from backend
    final nextSession = _progressData?['next_session'] ?? {};
    final sessionType = nextSession['session_type'] ?? 'base_aerobic';
    final recommendation = nextSession['recommendation'] ?? {};
    final duration = recommendation['duration'] ?? '45 minutes';
    final intensity = recommendation['intensity'] ?? 'Conversational pace';
    final load = recommendation['load'] ?? 'Moderate';
    final description = recommendation['description'] ?? 'Training session';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CoachingPlanDetailsScreen(),
              ),
            ).then((_) => _loadPlanData()); // Reload when returning
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withOpacity(0.08),
                  AppColors.primary.withOpacity(0.03),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
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
                          color: AppColors.primary.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.fitness_center,
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
                              planName,
                              style: AppTextStyles.titleMedium.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textDark,
                              ),
                            ),
                            Text(
                              'Week $currentWeek of $totalWeeks • $coachingPersonality',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textDarkSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        color: AppColors.primary.withOpacity(0.5),
                        size: 18,
                      ),
                    ],
                  ),
                ),

                // Progress section
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Adherence bar
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'This Week',
                            style: AppTextStyles.bodySmall.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '$completedSessions/$totalSessions sessions',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textDarkSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: totalSessions > 0
                              ? completedSessions / totalSessions
                              : 0,
                          backgroundColor: AppColors.greyLight.withOpacity(0.3),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            adherence >= 70
                                ? AppColors.success
                                : AppColors.warning,
                          ),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Today's workout - more detailed
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.secondary.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.flag,
                                  size: 18,
                                  color: AppColors.secondary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'TODAY\'S GOAL',
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: AppColors.secondary,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              description,
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textDark,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 12,
                              children: [
                                _buildSessionDetail(Icons.timer, duration),
                                _buildSessionDetail(Icons.speed, intensity),
                                _buildSessionDetail(Icons.fitness_center, load),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
