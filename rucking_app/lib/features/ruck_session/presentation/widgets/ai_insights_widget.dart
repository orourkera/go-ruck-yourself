import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/services/ai_insights_service.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
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

  @override
  void initState() {
    super.initState();
    _generateInsights();
  }

  @override
  void didUpdateWidget(AIInsightsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Regenerate insights if session data changed significantly
    if ((widget.recentSessions?.length ?? 0) != (oldWidget.recentSessions?.length ?? 0)) {
      _generateInsights();
    }
  }

  Future<void> _generateInsights({bool force = false}) async {
    // Skip if current insight is fresh
    if (!force && _currentInsight != null && !_currentInsight!.isStale) {
      return;
    }

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

      // Try cache first (daily)
      if (!force) {
        final cached = await _loadCachedInsight(user.userId);
        if (cached != null) {
          if (mounted) {
            setState(() {
              _currentInsight = cached;
              _isLoading = false;
            });
          }
          return;
        }
      }

      final insight = await aiService.generateHomepageInsights(
        preferMetric: user.preferMetric,
        timeOfDay: timeOfDay,
        dayOfWeek: dayOfWeek,
        username: user.username,
      );

      if (mounted) {
        setState(() {
          _currentInsight = insight;
          _isLoading = false;
        });
      }

      // Persist cache for the day
      await _saveCachedInsight(user.userId, insight);

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
    
    AppLogger.debug('[AI_INSIGHTS] Widget rendering: loading=$_isLoading, hasInsight=${_currentInsight != null}, hasError=$_hasError');

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

    if (_hasError || _currentInsight == null) {
      return _buildFallbackContent();
    }

    return _buildInsightContent(_currentInsight!);
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
    final username = authState is Authenticated ? authState.user.username : 'Rucker';
    
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
                _generateInsights(force: true);
              },
              tooltip: 'Refresh insights',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // Insight content
        _buildInsightSection('📊 Insight', insight.insight),
        const SizedBox(height: 12),
        _buildInsightSection('💡 Recommendation', insight.recommendation),
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
      generatedAt: DateTime.tryParse(map['generatedAt'] ?? '') ?? DateTime.now(),
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
