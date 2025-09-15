import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/network/api_endpoints.dart';
import 'package:rucking_app/features/ai_cheerleader/services/openai_service.dart';
import 'package:rucking_app/features/ai_cheerleader/services/openai_responses_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/social_sharing/models/instagram_post.dart';
import 'package:rucking_app/features/social_sharing/models/time_range.dart';
import 'package:rucking_app/features/social_sharing/models/post_template.dart';
import 'package:rucking_app/features/social_sharing/services/route_map_service.dart';
import 'package:rucking_app/features/social_sharing/services/stats_visualization_service.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/features/ruck_session/data/repositories/session_repository.dart';

class InstagramPostService {
  final ApiClient _apiClient;
  final OpenAIService _openAIService;
  final OpenAIResponsesService _responsesService;
  final RouteMapService _routeMapService;
  final StatsVisualizationService _statsVisualizationService;
  final SessionRepository _sessionRepository;

  InstagramPostService({
    ApiClient? apiClient,
    OpenAIService? openAIService,
    OpenAIResponsesService? responsesService,
    RouteMapService? routeMapService,
    StatsVisualizationService? statsVisualizationService,
    SessionRepository? sessionRepository,
  })  : _apiClient = apiClient ?? GetIt.instance<ApiClient>(),
        _openAIService = openAIService ?? GetIt.instance<OpenAIService>(),
        _responsesService = responsesService ?? GetIt.instance<OpenAIResponsesService>(),
        _routeMapService = routeMapService ?? RouteMapService(),
        _statsVisualizationService = statsVisualizationService ?? StatsVisualizationService(),
        _sessionRepository = sessionRepository ?? GetIt.instance<SessionRepository>();

  /// Generate an Instagram post based on time range and template
  Future<InstagramPost> generatePost({
    required TimeRange timeRange,
    required PostTemplate template,
    String? sessionId,
    DateTime? dateFrom,
    DateTime? dateTo,
    required void Function(String) onDelta,
    void Function(Object)? onError,
  }) async {
    try {
      AppLogger.info('[INSTAGRAM] Generating post for ${timeRange.value} with ${template.name} template');

      // 1. Fetch user insights for the time range
      final insights = await _fetchInsights(
        timeRange: timeRange,
        sessionId: sessionId,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );

      // 2. Generate visual content (route map or stats card)
      onDelta('Generating visuals...\n');
      final visualContent = await _generateVisualContent(
        timeRange: timeRange,
        template: template,
        insights: insights,
        sessionId: sessionId,
      );

      // Add visual content to insights for photo extraction
      if (visualContent != null) {
        final existingPhotos = insights['photos'] as List? ?? [];
        insights['photos'] = [visualContent, ...existingPhotos];
        AppLogger.info('[INSTAGRAM] Added generated visual content as first photo');
      }

      // 3. Build the prompt for OpenAI
      onDelta('Creating caption...\n');
      final prompt = _buildPrompt(
        insights: insights,
        timeRange: timeRange,
        template: template,
      );

      // 4. Generate content using OpenAI
      final generatedContent = await _generateContent(
        prompt: prompt,
        onDelta: onDelta,
        onError: onError,
      );

      // 5. Parse and format the response
      final post = _parseResponse(
        content: generatedContent,
        insights: insights,
        template: template,
      );

      AppLogger.info('[INSTAGRAM] Post generated successfully');
      return post;
    } catch (e) {
      AppLogger.error('[INSTAGRAM] Failed to generate post: $e');
      if (onError != null) onError(e);
      rethrow;
    }
  }

