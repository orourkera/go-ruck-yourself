// Standard library imports
import 'dart:io';
import 'dart:math' as math;
import 'dart:async';

// Flutter and third-party imports
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:get_it/get_it.dart';

// Core imports
import 'package:rucking_app/core/error_messages.dart' as error_msgs;
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/core/models/terrain_segment.dart';
import 'package:rucking_app/core/services/terrain_service.dart';

// Achievement imports
import 'package:rucking_app/features/achievements/presentation/bloc/achievement_bloc.dart';
import 'package:rucking_app/features/achievements/presentation/bloc/achievement_event.dart';
import 'package:rucking_app/features/achievements/presentation/bloc/achievement_state.dart';
import 'package:rucking_app/features/achievements/presentation/widgets/session_achievement_notification.dart';

// Project-specific imports
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/health_integration/bloc/health_bloc.dart';
import 'package:rucking_app/features/ruck_session/data/repositories/session_repository.dart';
import 'package:rucking_app/features/ruck_session/data/models/location_point.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_photo.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/features/ruck_session/domain/models/session_split.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/session_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/home_screen.dart';
import 'package:rucking_app/features/ruck_session/presentation/widgets/photo_upload_section.dart';
import 'package:rucking_app/features/ruck_session/presentation/widgets/splits_display.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';
import 'package:rucking_app/shared/widgets/custom_text_field.dart';
import 'package:rucking_app/shared/widgets/stat_card.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';
import 'package:rucking_app/shared/widgets/photo/photo_carousel.dart';
import 'package:rucking_app/core/services/share_service.dart';
import 'package:rucking_app/shared/widgets/share/share_preview_screen.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_bloc.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_state.dart';
import 'package:rucking_app/shared/widgets/stat_row.dart';

/// Screen displayed after a ruck session is completed, showing summary statistics
/// and allowing the user to rate and add notes about the session
class SessionCompleteScreen extends StatefulWidget {
  final DateTime completedAt;
  final String ruckId;
  final Duration duration;
  final double distance;
  final int caloriesBurned;
  final double elevationGain;
  final double elevationLoss;
  final double ruckWeight;
  final String? initialNotes;
  final List<HeartRateSample>? heartRateSamples;
  final List<SessionSplit>? splits;
  final List<TerrainSegment>? terrainSegments;

  const SessionCompleteScreen({
    super.key,
    required this.completedAt,
    required this.ruckId,
    required this.duration,
    required this.distance,
    required this.caloriesBurned,
    required this.elevationGain,
    required this.elevationLoss,
    required this.ruckWeight,
    this.initialNotes,
    this.heartRateSamples,
    this.splits,
    this.terrainSegments,
  });

  @override
  State<SessionCompleteScreen> createState() => _SessionCompleteScreenState();
}

class _SessionCompleteScreenState extends State<SessionCompleteScreen> {
  // Dependencies
  late final ApiClient _apiClient;
  final _notesController = TextEditingController();
  final _sessionRepo = SessionRepository(apiClient: GetIt.I<ApiClient>());

  // Form state
  int _rating = 3;
  int _perceivedExertion = 5;
  List<String> _selectedPhotos = [];
  bool _isSaving = false;
  bool _isUploadingPhotos = false;
  bool? _shareSession; // null means use user's default preference

  // Heart rate data
  List<HeartRateSample>? _heartRateSamples;
  int? _avgHeartRate;
  int? _maxHeartRate;
  int? _minHeartRate;

  // New variables to track achievement dialog and upsell navigation
  bool _isLoading = false;
  bool _isAchievementDialogShowing = false;
  bool _pendingUpsellNavigation = false;
  RuckSession? _pendingSessionData;

