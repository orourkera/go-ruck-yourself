import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/home_screen.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';
import 'package:rucking_app/shared/widgets/custom_text_field.dart';
import 'package:rucking_app/shared/widgets/stat_card.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/ruck_session/domain/services/session_validation_service.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';

/// Screen displayed after a ruck session is completed, showing summary statistics
/// and allowing the user to rate and add notes about the session
class SessionCompleteScreen extends StatefulWidget {
  /// Timestamp when the user ended the session
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

  const SessionCompleteScreen({
    required this.completedAt,
    Key? key,
    required this.ruckId,
    required this.duration,
    required this.distance,
    required this.caloriesBurned,
    required this.elevationGain,
    required this.elevationLoss,
    required this.ruckWeight,
    this.initialNotes,
    this.heartRateSamples,
  }) : super(key: key);

  @override
  State<SessionCompleteScreen> createState() => _SessionCompleteScreenState();
}

class _SessionCompleteScreenState extends State<SessionCompleteScreen> {
  late final ApiClient _apiClient;
  
  int _rating = 3;
  int _perceivedExertion = 5;
  String _notes = '';
  List<String> _selectedTags = [];
  
  final List<String> _availableTags = [
    'morning', 'afternoon', 'evening',
    'urban', 'trail', 'hills', 'flat',
    'easy', 'moderate', 'hard',
    'recovery', 'training'
  ];
  
  bool _isSaving = false;
  
  // Form controllers and state
  final TextEditingController _notesController = TextEditingController();
  
  List<HeartRateSample>? _heartRateSamples;
  int? _avgHeartRate;
  int? _maxHeartRate;
  int? _minHeartRate;

  void setHeartRateSamples(List<HeartRateSample> samples) {
    setState(() {
      _heartRateSamples = samples;
      if (samples.isNotEmpty) {
        _avgHeartRate = (samples.map((e) => e.bpm).reduce((a, b) => a + b) / samples.length).round();
        _maxHeartRate = samples.map((e) => e.bpm).reduce((a, b) => a > b ? a : b);
        _minHeartRate = samples.map((e) => e.bpm).reduce((a, b) => a < b ? a : b);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    
    // Initialize API client
    _apiClient = GetIt.instance<ApiClient>();
    
    // Initialize notes controller with initial notes if provided
    _notesController.text = widget.initialNotes ?? '';
    
    // Populate stats
    // _populateStats(); // This method was empty anyway
    
    // --- Heart Rate: get samples from arguments if present
    if (widget.heartRateSamples != null) {
      setHeartRateSamples(widget.heartRateSamples!);
    }
  }
  
  /// Format duration as HH:MM:SS
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }
  
  /// Format pace based on user preference (metric/imperial)
  String _formatPace(bool preferMetric) {
    // Ensure distance is positive to avoid division by zero or negative pace
    if (widget.distance <= 0 || widget.duration.inSeconds <= 0) return '--:--';
    
    // Calculate pace in seconds per kilometer (assuming widget.distance is in km)
    final paceSecondsPerKm = widget.duration.inSeconds / widget.distance;
    
    // Use formatPaceSeconds which correctly handles metric/imperial conversion
    return MeasurementUtils.formatPaceSeconds(paceSecondsPerKm, metric: preferMetric);
  }
  
  /// Toggle a tag's selection status
  void _toggleTag(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else {
        _selectedTags.add(tag);
      }
    });
  }
  