  /// Fetch insights from the backend
  Future<Map<String, dynamic>> _fetchInsights({
    required TimeRange timeRange,
    String? sessionId,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final queryParams = <String, dynamic>{
      'time_range': timeRange.value,
      'fresh': 1,
      'include_photos': true,
    };

    if (sessionId != null) {
      queryParams['session_id'] = sessionId;
    }
    if (dateFrom != null) {
      queryParams['date_from'] = dateFrom.toIso8601String().split('T')[0];
    }
    if (dateTo != null) {
      queryParams['date_to'] = dateTo.toIso8601String().split('T')[0];
    }

    final response = await _apiClient.get(
      ApiEndpoints.userInsights,
      queryParams: queryParams,
    );

    final map = Map<String, dynamic>.from(response ?? {});
    return Map<String, dynamic>.from(map['insights'] ?? {});
  }

  /// Build the OpenAI prompt
  String _buildPrompt({
    required Map<String, dynamic> insights,
    required TimeRange timeRange,
    required PostTemplate template,
  }) {
    final facts = insights['facts'] ?? {};
    final triggers = insights['triggers'] ?? {};
    final achievements = insights['achievements'] ?? [];

    // Extract key stats based on time range
    final stats = _extractStats(facts, timeRange, insights);

    return '''
You are a data-focused fitness analyst creating an Instagram post for a serious rucking athlete.

CONTEXT:
Time Range: ${timeRange.displayName}
Template Style: ${template.name}
${stats.isNotEmpty ? 'Key Stats: ${jsonEncode(stats)}' : ''}
${achievements.isNotEmpty ? 'Recent Achievements: ${achievements.join(', ')}' : ''}

CONTENT APPROACH:
- 90% DATA and concrete metrics (distance, time, pace, weight, elevation, etc.)
- 10% motivational language (keep it minimal and authentic)
- Lead with numbers and achievements
- Be specific about performance improvements
- Focus on factual progress rather than flowery descriptions

STYLE GUIDE for ${template.name}:
${_getTemplateGuidelines(template)}

REQUIREMENTS:
1. Create a data-rich Instagram caption (max 2200 characters)
2. Include @get.rucky naturally in the text
3. Use minimal emojis (only for key stats/achievements)
4. Generate exactly 3 highly relevant hashtags
5. ${_getTimeRangeRequirement(timeRange)}
6. Include a brief, factual call-to-action
7. Keep the tone ${_getTone(template)} but prioritize data over emotion

OUTPUT FORMAT (valid JSON):
{
  "caption": "Data-focused post text with specific metrics and @get.rucky tag",
  "hashtags": ["tag1", "tag2", "tag3"],
  "cta": "Brief call to action",
  "key_stats": ["stat1", "stat2", "stat3"],
  "highlight": "One key data point or achievement to emphasize"
}

IMPORTANT: Return ONLY valid JSON, no additional text.
''';
  }

  /// Extract relevant stats based on time range
  Map<String, dynamic> _extractStats(Map<String, dynamic> facts, TimeRange timeRange, Map<String, dynamic> insights) {
    switch (timeRange) {
      case TimeRange.lastRuck:
        // Check if we have time_range data from backend (when time_range=last_ruck is specified)
        if (insights['time_range'] != null) {
          final timeRangeData = insights['time_range'] as Map<String, dynamic>;
          // Convert backend format to expected frontend format
          return {
            'total_distance': timeRangeData['total_distance_km'],
            'total_duration': timeRangeData['total_duration_seconds'],
            'total_calories': timeRangeData['total_calories'],
            'total_elevation_gain': timeRangeData['elevation_gain_m'],
            'session_count': timeRangeData['sessions_count'],
          };
        }
        // Fallback to recent_sessions format if available
        final recentSessions = facts['recent_sessions'] as List? ?? [];
        if (recentSessions.isNotEmpty) {
          return recentSessions[0] as Map<String, dynamic>;
        }
        break;
      case TimeRange.week:
        return facts['weekly_stats'] ?? {};
      case TimeRange.month:
        return facts['monthly_stats'] ?? {};
      case TimeRange.allTime:
        return facts['all_time_stats'] ?? {};
    }
    return {};
  }

  /// Get template-specific guidelines
  String _getTemplateGuidelines(PostTemplate template) {
    switch (template) {
      case PostTemplate.beastMode:
        return '''
- Lead with specific performance metrics and PRs
- Highlight quantifiable improvements (pace, distance, weight carried)
- Use precise numbers: "PR 25.6km in 3:42:15 with 22.7kg ruck"
- Mention specific challenges overcome (elevation gain, weather conditions)
- Keep motivational language brief and factual''';

      case PostTemplate.journey:
        return '''
- Present training progression with concrete data
- Include historical comparisons with specific numbers
- Focus on measurable growth over time periods
- Reference technical aspects (route difficulty, gear used)
- Share data-driven insights about performance patterns''';

      case PostTemplate.community:
        return '''
- Share actionable training data and benchmarks
- Include specific tips with measurable outcomes
- Reference group performance statistics if available
- Mention technical details that help others improve
- Use encouraging but factual language about achievements''';

      default:
        return 'Be authentic and data-focused';
    }
  }

  /// Get time range specific requirement
  String _getTimeRangeRequirement(TimeRange timeRange) {
    switch (timeRange) {
      case TimeRange.lastRuck:
        return 'Focus on specific details from this single session';
      case TimeRange.week:
        return 'Summarize the week\'s progress and consistency';
      case TimeRange.month:
        return 'Highlight monthly achievements and total stats';
      case TimeRange.allTime:
        return 'Tell the complete transformation story';
    }
  }

  /// Get tone for template
  String _getTone(PostTemplate template) {
    switch (template) {
      case PostTemplate.beastMode:
        return 'analytical, performance-focused, and results-driven';
      case PostTemplate.journey:
        return 'methodical, progress-oriented, and data-informed';
      case PostTemplate.community:
        return 'informative, helpful, and metric-based';
      default:
        return 'factual and authentic';
    }
  }

  /// Generate content using OpenAI
  Future<String> _generateContent({
    required String prompt,
    required void Function(String) onDelta,
    void Function(Object)? onError,
  }) async {
    final completer = Completer<String>();
    final buffer = StringBuffer();

    await _responsesService.stream(
      model: 'gpt-4o-mini',
      instructions: prompt,
      input: 'Generate the Instagram post now.',
      temperature: 0.8,
      maxOutputTokens: 800,
      store: false,
      onDelta: (delta) {
        buffer.write(delta);
        onDelta(delta);
      },
      onComplete: (full) {
        completer.complete(full);
      },
      onError: (e) {
        if (onError != null) onError(e);
        completer.completeError(e);
      },
    );

    return completer.future;
  }

  /// Parse the OpenAI response into an InstagramPost
  InstagramPost _parseResponse({
    required String content,
    required Map<String, dynamic> insights,
    required PostTemplate template,
  }) {
    try {
      // Try to parse as JSON
      final json = jsonDecode(content);

      // Extract photos from insights
      final photos = _extractPhotos(insights);

      return InstagramPost(
        caption: json['caption'] ?? '',
        hashtags: List<String>.from(json['hashtags'] ?? []),
        cta: json['cta'] ?? '',
        keyStats: List<String>.from(json['key_stats'] ?? []),
        highlight: json['highlight'] ?? '',
        photos: photos,
        template: template,
      );
    } catch (e) {
      AppLogger.error('[INSTAGRAM] Failed to parse response: $e');

      // Fallback to a basic post
      return InstagramPost(
        caption: content,
        hashtags: _generateDefaultHashtags(),
        cta: 'Join me on @get.rucky!',
        keyStats: [],
        highlight: '',
        photos: [],
        template: template,
      );
    }
  }

  /// Extract photos from insights
  List<String> _extractPhotos(Map<String, dynamic> insights) {
    final photos = <String>[];

    // Try different possible photo locations in the response
    if (insights['photos'] != null) {
      final photoList = insights['photos'] as List;
      photos.addAll(photoList.map((p) => p.toString()));
    }

    if (insights['recent_sessions'] != null) {
      final sessions = insights['recent_sessions'] as List;
      for (final session in sessions) {
        if (session['photos'] != null) {
          final sessionPhotos = session['photos'] as List;
          photos.addAll(sessionPhotos.map((p) => p.toString()));
        }
      }
    }

    // Limit to 10 photos max
    return photos.take(10).toList();
  }

  /// Generate default hashtags as fallback
  List<String> _generateDefaultHashtags() {
    return [
      'RuckingData',
      'GetRucky',
      'TrainingMetrics'
    ];
  }

  /// Generate visual content (route map for Last Ruck, stats card for others)
  Future<String?> _generateVisualContent({
    required TimeRange timeRange,
    required PostTemplate template,
    required Map<String, dynamic> insights,
    String? sessionId,
  }) async {
    try {
      if (timeRange == TimeRange.lastRuck && sessionId != null) {
        // Generate route map for Last Ruck
        return await _generateRouteMapForSession(sessionId, template);
      } else {
        // Generate stats card for aggregate time ranges
        return await _generateStatsCard(insights, timeRange, template);
      }
    } catch (e) {
      AppLogger.error('[INSTAGRAM] Error generating visual content: $e');
      return null;
    }
  }

  /// Generate route map for a specific session
  Future<String?> _generateRouteMapForSession(String sessionId, PostTemplate template) async {
    try {
      AppLogger.info('[INSTAGRAM] Generating route map for session: $sessionId');

      // Fetch the session with location points
      final session = await _sessionRepository.fetchSessionById(sessionId);
      if (session == null) {
        AppLogger.warning('[INSTAGRAM] Session not found: $sessionId');
        return null;
      }

      // Check if session has location points
      if (session.locationPoints?.isEmpty ?? true) {
        AppLogger.info('[INSTAGRAM] Session has no location points, skipping route map');
        return null;
      }

      // Generate route map image
      final imageBytes = await _routeMapService.generateInstagramRouteMap(
        session: session,
        preferMetric: true, // TODO: Get from user preferences
      );

      if (imageBytes == null) {
        AppLogger.warning('[INSTAGRAM] Failed to generate route map image');
        return null;
      }

      // Save image to temporary file and return path
      final imagePath = await _saveImageToTemp(imageBytes, 'route_map_$sessionId.png');
      AppLogger.info('[INSTAGRAM] Route map saved to: $imagePath');
      return imagePath;
    } catch (e) {
      AppLogger.error('[INSTAGRAM] Error generating route map: $e');
      return null;
    }
  }

  /// Generate stats card for aggregate time ranges
  Future<String?> _generateStatsCard(
    Map<String, dynamic> insights,
    TimeRange timeRange,
    PostTemplate template,
  ) async {
    try {
      AppLogger.info('[INSTAGRAM] Generating stats card for ${timeRange.displayName}');

      // Generate stats visualization
      final imageBytes = await _statsVisualizationService.generateStatsCard(
        insights: insights,
        timeRange: timeRange,
        template: template,
        preferMetric: true, // TODO: Get from user preferences
      );

      if (imageBytes == null) {
        AppLogger.warning('[INSTAGRAM] Failed to generate stats card image');
        return null;
      }

      // Save image to temporary file and return path
      final imagePath = await _saveImageToTemp(imageBytes, 'stats_${timeRange.value}_${template.name}.png');
      AppLogger.info('[INSTAGRAM] Stats card saved to: $imagePath');
      return imagePath;
    } catch (e) {
      AppLogger.error('[INSTAGRAM] Error generating stats card: $e');
      return null;
    }
  }

  /// Save image bytes to temporary file
  Future<String> _saveImageToTemp(Uint8List imageBytes, String fileName) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(imageBytes);
      return file.path;
    } catch (e) {
      AppLogger.error('[INSTAGRAM] Error saving image to temp: $e');
      rethrow;
    }
  }
}