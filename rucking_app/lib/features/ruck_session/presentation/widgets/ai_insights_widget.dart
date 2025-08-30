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
  bool _isStreaming = false;
  String _streamingText = '';

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
      AppLogger.info('[AI_INSIGHTS_WIDGET] Stream kick-off (user=${user.username})');
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

      // Safety net: if streaming hasn't produced a final after 7s, do a non-streaming generation
      // to avoid showing a generic fallback forever.
      // ignore: unawaited_futures
      Future.delayed(const Duration(seconds: 7), () async {
        if (!mounted) return;
        if (_currentInsight != null) return; // stream succeeded
        try {
          AppLogger.info('[AI_INSIGHTS_WIDGET] Stream timeout fallback – generating non-streaming insight');
          final fallback = await aiService.generateHomepageInsights(
            preferMetric: user.preferMetric,
            timeOfDay: timeOfDay,
            dayOfWeek: dayOfWeek,
            username: user.username,
          );
          if (!mounted) return;
          setState(() {
            _currentInsight = fallback;
            _isStreaming = false;
            _isLoading = false;
          });
          await _saveCachedInsight(user.userId, fallback);
        } catch (e) {
          AppLogger.error('[AI_INSIGHTS_WIDGET] Fallback generation failed: $e');
        }
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
    final username = authState is Authenticated ? authState.user.username : 'Rucker';
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
                style: AppTextStyles.titleLarge.copyWith(color: AppColors.primary),
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
        _buildInsightSection('📊 Insight', 'Analyzing your recent rucks and milestones…'),
        const SizedBox(height: 12),
        _buildInsightSection(
          '💡 Recommendation',
          (_extractRecommendationFromStream(_streamingText) ?? 'Generating a fresh recommendation…') + ' ▌',
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
        _buildInsightSection(
          '💡 Recommendation',
          _isStreaming
              ? ((_extractRecommendationFromStream(_streamingText) ?? 'Generating a fresh recommendation…') + ' ▌')
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
