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
import 'package:supabase_flutter/supabase_flutter.dart';

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
    bool? preferMetric, // Allow override, otherwise get from user settings
  }) async {
    try {
      AppLogger.info('[INSTAGRAM] Generating post for ${timeRange.value} with ${template.name} template');

      // 0. Get user's unit preference
      final useMetric = preferMetric ?? await _getUserMetricPreference();
      AppLogger.info('[INSTAGRAM] Using ${useMetric ? 'metric' : 'imperial'} units');

      // 1. Fetch user insights for the time range
      final insights = await _fetchInsights(
        timeRange: timeRange,
        sessionId: sessionId,
        dateFrom: dateFrom,
        dateTo: dateTo,
        useMetric: useMetric,
      );

      // Ensure nested maps use string keys for downstream consumers.
      final normalizedInsights = _normalizeInsights(insights);

      // 2. Generate visual content (route map or stats card)
      onDelta('Generating visuals...\n');
      final visualContent = await _generateVisualContent(
        timeRange: timeRange,
        template: template,
        insights: normalizedInsights,
        sessionId: sessionId,
        useMetric: useMetric,
      );

      // Add visual content to insights for photo extraction
      if (visualContent != null) {
        final existingPhotos = normalizedInsights['photos'] as List? ?? [];
        normalizedInsights['photos'] = [visualContent, ...existingPhotos];
        print('[INSTAGRAM] Added generated visual content as first photo. Total photos now: ${normalizedInsights['photos']?.length ?? 0}');
        print('[INSTAGRAM] Visual content path: $visualContent');
        print('[INSTAGRAM] All photos: ${normalizedInsights['photos']}');
      } else {
        print('[INSTAGRAM] No visual content was generated');
      }

      // 3. Build the prompt for OpenAI
      onDelta('Creating caption...\n');
      final prompt = _buildPrompt(
        insights: normalizedInsights,
        timeRange: timeRange,
        template: template,
        useMetric: useMetric,
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
        insights: normalizedInsights,
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

  /// Get user's metric preference from settings
  Future<bool> _getUserMetricPreference() async {
    try {
      final response = await _apiClient.get('/api/users/profile');
      final profile = Map<String, dynamic>.from(response as Map);
      final preferMetric = profile['prefer_metric'] as bool? ?? true;
      AppLogger.info('[INSTAGRAM] User metric preference: $preferMetric');
      return preferMetric;
    } catch (e) {
      AppLogger.error('[INSTAGRAM] Failed to get user metric preference: $e');
      return true; // Default to metric on error
    }
  }

  /// Fetch session data from the correct endpoints
  Future<Map<String, dynamic>> _fetchInsights({
    required TimeRange timeRange,
    String? sessionId,
    DateTime? dateFrom,
    DateTime? dateTo,
    required bool useMetric,
  }) async {
    switch (timeRange) {
      case TimeRange.lastRuck:
        return await _fetchLastRuckData(sessionId, useMetric);
      case TimeRange.week:
      case TimeRange.month:
      case TimeRange.allTime:
        return await _fetchTimeRangeData(timeRange, dateFrom, dateTo, useMetric);
    }
  }

  /// Fetch latest session data from /api/rucks (which includes photos)
  Future<Map<String, dynamic>> _fetchLastRuckData(String? sessionId, bool useMetric) async {
    try {
      AppLogger.info('[INSTAGRAM] Fetching last ruck data from /api/rucks');

      final response = await _apiClient.get('/api/rucks', queryParams: {'limit': 1});
      final sessions = response as List? ?? [];

      if (sessions.isEmpty) {
        AppLogger.warning('[INSTAGRAM] No sessions found for last ruck');
        return {};
      }

      final latestSession = Map<String, dynamic>.from(sessions.first as Map);
      AppLogger.info('[INSTAGRAM] Found latest session: ${latestSession['id']}');

      // Fetch photos using the correct photos endpoint
      final photos = await _fetchPhotosForSession(latestSession['id']?.toString());
      AppLogger.info('[INSTAGRAM] Found ${photos.length} photos for last ruck from photos endpoint');

      // Transform session data to expected format with unit conversion
      final distanceKm = (latestSession['distance_km'] as num?)?.toDouble() ?? 0.0;
      final elevationM = (latestSession['elevation_gain_m'] as num?)?.toDouble() ?? 0.0;
      final ruckWeightKg = (latestSession['ruck_weight_kg'] as num?)?.toDouble() ?? 0.0;
      final paceMinPerKm = (latestSession['pace_min_per_km'] as num?)?.toDouble();

      return {
        'session': latestSession,
        'photos': photos,
        'stats': {
          'distance': useMetric ? distanceKm : _kmToMiles(distanceKm),
          'distance_unit': useMetric ? 'km' : 'mi',
          'duration_seconds': latestSession['duration_seconds'] ?? 0,
          'calories': latestSession['calories'] ?? 0,
          'elevation_gain': useMetric ? elevationM : _metersToFeet(elevationM),
          'elevation_unit': useMetric ? 'm' : 'ft',
          'pace': useMetric ? paceMinPerKm : _paceKmToMiles(paceMinPerKm),
          'pace_unit': useMetric ? 'min/km' : 'min/mi',
          'completed_at': latestSession['completed_at'],
          'ruck_weight': useMetric ? ruckWeightKg : _kgToLbs(ruckWeightKg),
          'weight_unit': useMetric ? 'kg' : 'lbs',
        },
        'use_metric': useMetric,
      };
    } catch (e) {
      AppLogger.error('[INSTAGRAM] Failed to fetch last ruck data: $e');
      return {};
    }
  }

  /// Unit conversion helpers
  double _kmToMiles(double km) => km * 0.621371;
  double _metersToFeet(double meters) => meters * 3.28084;
  double _kgToLbs(double kg) => kg * 2.20462;
  double? _paceKmToMiles(double? paceMinPerKm) {
    if (paceMinPerKm == null) return null;
    return paceMinPerKm / 0.621371; // Convert min/km to min/mile
  }

  /// Fetch time range data using the SAME RPC as home screen to get photos
  Future<Map<String, dynamic>> _fetchTimeRangeData(
    TimeRange timeRange,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool useMetric,
  ) async {
    try {
      AppLogger.info('[INSTAGRAM] Fetching time range data for ${timeRange.value} using /api/rucks');

      // Use /api/rucks endpoint which includes photos
      final response = await _apiClient.get('/api/rucks', queryParams: {'limit': 100});
      final allSessions = (response as List? ?? []).cast<Map<String, dynamic>>();

      // Filter sessions by time range
      final filteredSessions = _filterSessionsByTimeRange(allSessions, timeRange);

      AppLogger.info('[INSTAGRAM] Found ${filteredSessions.length} sessions for ${timeRange.value}');

      // Extract photos from filtered sessions using correct photos endpoint
      final photos = <String>[];
      for (final session in filteredSessions) {
        try {
          final sessionPhotos = await _fetchPhotosForSession(session['id']?.toString());
          photos.addAll(sessionPhotos);
          AppLogger.info('[INSTAGRAM] Added ${sessionPhotos.length} photos from session ${session['id']}');
        } catch (e) {
          AppLogger.warning('[INSTAGRAM] Failed to fetch photos for session ${session['id']}: $e');
        }
      }

      // Randomize and limit to 5 photos max
      photos.shuffle();
      final selectedPhotos = photos.take(5).toList();

      AppLogger.info('[INSTAGRAM] Found ${photos.length} total photos for ${timeRange.value}, selected ${selectedPhotos.length}');

      return {
        'photos': selectedPhotos,
        'recent_sessions': filteredSessions,
        'use_metric': useMetric,
      };
    } catch (e) {
      AppLogger.error('[INSTAGRAM] Error fetching time range data: $e');
      return {'photos': [], 'recent_sessions': []};
    }
  }

  /// Fetch photos for a specific session using the correct photos endpoint
  Future<List<String>> _fetchPhotosForSession(String? sessionId) async {
    AppLogger.info('[INSTAGRAM] _fetchPhotosForSession called with sessionId: $sessionId');

    if (sessionId == null || sessionId.isEmpty) {
      AppLogger.warning('[INSTAGRAM] Session ID is null or empty');
      return [];
    }

    try {
      AppLogger.info('[INSTAGRAM] Fetching photos for session: $sessionId');

      // Parse session ID to integer as expected by the API
      final parsedRuckId = int.tryParse(sessionId.trim());
      if (parsedRuckId == null) {
        AppLogger.error('[INSTAGRAM] Invalid session ID format: $sessionId');
        return [];
      }

      // Call the photos endpoint with ruck_id parameter
      final response = await _apiClient.get('/ruck-photos', queryParams: {
        'ruck_id': parsedRuckId.toString(),
      });

      AppLogger.info('[INSTAGRAM] Photos API response for session $sessionId: $response');
      AppLogger.info('[INSTAGRAM] Photos API response type: ${response.runtimeType}');

      // The API returns {"success": true, "data": [...]} format
      if (response is Map && response['data'] is List) {
        final photoList = response['data'] as List;
        final photoUrls = <String>[];

        for (final photo in photoList) {
          AppLogger.info('[INSTAGRAM] Processing photo data: $photo');
          if (photo is Map && photo['url'] != null) {
            final photoUrl = photo['url'].toString();
            photoUrls.add(photoUrl);
            AppLogger.info('[INSTAGRAM] Added photo URL: $photoUrl');
          } else {
            AppLogger.info('[INSTAGRAM] Photo data missing URL or not a Map: ${photo.runtimeType} - $photo');
          }
        }
        AppLogger.info('[INSTAGRAM] Final photo URLs for session $sessionId: $photoUrls');
        return photoUrls;
      } else {
        AppLogger.warning('[INSTAGRAM] Unexpected response format for photos: ${response.runtimeType} - $response');
        return [];
      }
    } catch (e) {
      AppLogger.error('[INSTAGRAM] Failed to fetch photos for session $sessionId: $e');
      return [];
    }
  }

  /// Build the OpenAI prompt
  String _buildPrompt({
    required Map<String, dynamic> insights,
    required TimeRange timeRange,
    required PostTemplate template,
    required bool useMetric,
  }) {
    final facts = _asStringKeyedMap(insights['facts']);
    final triggers = _asStringKeyedMap(insights['triggers']);
    final achievements = insights['achievements'] ?? [];

    // Extract key stats based on time range
    final stats = _extractStats(facts, timeRange, insights);

    return '''
You are a data-focused fitness analyst creating an Instagram post for a serious rucking athlete.

CONTEXT:
Time Range: ${timeRange.displayName}
Template Style: ${template.name}
Units: ${useMetric ? 'Metric (km, m, kg)' : 'Imperial (miles, feet, lbs)'}
${stats.isNotEmpty ? 'Key Stats: ${jsonEncode(stats)}' : ''}
${achievements.isNotEmpty ? 'Recent Achievements: ${achievements.join(', ')}' : ''}

CONTENT APPROACH:
- 90% DATA and concrete metrics (distance, time, pace, weight, elevation, etc.)
- 10% motivational language (keep it minimal and authentic)
- Lead with numbers and achievements
- Be specific about performance improvements
- Focus on factual progress rather than flowery descriptions
- Use ${useMetric ? 'metric units (km, m, kg, min/km)' : 'imperial units (miles, feet, lbs, min/mile)'} throughout

STYLE GUIDE for ${template.name}:
${_getTemplateGuidelines(template)}

REQUIREMENTS:
1. Create a data-rich Instagram caption (max 2200 characters)
2. Include @get.rucky naturally in the text
3. Use minimal emojis (only for key stats/achievements)
4. Generate exactly 3 highly relevant hashtags (without # symbol)
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
        // Use the session data we fetched from /api/rucks
        if (insights['stats'] != null) {
          return _asStringKeyedMap(insights['stats']);
        }
        // Fallback to session data directly
        if (insights['session'] != null) {
          final session = _asStringKeyedMap(insights['session']);
          return {
            'distance_km': session['distance_km'] ?? 0.0,
            'duration_seconds': session['duration_seconds'] ?? 0,
            'calories': session['calories'] ?? 0,
            'elevation_gain_m': session['elevation_gain_m'] ?? 0,
            'pace_min_per_km': session['pace_min_per_km'],
            'completed_at': session['completed_at'],
            'ruck_weight_kg': session['ruck_weight_kg'],
          };
        }
        break;
      case TimeRange.week:
        return _asStringKeyedMap(facts['weekly_stats']);
      case TimeRange.month:
        return _asStringKeyedMap(facts['monthly_stats']);
      case TimeRange.allTime:
        return _asStringKeyedMap(facts['all_time_stats']);
    }
    return {};
  }

  Map<String, dynamic> _normalizeInsights(Map<String, dynamic> insights) {
    final normalized = Map<String, dynamic>.from(insights);

    void assignIfPresent(String key) {
      if (normalized.containsKey(key)) {
        normalized[key] = _asStringKeyedMap(normalized[key]);
      }
    }

    assignIfPresent('facts');
    assignIfPresent('triggers');
    assignIfPresent('stats');
    assignIfPresent('time_range');
    assignIfPresent('weekly_stats');
    assignIfPresent('monthly_stats');
    assignIfPresent('all_time_stats');

    if (normalized['recent_sessions'] is List) {
      normalized['recent_sessions'] = (normalized['recent_sessions'] as List)
          .map((session) => _asStringKeyedMap(session))
          .toList();
    }

    return normalized;
  }

  Map<String, dynamic> _asStringKeyedMap(dynamic value) {
    if (value == null) return {};
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
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

    AppLogger.info('[INSTAGRAM] Extracting photos from insights. Keys: ${insights.keys.toList()}');

    // Try different possible photo locations in the response
    if (insights['photos'] != null) {
      final photoList = insights['photos'] as List;
      AppLogger.info('[INSTAGRAM] Found ${photoList.length} photos in insights[photos]');
      photos.addAll(photoList.map((p) => p.toString()));
    }

    if (insights['recent_sessions'] != null) {
      final sessions = insights['recent_sessions'] as List;
      AppLogger.info('[INSTAGRAM] Found ${sessions.length} sessions in insights[recent_sessions]');
      for (final session in sessions) {
        if (session['photos'] != null) {
          final sessionPhotos = session['photos'] as List;
          AppLogger.info('[INSTAGRAM] Found ${sessionPhotos.length} photos in session ${session['id']}');
          photos.addAll(sessionPhotos.map((p) => p.toString()));
        }
      }
    }

    // Randomize and limit to 5 photos max
    if (photos.isEmpty) {
      AppLogger.warning('[INSTAGRAM] No photos found in insights');
      return [];
    }

    // For Last Ruck, don't shuffle or limit - show all photos in order
    // For time ranges, limit and randomize
    if (photos.length <= 6) { // Assume if <= 6 photos, it's a single session (Last Ruck)
      AppLogger.info('[INSTAGRAM] Selected ${photos.length} photos (no shuffle/limit for single session)');
      return photos;
    } else {
      photos.shuffle(); // Randomize the order for time ranges
      final selectedPhotos = photos.take(5).toList();
      AppLogger.info('[INSTAGRAM] Selected ${selectedPhotos.length} photos from ${photos.length} total');
      return selectedPhotos;
    }
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
    required bool useMetric,
  }) async {
    try {
      print('[INSTAGRAM] Generating visual content for timeRange: ${timeRange.value}, sessionId: $sessionId');

      if (timeRange == TimeRange.lastRuck && sessionId != null) {
        print('[INSTAGRAM] Generating route map for Last Ruck with sessionId: $sessionId');
        // Generate route map for Last Ruck
        final result = await _generateRouteMapForSession(sessionId, template, useMetric);
        print('[INSTAGRAM] Route map generation result: $result');
        return result;
      } else {
        print('[INSTAGRAM] Generating stats card for time range: ${timeRange.value}');
        // Generate stats card for aggregate time ranges
        final result = await _generateStatsCard(insights, timeRange, template, useMetric);
        print('[INSTAGRAM] Stats card generation result: $result');
        return result;
      }
    } catch (e) {
      AppLogger.error('[INSTAGRAM] Error generating visual content: $e');
      return null;
    }
  }

  /// Generate route map for a specific session
  Future<String?> _generateRouteMapForSession(String sessionId, PostTemplate template, bool useMetric) async {
    try {
      AppLogger.info('[INSTAGRAM] Generating route map for session: $sessionId');

      // Fetch the session using the SAME RPC as home screen to get full route points
      final sessionData = await _fetchSessionUsingRPC(sessionId);
      if (sessionData == null) {
        AppLogger.warning('[INSTAGRAM] Session not found: $sessionId');
        return null;
      }

      AppLogger.info('[INSTAGRAM] Session data found: ${sessionData['id']}, location points: ${sessionData['route']?.length ?? 0}');

      // Convert RPC data to session object
      final session = RuckSession.fromJson(sessionData);

      // Check if session has location points
      if (session.locationPoints?.isEmpty ?? true) {
        AppLogger.warning('[INSTAGRAM] Session has no location points, skipping route map. locationPoints: ${session.locationPoints}');
        return null;
      }

      AppLogger.info('[INSTAGRAM] Session has ${session.locationPoints!.length} location points, generating route map');

      // Generate route map image
      final imageBytes = await _routeMapService.generateInstagramRouteMap(
        session: session,
        preferMetric: useMetric,
        applyPrivacyClipping: false, // Disable privacy clipping for now
      );

      if (imageBytes == null) {
        AppLogger.warning('[INSTAGRAM] Failed to generate route map image');
        return null;
      }

      AppLogger.info('[INSTAGRAM] Route map image generated successfully, size: ${imageBytes.length} bytes');

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
    bool useMetric,
  ) async {
    try {
      AppLogger.info('[INSTAGRAM] Generating stats card for ${timeRange.displayName}');

      // Generate stats visualization
      final imageBytes = await _statsVisualizationService.generateStatsCard(
        insights: insights,
        timeRange: timeRange,
        template: template,
        preferMetric: useMetric,
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

  /// Fetch session using the SAME RPC as home screen to get full route points
  Future<Map<String, dynamic>?> _fetchSessionUsingRPC(String sessionId) async {
    try {
      AppLogger.info('[INSTAGRAM] Fetching session $sessionId using RPC');

      // Use the EXACT same RPC call as home screen
      final result = await Supabase.instance.client
          .rpc('get_user_recent_sessions', params: {
        'p_limit': 50, // Get more sessions to find the specific one
      });

      if (result is List) {
        // Find the specific session by ID
        for (final sessionData in result) {
          if (sessionData is Map<String, dynamic> &&
              sessionData['id'].toString() == sessionId) {
            AppLogger.info('[INSTAGRAM] Found session $sessionId with ${sessionData['route']?.length ?? 0} route points');
            return sessionData;
          }
        }
      }

      AppLogger.warning('[INSTAGRAM] Session $sessionId not found in RPC results');
      return null;
    } catch (e) {
      AppLogger.error('[INSTAGRAM] Error fetching session via RPC: $e');
      return null;
    }
  }

  /// Filter sessions by time range
  List<Map<String, dynamic>> _filterSessionsByTimeRange(
    List<Map<String, dynamic>> sessions,
    TimeRange timeRange,
  ) {
    final now = DateTime.now();
    DateTime cutoffDate;

    switch (timeRange) {
      case TimeRange.week:
        cutoffDate = now.subtract(const Duration(days: 7));
        break;
      case TimeRange.month:
        cutoffDate = now.subtract(const Duration(days: 30));
        break;
      case TimeRange.allTime:
        // For all-time, return all sessions
        return sessions;
      case TimeRange.lastRuck:
        // Should not be called for lastRuck, but return first session as fallback
        return sessions.take(1).toList();
    }

    return sessions.where((session) {
      final dateString = session['started_at'] as String?;
      if (dateString == null) return false;

      final sessionDate = DateTime.tryParse(dateString);
      if (sessionDate == null) return false;

      return sessionDate.isAfter(cutoffDate);
    }).toList();
  }
}
