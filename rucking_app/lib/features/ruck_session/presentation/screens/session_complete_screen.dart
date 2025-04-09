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

/// Screen displayed after a ruck session is completed, showing summary statistics
/// and allowing the user to rate and add notes about the session
class SessionCompleteScreen extends StatefulWidget {
  final String ruckId;
  final Duration duration;
  final double distance;
  final int caloriesBurned;
  final double elevationGain;
  final double elevationLoss;
  final double ruckWeight;

  const SessionCompleteScreen({
    Key? key,
    required this.ruckId,
    required this.duration,
    required this.distance,
    required this.caloriesBurned,
    required this.elevationGain,
    required this.elevationLoss,
    required this.ruckWeight,
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
  
  @override
  void initState() {
    super.initState();
    
    // Initialize API client
    _apiClient = GetIt.instance<ApiClient>();
    
    // Populate stats
    _populateStats();
  }
  
  /// Format duration as HH:MM:SS
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }
  
  /// Format pace (minutes per km) as MM:SS
  String _formatPace() {
    if (widget.distance <= 0) return '--:--';
    
    // Calculate pace (minutes per km)
    final paceMinutes = widget.duration.inSeconds / 60 / widget.distance;
    final mins = paceMinutes.floor();
    final secs = ((paceMinutes - mins) * 60).round();
    
    return '$mins:${secs.toString().padLeft(2, '0')}';
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
  
  /// Save session details to the backend and navigate to home
  Future<void> _saveAndContinue() async {
    setState(() {
      _isSaving = true;
    });
    
    try {
      // Update session with rating, exertion, notes, tags
      await _apiClient.post('/api/rucks/${widget.ruckId}/complete', {
        'rating': _rating,
        'perceived_exertion': _perceivedExertion,
        'notes': _notes,
        'tags': _selectedTags,
      });
      
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save session: $e')),
      );
      setState(() {
        _isSaving = false;
      });
    }
  }

  /// Populate stats from widget parameters
  void _populateStats() {
    // Stats are already provided as parameters to the widget
    // No need to fetch from API in this case
  }

  @override
  Widget build(BuildContext context) {
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
                        style: AppTextStyles.headline4.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You completed your ruck',
                        style: AppTextStyles.headline6,
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
                  childAspectRatio: 1.5,
                  children: [
                    StatCard(
                      title: 'Time',
                      value: _formatDuration(widget.duration),
                      icon: Icons.timer,
                      color: AppColors.primary,
                    ),
                    StatCard(
                      title: 'Distance',
                      value: '${widget.distance.toStringAsFixed(2)} km',
                      icon: Icons.straighten,
                      color: AppColors.secondary,
                    ),
                    StatCard(
                      title: 'Calories',
                      value: '${widget.caloriesBurned}',
                      icon: Icons.local_fire_department,
                      color: Colors.orange,
                    ),
                    StatCard(
                      title: 'Pace',
                      value: _formatPace(),
                      icon: Icons.speed,
                      color: Colors.purple,
                    ),
                    StatCard(
                      title: 'Elevation',
                      value: '+${widget.elevationGain.toStringAsFixed(1)} m',
                      secondaryValue: '-${widget.elevationLoss.toStringAsFixed(1)} m',
                      icon: Icons.terrain,
                      color: Colors.green,
                    ),
                    StatCard(
                      title: 'Ruck Weight',
                      value: '${widget.ruckWeight} kg',
                      icon: Icons.fitness_center,
                      color: Colors.blueGrey,
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // Rating
                Text(
                  'How would you rate this session?',
                  style: AppTextStyles.subtitle1,
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
                  style: AppTextStyles.subtitle1,
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
                    Text('Easy', style: AppTextStyles.body2),
                    Text('Hard', style: AppTextStyles.body2),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // Tags
                Text(
                  'Add tags',
                  style: AppTextStyles.subtitle1,
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
                  style: AppTextStyles.subtitle1,
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
                    onPressed: _isSaving ? _saveAndContinue : () {},
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