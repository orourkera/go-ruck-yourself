import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/ai_cheerleader/services/openai_responses_service.dart';
import 'package:rucking_app/features/coaching/data/services/coaching_service.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/core/config/app_config.dart';

/// Widget that displays AI-powered coaching guidance for the session creation screen
class AICoachingSessionWidget extends StatefulWidget {
  final Map<String, dynamic>? coachingPlan;
  final Map<String, dynamic>? nextSession;
  final Map<String, dynamic>? progress;
  final bool preferMetric;
  final String? coachingPersonality;

  const AICoachingSessionWidget({
    Key? key,
    this.coachingPlan,
    this.nextSession,
    this.progress,
    required this.preferMetric,
    this.coachingPersonality,
  }) : super(key: key);

  @override
  State<AICoachingSessionWidget> createState() => _AICoachingSessionWidgetState();
}

class _AICoachingSessionWidgetState extends State<AICoachingSessionWidget> {
  String _aiMessage = '';
  bool _isLoading = true;
  bool _isStreaming = false;
  late OpenAIResponsesService _openAiService;

  @override
  void initState() {
    super.initState();
    _openAiService = GetIt.instance<OpenAIResponsesService>();
    _generateAIGuidance();
  }

  Future<void> _generateAIGuidance() async {
    if (widget.coachingPlan == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final authState = context.read<AuthBloc>().state;
      final username = authState is Authenticated ? authState.user.username : 'Rucker';

      // Build context for AI
      final planName = widget.coachingPlan!['plan_name'] ?? 'Training Plan';
      final weekNumber = widget.coachingPlan!['current_week'] ?? 1;
      final totalWeeks = widget.coachingPlan!['duration_weeks'] ?? 8;
      final phase = widget.coachingPlan!['current_phase'] ?? 'Base Building';

      // Progress data
      final adherence = widget.progress?['adherence_percentage'] ?? 0;
      final completedSessions = widget.progress?['completed_sessions'] ?? 0;
      final totalSessions = widget.progress?['total_sessions'] ?? 0;
      final isOnTrack = adherence >= 70;

      // Next session details
      final sessionType = widget.nextSession?['type'] ?? 'Base Ruck';
      final distanceKm = widget.nextSession?['distance_km'];
      final durationMinutes = widget.nextSession?['duration_minutes'];
      final weightKg = widget.nextSession?['weight_kg'];
      final notes = widget.nextSession?['notes'] ?? '';

      // Convert units based on preference
      final distanceUnit = widget.preferMetric ? 'km' : 'miles';
      final weightUnit = widget.preferMetric ? 'kg' : 'lbs';

      String distanceStr = '';
      if (distanceKm != null) {
        final distance = widget.preferMetric
            ? distanceKm
            : MeasurementUtils.distance(distanceKm, metric: false);
        distanceStr = '${distance.toStringAsFixed(1)} $distanceUnit';
      }

      String weightStr = '';
      if (weightKg != null) {
        final weight = widget.preferMetric
            ? weightKg
            : weightKg * AppConfig.kgToLbs;
        weightStr = '${weight.toStringAsFixed(0)} $weightUnit';
      }

      final personality = widget.coachingPersonality ?? 'Supportive Friend';

      final prompt = '''
You are an AI coaching assistant with the personality of "$personality" helping $username prepare for their ruck session.

Context:
- Plan: $planName (Week $weekNumber of $totalWeeks)
- Current Phase: $phase
- Progress: $completedSessions/$totalSessions sessions complete (${adherence}% adherence)
- Status: ${isOnTrack ? 'ON TRACK' : 'NEEDS ENCOURAGEMENT'}
- Today's Session: $sessionType
${distanceStr.isNotEmpty ? '- Target Distance: $distanceStr' : ''}
${durationMinutes != null ? '- Target Duration: ${durationMinutes} minutes' : ''}
${weightStr.isNotEmpty ? '- Recommended Weight: $weightStr' : ''}
${notes.isNotEmpty ? '- Coach Notes: $notes' : ''}

Generate a brief, motivating message (2-3 sentences max) that:
1. Acknowledges their progress so far (be specific about their ${adherence}% adherence)
2. Briefly explains what today's $sessionType session will do for them
3. Gives ONE specific, actionable tip for this session

Match the "$personality" coaching style exactly. Keep it concise and focused on THIS specific session.
''';

      setState(() {
        _aiMessage = '';
        _isStreaming = true;
        _isLoading = false;
      });

      await _openAiService.stream(
        model: 'gpt-4o-mini',
        instructions: 'You are a concise rucking coach. Keep responses under 50 words. Be specific and actionable.',
        input: prompt,
        temperature: 0.7,
        maxOutputTokens: 150,
        onDelta: (delta) {
          if (mounted) {
            setState(() {
              _aiMessage += delta;
            });
          }
        },
        onDone: () {
          if (mounted) {
            setState(() {
              _isStreaming = false;
            });
          }
        },
      );
    } catch (e) {
      AppLogger.error('Failed to generate AI coaching guidance: $e');
      if (mounted) {
        setState(() {
          _aiMessage = _getFallbackMessage();
          _isLoading = false;
          _isStreaming = false;
        });
      }
    }
  }

