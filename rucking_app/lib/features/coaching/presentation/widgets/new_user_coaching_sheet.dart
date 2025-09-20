import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/features/coaching/data/services/coaching_service.dart';
import 'package:rucking_app/features/coaching/domain/models/coaching_personality.dart';
import 'package:rucking_app/features/coaching/domain/models/plan_personalization.dart';
import 'package:rucking_app/features/coaching/presentation/screens/plan_creation_screen.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

class NewUserCoachingSheet extends StatefulWidget {
  const NewUserCoachingSheet({Key? key}) : super(key: key);

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const NewUserCoachingSheet(),
    );
  }

  @override
  State<NewUserCoachingSheet> createState() => _NewUserCoachingSheetState();
}

class _NewUserCoachingSheetState extends State<NewUserCoachingSheet> {
  bool _isCreatingQuickStart = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'New to rucking? Start here.',
                style: AppTextStyles.displayMedium.copyWith(
                  color: AppColors.primary,
                  fontSize: 28,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Kick off with a 7-day quick start (four short rucks this week), then upgrade to a fully personalized plan whenever you want.',
                style: AppTextStyles.bodyLarge.copyWith(
                  color: Colors.grey[700],
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              _buildBulletPoint(
                icon: Icons.flag,
                title: 'Quick 7-day challenge: complete 4 rucks to build your habit',
                color: AppColors.primary,
              ),
              const SizedBox(height: 16),
              _buildBulletPoint(
                icon: Icons.notifications_active,
                title: 'Daily coaching nudges to keep momentum up',
                color: AppColors.secondary,
              ),
              const SizedBox(height: 16),
              _buildBulletPoint(
                icon: Icons.tune,
                title: 'Upgrade to a full science-backed plan anytime',
                color: AppColors.success,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      _isCreatingQuickStart ? null : _startQuickStartPlan,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 4,
                  ),
                  child: _isCreatingQuickStart
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Starting your 7-day challenge...',
                              style: AppTextStyles.titleMedium.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          'Start 7-Day Quick Start',
                          style: AppTextStyles.titleLarge.copyWith(
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PlanCreationScreen(),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(color: AppColors.primary, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Build a full personalized plan',
                    style: AppTextStyles.titleMedium.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Maybe later',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBulletPoint({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: color,
            size: 20,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: Text(
              title,
              style: AppTextStyles.bodyLarge.copyWith(
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _startQuickStartPlan() async {
    setState(() {
      _isCreatingQuickStart = true;
    });

    final coachingService = GetIt.instance<CoachingService>();
    final personalization = _buildQuickStartPersonalization();

    try {
      await coachingService.createCoachingPlan(
        basePlanId: 'daily-discipline',
        coachingPersonality: CoachingPersonality.supportiveFriend.id,
        personalization: personalization,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Your 7-day quick start is ready! Let\'s hit 4 rucks this week to build your habit.',
          ),
          backgroundColor: AppColors.primary,
          duration: const Duration(seconds: 4),
        ),
      );

      Navigator.pop(context);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isCreatingQuickStart = false;
      });

      final message = error.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn\'t start quick challenge: $message'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  PlanPersonalization _buildQuickStartPersonalization() {
    final preferredDays = <String>[];
    final now = DateTime.now();

    for (int i = 0; i < 7 && preferredDays.length < 4; i++) {
      final futureDate = now.add(Duration(days: i));
      final weekdayIndex = (futureDate.weekday - 1)
          .clamp(0, PlanPersonalization.weekdays.length - 1);
      final weekdayName = PlanPersonalization.weekdays[weekdayIndex];
      if (!preferredDays.contains(weekdayName)) {
        preferredDays.add(weekdayName);
      }
    }

    return PlanPersonalization(
      why: const ['Build a rucking habit'],
      successDefinition: 'Complete 4 rucks in 7 days to activate habit formation',
      trainingDaysPerWeek: 4,
      preferredDays: preferredDays,
      challenges: const ['Time', 'Motivation'],
      minimumSessionMinutes: 25,
      unloadedOk: true,
      streakTargetDays: 7,
      streakTargetRucks: 4,
      streakTimeframeDays: 7,
      equipmentType: 'none',
      equipmentWeight: 0.0,
    );
  }
}
