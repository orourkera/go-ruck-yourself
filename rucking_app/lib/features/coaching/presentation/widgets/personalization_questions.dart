import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rucking_app/features/coaching/domain/models/plan_personalization.dart';
import 'package:rucking_app/features/coaching/domain/models/coaching_plan_type.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

class PersonalizationQuestions extends StatefulWidget {
  final void Function(PlanPersonalization) onPersonalizationComplete;
  final CoachingPlanType? planType;

  const PersonalizationQuestions({
    super.key,
    required this.onPersonalizationComplete,
    this.planType,
  });

  @override
  State<PersonalizationQuestions> createState() =>
      _PersonalizationQuestionsState();
}

class _PersonalizationQuestionsState extends State<PersonalizationQuestions> {
  final PageController _pageController = PageController();
  int _currentQuestionIndex = 0;

  PlanPersonalization _personalization = const PlanPersonalization();

  List<String> get _questions {
    final baseQuestions = [
      "What's your why for this goal?",
      "In 8–12 weeks, what would make you say this was a win?",
      "How many days/week can you realistically train?",
      "Which days usually work best?",
      "What's your biggest challenge to hitting this goal?",
    ];

    // Add streak question for Daily Discipline plan
    if (widget.planType?.id == 'daily-discipline') {
      baseQuestions.add("How many days in a row are you aiming for?");
    }

    baseQuestions.add("On tough days, what's your minimum viable session?");

    return baseQuestions;
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
          FocusScope.of(context).requestFocus(FocusNode());
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
    final pages = [
      _buildWhyQuestion(),
      _buildSuccessQuestion(),
      _buildTrainingDaysQuestion(),
      _buildPreferredDaysQuestion(),
      _buildChallengesQuestion(),
    ];

    // Add streak question for Daily Discipline plan
    if (widget.planType?.id == 'daily-discipline') {
      pages.add(_buildStreakQuestion());
    }

    pages.add(_buildMinimumSessionQuestion());

    return pages;
  }

  bool _canProceed() {
    final isDailyDiscipline = widget.planType?.id == 'daily-discipline';
    final streakQuestionIndex = isDailyDiscipline ? 5 : -1;
    final minSessionIndex = isDailyDiscipline ? 6 : 5;

    switch (_currentQuestionIndex) {
      case 0:
        return _personalization.why != null && _personalization.why!.isNotEmpty;
      case 1:
        return _personalization.successDefinition != null &&
            _personalization.successDefinition!.isNotEmpty;
      case 2:
        return _personalization.trainingDaysPerWeek != null;
      case 3:
        return _personalization.preferredDays != null &&
            _personalization.preferredDays!.isNotEmpty;
      case 4:
        return _personalization.challenges != null &&
            _personalization.challenges!.isNotEmpty;
      case 5:
        if (isDailyDiscipline) {
          // This is the streak question - require either daily streak or flexible frequency
          return (_personalization.streakTargetDays != null) ||
              (_personalization.streakTargetRucks != null &&
                  _personalization.streakTimeframeDays != null);
        } else {
          // This is the minimum session question - always allow proceed
          return true;
        }
      case 6:
        // This is the minimum session question for daily discipline - always allow proceed
        return true;
      default:
        return false;
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
          title: Text('Personalize Your Plan (${_currentQuestionIndex + 1}/6)'),
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
    return _buildQuestionCard(
      question: _questions[0],
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
    return _buildQuestionCard(
      question: _questions[1],
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
              hintText: 'What would success look like?',
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
      question: _questions[2],
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
    return _buildQuestionCard(
      question: _questions[3],
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select your preferred training days (you can choose multiple):',
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
      question: _questions[4],
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

  Widget _buildMinimumSessionQuestion() {
    final questionIndex = widget.planType?.id == 'daily-discipline' ? 6 : 5;
    return _buildQuestionCard(
      question: _questions[questionIndex],
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
