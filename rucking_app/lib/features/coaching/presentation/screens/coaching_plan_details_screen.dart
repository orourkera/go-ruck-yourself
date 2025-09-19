import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/features/coaching/data/services/coaching_service.dart';
import 'package:rucking_app/features/coaching/domain/models/coaching_personality.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

class CoachingPlanDetailsScreen extends StatefulWidget {
  const CoachingPlanDetailsScreen({Key? key}) : super(key: key);

  @override
  State<CoachingPlanDetailsScreen> createState() => _CoachingPlanDetailsScreenState();
}

class _CoachingPlanDetailsScreenState extends State<CoachingPlanDetailsScreen> {
  final CoachingService _coachingService = GetIt.instance<CoachingService>();
  Map<String, dynamic>? _planData;
  bool _isLoading = true;
  bool _isEditing = false;

  // Editable fields
  int _trainingDaysPerWeek = 3;
  String _selectedPersonality = 'Supportive Friend';
  List<String> _selectedDays = [];

  @override
  void initState() {
    super.initState();
    _loadPlanData();
  }

  Future<void> _loadPlanData() async {
    try {
      final data = await _coachingService.getActiveCoachingPlan();
      if (data != null) {
        setState(() {
          _planData = data;
          // Extract current values
          _trainingDaysPerWeek = data['training_days_per_week'] ?? 3;
          _selectedPersonality = data['personality'] ?? 'Supportive Friend';
          _selectedDays = List<String>.from(data['preferred_days'] ?? []);
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.error('Failed to load coaching plan: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _savePlanChanges() async {
    // TODO: Implement API call to update plan
    setState(() {
      _isEditing = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Plan updated successfully!'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text('Your Coaching Plan'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if (!_isLoading && _planData != null)
            IconButton(
              icon: Icon(_isEditing ? Icons.save : Icons.edit),
              onPressed: () {
                if (_isEditing) {
                  _savePlanChanges();
                } else {
                  setState(() {
                    _isEditing = true;
                  });
                }
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _planData == null
              ? _buildNoPlanView()
              : _buildPlanView(),
    );
  }

  Widget _buildNoPlanView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.fitness_center,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No active coaching plan',
            style: AppTextStyles.headlineMedium.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a personalized plan to get started',
            style: AppTextStyles.bodyMedium.copyWith(
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pushReplacementNamed('/create-plan');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Create Plan'),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Plan Overview Card
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.emoji_events,
                          color: AppColors.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _planData!['plan_name'] ?? 'Custom Plan',
                              style: AppTextStyles.titleLarge.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Started ${_formatDate(_planData!['start_date'])}',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildProgressIndicator(),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Training Schedule Card
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Training Schedule',
                    style: AppTextStyles.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Days per week
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Days per week',
                        style: AppTextStyles.bodyLarge,
                      ),
                      if (_isEditing)
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: _trainingDaysPerWeek > 1
                                  ? () => setState(() => _trainingDaysPerWeek--)
                                  : null,
                              color: AppColors.primary,
                            ),
                            Text(
                              '$_trainingDaysPerWeek',
                              style: AppTextStyles.titleMedium.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: _trainingDaysPerWeek < 7
                                  ? () => setState(() => _trainingDaysPerWeek++)
                                  : null,
                              color: AppColors.primary,
                            ),
                          ],
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '$_trainingDaysPerWeek days',
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Preferred days
                  Text(
                    'Preferred days',
                    style: AppTextStyles.bodyLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _buildDayChips(),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Coaching Style Card
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Coaching Style',
                    style: AppTextStyles.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_isEditing)
                    DropdownButtonFormField<String>(
                      value: _selectedPersonality,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      items: CoachingPersonality.allPersonalities
                          .map((personality) => DropdownMenuItem(
                                value: personality.id,
                                child: Row(
                                  children: [
                                    Icon(
                                      personality.icon,
                                      size: 20,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(personality.name),
                                  ],
                                ),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedPersonality = value;
                          });
                        }
                      },
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _getPersonalityIcon(),
                            color: AppColors.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _selectedPersonality,
                            style: AppTextStyles.bodyLarge.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Next Scheduled Activity Card
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        color: AppColors.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Next Activity',
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Tomorrow - Base Ruck',
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '45 minutes • 30 lbs • Zone 2',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDayChips() {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return days.map((day) {
      final isSelected = _selectedDays.contains(day);

      return FilterChip(
        label: Text(day),
        selected: isSelected,
        onSelected: _isEditing
            ? (selected) {
                setState(() {
                  if (selected) {
                    _selectedDays.add(day);
                  } else {
                    _selectedDays.remove(day);
                  }
                });
              }
            : null,
        selectedColor: AppColors.primary.withOpacity(0.2),
        checkmarkColor: AppColors.primary,
        backgroundColor: Colors.grey[100],
        disabledColor: isSelected
            ? AppColors.primary.withOpacity(0.1)
            : Colors.grey[100],
        labelStyle: TextStyle(
          color: isSelected ? AppColors.primary : Colors.grey[700],
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      );
    }).toList();
  }

  Widget _buildProgressIndicator() {
    final weeksCompleted = _calculateWeeksCompleted();
    final totalWeeks = _planData!['duration_weeks'] ?? 8;
    final progress = weeksCompleted / totalWeeks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Week $weeksCompleted of $totalWeeks',
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${(progress * 100).toInt()}%',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: AppColors.primary.withOpacity(0.2),
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          minHeight: 8,
        ),
      ],
    );
  }

  IconData _getPersonalityIcon() {
    final personality = CoachingPersonality.allPersonalities.firstWhere(
      (p) => p.id == _selectedPersonality,
      orElse: () => CoachingPersonality.supportiveFriend,
    );
    return personality.icon;
  }

  int _calculateWeeksCompleted() {
    if (_planData?['start_date'] == null) return 1;

    try {
      final startDate = DateTime.parse(_planData!['start_date']);
      final daysSinceStart = DateTime.now().difference(startDate).inDays;
      return (daysSinceStart / 7).floor() + 1;
    } catch (e) {
      return 1;
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'Recently';

    try {
      final date = DateTime.parse(dateString);
      final daysSince = DateTime.now().difference(date).inDays;

      if (daysSince == 0) return 'Today';
      if (daysSince == 1) return 'Yesterday';
      if (daysSince < 7) return '$daysSince days ago';

      final weeksSince = (daysSince / 7).floor();
      if (weeksSince == 1) return '1 week ago';
      if (weeksSince < 4) return '$weeksSince weeks ago';

      return '${date.month}/${date.day}/${date.year}';
    } catch (e) {
      return 'Recently';
    }
  }
}