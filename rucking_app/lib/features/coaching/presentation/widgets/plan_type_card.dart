import 'package:flutter/material.dart';
import 'package:rucking_app/features/coaching/domain/models/coaching_plan_type.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

class PlanTypeCard extends StatelessWidget {
  final CoachingPlanType planType;
  final VoidCallback onTap;

  const PlanTypeCard({
    super.key,
    required this.planType,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                planType.color.withOpacity(0.1),
                planType.color.withOpacity(0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: planType.color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          planType.emoji,
                          style: const TextStyle(fontSize: 24),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          planType.icon,
                          color: planType.color,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
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
                      style: AppTextStyles.bodySmall.copyWith(
                        color: planType.color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              Text(
                planType.name,
                style: AppTextStyles.titleLarge.copyWith(
                  fontWeight: FontWeight.bold,
                  color: planType.color,
                ),
              ),
              const SizedBox(height: 8),
              
              Text(
                planType.description,
                style: AppTextStyles.bodyMedium.copyWith(
                  height: 1.4,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 16),
              
              Row(
                children: [
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward,
                    color: planType.color,
                    size: 20,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}