  String _getFallbackMessage() {
    final sessionType = widget.nextSession?['type'] ?? 'session';
    final adherence = widget.progress?['adherence_percentage'] ?? 0;

    if (adherence >= 80) {
      return "Outstanding consistency at ${adherence}% adherence! Today's $sessionType will build on your strong foundation. Focus on maintaining good posture throughout.";
    } else if (adherence >= 60) {
      return "Good progress with ${adherence}% adherence! This $sessionType session is perfectly timed to get you back on track. Start conservatively and find your rhythm.";
    } else {
      return "Every session counts! Today's $sessionType is your opportunity to rebuild momentum. Keep it comfortable and focus on completing the session.";
    }
  }

  @override
  Widget build(BuildContext context) {
    // Don't show if no coaching plan
    if (widget.coachingPlan == null) {
      return const SizedBox.shrink();
    }

    // Don't show if still loading
    if (_isLoading) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withOpacity(0.05),
              AppColors.primary.withOpacity(0.02),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Your coach is preparing guidance...',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textDarkSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withOpacity(0.08),
            AppColors.primary.withOpacity(0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isStreaming ? null : () => _generateAIGuidance(),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.auto_awesome,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your AI Coach',
                            style: AppTextStyles.labelLarge.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (widget.coachingPersonality != null)
                            Text(
                              widget.coachingPersonality!,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textDarkSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (!_isStreaming)
                      IconButton(
                        icon: Icon(
                          Icons.refresh,
                          size: 20,
                          color: AppColors.primary.withOpacity(0.7),
                        ),
                        onPressed: _generateAIGuidance,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Get new advice',
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // AI Message
                if (_aiMessage.isNotEmpty)
                  Text(
                    _aiMessage + (_isStreaming ? ' ▌' : ''),
                    style: AppTextStyles.bodyMedium.copyWith(
                      height: 1.5,
                      color: AppColors.textDark,
                    ),
                  ),

                // Progress indicator
                if (widget.progress != null && _aiMessage.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildProgressIndicator(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    final adherence = widget.progress?['adherence_percentage'] ?? 0;
    final weekNumber = widget.coachingPlan?['current_week'] ?? 1;
    final totalWeeks = widget.coachingPlan?['duration_weeks'] ?? 8;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Week $weekNumber of $totalWeeks',
                style: AppTextStyles.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${adherence}% adherence',
                style: AppTextStyles.bodySmall.copyWith(
                  color: adherence >= 70 ? AppColors.success : AppColors.warning,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: adherence / 100,
              backgroundColor: AppColors.greyLight.withOpacity(0.3),
              valueColor: AlwaysStoppedAnimation<Color>(
                adherence >= 70 ? AppColors.success : AppColors.warning,
              ),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}