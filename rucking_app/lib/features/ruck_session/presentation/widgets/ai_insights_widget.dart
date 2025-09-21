import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/services/ai_insights_service.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/coaching/data/services/coaching_service.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rucking_app/shared/widgets/skeleton/skeleton_loader.dart';

/// Widget that displays AI-powered insights on the homepage
class AIInsightsWidget extends StatefulWidget {
  final List<dynamic>? recentSessions;
  final List<dynamic>? achievements;

  const AIInsightsWidget({
    Key? key,
    this.recentSessions,
    this.achievements,
  }) : super(key: key);

  @override
  State<AIInsightsWidget> createState() => _AIInsightsWidgetState();
}

class _AIInsightsWidgetState extends State<AIInsightsWidget> {
  AIInsight? _currentInsight;
  bool _isLoading = false;
  bool _hasError = false;
  bool _isStreaming = false;
  String _streamingText = '';
  Map<String, dynamic>? _activeCoachingPlan;

  String? _extractRecommendationFromStream(String buf) {
    try {
      if (buf.isEmpty) return null;
      final keyIndex = buf.indexOf('"recommendation"');
      if (keyIndex == -1) return null;
      // Find the first quote after the colon following the key
      final colon = buf.indexOf(':', keyIndex);
      if (colon == -1) return null;
      // Find the opening quote of the value
      int start = buf.indexOf('"', colon + 1);
      if (start == -1) return null;
      start += 1; // move past opening quote
      // Accumulate until the next unescaped quote or end of buffer
      final sb = StringBuffer();
      bool escape = false;
      for (int i = start; i < buf.length; i++) {
        final ch = buf[i];
        if (escape) {
          // Handle simple escape sequences; just append the char
          sb.write(ch);
          escape = false;
        } else if (ch == '\\') {
          escape = true;
        } else if (ch == '"') {
          // closing quote reached
          break;
        } else {
          sb.write(ch);
        }
      }
      final text = sb.toString().trim();
      if (text.isEmpty) return null;
      return text;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _checkCoachingPlan();
  }

  Future<void> _checkCoachingPlan() async {
    try {
      final coachingService = GetIt.instance<CoachingService>();
      final plan = await coachingService.getActiveCoachingPlan();

      if (mounted) {
        setState(() {
          _activeCoachingPlan = plan;
        });

        // If user has a plan, show next workout. Otherwise generate AI insights
        if (plan != null) {
          _showNextPlannedWorkout(plan);
        } else {
          _generateInsights();
        }
      }
    } catch (e) {
      AppLogger.error('[AI_INSIGHTS_WIDGET] Failed to check coaching plan: $e');
      // Fall back to regular insights
      _generateInsights();
    }
  }

  void _showNextPlannedWorkout(Map<String, dynamic> plan) async {
    try {
      // Get progress data for adherence stats
      Map<String, dynamic>? progressData;
      Map<String, dynamic>? nextSession;
      try {
        final coachingService = GetIt.instance<CoachingService>();
        final progressResponse =
            await coachingService.getCoachingPlanProgress();

        progressData = progressResponse['progress'] is Map
            ? Map<String, dynamic>.from(progressResponse['progress'])
            : null;

        if (progressResponse['next_session'] is Map) {
          nextSession = Map<String, dynamic>.from(
              progressResponse['next_session'] as Map);
        }

        if (nextSession != null) {
          plan['next_session'] = nextSession;
        }
      } catch (e) {
        AppLogger.error('[AI_INSIGHTS_WIDGET] Failed to fetch progress: $e');
      }

      nextSession ??= plan['next_session'] is Map
          ? Map<String, dynamic>.from(plan['next_session'])
          : null;

      nextSession ??= plan['recent_sessions']?.firstWhere(
        (s) => s['completion_status'] == 'planned',
        orElse: () => null,
      );

      String insight = "";
      String recommendation = "Loading next workout...";
      String motivation = "";

      // Build detailed progress insight
      final currentWeek = plan['current_week'] ?? 1;
      final totalWeeks = plan['duration_weeks'] ?? 8;
      final planName = plan['plan_name'] ?? 'Training Plan';

      // Get adherence data
      final adherence = (progressData?['adherence_percentage'] as num? ??
              plan['adherence_percentage'] as num? ??
              0)
          .toDouble();
      final completedSessions =
          (progressData?['completed_sessions'] as num?)?.toInt() ?? 0;
      final totalSessions =
          (progressData?['total_sessions'] as num?)?.toInt() ?? 0;
      final weeklyStreak =
          (progressData?['weekly_streak'] as num?)?.toInt() ?? 0;

      // Build progress narrative
      String progressStatus = "";
      if (adherence >= 80) {
        progressStatus = "You're crushing it with ${adherence}% adherence!";
      } else if (adherence >= 60) {
        progressStatus = "Good progress at ${adherence}% adherence";
      } else if (adherence > 0) {
        progressStatus = "Building momentum with ${adherence}% adherence";
      } else {
        progressStatus = "Ready to start your journey";
      }

      insight = "$planName • Week $currentWeek of $totalWeeks\n$progressStatus";
      if (completedSessions > 0) {
        insight += " • $completedSessions/$totalSessions sessions this week";
      }
      if (weeklyStreak > 1) {
        insight += " • $weeklyStreak week streak! 🔥";
      }

      if (nextSession != null) {
        // Get detailed session info from the recommendation object
        final sessionRecommendation = nextSession['recommendation'] ?? {};
        final sessionType = nextSession['session_type'] ??
            nextSession['planned_session_type'] ??
            nextSession['type'] ??
            'training';

        // Format the session type nicely
        String sessionTitle = _formatSessionType(sessionType);

        // Extract details from recommendation
        final duration = sessionRecommendation['duration'] ??
            (nextSession['duration_minutes'] != null
                ? "${nextSession['duration_minutes']} min"
                : null);
        final intensity = sessionRecommendation['intensity'];
        final load = sessionRecommendation['load'];
        final description =
            sessionRecommendation['description'] ?? sessionTitle;

        // Build detailed recommendation
        recommendation = "Today: $description";

        List<String> details = [];
        if (duration != null) details.add(duration);
        if (intensity != null) details.add(intensity);
        if (load != null) details.add(load);

        if (details.isNotEmpty) {
          recommendation += "\n" + details.join(' • ');
        }

        // Add motivational text based on personality
        final personality = plan['coaching_personality'] ??
            plan['personality'] ??
            'Supportive Friend';
        motivation = _getPersonalityMotivation(personality, sessionType);

        // Add context based on performance
        if (adherence < 50 && completedSessions < totalSessions / 2) {
          motivation += " Every session counts!";
        } else if (adherence >= 80) {
          motivation += " Keep that streak alive!";
        }
      } else {
        // Check if it's a rest day or plan complete
        if (currentWeek >= totalWeeks) {
          recommendation =
              "Plan complete! Time to celebrate your achievement 🎉";
          motivation =
              "You've completed your ${totalWeeks}-week plan. Incredible work!";
        } else {
          recommendation = "Rest day - recovery is part of the journey";
          motivation =
              "Use today to stretch, hydrate, and prepare for your next session";
        }
      }

      if (mounted) {
        setState(() {
          _currentInsight = AIInsight(
            greeting: "Your Plan Progress",
            insight: insight,
            recommendation: recommendation,
            motivation: motivation,
            emoji: "📋",
            generatedAt: DateTime.now(),
          );
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.error('[AI_INSIGHTS_WIDGET] Failed to parse next workout: $e');
      // Fall back to regular insights
      _generateInsights();
    }
  }

  String _formatSessionType(String type) {
    switch (type) {
      case 'base_aerobic':
        return 'Base Ruck';
      case 'tempo':
        return 'Tempo Ruck';
      case 'intervals':
        return 'Speed Intervals';
      case 'recovery':
        return 'Recovery';
      case 'long_slow':
        return 'Long Ruck';
      case 'hill_work':
        return 'Hill Training';
      case 'test':
        return 'Test/Time Trial';
      default:
        return 'Training Session';
    }
  }

  String _getPersonalityMotivation(String personality, String sessionType) {
    final isHard = sessionType.contains('interval') ||
        sessionType.contains('tempo') ||
        sessionType.contains('hill');

    switch (personality.toLowerCase()) {
      case 'drill_sergeant':
      case 'drill sergeant':
        return isHard
            ? "No excuses! Time to push your limits!"
            : "Stay disciplined, soldier!";
      case 'supportive_friend':
      case 'supportive friend':
        return isHard
            ? "You've got this! I believe in you!"
            : "Great job staying consistent!";
      case 'southern_redneck':
      case 'southern redneck':
        return isHard ? "Time to get after it, partner!" : "Keep on truckin'!";
      case 'yoga_instructor':
      case 'yoga instructor':
        return isHard
            ? "Embrace the challenge with mindfulness"
            : "Focus on your breath and form";
      case 'british_butler':
      case 'british butler':
        return isHard
            ? "A splendid opportunity to excel, sir"
            : "Steady progress, as always";
      case 'cowboy':
      case 'cowboy/cowgirl':
        return isHard
            ? "Saddle up for a tough ride!"
            : "Keep movin' down the trail";
      case 'nature_lover':
      case 'nature lover':
        return isHard ? "Channel the mountain's strength" : "Enjoy the journey";
      default:
        return "Stay focused on your goals!";
    }
  }

  @override
  void didUpdateWidget(AIInsightsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Regenerate insights if session data changed significantly
    final oldSessionCount = oldWidget.recentSessions?.length ?? 0;
    final newSessionCount = widget.recentSessions?.length ?? 0;
    final oldAchievementCount = oldWidget.achievements?.length ?? 0;
    final newAchievementCount = widget.achievements?.length ?? 0;

    // Force refresh on any data change since behavioral patterns are now much richer
    if (newSessionCount != oldSessionCount ||
        newAchievementCount != oldAchievementCount) {
      AppLogger.info(
          '[AI_INSIGHTS_WIDGET] Data change detected - forcing insight refresh (sessions: $oldSessionCount->$newSessionCount, achievements: $oldAchievementCount->$newAchievementCount)');
      _generateInsights(force: true); // Force refresh to bypass cache
    }
  }

  /// Manually clear the insight cache - useful when profile or integration changes occur
  Future<void> clearInsightCache() async {
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is! Authenticated) return;

      final prefs = await SharedPreferences.getInstance();
      final user = authState.user;
      final key = 'ai_home_cache_${user.userId}_${DateTime.now().yyyymmdd}';
      await prefs.remove(key);

      AppLogger.info(
          '[AI_INSIGHTS_WIDGET] Cleared insight cache for ${user.username}');

      // Regenerate insights
      if (mounted) {
        _generateInsights(force: true);
      }
    } catch (e) {
      AppLogger.error('[AI_INSIGHTS_WIDGET] Failed to clear insight cache: $e');
    }
  }

  Future<void> _generateInsights({bool force = false}) async {
    // Do not early-return on fresh insight; we still stream a refresh in the background

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is! Authenticated) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final user = authState.user;
      final aiService = GetIt.instance<AIInsightsService>();

      // Get current time context
      final now = DateTime.now();
      final timeOfDay = _getTimeOfDay(now);
      final dayOfWeek = DateFormat('EEEE').format(now);

      AppLogger.info('[AI_INSIGHTS] Generating insights for ${user.username}');

      // Try cache first (daily). If found, render immediately but continue to refresh via stream.
      if (!force) {
        final cached = await _loadCachedInsight(user.userId);
        if (cached != null && mounted) {
          setState(() {
            _currentInsight = cached;
            _isLoading = false; // show cached immediately
          });
          // Do not return; we will still stream a fresh insight to polish the card
        }
      }

      // Start streaming with immediate cache fallback
      if (mounted) {
        setState(() {
          _isStreaming = true;
          _streamingText = '';
          _isLoading = false; // hide skeleton while streaming
        });
      } else {
        _isStreaming = true;
        _streamingText = '';
        _isLoading = false;
      }
      AppLogger.info(
          '[AI_INSIGHTS_WIDGET] Stream kick-off (user=${user.username})');
      // Fire-and-forget to avoid awaiting until the stream completes
      // ignore: unawaited_futures
      aiService.streamHomepageInsights(
        preferMetric: user.preferMetric,
        username: user.username,
        onDelta: (delta) {
          if (!mounted) return;
          setState(() {
            _streamingText += delta;
          });
        },
        onFinal: (insight) async {
          if (!mounted) return;
          setState(() {
            _currentInsight = insight;
            _isStreaming = false;
            _isLoading = false;
          });
          await _saveCachedInsight(user.userId, insight);
        },
        onError: (e) {
          AppLogger.error('[AI_INSIGHTS] Streaming error: $e');
          // Fall back to non-streaming generation
        },
      );

      // Safety net: if streaming hasn't produced a final after 10s, show error state
      // The streamHomepageInsights method handles its own non-streaming fallback
      // ignore: unawaited_futures
      Future.delayed(const Duration(seconds: 10), () async {
        if (!mounted) return;
        if (_currentInsight != null) return; // stream succeeded
        AppLogger.warning(
            '[AI_INSIGHTS_WIDGET] Stream timeout after 10s - showing error state');
        setState(() {
          _hasError = true;
          _isStreaming = false;
          _isLoading = false;
        });
      });
    } catch (e) {
      AppLogger.error('[AI_INSIGHTS] Failed to generate insights: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  String _getTimeOfDay(DateTime time) {
    final hour = time.hour;
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    if (hour < 21) return 'evening';
    return 'night';
  }

  @override
  Widget build(BuildContext context) {
    // Don't show widget if user is not authenticated
    final authState = context.watch<AuthBloc>().state;
    if (authState is! Authenticated) {
      return const SizedBox.shrink();
    }

    // Always show widget during loading or if we have insights
    // Only hide if we explicitly failed and have no fallback
    if (!_isLoading && _currentInsight == null && _hasError) {
      AppLogger.debug('[AI_INSIGHTS] Widget hidden due to error state');
      return const SizedBox.shrink();
    }

    AppLogger.debug(
        '[AI_INSIGHTS] Widget rendering: loading=$_isLoading, hasInsight=${_currentInsight != null}, hasError=$_hasError');

    return Card(
      // Tighter outer spacing so the card blends into the feed
      margin: const EdgeInsets.only(bottom: 8.0),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary.withOpacity(0.05),
              AppColors.primary.withOpacity(0.02),
            ],
          ),
        ),
        child: Padding(
          // Slightly reduce inner padding for a denser look
          padding: const EdgeInsets.all(16.0),
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return _buildLoadingState();
    }

    // Show a dedicated streaming view when no insight is loaded yet
    if (_currentInsight == null && _isStreaming) {
      return _buildStreamingContent();
    }

    if (_hasError || _currentInsight == null) {
      return _buildFallbackContent();
    }

    return _buildInsightContent(_currentInsight!);
  }

