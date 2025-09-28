import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/coaching/domain/models/plan_personalization.dart';
import 'package:rucking_app/features/coaching/domain/models/coaching_plan_type.dart';
import 'package:rucking_app/features/coaching/domain/models/plan_custom_questions.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';

class PersonalizationQuestions extends StatefulWidget {
  final void Function(PlanPersonalization) onPersonalizationComplete;
  final CoachingPlanType? planType;
  final Map<String, dynamic>? userInsights;

  const PersonalizationQuestions({
    super.key,
    required this.onPersonalizationComplete,
    this.planType,
    this.userInsights,
  });

  @override
  State<PersonalizationQuestions> createState() =>
      _PersonalizationQuestionsState();
}

class _PersonalizationQuestionsState extends State<PersonalizationQuestions> {
  final PageController _pageController = PageController();
  int _currentQuestionIndex = 0;

  // Provide sensible defaults so controls like sliders start in an enabled state
  PlanPersonalization _personalization =
      const PlanPersonalization(trainingDaysPerWeek: 4);
  bool _useMetric = true; // User's metric preference

  @override
  void initState() {
    super.initState();
    _loadMetricPreference();
    _initializeWithInsights();
  }

  void _initializeWithInsights() {
    if (widget.userInsights != null) {
      // Use user insights to set smart defaults
      final insights = widget.userInsights!;

      // Set training days per week based on weekly average
      if (insights['weekly_avg'] != null) {
        final weeklyAvg = insights['weekly_avg'] as double;
        _personalization = _personalization.copyWith(
          trainingDaysPerWeek: weeklyAvg.round().clamp(1, 7),
        );
      }

      // Pre-populate custom responses based on user data
      Map<String, dynamic> customResponses = {};

      // For load capacity plan - set current max load
      if (widget.planType?.id == 'load-capacity' &&
          insights['ruck_weight'] != null) {
        customResponses['current_max_load'] = insights['ruck_weight'];
      }

      // For get faster plan - set current pace
      if (widget.planType?.id == 'get-faster' && insights['avg_pace'] != null) {
        customResponses['current_pace'] = insights['avg_pace'];
      }

      // For event prep - hardcode 12 miles (19.3 km) since this is the specific challenge
      if (widget.planType?.id == 'event-prep') {
        customResponses['event_distance'] = 19.3; // legacy key
        customResponses['eventDistanceKm'] = 19.3;
      }

      if (customResponses.isNotEmpty) {
        _personalization = _personalization.copyWith(
          customResponses: customResponses,
        );
      }

      // Pre-populate equipment data from history if available
      double? equipmentWeight;

      if (insights['ruck_weight'] != null && insights['ruck_weight'] > 0) {
        equipmentWeight = (insights['ruck_weight'] as num).toDouble();
      } else if (insights['average_ruck_weight'] != null &&
          insights['average_ruck_weight'] > 0) {
        equipmentWeight = (insights['average_ruck_weight'] as num).toDouble();
      }

      if (equipmentWeight != null) {
        _personalization = _personalization.copyWith(
          equipmentType:
              'rucksack', // Default to rucksack if they have weight history
          equipmentWeight: equipmentWeight,
        );
      }
    }
  }

