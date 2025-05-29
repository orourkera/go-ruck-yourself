// Standard library imports
import 'dart:io';
import 'dart:math' as math;

// Flutter and third-party imports
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:get_it/get_it.dart';

// Project-specific imports
import 'package:rucking_app/core/error_messages.dart' as error_msgs;
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/health_integration/bloc/health_bloc.dart';
import 'package:rucking_app/features/ruck_session/data/repositories/session_repository.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_photo.dart';
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
      
      // Include is_public field - either user's explicit choice or their default preference
      final authState = BlocProvider.of<AuthBloc>(context).state;
      final bool userAllowsSharing = authState is Authenticated ? 
          authState.user.allowRuckSharing : false;
      completionData['is_public'] = _shareSession ?? userAllowsSharing;

      // Save session first - this is fast and immediate
      await _apiClient.patch('/rucks/${widget.ruckId}', completionData);
      
      // Session saved successfully, navigate immediately - don't wait for photo uploads
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

  // UI helpers
  Color _getLadyModeColor(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    return authState is Authenticated && authState.user.gender == 'female'
        ? AppColors.ladyPrimary
        : AppColors.primary;
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
        StatCard(title: 'Ruck Weight', value: MeasurementUtils.formatWeight(widget.ruckWeight, metric: preferMetric), icon: Icons.fitness_center, color: AppColors.secondary, centerContent: true, valueFontSize: 36),
        if (_heartRateSamples?.isNotEmpty ?? false)
          StatCard(title: 'Avg HR', value: _avgHeartRate?.toString() ?? '--', icon: Icons.favorite, color: AppColors.error, centerContent: true, valueFontSize: 36),
        if (_heartRateSamples?.isNotEmpty ?? false)
          StatCard(title: 'Max HR', value: _maxHeartRate?.toString() ?? '--', icon: Icons.favorite_border, color: AppColors.error, centerContent: true, valueFontSize: 36),
      ],
    );
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