  Widget _buildStreamingContent() {
    final authState = context.read<AuthBloc>().state;
    final username =
        authState is Authenticated ? authState.user.username : 'Rucker';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('🧠', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Cooking up something good, $username…',
                style:
                    AppTextStyles.titleLarge.copyWith(color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 4),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          ],
        ),
        const SizedBox(height: 16),
        _buildInsightSection(
            '📊 Insight', 'Analyzing your recent rucks and milestones…'),
        const SizedBox(height: 12),
        _buildInsightSection(
          '💡 Recommendation',
          (_extractRecommendationFromStream(_streamingText) ??
                  'Generating a fresh recommendation…') +
              ' ▌',
        ),
        const SizedBox(height: 12),
        _buildInsightSection('🚀 Motivation', 'Lacing up some motivation…'),
      ],
    );
  }

  Widget _buildLoadingState() {
    return SkeletonLoader(
      isLoading: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          // Header skeleton
          SkeletonLine(width: 180, height: 22),
          SizedBox(height: 16),
          // Three lines for sections
          SkeletonLine(width: 120, height: 14),
          SizedBox(height: 8),
          SkeletonLine(width: double.infinity, height: 16),
          SizedBox(height: 14),
          SkeletonLine(width: 160, height: 14),
          SizedBox(height: 8),
          SkeletonLine(width: double.infinity, height: 16),
          SizedBox(height: 14),
          SkeletonLine(width: 140, height: 14),
          SizedBox(height: 8),
          SkeletonLine(width: double.infinity, height: 16),
        ],
      ),
    );
  }

  Widget _buildFallbackContent() {
    final authState = context.read<AuthBloc>().state;
    final username =
        authState is Authenticated ? authState.user.username : 'Rucker';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '💪',
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Ready to ruck, $username?',
                style: AppTextStyles.titleLarge.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Every step forward is progress. Time to build that resilience!',
          style: AppTextStyles.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildInsightContent(AIInsight insight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with emoji and greeting
        Row(
          children: [
            Text(
              insight.emoji,
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                insight.greeting,
                style: AppTextStyles.titleLarge.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
            // Refresh button
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () {
                setState(() {
                  _currentInsight = null; // Force refresh
                });
                // Check for coaching plan first
                _checkCoachingPlan();
              },
              tooltip: 'Refresh',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Insight content
        _buildInsightSection('📊 Insight', insight.insight),
        const SizedBox(height: 12),
        _buildInsightSection(
          '💡 Recommendation',
          _isStreaming
              ? ((_extractRecommendationFromStream(_streamingText) ??
                      'Generating a fresh recommendation…') +
                  ' ▌')
              : insight.recommendation,
        ),
        const SizedBox(height: 12),
        _buildInsightSection('🚀 Motivation', insight.motivation),
      ],
    );
  }

  Widget _buildInsightSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.bodySmall.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          content,
          style: AppTextStyles.bodyMedium,
        ),
      ],
    );
  }
}

