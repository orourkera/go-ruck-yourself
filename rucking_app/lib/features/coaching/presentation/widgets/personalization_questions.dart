import 'package:flutter/material.dart';
import 'package:rucking_app/features/coaching/domain/models/plan_personalization.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

class PersonalizationQuestions extends StatefulWidget {
  final void Function(PlanPersonalization) onPersonalizationComplete;

  const PersonalizationQuestions({
    super.key,
    required this.onPersonalizationComplete,
  });

  @override
  State<PersonalizationQuestions> createState() => _PersonalizationQuestionsState();
}

class _PersonalizationQuestionsState extends State<PersonalizationQuestions> {
  final PageController _pageController = PageController();
  int _currentQuestionIndex = 0;
  
  PlanPersonalization _personalization = const PlanPersonalization();

  final List<String> _questions = [
    "What's your why for this goal?",
    "In 8–12 weeks, what would make you say this was a win?",
    "How many days/week can you realistically train?",
    "Which days usually work best?",
    "What's your biggest challenge to hitting this goal?",
    "On tough days, what's your minimum viable session?",
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextQuestion() {
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

  bool _canProceed() {
    switch (_currentQuestionIndex) {
      case 0:
        return _personalization.why != null && _personalization.why!.isNotEmpty;
      case 1:
        return _personalization.successDefinition != null && _personalization.successDefinition!.isNotEmpty;
      case 2:
        return _personalization.trainingDaysPerWeek != null;
      case 3:
        return _personalization.preferredDays != null && _personalization.preferredDays!.isNotEmpty;
      case 4:
        return _personalization.challenges != null && _personalization.challenges!.isNotEmpty;
      case 5:
        // Always allow proceed on last question - we'll use defaults if needed
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
        FocusScope.of(context).unfocus();
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
              children: [
                _buildWhyQuestion(),
                _buildSuccessQuestion(),
                _buildTrainingDaysQuestion(),
                _buildPreferredDaysQuestion(),
                _buildChallengesQuestion(),
                _buildMinimumSessionQuestion(),
              ],
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
                  _currentQuestionIndex == _questions.length - 1 ? 'Complete' : 'Next',
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

  Widget _buildQuestionCard({required String question, required Widget content}) {
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
            const SizedBox(height: 100), // Add extra space at bottom for keyboard
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
          // Suggested chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: PlanPersonalization.whySuggestions.map((suggestion) {
              final isSelected = _personalization.why == suggestion;
              return FilterChip(
                label: Text(suggestion),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _personalization = _personalization.copyWith(
                      why: selected ? suggestion : null,
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
                _personalization = _personalization.copyWith(
                  why: value.isNotEmpty ? value : null,
                );
              });
            },
            onTap: () {
              // Clear chip selection when typing custom text
              if (PlanPersonalization.whySuggestions.contains(_personalization.why)) {
                setState(() {
                  _personalization = _personalization.copyWith(why: '');
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
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [2, 3, 4, 5, 6, 7].map((days) {
              final isSelected = _personalization.trainingDaysPerWeek == days;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _personalization = _personalization.copyWith(
                      trainingDaysPerWeek: days,
                    );
                  });
                },
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : Colors.grey.shade300,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      days.toString(),
                      style: AppTextStyles.titleLarge.copyWith(
                        color: isSelected ? Colors.white : Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
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
              final isSelected = _personalization.preferredDays?.contains(day) ?? false;
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
              final isSelected = _personalization.challenges?.contains(challenge) ?? false;
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
                      newChallenges = currentChallenges.where((c) => c != challenge).toList();
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

  Widget _buildMinimumSessionQuestion() {
    return _buildQuestionCard(
      question: _questions[5],
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