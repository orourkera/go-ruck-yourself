import 'package:flutter/material.dart';
import 'package:rucking_app/features/coaching/domain/models/coaching_plan_type.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

class PlanPreviewCard extends StatelessWidget {
  final CoachingPlanType planType;

  const PlanPreviewCard({
    super.key,
    required this.planType,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              planType.color.withOpacity(0.15),
              planType.color.withOpacity(0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with emoji and title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: planType.color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    planType.emoji,
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        planType.name,
                        style: AppTextStyles.headlineMedium.copyWith(
                          fontWeight: FontWeight.bold,
                          color: planType.color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: planType.color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: planType.color.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          planType.duration,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: planType.color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Description
            Text(
              planType.description,
              style: AppTextStyles.bodyLarge.copyWith(
                height: 1.5,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 24),
            
            // Plan features based on type
            _buildPlanFeatures(),
            const SizedBox(height: 20),
            
            // Success metrics preview
            _buildSuccessMetrics(),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanFeatures() {
    List<String> features;
    
    switch (planType.id) {
      case 'fat-loss':
        features = [
          'Progressive calorie deficit training',
          'Low-impact, joint-friendly sessions',
          'Body composition tracking',
          'Energy level optimization',
        ];
        break;
      case 'get-faster':
        features = [
          'Aerobic base building (Zone 2 focus)',
          'Controlled tempo work',
          'Smart hill training',
          'Heart rate optimization',
        ];
        break;
      case 'event-prep':
        features = [
          'Long-ruck progression system',
          'Event-specific pacing practice',
          'Proper taper protocol',
          'Foot/skin care guidance',
        ];
        break;
      case 'daily-discipline':
        features = [
          'Flexible 15-30 minute sessions',
          'Habit-building psychology',
          'Streak protection strategies',
          'Recovery-focused programming',
        ];
        break;
      case 'age-strong':
        features = [
          'Joint-friendly load progression',
          'Balance and stability work',
          'Functional strength focus',
          'Daily activity improvement',
        ];
        break;
      case 'load-capacity':
        features = [
          'One variable progression (time→hills→weight)',
          'Joint adaptation monitoring',
          'Progressive overload safety',
          'Load tolerance assessment',
        ];
        break;
      default:
        features = [
          'Personalized progression',
          'Safe and effective training',
          'Regular progress tracking',
          'Flexible scheduling',
        ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What you\'ll get:',
          style: AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
            color: planType.color,
          ),
        ),
        const SizedBox(height: 12),
        ...features.map((feature) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(
                Icons.check_circle,
                color: planType.color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  feature,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }

  Widget _buildSuccessMetrics() {
    String successText;
    
    switch (planType.id) {
      case 'fat-loss':
        successText = 'Track weekly calorie burn, body mass trends, and energy levels';
        break;
      case 'get-faster':
        successText = 'Monitor 60-minute pace improvements and heart rate efficiency';
        break;
      case 'event-prep':
        successText = 'Build to event distance with proper pacing and form';
        break;
      case 'daily-discipline':
        successText = 'Achieve 30+ day streaks while maintaining energy and motivation';
        break;
      case 'age-strong':
        successText = 'Improve balance times, carry strength, and daily function';
        break;
      case 'load-capacity':
        successText = 'Safely increase carrying capacity without pain or injury';
        break;
      default:
        successText = 'Track progress toward your specific goals';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: planType.color.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.analytics,
            color: planType.color,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Success Tracking',
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.bold,
                    color: planType.color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  successText,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}