extension on DateTime {
  String get yyyymmdd => DateFormat('yyyy-MM-dd').format(this);
}

Future<AIInsight?> _loadCachedInsight(String userId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final key = 'ai_home_cache_${userId}_${DateTime.now().yyyymmdd}';
    final json = prefs.getString(key);
    if (json == null) return null;
    final map = Map<String, dynamic>.from(jsonDecode(json) as Map);
    return AIInsight(
      greeting: map['greeting'] ?? '',
      insight: map['insight'] ?? '',
      recommendation: map['recommendation'] ?? '',
      motivation: map['motivation'] ?? '',
      emoji: map['emoji'] ?? '💪',
      generatedAt:
          DateTime.tryParse(map['generatedAt'] ?? '') ?? DateTime.now(),
    );
  } catch (_) {
    return null;
  }
}

Future<void> _saveCachedInsight(String userId, AIInsight insight) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final key = 'ai_home_cache_${userId}_${DateTime.now().yyyymmdd}';
    final map = {
      'greeting': insight.greeting,
      'insight': insight.insight,
      'recommendation': insight.recommendation,
      'motivation': insight.motivation,
      'emoji': insight.emoji,
      'generatedAt': insight.generatedAt.toIso8601String(),
    };
    await prefs.setString(key, jsonEncode(map));
  } catch (_) {}
}