  @override
  void initState() {
    super.initState();
    _apiClient = GetIt.I<ApiClient>();
    _notesController.text = widget.initialNotes ?? '';
    
    if (widget.heartRateSamples != null && widget.heartRateSamples!.isNotEmpty) {
      _setHeartRateSamples(widget.heartRateSamples!);
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  // Heart rate handling
  void _setHeartRateSamples(List<HeartRateSample> samples) {
    setState(() {
      _heartRateSamples = samples;
      _avgHeartRate = (samples.map((e) => e.bpm).reduce((a, b) => a + b) / samples.length).round();
      _maxHeartRate = samples.map((e) => e.bpm).reduce(math.max);
      _minHeartRate = samples.map((e) => e.bpm).reduce(math.min);
    });
  }

  // Formatting utilities
  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _formatPace(bool preferMetric) {
    // Return -- for no distance or duration
    if (widget.distance <= 0.001 || widget.duration.inSeconds <= 0) return '--:--';
    
    final paceSecondsPerKm = widget.duration.inSeconds / widget.distance;
    
    // Cap pace at a reasonable maximum (99:59 per km/mi)
    if (paceSecondsPerKm > 5999) return '--:--';
    
    return MeasurementUtils.formatPaceSeconds(paceSecondsPerKm, metric: preferMetric);
  }

  // Session management
  Future<void> _saveAndContinue() async {
    if (_isSaving) return;
    
    setState(() => _isSaving = true);
    
    try {
      final completionData = {
        'rating': _rating,
        'perceived_exertion': _perceivedExertion,
        'completed': true,
        'notes': _notesController.text.trim(),
        'distance_km': widget.distance,
        'calories_burned': widget.caloriesBurned,
        'elevation_gain_m': widget.elevationGain,
        'elevation_loss_m': widget.elevationLoss,
      };
      
      // Include splits if available to preserve them during completion
      if (widget.splits != null && widget.splits!.isNotEmpty) {
        completionData['splits'] = widget.splits!.map((split) => split.toJson()).toList();
      }
      
      // Include is_public field - either user's explicit choice or their default preference
      final authState = BlocProvider.of<AuthBloc>(context).state;
      final bool userAllowsSharing = authState is Authenticated ? 
          authState.user.allowRuckSharing : false;
      completionData['is_public'] = _shareSession ?? userAllowsSharing;

      // Save session first - this is fast and immediate
      await _apiClient.patch('/rucks/${widget.ruckId}', completionData);
      
      // Check for new achievements after saving the session
      context.read<AchievementBloc>().add(CheckSessionAchievements(int.parse(widget.ruckId)));
      print('[DEBUG] SessionComplete: Dispatched CheckSessionAchievements for session ${widget.ruckId}');
      
      // Check premium status and navigate accordingly
      final premiumState = context.read<PremiumBloc>().state;
      bool isPremium = false;
      if (premiumState is PremiumLoaded) {
        isPremium = premiumState.isPremium;
      }
      
      // COMMENTED OUT: Paywall/upsell logic disabled per user request
      /*
      if (!isPremium) {
        // Free user - navigate to post-session upsell screen
        double avgPace = 0.0;
        if (widget.distance > 0) {
          avgPace = (widget.duration.inSeconds / 60) / widget.distance;
        }
        
        // Try to get location points from active session state first or the repository
        List<dynamic>? locationPoints;
        final activeSessionState = GetIt.instance<ActiveSessionBloc>().state;
        
        if (activeSessionState is ActiveSessionRunning && activeSessionState.locationPoints.isNotEmpty) {
          // Convert LocationPoint objects to Map<String, dynamic>
          locationPoints = activeSessionState.locationPoints
              .map((point) => point.toJson())
              .toList();
          AppLogger.info('Using ${locationPoints.length} location points from active session');
        } else {
          // Fallback: try to load from repository
          try {
            final sessionRepository = GetIt.instance<SessionRepository>();
            final fullSession = await sessionRepository.fetchSessionById(widget.ruckId);
            locationPoints = fullSession?.locationPoints;
            AppLogger.info('Loaded ${locationPoints?.length ?? 0} location points from repository');
          } catch (e) {
            AppLogger.warning('Could not load location points from repository: $e');
            locationPoints = null;
          }
        }
        
        final sessionData = RuckSession(
          id: widget.ruckId,
          startTime: DateTime.now().subtract(widget.duration),
          endTime: DateTime.now(),
          duration: widget.duration,
          distance: widget.distance,
          elevationGain: widget.elevationGain,
          elevationLoss: widget.elevationLoss,
          caloriesBurned: widget.caloriesBurned,
          ruckWeightKg: widget.ruckWeight,
          status: RuckStatus.completed,
          notes: _notesController.text.trim(),
          rating: _rating,
          averagePace: avgPace,
          heartRateSamples: _heartRateSamples,
          avgHeartRate: _avgHeartRate,
          maxHeartRate: _maxHeartRate,
          minHeartRate: _minHeartRate,
          locationPoints: locationPoints,
          splits: widget.splits,
        );
        
        // Check if we're currently showing achievements
        if (_isAchievementDialogShowing) {
          // Wait for achievements to be dismissed before navigating
          setState(() {
            _pendingUpsellNavigation = true;
            _pendingSessionData = sessionData;
          });
        } else {
          // No achievements showing, navigate immediately
          Navigator.pushNamedAndRemoveUntil(
            context, 
            '/post_session_upsell', 
            (route) => false,
            arguments: sessionData,
          );
        }
      } else {
        // Premium user - navigate directly to home
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      }
      */
      
      // SIMPLIFIED: Always navigate to home (no paywall for any user)
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);

      // Clear session history cache so new session appears in history
      SessionRepository.clearSessionHistoryCache();

      // Reset active session state to return to home screen properly
      context.read<ActiveSessionBloc>().add(const SessionReset());
      
      // Upload photos in background if any are selected - using repository
      if (_selectedPhotos.isNotEmpty) {
        // Start background upload using repository's independent method
        _sessionRepo.uploadSessionPhotosInBackground(
          widget.ruckId,
          _selectedPhotos.map((path) => File(path)).toList(),
        );
        
        // Show notification that upload started
        StyledSnackBar.show(
          context: context, 
          message: 'Uploading ${_selectedPhotos.length} photos in background...',
          duration: const Duration(seconds: 3),
        );
      }
      
    } catch (e) {
      StyledSnackBar.showError(context: context, message: 'Error saving session: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }
  
  void _discardSession(BuildContext context) {
    if (widget.ruckId.isEmpty) {
      StyledSnackBar.showError(context: context, message: 'Session ID missing');
      return;
    }
    context.read<SessionBloc>().add(DeleteSessionEvent(sessionId: widget.ruckId));
  }

  /// Share the completed session immediately without saving first
  void _shareSessionExternal(BuildContext context) async {
    AppLogger.info('Sharing completed session ${widget.ruckId}');
    
    try {
      // Get user preferences for metric/imperial and lady mode
      final authState = context.read<AuthBloc>().state;
      final bool preferMetric = authState is Authenticated ? authState.user.preferMetric : true;
      final bool isLadyMode = authState is Authenticated ? authState.user.gender == 'female' : false;
      
      // Try to get location points from active session state first
      List<dynamic>? locationPoints;
      final activeSessionState = GetIt.instance<ActiveSessionBloc>().state;
      
      if (activeSessionState is ActiveSessionRunning && activeSessionState.locationPoints.isNotEmpty) {
        // Convert LocationPoint objects to Map<String, dynamic>
        locationPoints = activeSessionState.locationPoints
            .map((point) => point.toJson())
            .toList();
        AppLogger.info('Using ${locationPoints.length} location points from active session');
      } else {
        // Fallback: try to load from repository
        try {
          final sessionRepository = GetIt.instance<SessionRepository>();
          final fullSession = await sessionRepository.fetchSessionById(widget.ruckId);
          locationPoints = fullSession?.locationPoints;
          AppLogger.info('Loaded ${locationPoints?.length ?? 0} location points from repository');
        } catch (e) {
          AppLogger.warning('Could not load location points from repository: $e');
          locationPoints = null;
        }
      }
      
      // Create a RuckSession from the complete screen data
      final sessionForSharing = RuckSession(
        id: widget.ruckId,
        startTime: widget.completedAt.subtract(widget.duration),
        endTime: widget.completedAt,
        duration: widget.duration,
        distance: widget.distance,
        caloriesBurned: widget.caloriesBurned,
        elevationGain: widget.elevationGain,
        elevationLoss: widget.elevationLoss,
        averagePace: widget.duration.inSeconds > 0 && widget.distance > 0 
            ? (widget.duration.inMinutes / widget.distance) : 0.0,
        ruckWeightKg: widget.ruckWeight ?? 0.0,
        status: RuckStatus.completed,
        heartRateSamples: _heartRateSamples,
        avgHeartRate: _avgHeartRate,
        maxHeartRate: _maxHeartRate,
        minHeartRate: _minHeartRate,
        splits: widget.splits,
        locationPoints: locationPoints,
      );
      
      // Get session photos - handle both file paths and URLs
      String? backgroundImageUrl;
      List<String> sessionPhotos = [];
      
      // First, check if we have selected photos as file paths
      if (_selectedPhotos.isNotEmpty) {
        AppLogger.info('Found ${_selectedPhotos.length} selected photos as file paths');
        
        // Check if these are already URLs or file paths
        if (_selectedPhotos.first.startsWith('http')) {
          // These are already URLs
          sessionPhotos = _selectedPhotos;
          backgroundImageUrl = _selectedPhotos.first;
          AppLogger.info('Using photos as URLs directly');
        } else {
          // These are file paths - we need URLs from the uploaded photos
          // Check if photos have been uploaded and are available in the active session state
          if (activeSessionState is SessionPhotosLoadedForId && activeSessionState.photos.isNotEmpty) {
            final availablePhotos = activeSessionState.photos;
            sessionPhotos = availablePhotos
                .map((photo) => photo.url)
                .where((url) => url != null)
                .cast<String>()
                .toList();
            backgroundImageUrl = sessionPhotos.isNotEmpty ? sessionPhotos.first : null;
            AppLogger.info('Found ${sessionPhotos.length} uploaded photo URLs from SessionPhotosLoadedForId');
          } else if (activeSessionState is SessionSummaryGenerated && activeSessionState.photos.isNotEmpty) {
            final availablePhotos = activeSessionState.photos;
            sessionPhotos = availablePhotos
                .map((photo) => photo.url)
                .where((url) => url != null)
                .cast<String>()
                .toList();
            backgroundImageUrl = sessionPhotos.isNotEmpty ? sessionPhotos.first : null;
            AppLogger.info('Found ${sessionPhotos.length} uploaded photo URLs from SessionSummaryGenerated');
          } else {
            // Photos not uploaded yet - we can only share without photos
            AppLogger.warning('Photos selected but not uploaded yet, sharing without photos');
          }
        }
      } else {
        // No photos selected in this screen, check active session state
        AppLogger.info('No photos selected, checking active session state');
        
        if (activeSessionState is SessionPhotosLoadedForId && activeSessionState.photos.isNotEmpty) {
          final availablePhotos = activeSessionState.photos;
          sessionPhotos = availablePhotos
              .map((photo) => photo.url)
              .where((url) => url != null)
              .cast<String>()
              .toList();
          backgroundImageUrl = sessionPhotos.isNotEmpty ? sessionPhotos.first : null;
          AppLogger.info('Found ${sessionPhotos.length} photo URLs from SessionPhotosLoadedForId');
        } else if (activeSessionState is SessionSummaryGenerated && activeSessionState.photos.isNotEmpty) {
          final availablePhotos = activeSessionState.photos;
          sessionPhotos = availablePhotos
              .map((photo) => photo.url)
              .where((url) => url != null)
              .cast<String>()
              .toList();
          backgroundImageUrl = sessionPhotos.isNotEmpty ? sessionPhotos.first : null;
          AppLogger.info('Found ${sessionPhotos.length} photo URLs from SessionSummaryGenerated');
        } else {
          AppLogger.warning('No photos found in active session state');
        }
      }
      
      AppLogger.info('Navigating to share preview with ${locationPoints?.length ?? 0} location points and ${sessionPhotos.length} photos');
      
      // Navigate to share preview screen
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => SharePreviewScreen(
            session: sessionForSharing,
            preferMetric: preferMetric,
            backgroundImageUrl: backgroundImageUrl,
            achievements: [], // Could populate with achievement strings if available
            isLadyMode: isLadyMode,
            sessionPhotos: sessionPhotos,
          ),
        ),
      );
    } catch (e) {
      AppLogger.error('Failed to open share preview: $e', exception: e);
      
      // Show error message
      if (context.mounted) {
        StyledSnackBar.showError(
          context: context,
          message: 'Failed to open share preview: ${e.toString()}',
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  // UI helpers
  Color _getLadyModeColor(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    return authState is Authenticated && authState.user.gender == 'female'
        ? AppColors.ladyPrimary
        : AppColors.primary;
  }

  void _handleAchievementDismissed() {
    setState(() {
      _isAchievementDialogShowing = false;
    });
    // COMMENTED OUT: Paywall/upsell logic disabled per user request
    /*
    if (_pendingUpsellNavigation) {
      setState(() {
        _pendingUpsellNavigation = false;
      });
      Navigator.pushNamedAndRemoveUntil(
        context, 
        '/post_session_upsell', 
        (route) => false,
        arguments: _pendingSessionData,
      );
      _pendingSessionData = null;
    }
    */
    
    // SIMPLIFIED: Always navigate to home after achievements dismissed
    if (_pendingUpsellNavigation) {
      setState(() {
        _pendingUpsellNavigation = false;
      });
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      _pendingSessionData = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final preferMetric = authState is Authenticated ? authState.user.preferMetric : true;

    return MultiBlocListener(
      listeners: [
        BlocListener<SessionBloc, SessionState>(
          listener: (context, state) {
            if (state is SessionOperationInProgress) {
              StyledSnackBar.show(context: context, message: 'Discarding session...');
            } else if (state is SessionDeleteSuccess) {
              StyledSnackBar.showSuccess(context: context, message: 'Session discarded');
              Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
            } else if (state is SessionOperationFailure) {
              StyledSnackBar.showError(context: context, message: 'Error: ${state.message}');
            }
          },
        ),
        BlocListener<HealthBloc, HealthState>(
          listener: (context, state) {
            if (state is HealthDataWriteStatus) {
              final message = state.success
                  ? 'Saved to Apple Health'
                  : 'Failed to save to Apple Health';
              state.success
                  ? StyledSnackBar.showSuccess(context: context, message: message)
                  : StyledSnackBar.showError(context: context, message: message);
            }
          },
        ),
        BlocListener<AchievementBloc, AchievementState>(
          listener: (context, state) {
            print('[DEBUG] SessionComplete: Achievement state changed to ${state.runtimeType}');
            if (state is AchievementsSessionChecked) {
              print('[DEBUG] SessionComplete: AchievementsSessionChecked with ${state.newAchievements.length} new achievements');
              if (state.newAchievements.isNotEmpty) {
                print('[DEBUG] SessionComplete: Showing achievement notification dialog');
                setState(() {
                  _isAchievementDialogShowing = true;
                });
                
                // Show achievement unlock celebration
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => AlertDialog(
                      content: SessionAchievementNotification(
                        newAchievements: state.newAchievements,
                        onDismiss: () {
                          Navigator.of(context).pop();
                          _handleAchievementDismissed();
                        },
                      ),
                      contentPadding: EdgeInsets.zero,
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                    ),
                  );
                  
                  // Auto-dismiss after 4 seconds to give users time to see it
                  Timer(const Duration(seconds: 4), () {
                    if (_isAchievementDialogShowing && mounted) {
                      Navigator.of(context).pop();
                      _handleAchievementDismissed();
                    }
                  });
                });
              }
            }
          },
        ),
      ],
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Session Complete'),
          centerTitle: true,
          backgroundColor: _getLadyModeColor(context),
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 24),
                _buildStatsGrid(preferMetric),
                if (widget.terrainSegments != null && widget.terrainSegments!.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _buildTerrainBreakdownSection(preferMetric),
                ],
                if (widget.splits != null && widget.splits!.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _buildSplitsSection(preferMetric),
                ],
                if (_heartRateSamples?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 24),
                  _buildHeartRateSection(),
                ],
                const SizedBox(height: 24),
                _buildPhotoUploadSection(),
                const SizedBox(height: 24),
                _buildRatingSection(),
                const SizedBox(height: 24),
                _buildExertionSection(),
                const SizedBox(height: 24),
                _buildNotesSection(),
                const SizedBox(height: 24),
                _buildSharingSection(),
                const SizedBox(height: 32),
                _buildActionButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Center(
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 72),
          const SizedBox(height: 16),
          Text('Great job rucker!', style: AppTextStyles.headlineLarge.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('You completed your ruck', style: AppTextStyles.titleLarge),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(bool preferMetric) {
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.1,
      children: [
        StatCard(title: 'Time', value: _formatDuration(widget.duration), icon: Icons.timer, color: _getLadyModeColor(context), centerContent: true, valueFontSize: 36),
        StatCard(title: 'Distance', value: MeasurementUtils.formatDistance(widget.distance, metric: preferMetric), icon: Icons.straighten, color: _getLadyModeColor(context), centerContent: true, valueFontSize: 36),
        StatCard(title: 'Calories', value: widget.caloriesBurned.toString(), icon: Icons.local_fire_department, color: AppColors.accent, centerContent: true, valueFontSize: 36),
        StatCard(title: 'Pace', value: _formatPace(preferMetric), icon: Icons.speed, color: AppColors.secondary, centerContent: true, valueFontSize: 36),
        StatCard(
          title: 'Elevation',
          value: preferMetric ? '${widget.elevationGain.toStringAsFixed(0)} m' : '${(widget.elevationGain * 3.28084).toStringAsFixed(0)} ft',
          icon: Icons.terrain,
          color: AppColors.success,
          centerContent: true,
          valueFontSize: 28
        ),
        StatCard(title: 'Ruck Weight', value: widget.ruckWeight == 0.0 ? 'HIKE' : MeasurementUtils.formatWeight(widget.ruckWeight, metric: preferMetric), icon: Icons.fitness_center, color: AppColors.secondary, centerContent: true, valueFontSize: 36),
        if (_heartRateSamples?.isNotEmpty ?? false)
          StatCard(title: 'Avg HR', value: _avgHeartRate?.toString() ?? '--', icon: Icons.favorite, color: AppColors.error, centerContent: true, valueFontSize: 36),
        if (_heartRateSamples?.isNotEmpty ?? false)
          StatCard(title: 'Max HR', value: _maxHeartRate?.toString() ?? '--', icon: Icons.favorite_border, color: AppColors.error, centerContent: true, valueFontSize: 36),
      ],
    );
  }

  Widget _buildTerrainBreakdownSection(bool preferMetric) {
    final stats = TerrainSegment.getTerrainStats(widget.terrainSegments!);
    final surfaceBreakdown = stats['surface_breakdown'] as Map<String, double>? ?? <String, double>{};
    final weightedMultiplier = stats['weighted_multiplier'] as double? ?? 1.0;
    final mostCommonSurface = stats['most_common_surface'] as String? ?? 'paved';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.terrain, color: AppColors.success, size: 20),
              const SizedBox(width: 8),
              Text('Terrain Impact', style: AppTextStyles.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Primary Surface:', style: AppTextStyles.bodyMedium),
              Text(_formatSurfaceType(mostCommonSurface), style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Energy Multiplier:', style: AppTextStyles.bodyMedium),
              Text('${weightedMultiplier.toStringAsFixed(2)}x', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          if (surfaceBreakdown.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Surface Breakdown:', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...surfaceBreakdown.entries.map((entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatSurfaceType(entry.key), style: AppTextStyles.bodySmall),
                  Text('${MeasurementUtils.formatDistance(entry.value, metric: preferMetric)}', style: AppTextStyles.bodySmall),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }

  String _formatSurfaceType(String surfaceType) {
    return surfaceType
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  Widget _buildSplitsSection(bool preferMetric) {
    return SplitsDisplay(splits: widget.splits!, isMetric: preferMetric);
  }

  Widget _buildHeartRateSection() {
    // Check if heart rate samples are available
    final bool hasHeartRateData = _heartRateSamples != null && _heartRateSamples!.isNotEmpty;
    
    // Log heart rate data for debugging
    if (!hasHeartRateData) {
      debugPrint('[SessionCompleteScreen] No heart rate samples available to display');
    } else {
      debugPrint('[SessionCompleteScreen] Displaying ${_heartRateSamples!.length} heart rate samples');
      debugPrint('[SessionCompleteScreen] Avg: $_avgHeartRate, Min: $_minHeartRate, Max: $_maxHeartRate');
    }
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.favorite, color: AppColors.error, size: 20),
              const SizedBox(width: 8),
              Text('Heart Rate', style: AppTextStyles.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatCard('Avg', _avgHeartRate?.toString() ?? '--', 'bpm'),
              _buildStatCard('Max', _maxHeartRate?.toString() ?? '--', 'bpm'),
              _buildStatCard('Min', _minHeartRate?.toString() ?? '--', 'bpm'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: hasHeartRateData 
              ? AnimatedHeartRateChart(
                  heartRateSamples: _heartRateSamples!,
                  avgHeartRate: _avgHeartRate,
                  maxHeartRate: _maxHeartRate,
                  minHeartRate: _minHeartRate,
                  getLadyModeColor: _getLadyModeColor,
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.timeline_outlined, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        'No heart rate data available',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, String unit) {
    return Card(
      color: _getLadyModeColor(context).withOpacity(0.08),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            Text(label, style: AppTextStyles.bodySmall),
            Text(value, style: AppTextStyles.headlineMedium),
            Text(unit, style: AppTextStyles.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoUploadSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: PhotoUploadSection(
        ruckId: widget.ruckId,
        onPhotosSelected: (photos) => setState(() => _selectedPhotos = photos.map((file) => file.path).toList()),
        isUploading: _isUploadingPhotos,
      ),
    );
  }

  Widget _buildRatingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How would you rate this session?', style: AppTextStyles.titleMedium),
        const SizedBox(height: 8),
        Center(
          child: RatingBar.builder(
            initialRating: _rating.toDouble(),
            minRating: 1,
            direction: Axis.horizontal,
            allowHalfRating: false,
            itemCount: 5,
            itemPadding: const EdgeInsets.symmetric(horizontal: 4),
            itemBuilder: (context, _) => const Icon(Icons.star, color: Colors.amber),
            unratedColor: Theme.of(context).brightness == Brightness.dark 
                ? Colors.grey.shade600 // Light gray in dark mode for visibility
                : Colors.grey.shade300, // Original light gray in light mode
            onRatingUpdate: (rating) => setState(() => _rating = rating.toInt()),
          ),
        ),
      ],
    );
  }

  Widget _buildExertionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How difficult was this session? (1-10)', style: AppTextStyles.titleMedium),
        const SizedBox(height: 8),
        Slider(
          value: _perceivedExertion.toDouble(),
          min: 1,
          max: 10,
          divisions: 9,
          label: _perceivedExertion.toString(),
          onChanged: (value) => setState(() => _perceivedExertion = value.toInt()),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Easy', style: AppTextStyles.bodyMedium),
            Text('Hard', style: AppTextStyles.bodyMedium),
          ],
        ),
      ],
    );
  }

  Widget _buildNotesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Notes', style: AppTextStyles.titleMedium),
        const SizedBox(height: 8),
        CustomTextField(
          controller: _notesController,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
          label: 'Add notes about this session',
          hint: 'How did it feel? What went well? What could be improved?',
          maxLines: 4,
          keyboardType: TextInputType.multiline,
        ),
      ],
    );
  }

  Widget _buildSharingSection() {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        final bool userAllowsSharing = authState is Authenticated 
            ? authState.user.allowRuckSharing 
            : false;
        
        final bool effectiveShareSetting = _shareSession ?? userAllowsSharing;
      final bool preferMetric = authState is Authenticated ? authState.user.preferMetric : true;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Session Sharing', style: AppTextStyles.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Default: ${userAllowsSharing ? 'Public' : 'Private'} (based on your preferences)',
              style: AppTextStyles.bodySmall.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  effectiveShareSetting ? Icons.public : Icons.lock,
                  size: 20,
                  color: effectiveShareSetting ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    effectiveShareSetting 
                        ? 'This session will be visible to other users'
                        : 'This session will be private',
                    style: AppTextStyles.bodyMedium,
                  ),
                ),
                Switch(
                  value: effectiveShareSetting,
                  onChanged: (value) {
                    setState(() {
                      // If the new value matches user's default, clear override
                      _shareSession = (value == userAllowsSharing) ? null : value;
                    });
                  },
                ),
              ],
            ),
            if (_shareSession != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Override: ${_shareSession! ? 'Public' : 'Private'} for this session',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: _shareSession! ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              preferMetric
                  ? 'The first and last 400m of the ruck will be only visible to you and not shown publicly.'
                  : 'The first and last 1/4 mile of the ruck will be only visible to you and not shown publicly.',
              style: AppTextStyles.bodySmall.copyWith(color: Colors.grey.shade600),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        Center(
          child: CustomButton(
            onPressed: _isSaving ? null : _saveAndContinue,
            text: 'Save and Continue',
            icon: Icons.save,
            color: _getLadyModeColor(context),
            isLoading: _isSaving,
            width: 250,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: CustomButton(
            onPressed: () => _shareSessionExternal(context),
            text: 'Share Session',
            icon: Icons.share,
            color: AppColors.success,
            width: 250,
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: TextButton(
            onPressed: () => showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Discard Ruck?'),
                content: const Text('This will delete this ruck session and all associated data. This action cannot be undone.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _discardSession(context);
                    },
                    child: const Text('Discard', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ),
            child: const Text('Discard this ruck', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500)),
          ),
        ),
      ],
    );
  }
}