  Future<void> _loadMetricPreference() async {
    bool? preferMetric;

    if (mounted) {
      final authState = context.read<AuthBloc>().state;
      if (authState is Authenticated) {
        preferMetric = authState.user.preferMetric;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final storedPreference =
        prefs.getBool('prefer_metric') ?? prefs.getBool('preferMetric');

    final useMetric = storedPreference ?? preferMetric ?? true;

    if (mounted) {
      setState(() {
        _useMetric = useMetric;
      });
    }
  }

  bool get _hasEquipmentHistory {
    // Check if user has ruck weight history
    final insights = widget.userInsights;
    if (insights == null) return false;

    // Check for any indication of weight usage
    final ruckWeight = insights['ruck_weight'];
    final averageRuckWeight = insights['average_ruck_weight'];

    return (ruckWeight != null && ruckWeight > 0) ||
        (averageRuckWeight != null && averageRuckWeight > 0);
  }

  List<String> get _questions {
    final questions = <String>[];
    final planId = widget.planType?.id;

    switch (planId) {
      case 'daily-discipline':
        // Custom questions first for streak
        final customQuestions =
            PlanCustomQuestions.getQuestionsForPlan(planId!);
        for (final question in customQuestions) {
          questions.add(question.prompt);
        }
        // Then relevant base questions (no training days/preferred days/equipment)
        questions.addAll([
          "Why is this streak important to you?",
          "In 8–12 weeks, what would make you say this was a win?",
          "What's your biggest challenge to hitting this goal?",
        ]);
        break;

      case 'fat-loss':
        // Weight loss target first
        final customQuestions =
            PlanCustomQuestions.getQuestionsForPlan(planId!);
        if (customQuestions.isNotEmpty) {
          questions.add(customQuestions[0].prompt); // Weight loss target
        }
        // Base questions
        questions.addAll([
          "What's your why for this goal?",
          "In 8–12 weeks, what would make you say this was a win?",
          "How many days/week can you realistically train?",
          "Which days usually work best?",
          "What's your biggest challenge to hitting this goal?",
        ]);
        // Only ask about equipment if user doesn't have weight history
        if (!_hasEquipmentHistory) {
          questions.add("What equipment do you have?");
        }
        // Remaining custom questions
        for (int i = 1; i < customQuestions.length; i++) {
          questions.add(customQuestions[i].prompt);
        }
        questions.add("On tough days, what's your minimum viable session?");
        break;

      case 'load-capacity':
        // Target load first
        final customQuestions =
            PlanCustomQuestions.getQuestionsForPlan(planId!);
        if (customQuestions.isNotEmpty) {
          questions.add(customQuestions[0].prompt); // Target load
        }
        // Base questions
        questions.addAll([
          "What's your why for this goal?",
          "In 8–12 weeks, what would make you say this was a win?",
          "How many days/week can you realistically train?",
          "Which days usually work best?",
          "What's your biggest challenge to hitting this goal?",
        ]);
        // Only ask about equipment if user doesn't have weight history
        if (!_hasEquipmentHistory) {
          questions.add("What equipment do you have?");
        }
        // Remaining custom questions
        for (int i = 1; i < customQuestions.length; i++) {
          questions.add(customQuestions[i].prompt);
        }
        questions.add("On tough days, what's your minimum viable session?");
        break;

      case 'event-prep':
        // Event date first
        final customQuestions =
            PlanCustomQuestions.getQuestionsForPlan(planId!);
        if (customQuestions.isNotEmpty) {
          questions.add(customQuestions[0].prompt); // Event date
        }
        // Base questions (removed success definition since we have specific event date)
        questions.addAll([
          "What's your why for this goal?",
          "How many days/week can you realistically train?",
          "Which days usually work best?",
          "What's your biggest challenge to hitting this goal?",
        ]);
        // Only ask about equipment if user doesn't have weight history
        if (!_hasEquipmentHistory) {
          questions.add("What equipment do you have?");
        }
        // Remaining custom questions
        for (int i = 1; i < customQuestions.length; i++) {
          questions.add(customQuestions[i].prompt);
        }
        questions.add("On tough days, what's your minimum viable session?");
        break;

      default:
        // Standard order for other plans
        questions.addAll([
          "What's your why for this goal?",
          "In 8–12 weeks, what would make you say this was a win?",
          "How many days/week can you realistically train?",
          "Which days usually work best?",
          "What's your biggest challenge to hitting this goal?",
        ]);
        // Only ask about equipment if user doesn't have weight history
        if (!_hasEquipmentHistory) {
          questions.add("What equipment do you have?");
        }
        // Add custom questions
        if (widget.planType != null) {
          final customQuestions =
              PlanCustomQuestions.getQuestionsForPlan(widget.planType!.id);
          for (final question in customQuestions) {
            questions.add(question.prompt);
          }
        }
        questions.add("On tough days, what's your minimum viable session?");
    }

    return questions;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    try {
      // Multiple aggressive approaches to dismiss keyboard
      SystemChannels.textInput.invokeMethod('TextInput.hide');
      FocusScope.of(context).unfocus();
      FocusManager.instance.primaryFocus?.unfocus();

      // Additional fallback methods
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          FocusScope.of(context).unfocus();
        }
      });

      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          SystemChannels.textInput.invokeMethod('TextInput.hide');
        }
      });
    } catch (e) {
      // Fallback if any method fails
      try {
        FocusScope.of(context).unfocus();
      } catch (_) {}
    }
  }

  void _nextQuestion() {
    // Dismiss keyboard before navigation
    _dismissKeyboard();

    if (_currentQuestionIndex < _questions.length - 1) {
      setState(() {
        _currentQuestionIndex++;
      });
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // All questions completed - set defaults for missing values
      final completedPersonalization = _personalization.copyWith(
        minimumSessionMinutes: _personalization.minimumSessionMinutes ?? 15,
        unloadedOk: _personalization.unloadedOk ?? false,
        preferMetric: _useMetric,
      );
      widget.onPersonalizationComplete(completedPersonalization);
    }
  }

  void _previousQuestion() {
    // Dismiss keyboard before navigation
    _dismissKeyboard();

    if (_currentQuestionIndex > 0) {
      setState(() {
        _currentQuestionIndex--;
      });
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  List<Widget> _buildQuestionPages() {
    final pages = <Widget>[];
    final planId = widget.planType?.id;

    switch (planId) {
      case 'daily-discipline':
        // Custom questions first
        final customQuestionMaps =
            PlanCustomQuestions.getQuestionMapsForPlan(planId!);
        for (final questionConfig in customQuestionMaps) {
          pages.add(_buildCustomQuestion(questionConfig));
        }
        // Then relevant base questions (no preferred days for streak)
        pages.addAll([
          _buildWhyQuestion(),
          _buildSuccessQuestion(),
          _buildChallengesQuestion(),
        ]);
        break;

      case 'fat-loss':
        // Weight loss target first
        final customQuestionMaps =
            PlanCustomQuestions.getQuestionMapsForPlan(planId!);
        if (customQuestionMaps.isNotEmpty) {
          pages.add(_buildCustomQuestion(customQuestionMaps[0]));
        }
        // Base questions
        pages.addAll([
          _buildWhyQuestion(),
          _buildSuccessQuestion(),
          _buildTrainingDaysQuestion(),
          _buildPreferredDaysQuestion(),
          _buildChallengesQuestion(),
        ]);
        // Only ask about equipment if user doesn't have weight history
        if (!_hasEquipmentHistory) {
          pages.add(_buildEquipmentQuestion());
        }
        // Then remaining custom questions
        for (int i = 1; i < customQuestionMaps.length; i++) {
          pages.add(_buildCustomQuestion(customQuestionMaps[i]));
        }
        pages.add(_buildMinimumSessionQuestion());
        break;

      case 'load-capacity':
        // Target load first
        final customQuestionMaps =
            PlanCustomQuestions.getQuestionMapsForPlan(planId!);
        if (customQuestionMaps.isNotEmpty) {
          pages.add(_buildCustomQuestion(customQuestionMaps[0]));
        }
        // Base questions
        pages.addAll([
          _buildWhyQuestion(),
          _buildSuccessQuestion(),
          _buildTrainingDaysQuestion(),
          _buildPreferredDaysQuestion(),
          _buildChallengesQuestion(),
        ]);
        // Only ask about equipment if user doesn't have weight history
        if (!_hasEquipmentHistory) {
          pages.add(_buildEquipmentQuestion());
        }
        // Then remaining custom questions
        for (int i = 1; i < customQuestionMaps.length; i++) {
          pages.add(_buildCustomQuestion(customQuestionMaps[i]));
        }
        pages.add(_buildMinimumSessionQuestion());
        break;

      case 'event-prep':
        // First custom question comes first (event date)
        final customQuestionMaps =
            PlanCustomQuestions.getQuestionMapsForPlan(planId!);
        if (customQuestionMaps.isNotEmpty) {
          pages.add(_buildCustomQuestion(customQuestionMaps[0]));
        }
        // Then base questions (removed success definition since we have specific event date)
        pages.addAll([
          _buildWhyQuestion(),
          _buildTrainingDaysQuestion(),
          _buildPreferredDaysQuestion(),
          _buildChallengesQuestion(),
        ]);
        // Only ask about equipment if user doesn't have weight history
        if (!_hasEquipmentHistory) {
          pages.add(_buildEquipmentQuestion());
        }
        // Then remaining custom questions
        for (int i = 1; i < customQuestionMaps.length; i++) {
          pages.add(_buildCustomQuestion(customQuestionMaps[i]));
        }
        pages.add(_buildMinimumSessionQuestion());
        break;

      default:
        // Standard order for other plans
        pages.addAll([
          _buildWhyQuestion(),
          _buildSuccessQuestion(),
          _buildTrainingDaysQuestion(),
          _buildPreferredDaysQuestion(),
          _buildChallengesQuestion(),
          _buildEquipmentQuestion(),
        ]);
        // Add custom questions after base questions
        if (widget.planType != null) {
          final customQuestionMaps =
              PlanCustomQuestions.getQuestionMapsForPlan(widget.planType!.id);
          for (final questionConfig in customQuestionMaps) {
            pages.add(_buildCustomQuestion(questionConfig));
          }
        }
        pages.add(_buildMinimumSessionQuestion());
    }

    return pages;
  }

  bool _canProceed() {
    final planId = widget.planType?.id;

    switch (planId) {
      case 'daily-discipline':
        // Custom questions first (0-2), then base questions (3-5)
        switch (_currentQuestionIndex) {
          case 0: // How many days to ruck?
            return _personalization.customResponses != null &&
                _personalization.customResponses!['streak_days'] != null;
          case 1: // Rest days (optional)
            return true;
          case 2: // Minimum session length
            return true;
          case 3: // Why question
            return _personalization.why != null &&
                _personalization.why!.isNotEmpty;
          case 4: // Success definition (optional)
            return true;
          case 5: // Challenges
            return _personalization.challenges != null &&
                _personalization.challenges!.isNotEmpty;
          default:
            return false;
        }

      case 'fat-loss':
        // Weight loss target first, then base, then other custom
        switch (_currentQuestionIndex) {
          case 0: // Weight loss target
            return _personalization.customResponses != null &&
                _personalization.customResponses!['weight_loss_target'] != null;
          case 1: // Why
            return _personalization.why != null &&
                _personalization.why!.isNotEmpty;
          case 2: // Success (optional)
            return true;
          case 3: // Training days
            return _personalization.trainingDaysPerWeek != null;
          case 4: // Preferred days
            return _personalization.preferredDays != null &&
                _personalization.preferredDays!.isNotEmpty;
          case 5: // Challenges
            return _personalization.challenges != null &&
                _personalization.challenges!.isNotEmpty;
          case 6: // Equipment
            return true;
          case 7: // Current activity level
            return _personalization.customResponses != null &&
                _personalization.customResponses!['current_activity'] != null;
          case 8: // Complementary activities (optional)
            return true;
          case 9: // Minimum session
            return _personalization.minimumSessionMinutes != null;
          default:
            return true;
        }

      case 'load-capacity':
        // Target load first, then base, then other custom
        switch (_currentQuestionIndex) {
          case 0: // Target load
            return _personalization.customResponses != null &&
                _personalization.customResponses!['target_load'] != null;
          case 1: // Why
            return _personalization.why != null &&
                _personalization.why!.isNotEmpty;
          case 2: // Success (optional)
            return true;
          case 3: // Training days
            return _personalization.trainingDaysPerWeek != null;
          case 4: // Preferred days
            return _personalization.preferredDays != null &&
                _personalization.preferredDays!.isNotEmpty;
          case 5: // Challenges
            return _personalization.challenges != null &&
                _personalization.challenges!.isNotEmpty;
          case 6: // Equipment
            return true;
          case 7: // Current max load
            return _personalization.customResponses != null &&
                _personalization.customResponses!['current_max_load'] != null;
          case 8: // Injury concerns (optional)
            return true;
          case 9: // Minimum session
            return _personalization.minimumSessionMinutes != null;
          default:
            return true;
        }

      case 'event-prep':
        final includesEquipmentQuestion = !_hasEquipmentHistory;
        switch (_currentQuestionIndex) {
          case 0: // Event date
            return _personalization.customResponses != null &&
                (_personalization.customResponses!['event_date'] != null ||
                    _personalization.customResponses!['eventDate'] != null);
          case 1: // Why
            return _personalization.why != null &&
                _personalization.why!.isNotEmpty;
          case 2: // Training days
            return _personalization.trainingDaysPerWeek != null;
          case 3: // Preferred days
            // Optional for event prep; treat empty as flexible schedule
            return true;
          case 4: // Challenges
            return _personalization.challenges != null &&
                _personalization.challenges!.isNotEmpty;
          case 5:
            if (includesEquipmentQuestion) {
              // Equipment question is informational; always allow
              return true;
            }
            // Without equipment step, this index is event load
            return _personalization.customResponses != null &&
                (_personalization.customResponses!['eventLoadKg'] != null ||
                    _personalization.customResponses!['event_load'] != null);
          case 6:
            if (includesEquipmentQuestion) {
              // Event load when equipment question present
              return _personalization.customResponses != null &&
                  (_personalization.customResponses!['eventLoadKg'] != null ||
                      _personalization.customResponses!['event_load'] != null);
            }
            // Time goal (optional) when equipment question skipped
            return true;
          case 7:
            if (includesEquipmentQuestion) {
              // Time goal (optional) when equipment question present
              return true;
            }
            // Minimum session when equipment question skipped
            return _personalization.minimumSessionMinutes != null;
          case 8:
            if (includesEquipmentQuestion) {
              // Minimum session when equipment question present
              return _personalization.minimumSessionMinutes != null;
            }
            // This case shouldn't be reached when equipment is skipped
            return true;
          case 9:
            // Minimum session when equipment question present
            return _personalization.minimumSessionMinutes != null;
          default:
            return true;
        }

      default:
        // Standard order for other plans
        switch (_currentQuestionIndex) {
          case 0: // Why
            return _personalization.why != null &&
                _personalization.why!.isNotEmpty;
          case 1: // Success (optional)
            return true;
          case 2: // Training days
            return _personalization.trainingDaysPerWeek != null;
          case 3: // Preferred days
            return _personalization.preferredDays != null &&
                _personalization.preferredDays!.isNotEmpty;
          case 4: // Challenges
            return _personalization.challenges != null &&
                _personalization.challenges!.isNotEmpty;
          case 5: // Equipment
            return true;
          default:
            // Custom questions and minimum session - allow proceed
            return true;
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Dismiss keyboard when tapping outside
        _dismissKeyboard();
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundLight,
        appBar: AppBar(
          title: Text(
              'Personalize Your Plan (${_currentQuestionIndex + 1}/${_questions.length})'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: _currentQuestionIndex > 0
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _previousQuestion,
                )
              : null,
        ),
        body: Column(
          children: [
            // Progress indicator
            Container(
              padding: const EdgeInsets.all(16),
              child: LinearProgressIndicator(
                value: (_currentQuestionIndex + 1) / _questions.length,
                backgroundColor: AppColors.primary.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),

            // Questions
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: _buildQuestionPages(),
              ),
            ),

            // Next/Continue button
            Container(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canProceed() ? _nextQuestion : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _currentQuestionIndex == _questions.length - 1
                        ? 'Complete'
                        : 'Next',
                    style: AppTextStyles.titleMedium,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionCard(
      {required String question, required Widget content}) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              question,
              style: AppTextStyles.headlineMedium.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            content,
            const SizedBox(
                height: 100), // Add extra space at bottom for keyboard
          ],
        ),
      ),
    );
  }

  Widget _buildWhyQuestion() {
    // Get the correct question text based on current index
    return _buildQuestionCard(
      question: _questions[_currentQuestionIndex],
      content: Column(
        children: [
          // Suggested chips (multi-select)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: PlanPersonalization.whySuggestions.map((suggestion) {
              final isSelected =
                  _personalization.why?.contains(suggestion) ?? false;
              return FilterChip(
                label: Text(suggestion),
                selected: isSelected,
                onSelected: (selected) {
                  _dismissKeyboard();
                  setState(() {
                    final currentWhy = _personalization.why ?? [];
                    List<String> newWhy;

                    if (selected) {
                      newWhy = [...currentWhy, suggestion];
                    } else {
                      newWhy =
                          currentWhy.where((w) => w != suggestion).toList();
                    }

                    _personalization = _personalization.copyWith(
                      why: newWhy,
                    );
                  });
                },
                selectedColor: AppColors.primary.withOpacity(0.3),
                checkmarkColor: AppColors.primary,
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Custom text input
          TextField(
            autofocus: false,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Or describe your own reason...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primary),
              ),
            ),
            onChanged: (value) {
              setState(() {
                if (value.isNotEmpty) {
                  // Clear chip selections and set custom text
                  _personalization = _personalization.copyWith(
                    why: [value],
                  );
                } else {
                  _personalization = _personalization.copyWith(
                    why: [],
                  );
                }
              });
            },
            onTap: () {
              // Clear chip selection when typing custom text
              final currentWhy = _personalization.why ?? [];
              final hasChipSelections = currentWhy
                  .any((w) => PlanPersonalization.whySuggestions.contains(w));
              if (hasChipSelections) {
                setState(() {
                  _personalization = _personalization.copyWith(why: []);
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessQuestion() {
    // Dynamically get question text based on whether it's Daily Discipline and the streak duration
    String questionText = _questions[_currentQuestionIndex];

    // For Daily Discipline, customize based on streak duration
    if (widget.planType?.id == 'daily-discipline' &&
        _personalization.customResponses != null &&
        _personalization.customResponses!['streak_days'] != null) {
      final streakDays = _personalization.customResponses!['streak_days'];
      questionText =
          "After $streakDays days, what would make you say this was a win? (Optional)";
    }

    return _buildQuestionCard(
      question: questionText,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Be specific! Examples: "−4 kg," "12 miles under 3:00," "no knee pain on stairs"',
            style: AppTextStyles.bodyMedium.copyWith(
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            autofocus: false,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: widget.planType?.id == 'daily-discipline'
                  ? 'Optional - What would success look like?'
                  : 'What would success look like?',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primary),
              ),
            ),
            maxLines: 2,
            onChanged: (value) {
              setState(() {
                _personalization = _personalization.copyWith(
                  successDefinition: value.isNotEmpty ? value : null,
                );
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTrainingDaysQuestion() {
    return _buildQuestionCard(
      question: _questions[_currentQuestionIndex],
      content: Column(
        children: [
          Text(
            'Be realistic - you can always adjust later!',
            style: AppTextStyles.bodyMedium.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          Column(
            children: [
              // Display current selection
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Text(
                  '${_personalization.trainingDaysPerWeek ?? 4} days per week',
                  style: AppTextStyles.titleLarge.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Slider
              Slider(
                value: (_personalization.trainingDaysPerWeek ?? 4).toDouble(),
                min: 2,
                max: 7,
                divisions: 5, // 2,3,4,5,6,7 = 5 divisions
                activeColor: AppColors.primary,
                inactiveColor: Colors.grey.shade300,
                thumbColor: AppColors.primary,
                onChanged: (value) {
                  setState(() {
                    _personalization = _personalization.copyWith(
                      trainingDaysPerWeek: value.round(),
                    );
                  });
                },
              ),

              // Labels under slider
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('2',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: Colors.grey[600])),
                    Text('3',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: Colors.grey[600])),
                    Text('4',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: Colors.grey[600])),
                    Text('5',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: Colors.grey[600])),
                    Text('6',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: Colors.grey[600])),
                    Text('7',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: Colors.grey[600])),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreferredDaysQuestion() {
    // Get the correct question index and text
    final isDailyDiscipline = widget.planType?.id == 'daily-discipline';
    final questionIndex = isDailyDiscipline ? 5 : 3;
    String questionText = _questions[questionIndex];

    // For Daily Discipline, customize based on streak duration
    if (isDailyDiscipline &&
        _personalization.customResponses != null &&
        _personalization.customResponses!['streak_days'] != null) {
      final streakDays = _personalization.customResponses!['streak_days'];
      questionText =
          "Which days usually work best for your $streakDays-day journey? (Optional)";
    }

    return _buildQuestionCard(
      question: questionText,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isDailyDiscipline
                ? 'Select any days that work particularly well for you (skip if flexible):'
                : 'Select your preferred training days (you can choose multiple):',
            style: AppTextStyles.bodyMedium.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: PlanPersonalization.weekdays.map((day) {
              final isSelected =
                  _personalization.preferredDays?.contains(day) ?? false;
              return FilterChip(
                label: Text(day),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    final currentDays = _personalization.preferredDays ?? [];
                    List<String> newDays;

                    if (selected) {
                      newDays = [...currentDays, day];
                    } else {
                      newDays = currentDays.where((d) => d != day).toList();
                    }

                    _personalization = _personalization.copyWith(
                      preferredDays: newDays,
                    );
                  });
                },
                selectedColor: AppColors.primary.withOpacity(0.3),
                checkmarkColor: AppColors.primary,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildChallengesQuestion() {
    return _buildQuestionCard(
      question: _questions[_currentQuestionIndex],
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select all that apply - this helps me create better backup plans:',
            style: AppTextStyles.bodyMedium.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: PlanPersonalization.challengeSuggestions.map((challenge) {
              final isSelected =
                  _personalization.challenges?.contains(challenge) ?? false;
              return FilterChip(
                label: Text(challenge),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    final currentChallenges = _personalization.challenges ?? [];
                    List<String> newChallenges;

                    if (selected) {
                      newChallenges = [...currentChallenges, challenge];
                    } else {
                      newChallenges = currentChallenges
                          .where((c) => c != challenge)
                          .toList();
                    }

                    _personalization = _personalization.copyWith(
                      challenges: newChallenges,
                    );
                  });
                },
                selectedColor: AppColors.primary.withOpacity(0.3),
                checkmarkColor: AppColors.primary,
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            autofocus: false,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Other challenges?',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primary),
              ),
            ),
            onChanged: (value) {
              if (value.isNotEmpty) {
                setState(() {
                  final currentChallenges = _personalization.challenges ?? [];
                  _personalization = _personalization.copyWith(
                    challenges: [...currentChallenges, value],
                  );
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStreakQuestion() {
    return _buildQuestionCard(
      question: "How many days in a row are you aiming for?",
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose your discipline goal:',
            style: AppTextStyles.bodyMedium.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),

          // Daily streak option
          Text(
            'Daily streak (every day):',
            style: AppTextStyles.titleSmall.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [7, 14, 21, 30].map((days) {
              final isSelected = _personalization.streakTargetDays == days &&
                  _personalization.streakTargetRucks == null;
              return GestureDetector(
                onTap: () {
                  _dismissKeyboard();
                  setState(() {
                    _personalization = _personalization.copyWith(
                      streakTargetDays: days,
                      streakTargetRucks: null,
                      streakTimeframeDays: null,
                    );
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.white,
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(
                      color:
                          isSelected ? AppColors.primary : Colors.grey.shade300,
                      width: 2,
                    ),
                  ),
                  child: Text(
                    days == 7
                        ? '1 week'
                        : days == 14
                            ? '2 weeks'
                            : days == 21
                                ? '3 weeks'
                                : '1 month',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: isSelected ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // Flexible frequency option
          Text(
            'Or flexible frequency:',
            style: AppTextStyles.titleSmall.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              {'rucks': 15, 'days': 30, 'label': '15 rucks in 30 days'},
              {'rucks': 20, 'days': 30, 'label': '20 rucks in 30 days'},
              {'rucks': 10, 'days': 21, 'label': '10 rucks in 3 weeks'},
              {'rucks': 12, 'days': 21, 'label': '12 rucks in 3 weeks'},
            ].map((option) {
              final isSelected =
                  _personalization.streakTargetRucks == option['rucks'] &&
                      _personalization.streakTimeframeDays == option['days'];
              return GestureDetector(
                onTap: () {
                  _dismissKeyboard();
                  setState(() {
                    _personalization = _personalization.copyWith(
                      streakTargetDays: null,
                      streakTargetRucks: option['rucks'] as int,
                      streakTimeframeDays: option['days'] as int,
                    );
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.white,
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(
                      color:
                          isSelected ? AppColors.primary : Colors.grey.shade300,
                      width: 2,
                    ),
                  ),
                  child: Text(
                    option['label'] as String,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: isSelected ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),

          // Custom inputs
          Row(
            children: [
              Expanded(
                child: TextField(
                  autofocus: false,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'X rucks',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                  ),
                  onChanged: (value) {
                    final rucks = int.tryParse(value);
                    if (rucks != null && rucks > 0) {
                      setState(() {
                        _personalization = _personalization.copyWith(
                          streakTargetDays: null,
                          streakTargetRucks: rucks,
                          streakTimeframeDays:
                              _personalization.streakTimeframeDays ?? 30,
                        );
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              const Text('in'),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  autofocus: false,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Y days',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                  ),
                  onChanged: (value) {
                    final days = int.tryParse(value);
                    if (days != null && days > 0) {
                      setState(() {
                        _personalization = _personalization.copyWith(
                          streakTargetDays: null,
                          streakTargetRucks:
                              _personalization.streakTargetRucks ?? 15,
                          streakTimeframeDays: days,
                        );
                      });
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEquipmentQuestion() {
    return _buildQuestionCard(
      question: _questions[_currentQuestionIndex],
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select your available equipment:',
            style: AppTextStyles.bodyMedium.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 20),

          // Equipment type selection
          RadioListTile<String>(
            title: const Text('I have a rucksack/backpack'),
            value: 'ruck',
            groupValue: _personalization.equipmentType ?? 'none',
            activeColor: AppColors.primary,
            onChanged: (value) {
              setState(() {
                _personalization = _personalization.copyWith(
                  equipmentType: value,
                );
              });
            },
          ),
          RadioListTile<String>(
            title: const Text('I have a weighted vest'),
            value: 'vest',
            groupValue: _personalization.equipmentType ?? 'none',
            activeColor: AppColors.primary,
            onChanged: (value) {
              setState(() {
                _personalization = _personalization.copyWith(
                  equipmentType: value,
                );
              });
            },
          ),
          RadioListTile<String>(
            title: const Text('I have both'),
            value: 'both',
            groupValue: _personalization.equipmentType ?? 'none',
            activeColor: AppColors.primary,
            onChanged: (value) {
              setState(() {
                _personalization = _personalization.copyWith(
                  equipmentType: value,
                );
              });
            },
          ),
          RadioListTile<String>(
            title: const Text('I don\'t have equipment yet'),
            value: 'none',
            groupValue: _personalization.equipmentType ?? 'none',
            activeColor: AppColors.primary,
            onChanged: (value) {
              setState(() {
                _personalization = _personalization.copyWith(
                  equipmentType: value,
                  equipmentWeight: null,
                );
              });
            },
          ),

          // Weight input if they have equipment
          if (_personalization.equipmentType != null &&
              _personalization.equipmentType != 'none') ...[
            const SizedBox(height: 24),
            Text(
              'What\'s the maximum weight you can comfortably carry?',
              style: AppTextStyles.titleSmall.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Weight',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.primary),
                      ),
                    ),
                    onChanged: (value) {
                      final weight = double.tryParse(value);
                      if (weight != null && weight > 0) {
                        setState(() {
                          _personalization = _personalization.copyWith(
                            equipmentWeight: weight,
                          );
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    'lbs',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Common starting weights: 20-30 lbs for beginners, 30-45 lbs for intermediate',
              style: AppTextStyles.bodySmall.copyWith(
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Generic builders for custom questions from database
  Widget _buildCustomQuestion(Map<String, dynamic> questionConfig) {
    final type = questionConfig['type'] as String;

    switch (type) {
      case 'slider':
        return _buildSliderQuestion(questionConfig);
      case 'chips':
        return _buildChipsQuestion(questionConfig);
      case 'number':
        return _buildNumberQuestion(questionConfig);
      case 'text':
        return _buildTextQuestion(questionConfig);
      case 'date':
        return _buildDateQuestion(questionConfig);
      case 'rest_days':
        return _buildRestDaysQuestion(questionConfig);
      default:
        // Fallback to text input
        return _buildTextQuestion(questionConfig);
    }
  }

  Widget _buildSliderQuestion(Map<String, dynamic> config) {
    final id = config['id'] as String;
    final prompt = config['prompt'] as String;
    var min = (config['min'] as num).toDouble();
    var max = (config['max'] as num).toDouble();
    var step = (config['step'] as num?)?.toDouble() ?? 1.0;
    var unit = config['unit'] as String?;
    var defaultValue = (config['default'] as num?)?.toDouble() ?? min;
    final helperText = config['helper_text'] as String?;

    // For weight-related questions, check user's metric preference
    if (id == 'weight_loss_target' && unit == 'kg' && !_useMetric) {
      // Convert kg to lbs (1 kg = 2.20462 lbs)
      min = min * 2.20462;
      max = max * 2.20462;
      step = 1.0; // Use 1 lb steps for cleaner UX
      defaultValue = defaultValue * 2.20462;
      unit = 'lbs';
    }

    // Get current value from customResponses
    var currentValue =
        (_personalization.customResponses?[id] as num?)?.toDouble() ??
            defaultValue;

    // If we have a stored value in kg but showing in lbs, convert it
    if (id == 'weight_loss_target' && !_useMetric && unit == 'lbs') {
      final storedValue = _personalization.customResponses?[id];
      if (storedValue != null) {
        // Stored value is in kg, convert to lbs for display
        currentValue = (storedValue as num).toDouble() * 2.20462;
      }
    }

    return _buildQuestionCard(
      question: prompt,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (helperText != null) ...[
            Text(
              helperText,
              style: AppTextStyles.bodyMedium.copyWith(
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            '${currentValue.round()}${unit != null ? ' $unit' : ''}',
            style: AppTextStyles.titleLarge.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Slider(
            value: currentValue,
            min: min,
            max: max,
            divisions: ((max - min) / step).round(),
            activeColor: AppColors.primary,
            onChanged: (value) {
              setState(() {
                final customResponses = Map<String, dynamic>.from(
                  _personalization.customResponses ?? {},
                );
                // For weight loss target, always store in kg regardless of display unit
                if (id == 'weight_loss_target' && !_useMetric) {
                  // Convert lbs back to kg for storage
                  customResponses[id] = value / 2.20462;
                } else {
                  customResponses[id] = value;
                }
                _personalization = _personalization.copyWith(
                  customResponses: customResponses,
                );
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChipsQuestion(Map<String, dynamic> config) {
    final id = config['id'] as String;
    final prompt = config['prompt'] as String;
    final options = config['options'] as List<dynamic>;
    final multiple = config['multiple'] ?? false;
    final required = config['required'] ?? false;
    final helperText = config['helper_text'] as String?;

    // Get current value(s) from customResponses
    dynamic currentValue = _personalization.customResponses?[id];
    if (currentValue == null && id == 'event_load') {
      currentValue = _personalization.customResponses?['eventLoadKg'];
    }

    // Check if custom is selected for special handling
    final isCustomSelected = currentValue == 'custom' ||
        (currentValue is int &&
            !options.any(
                (opt) => (opt is Map ? opt['value'] : opt) == currentValue));

    return _buildQuestionCard(
      question: prompt,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (helperText != null) ...[
            Text(
              helperText,
              style: AppTextStyles.bodyMedium.copyWith(
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((option) {
              final label = option is Map ? option['label'] : option.toString();
              final value = option is Map ? option['value'] : option;

              bool isSelected;
              if (value == 'custom') {
                isSelected = isCustomSelected;
              } else if (multiple) {
                final selectedList = currentValue as List<dynamic>? ?? [];
                isSelected = selectedList.contains(value);
              } else {
                isSelected = currentValue == value;
              }

              return FilterChip(
                label: Text(label.toString()),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    final customResponses = Map<String, dynamic>.from(
                      _personalization.customResponses ?? {},
                    );

                    if (multiple) {
                      final selectedList = List<dynamic>.from(
                        customResponses[id] as List<dynamic>? ?? [],
                      );
                      if (selected) {
                        selectedList.add(value);
                      } else {
                        selectedList.remove(value);
                      }
                      customResponses[id] = selectedList;
                    } else {
                      customResponses[id] = selected ? value : null;
                    }

                    _personalization = _personalization.copyWith(
                      customResponses: customResponses,
                    );
                  });
                },
                backgroundColor: Colors.white,
                selectedColor: AppColors.primary.withOpacity(0.2),
                checkmarkColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color:
                        isSelected ? AppColors.primary : Colors.grey.shade300,
                  ),
                ),
              );
            }).toList(),
          ),
          // Show custom input field when "Custom" is selected
          if (isCustomSelected && id == 'streak_days') ...[
            const SizedBox(height: 16),
            TextField(
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Enter number of days',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.primary),
                ),
              ),
              onChanged: (value) {
                final days = int.tryParse(value);
                if (days != null && days > 0) {
                  setState(() {
                    final customResponses = Map<String, dynamic>.from(
                      _personalization.customResponses ?? {},
                    );
                    customResponses[id] = days;
                    _personalization = _personalization.copyWith(
                      customResponses: customResponses,
                    );
                  });
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNumberQuestion(Map<String, dynamic> config) {
    final id = config['id'] as String;
    final prompt = config['prompt'] as String;
    final unit = config['unit'] as String?;
    final validation = config['validation'] as Map<String, dynamic>?;
    final helperText = config['helper_text'] as String?;
    final placeholder = config['placeholder'] as String?;

    // Get current value and convert for display if needed
    final currentValue = _personalization.customResponses?[id];
    String initialText = '';
    if (currentValue != null) {
      if (id == 'event_load' && !_useMetric && currentValue is num) {
        // Convert stored kg back to lbs for display
        final lbsValue = currentValue.toDouble() / 0.453592;
        initialText = lbsValue.toStringAsFixed(1);
      } else if (currentValue is num) {
        initialText = currentValue.toString();
      }
    }

    // Adjust prompt, unit, and validation for weight-related questions based on user preference
    String displayPrompt = prompt;
    String? displayUnit = unit;

    if (id == 'event_load') {
      if (_useMetric) {
        displayPrompt = 'Required event load (kg)?';
        displayUnit = 'kg';
      } else {
        displayPrompt = 'Required event load (lbs)?';
        displayUnit = 'lbs';
      }
    }

    return _buildQuestionCard(
      question: displayPrompt,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (helperText != null) ...[
            Text(
              helperText,
              style: AppTextStyles.bodyMedium.copyWith(
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            key: ValueKey('${id}_$_useMetric'),  // Remove initialText from key to prevent rebuilds
            initialValue: initialText,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: false),
            decoration: InputDecoration(
              hintText: placeholder ?? 'Enter value',
              suffixText: displayUnit,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primary),
              ),
            ),
            onChanged: (value) {
              final sanitized = value.replaceAll(',', '.').trim();
              final numValue = double.tryParse(sanitized);
              double? finalStoredValue;

              final customResponses = Map<String, dynamic>.from(
                  _personalization.customResponses ?? {});

              if (numValue == null || numValue <= 0) {
                customResponses.remove(id);
                if (id == 'event_load') {
                  customResponses.remove('eventLoadKg');
                }
              } else {
                double finalValue = numValue;
                if (id == 'event_load' && !_useMetric) {
                  // Convert from lbs to kg for storage
                  finalValue = numValue * 0.453592;
                }
                customResponses[id] = finalValue;
                if (id == 'event_load') {
                  customResponses['eventLoadKg'] = finalValue;
                }
                finalStoredValue = finalValue;
              }

              // Update without setState to preserve focus
              _personalization = _personalization.copyWith(
                customResponses: customResponses,
                equipmentWeight: id == 'event_load' && finalStoredValue != null
                    ? finalStoredValue
                    : _personalization.equipmentWeight,
                equipmentType: id == 'event_load' && finalStoredValue != null
                    ? (_personalization.equipmentType ?? 'rucksack')
                    : _personalization.equipmentType,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTextQuestion(Map<String, dynamic> config) {
    final id = config['id'] as String;
    final prompt = config['prompt'] as String;
    final helperText = config['helper_text'] as String?;
    final placeholder = config['placeholder'] as String?;

    return _buildQuestionCard(
      question: prompt,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (helperText != null) ...[
            Text(
              helperText,
              style: AppTextStyles.bodyMedium.copyWith(
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: placeholder ?? 'Enter your response',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primary),
              ),
            ),
            onChanged: (value) {
              setState(() {
                final customResponses = Map<String, dynamic>.from(
                  _personalization.customResponses ?? {},
                );
                customResponses[id] = value;
                _personalization = _personalization.copyWith(
                  customResponses: customResponses,
                );
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRestDaysQuestion(Map<String, dynamic> config) {
    final id = config['id'] as String;
    final prompt = config['prompt'] as String;
    final helperText = config['helper_text'] as String?;

    // Get current values from customResponses
    final restData =
        _personalization.customResponses?[id] as Map<String, dynamic>? ?? {};
    final restCount = restData['count'] as int? ?? 0;
    final restPeriod = restData['period'] as String? ?? 'per_week';

    return _buildQuestionCard(
      question: prompt,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (helperText != null) ...[
            Text(
              helperText,
              style: AppTextStyles.bodyMedium.copyWith(
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              // Number input
              Expanded(
                child: TextField(
                  keyboardType: TextInputType.number,
                  controller: TextEditingController(
                      text: restCount > 0 ? restCount.toString() : ''),
                  decoration: InputDecoration(
                    hintText: '0',
                    labelText: 'Rest days',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                  ),
                  onChanged: (value) {
                    final count = int.tryParse(value) ?? 0;
                    setState(() {
                      final customResponses = Map<String, dynamic>.from(
                        _personalization.customResponses ?? {},
                      );
                      customResponses[id] = {
                        'count': count,
                        'period': restPeriod,
                      };
                      _personalization = _personalization.copyWith(
                        customResponses: customResponses,
                      );
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              // Period dropdown
              Flexible(
                flex: 1,
                child: DropdownButtonFormField<String>(
                  value: restPeriod,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Period',
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'per_week',
                        child:
                            Text('Per week', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(
                        value: 'per_month',
                        child:
                            Text('Per month', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(
                        value: 'total',
                        child: Text('Total', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        final customResponses = Map<String, dynamic>.from(
                          _personalization.customResponses ?? {},
                        );
                        customResponses[id] = {
                          'count': restCount,
                          'period': value,
                        };
                        _personalization = _personalization.copyWith(
                          customResponses: customResponses,
                        );
                      });
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            restCount == 0
                ? 'No rest days - going for an unbroken streak!'
                : restPeriod == 'per_week'
                    ? '$restCount rest ${restCount == 1 ? "day" : "days"} per week'
                    : restPeriod == 'per_month'
                        ? '$restCount rest ${restCount == 1 ? "day" : "days"} per month'
                        : '$restCount rest ${restCount == 1 ? "day" : "days"} total in the streak',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateQuestion(Map<String, dynamic> config) {
    final id = config['id'] as String;
    final prompt = config['prompt'] as String;
    final helperText = config['helper_text'] as String?;
    final validation = config['validation'] as Map<String, dynamic>?;

    final storedDateString = _personalization.customResponses?[id] ??
        _personalization.customResponses?['eventDate'];
    final DateTime? currentDate = storedDateString != null
        ? DateTime.tryParse(storedDateString as String)
        : null;

    return _buildQuestionCard(
      question: prompt,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (helperText != null) ...[
            Text(
              helperText,
              style: AppTextStyles.bodyMedium.copyWith(
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),
          ],
          InkWell(
            onTap: () async {
              final minDays = validation?['min_days_from_now'] as int? ?? 0;
              final maxDays = validation?['max_days_from_now'] as int? ?? 365;

              final picked = await showDatePicker(
                context: context,
                initialDate:
                    currentDate ?? DateTime.now().add(Duration(days: minDays)),
                firstDate: DateTime.now().add(Duration(days: minDays)),
                lastDate: DateTime.now().add(Duration(days: maxDays)),
              );

              if (picked != null) {
                setState(() {
                  final customResponses = Map<String, dynamic>.from(
                    _personalization.customResponses ?? {},
                  );
                  final iso = picked.toIso8601String();
                  customResponses[id] = iso;
                  if (id == 'event_date') {
                    customResponses['eventDate'] = iso;
                  }
                  _personalization = _personalization.copyWith(
                    customResponses: customResponses,
                  );
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    currentDate != null
                        ? '${currentDate.day}/${currentDate.month}/${currentDate.year}'
                        : 'Select date',
                    style: AppTextStyles.bodyLarge,
                  ),
                  Icon(Icons.calendar_today, color: AppColors.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMinimumSessionQuestion() {
    return _buildQuestionCard(
      question: _questions[_currentQuestionIndex],
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'For streak protection and busy days:',
            style: AppTextStyles.bodyMedium.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Minimum session length: ${_personalization.minimumSessionMinutes ?? 15} minutes',
            style: AppTextStyles.titleMedium,
          ),
          const SizedBox(height: 8),
          Slider(
            value: (_personalization.minimumSessionMinutes ?? 15).toDouble(),
            min: 10,
            max: 30,
            divisions: 4,
            activeColor: AppColors.primary,
            onChanged: (value) {
              _dismissKeyboard();
              setState(() {
                _personalization = _personalization.copyWith(
                  minimumSessionMinutes: value.round(),
                );
              });
            },
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Checkbox(
                value: _personalization.unloadedOk ?? false,
                activeColor: AppColors.primary,
                onChanged: (value) {
                  _dismissKeyboard();
                  setState(() {
                    _personalization = _personalization.copyWith(
                      unloadedOk: value ?? false,
                    );
                  });
                },
              ),
              Expanded(
                child: Text(
                  'Unloaded sessions are okay for minimum days',
                  style: AppTextStyles.bodyMedium,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