  /// Saves the session review/notes and navigates home
  void _saveAndContinue() {
    setState(() {
      _isSaving = true;
    });
    
    // Prevent saving if session distance is below minimum
    final distanceMeters = widget.distance * 1000;
    if (distanceMeters < SessionValidationService.minSessionDistanceMeters) {
      // Delete the short session
      try {
        _apiClient.delete('/rucks/${widget.ruckId}');
        debugPrint('Deleted short distance session ${widget.ruckId}');
      } catch (e) {
        debugPrint('Failed to delete short distance session: $e');
      }
      // Inform user and navigate home
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Distance too short. Session not saved.'),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
      return;
    }
    
    // Prepare data for the /complete endpoint
    final Map<String, dynamic> completionData = {
      'completed_at': widget.completedAt.toIso8601String(),
      'notes': _notesController.text,
      'final_distance_km': widget.distance,
      'final_calories_burned': widget.caloriesBurned,
      'final_elevation_gain': widget.elevationGain,
      'final_elevation_loss': widget.elevationLoss,
      'final_average_pace': widget.distance > 0 ? (widget.duration.inSeconds / 60 / widget.distance) : null,
      'rating': _rating,
      'perceived_exertion': _perceivedExertion,
      'tags': _selectedTags,
    };

    // Remove null values (especially if average pace is not computable)
    completionData.removeWhere((key, value) => value == null);

    _apiClient.post('/rucks/${widget.ruckId}/complete', completionData)
      .then((response) {
        debugPrint("Session completed successfully: $response");
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
            (route) => false,
          );
        }
    }).catchError((e) {
      debugPrint("Error completing session: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to complete session: $e'),
            backgroundColor: AppColors.error,
          ),
        );
        setState(() {
          _isSaving = false;
        });
      }
    });
  }

  /// Populate stats from widget parameters
  void _populateStats() {
    // Stats are already provided as parameters to the widget
    // No need to fetch from API in this case
  }

  Widget _buildHeartRateSection() {
    if (_heartRateSamples == null || _heartRateSamples!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('Heart Rate', style: AppTextStyles.titleMedium),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildStatCard('Avg', _avgHeartRate?.toString() ?? '--', 'bpm'),
            _buildStatCard('Max', _maxHeartRate?.toString() ?? '--', 'bpm'),
            _buildStatCard('Min', _minHeartRate?.toString() ?? '--', 'bpm'),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: LineChart(_buildHeartRateChart()),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, String unit) {
    return Card(
      color: AppColors.primary.withOpacity(0.08),
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

  LineChartData _buildHeartRateChart() {
    final spots = _heartRateSamples!.asMap().entries.map((entry) {
      final idx = entry.key;
      final bpm = entry.value.bpm;
      return FlSpot(idx.toDouble(), bpm.toDouble());
    }).toList();
    return LineChartData(
      gridData: FlGridData(show: false),
      titlesData: FlTitlesData(show: false),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: AppColors.primary,
          barWidth: 3,
          dotData: FlDotData(show: false),
        ),
      ],
      minY: _minHeartRate?.toDouble() ?? 0,
      maxY: _maxHeartRate?.toDouble() ?? 200,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get user measurement preference
    bool preferMetric = true;
    final authState = context.read<AuthBloc>().state;
    if (authState is Authenticated) {
      preferMetric = authState.user.preferMetric;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Complete'),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Congratulations header
                Center(
                  child: Column(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 72,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Great job!',
                        style: AppTextStyles.headlineLarge.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You completed your ruck',
                        style: AppTextStyles.titleLarge,
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Session stats
                GridView.count(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.1,
                  children: [
                    StatCard(
                      title: 'Time',
                      value: _formatDuration(widget.duration),
                      icon: Icons.timer,
                      color: AppColors.primary,
                      centerContent: true,
                      valueFontSize: 36,
                    ),
                    StatCard(
                      title: 'Distance',
                      value: MeasurementUtils.formatDistance(widget.distance, metric: preferMetric),
                      icon: Icons.straighten,
                      color: AppColors.primary,
                      centerContent: true,
                      valueFontSize: 36,
                    ),
                    StatCard(
                      title: 'Calories',
                      value: widget.caloriesBurned.toString(),
                      icon: Icons.local_fire_department,
                      color: AppColors.accent,
                      centerContent: true,
                      valueFontSize: 36,
                    ),
                    StatCard(
                      title: 'Pace',
                      value: _formatPace(preferMetric),
                      icon: Icons.speed,
                      color: AppColors.secondary,
                      centerContent: true,
                      valueFontSize: 36,
                    ),
                    StatCard(
                      title: 'Elevation',
                      value: MeasurementUtils.formatElevationCompact(widget.elevationGain, widget.elevationLoss, metric: preferMetric),
                      icon: Icons.terrain,
                      color: AppColors.success,
                      centerContent: true,
                      valueFontSize: 28,
                    ),
                    StatCard(
                      title: 'Ruck Weight',
                      value: MeasurementUtils.formatWeight(widget.ruckWeight, metric: preferMetric),
                      icon: Icons.fitness_center,
                      color: AppColors.secondary,
                      centerContent: true,
                      valueFontSize: 36,
                    ),
                    // Heart Rate summary (if available)
                    if (_heartRateSamples != null && _heartRateSamples!.isNotEmpty) ...[
                      StatCard(
                        title: 'Avg HR',
                        value: _avgHeartRate?.toString() ?? '--',
                        icon: Icons.favorite,
                        color: AppColors.error,
                        centerContent: true,
                        valueFontSize: 36,
                      ),
                      StatCard(
                        title: 'Max HR',
                        value: _maxHeartRate?.toString() ?? '--',
                        icon: Icons.favorite_border,
                        color: AppColors.error,
                        centerContent: true,
                        valueFontSize: 36,
                      ),
                    ],
                  ],
                ),
                
                // Insert Heart Rate Section after summary stats
                if (_heartRateSamples != null && _heartRateSamples!.isNotEmpty)
                  _buildHeartRateSection(),
                
                const SizedBox(height: 24),
                
                // Rating
                Text(
                  'How would you rate this session?',
                  style: AppTextStyles.titleMedium,
                ),
                const SizedBox(height: 8),
                Center(
                  child: RatingBar.builder(
                    initialRating: _rating.toDouble(),
                    minRating: 1,
                    direction: Axis.horizontal,
                    allowHalfRating: false,
                    itemCount: 5,
                    itemPadding: const EdgeInsets.symmetric(horizontal: 4.0),
                    itemBuilder: (context, _) => const Icon(
                      Icons.star,
                      color: Colors.amber,
                    ),
                    onRatingUpdate: (rating) {
                      setState(() {
                        _rating = rating.toInt();
                      });
                    },
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Perceived exertion
                Text(
                  'How difficult was this session? (1-10)',
                  style: AppTextStyles.titleMedium,
                ),
                const SizedBox(height: 8),
                Slider(
                  value: _perceivedExertion.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: _perceivedExertion.toString(),
                  onChanged: (value) {
                    setState(() {
                      _perceivedExertion = value.toInt();
                    });
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Easy', style: AppTextStyles.bodyMedium),
                    Text('Hard', style: AppTextStyles.bodyMedium),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // Tags
                Text(
                  'Add tags',
                  style: AppTextStyles.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _availableTags.map((tag) {
                    final isSelected = _selectedTags.contains(tag);
                    return FilterChip(
                      label: Text(tag),
                      selected: isSelected,
                      onSelected: (_) => _toggleTag(tag),
                      backgroundColor: Colors.grey[200],
                      selectedColor: AppColors.primary.withOpacity(0.2),
                      checkmarkColor: AppColors.primary,
                    );
                  }).toList(),
                ),
                
                const SizedBox(height: 24),
                
                // Notes
                Text(
                  'Notes',
                  style: AppTextStyles.titleMedium,
                ),
                const SizedBox(height: 8),
                CustomTextField(
                  controller: _notesController,
                  label: 'Add notes about this session',
                  hint: 'How did it feel? What went well? What could be improved?',
                  maxLines: 4,
                  keyboardType: TextInputType.multiline,
                ),
                
                const SizedBox(height: 32),
                
                // Save button
                Center(
                  child: CustomButton(
                    onPressed: () {
                      if (!_isSaving) {
                        _saveAndContinue();
                      }
                    },
                    text: 'Save and Continue',
                    icon: Icons.save,
                    color: AppColors.primary,
                    isLoading: _isSaving,
                    width: 250,
                  ),
                ),
                
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 