class AnimatedHeartRateChart extends StatefulWidget {
  final List<HeartRateSample> heartRateSamples;
  final int? avgHeartRate;
  final int? maxHeartRate;
  final int? minHeartRate;
  final Color Function(BuildContext) getLadyModeColor;

  const AnimatedHeartRateChart({
    super.key,
    required this.heartRateSamples,
    this.avgHeartRate,
    this.maxHeartRate,
    this.minHeartRate,
    required this.getLadyModeColor,
  });

  @override
  State<AnimatedHeartRateChart> createState() => _AnimatedHeartRateChartState();
}

class _AnimatedHeartRateChartState extends State<AnimatedHeartRateChart> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutQuad);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => LineChart(_buildChartData(_animation.value)),
    );
  }

  LineChartData _buildChartData(double animationValue) {
    if (widget.heartRateSamples.isEmpty) return LineChartData();

    final pointsToShow = (widget.heartRateSamples.length * animationValue).round().clamp(1, widget.heartRateSamples.length);
    final visibleSamples = widget.heartRateSamples.sublist(0, pointsToShow);
    final firstTimestamp = widget.heartRateSamples.first.timestamp.millisecondsSinceEpoch.toDouble();

    final spots = visibleSamples.map((sample) {
      final timeOffset = (sample.timestamp.millisecondsSinceEpoch - firstTimestamp) / (1000 * 60);
      return FlSpot(timeOffset, sample.bpm.toDouble());
    }).toList();

    final safeMaxX = spots.isNotEmpty ? spots.last.x : 10.0;
    final safeMinY = (widget.minHeartRate?.toDouble() ?? 60.0) - 10.0;
    final safeMaxY = (widget.maxHeartRate?.toDouble() ?? 180.0) + 10.0;

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: 30,
        verticalInterval: 5,
        getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.shade300, strokeWidth: 1),
        getDrawingVerticalLine: (_) => FlLine(color: Colors.grey.shade300, strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        show: true,
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            interval: spots.isNotEmpty && spots.last.x > 10 ? (spots.last.x / 5).roundToDouble().clamp(1.0, 20.0) : 5,
            getTitlesWidget: (value, meta) => SideTitleWidget(
              axisSide: meta.axisSide,
              child: Text('${value.round()}m', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            ),
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: 30,
            getTitlesWidget: (value, meta) => SideTitleWidget(
              axisSide: meta.axisSide,
              child: Text('${value.toInt()}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            ),
          ),
        ),
      ),
      borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.shade300)),
      minX: 0,
      maxX: safeMaxX,
      minY: safeMinY,
      maxY: safeMaxY,
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.25,
          color: widget.getLadyModeColor(context),
          barWidth: 3.5,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: widget.getLadyModeColor(context).withOpacity(0.2)),
        ),
      ],
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          if (widget.maxHeartRate != null)
            HorizontalLine(
              y: widget.maxHeartRate!.toDouble(),
              color: Colors.red.withOpacity(0.6),
              strokeWidth: 1,
              dashArray: [5, 5],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                padding: const EdgeInsets.only(right: 5, bottom: 5),
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 10),
                labelResolver: (_) => 'Max: ${widget.maxHeartRate} bpm',
              ),
            ),
        ],
      ),
    );
  }
}