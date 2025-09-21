import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/features/coaching/data/services/coaching_service.dart';
import 'package:rucking_app/features/coaching/domain/models/coaching_personality.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/coaching/presentation/widgets/weekly_schedule_view.dart';

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
  String _selectedPersonality = 'Supportive Friend';

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
          // Extract current values (personality is at root level in API response)
          _selectedPersonality = data['personality'] ??
                                data['coaching_personality'] ??
                                'Supportive Friend';
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

  Future<void> _showDeleteConfirmationDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Coaching Plan'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('Are you sure you want to delete your coaching plan?'),
                SizedBox(height: 8),
                Text(
                  'This action cannot be undone.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.red),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _deleteCoachingPlan();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteCoachingPlan() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _coachingService.deleteCoachingPlan();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Coaching plan deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );

        // Navigate back to profile screen
        Navigator.of(context).pop();
      }
    } catch (e) {
      AppLogger.error('Failed to delete coaching plan: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete plan: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );

        setState(() {
          _isLoading = false;
        });
      }
    }
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
          if (!_isLoading && _planData != null) ...[
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
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'delete') {
                  _showDeleteConfirmationDialog();
                }
              },
              itemBuilder: (BuildContext context) => [
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete Plan', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
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
                              _planData!['template']?['name'] ??
                              _planData!['plan_name'] ??
                              'Custom Plan',
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

          // Weekly Schedule Card
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Weekly Schedule',
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.calendar_month,
                          color: AppColors.primary,
                        ),
                        onPressed: () {
                          // Could open full calendar view
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Full weekly schedule
                  WeeklyScheduleView(
                    planData: _planData!,
                    currentWeek: _planData!['current_week'] ?? 1,
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

        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    final weeksCompleted = _calculateWeeksCompleted();
    final totalWeeks = _planData!['template']?['duration_weeks'] ??
                      _planData!['duration_weeks'] ?? 8;
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
    // Try current_week first (from API), then calculate from start_date
    if (_planData?['current_week'] != null) {
      return _planData!['current_week'];
    }

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