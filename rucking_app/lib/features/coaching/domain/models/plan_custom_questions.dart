import 'package:flutter/material.dart';

// Base class for all question types
abstract class CustomQuestion {
  final String id;
  final String prompt;
  final String? helperText;
  final bool required;

  const CustomQuestion({
    required this.id,
    required this.prompt,
    this.helperText,
    this.required = false,
  });

  // Convert to the map format used by PersonalizationQuestions
  Map<String, dynamic> toMap();
}

class SliderQuestion extends CustomQuestion {
  final double min;
  final double max;
  final double step;
  final String? unit;
  final double? defaultValue;

  const SliderQuestion({
    required String id,
    required String prompt,
    required this.min,
    required this.max,
    this.step = 1.0,
    this.unit,
    this.defaultValue,
    String? helperText,
    bool required = false,
  }) : super(id: id, prompt: prompt, helperText: helperText, required: required);

  @override
  Map<String, dynamic> toMap() => {
    'id': id,
    'prompt': prompt,
    'type': 'slider',
    'min': min,
    'max': max,
    'step': step,
    'unit': unit,
    'default': defaultValue ?? min,
    'helper_text': helperText,
    'required': required,
  };
}

class ChipsQuestion extends CustomQuestion {
  final List<ChipOption> options;
  final bool multiple;

  const ChipsQuestion({
    required String id,
    required String prompt,
    required this.options,
    this.multiple = false,
    String? helperText,
    bool required = false,
  }) : super(id: id, prompt: prompt, helperText: helperText, required: required);

  @override
  Map<String, dynamic> toMap() => {
    'id': id,
    'prompt': prompt,
    'type': 'chips',
    'options': options.map((o) => o.toMap()).toList(),
    'multiple': multiple,
    'helper_text': helperText,
    'required': required,
  };
}

class ChipOption {
  final String label;
  final dynamic value;

  const ChipOption({required this.label, required this.value});

  Map<String, dynamic> toMap() => {'label': label, 'value': value};
}

class NumberQuestion extends CustomQuestion {
  final num? min;
  final num? max;
  final String? unit;
  final String? placeholder;
  final num? defaultValue;

  const NumberQuestion({
    required String id,
    required String prompt,
    this.min,
    this.max,
    this.unit,
    this.placeholder,
    this.defaultValue,
    String? helperText,
    bool required = false,
  }) : super(id: id, prompt: prompt, helperText: helperText, required: required);

  @override
  Map<String, dynamic> toMap() => {
    'id': id,
    'prompt': prompt,
    'type': 'number',
    'unit': unit,
    'placeholder': placeholder,
    'default': defaultValue,
    'validation': {
      if (min != null) 'min': min,
      if (max != null) 'max': max,
    },
    'helper_text': helperText,
    'required': required,
  };
}

class TextQuestion extends CustomQuestion {
  final String? placeholder;

  const TextQuestion({
    required String id,
    required String prompt,
    this.placeholder,
    String? helperText,
    bool required = false,
  }) : super(id: id, prompt: prompt, helperText: helperText, required: required);

  @override
  Map<String, dynamic> toMap() => {
    'id': id,
    'prompt': prompt,
    'type': 'text',
    'placeholder': placeholder,
    'helper_text': helperText,
    'required': required,
  };
}

class DateQuestion extends CustomQuestion {
  final int? minDaysFromNow;
  final int? maxDaysFromNow;

  const DateQuestion({
    required String id,
    required String prompt,
    this.minDaysFromNow,
    this.maxDaysFromNow,
    String? helperText,
    bool required = false,
  }) : super(id: id, prompt: prompt, helperText: helperText, required: required);

  @override
  Map<String, dynamic> toMap() => {
    'id': id,
    'prompt': prompt,
    'type': 'date',
    'validation': {
      if (minDaysFromNow != null) 'min_days_from_now': minDaysFromNow,
      if (maxDaysFromNow != null) 'max_days_from_now': maxDaysFromNow,
    },
    'helper_text': helperText,
    'required': required,
  };
}

// Special question type for rest days with number + period dropdown
class RestDaysQuestion extends CustomQuestion {
  const RestDaysQuestion({
    required String id,
    required String prompt,
    String? helperText,
    bool required = false,
  }) : super(id: id, prompt: prompt, helperText: helperText, required: required);

  @override
  Map<String, dynamic> toMap() => {
    'id': id,
    'prompt': prompt,
    'type': 'rest_days',
    'helper_text': helperText,
    'required': required,
  };
}

// Plan-specific question definitions
class PlanCustomQuestions {
  static const Map<String, List<CustomQuestion>> questions = {
    'load-capacity': [
      SliderQuestion(
        id: 'target_load',
        prompt: 'What load are you working up to?',
        min: 10,
        max: 60,
        step: 5,
        unit: 'kg',
        defaultValue: 20,
        helperText: 'Your goal weight to carry comfortably for 60+ minutes',
      ),
      NumberQuestion(
        id: 'current_max_load',
        prompt: "What's the heaviest you've rucked with recently?",
        unit: 'kg',
        min: 0,
        max: 100,
        helperText: "Be honest - we'll build from here safely",
      ),
      ChipsQuestion(
        id: 'injury_concerns',
        prompt: 'Any areas we should be careful with?',
        options: [
          ChipOption(label: 'Back', value: 'Back'),
          ChipOption(label: 'Knees', value: 'Knees'),
          ChipOption(label: 'Ankles', value: 'Ankles'),
          ChipOption(label: 'Shoulders', value: 'Shoulders'),
          ChipOption(label: 'None', value: 'None'),
        ],
        multiple: true,
      ),
    ],

    'daily-discipline': [
      ChipsQuestion(
        id: 'streak_days',
        prompt: 'How many days do you want to ruck?',
        options: [
          ChipOption(label: '3 days', value: 3),
          ChipOption(label: '5 days', value: 5),
          ChipOption(label: '7 days', value: 7),
          ChipOption(label: '10 days', value: 10),
          ChipOption(label: '15 days', value: 15),
          ChipOption(label: '20 days', value: 20),
          ChipOption(label: '30 days', value: 30),
          ChipOption(label: 'Custom', value: 'custom'),
        ],
        helperText: 'Start with something achievable - you can always extend',
        required: true,
      ),
      RestDaysQuestion(
        id: 'rest_days',
        prompt: 'How many rest days do you want?',
        helperText: 'Optional - you can go every single day or build in recovery',
      ),
      SliderQuestion(
        id: 'minimum_time',
        prompt: 'Minimum session length on tough days?',
        min: 10,
        max: 45,
        step: 5,
        unit: 'minutes',
        defaultValue: 20,
        helperText: 'Your non-negotiable minimum to keep the streak alive',
      ),
    ],

    'fat-loss': [
      SliderQuestion(
        id: 'weight_loss_target',
        prompt: 'Weight loss goal over 12 weeks?',
        min: 2,
        max: 15,
        step: 0.5,
        unit: 'kg',
        defaultValue: 5,
        helperText: '0.5-1kg/week is sustainable',
      ),
      ChipsQuestion(
        id: 'current_activity',
        prompt: 'Current weekly activity level?',
        options: [
          ChipOption(label: 'Sedentary', value: 'sedentary'),
          ChipOption(label: 'Light (1-2x/week)', value: 'light'),
          ChipOption(label: 'Moderate (3-4x/week)', value: 'moderate'),
          ChipOption(label: 'Active (5+x/week)', value: 'active'),
        ],
        required: true,
      ),
      ChipsQuestion(
        id: 'complementary_activities',
        prompt: 'What else will you do alongside rucking?',
        options: [
          ChipOption(label: 'Strength training', value: 'Strength training'),
          ChipOption(label: 'Running', value: 'Running'),
          ChipOption(label: 'Cycling', value: 'Cycling'),
          ChipOption(label: 'Swimming', value: 'Swimming'),
          ChipOption(label: 'Yoga', value: 'Yoga'),
          ChipOption(label: 'None', value: 'None'),
        ],
        multiple: true,
      ),
    ],

    'get-faster': [
      NumberQuestion(
        id: 'current_pace',
        prompt: 'Current 60-minute ruck pace (min/km)?',
        min: 6,
        max: 12,
        helperText: 'Your comfortable pace for 60 minutes with standard load',
      ),
      NumberQuestion(
        id: 'target_pace',
        prompt: 'Goal 60-minute pace (min/km)?',
        min: 5,
        max: 10,
        helperText: 'Be realistic - 30sec/km improvement is significant',
      ),
      ChipsQuestion(
        id: 'speed_work_experience',
        prompt: 'Experience with speed/interval training?',
        options: [
          ChipOption(label: 'None', value: 'none'),
          ChipOption(label: 'Some', value: 'some'),
          ChipOption(label: 'Extensive', value: 'extensive'),
        ],
        required: true,
      ),
    ],

    'event-prep': [
      DateQuestion(
        id: 'event_date',
        prompt: 'When is your event?',
        minDaysFromNow: 14,
        maxDaysFromNow: 365,
        helperText: "We'll build your taper timing around this",
        required: true,
      ),
      NumberQuestion(
        id: 'event_distance',
        prompt: 'Event distance (km)?',
        defaultValue: 19.3,
        min: 5,
        max: 50,
        helperText: '12 miles = 19.3km',
      ),
      NumberQuestion(
        id: 'event_load',
        prompt: 'Required event load (kg)?',
        min: 5,
        max: 50,
        helperText: "The weight you'll carry during the event",
      ),
      TextQuestion(
        id: 'time_goal',
        prompt: 'Target finish time?',
        placeholder: 'e.g., 2:45:00 or sub-3 hours',
        helperText: 'Optional but helps set training paces',
      ),
    ],

    'age-strong': [
      ChipsQuestion(
        id: 'primary_goals',
        prompt: 'What matters most to you?',
        options: [
          ChipOption(label: 'Better posture', value: 'Better posture'),
          ChipOption(label: 'Improved balance', value: 'Improved balance'),
          ChipOption(label: 'Joint health', value: 'Joint health'),
          ChipOption(label: 'Daily energy', value: 'Daily energy'),
          ChipOption(label: 'Confidence walking', value: 'Confidence walking'),
        ],
        multiple: true,
        required: true,
      ),
      ChipsQuestion(
        id: 'mobility_concerns',
        prompt: 'Any mobility limitations?',
        options: [
          ChipOption(label: 'Stairs difficult', value: 'Stairs difficult'),
          ChipOption(label: 'Balance issues', value: 'Balance issues'),
          ChipOption(label: 'Joint stiffness', value: 'Joint stiffness'),
          ChipOption(label: 'Previous falls', value: 'Previous falls'),
          ChipOption(label: 'None', value: 'None'),
        ],
        multiple: true,
      ),
      ChipsQuestion(
        id: 'preferred_terrain',
        prompt: 'Preferred walking surface?',
        options: [
          ChipOption(label: 'Flat paths', value: 'flat'),
          ChipOption(label: 'Some hills OK', value: 'moderate'),
          ChipOption(label: 'Varied terrain', value: 'varied'),
        ],
        required: true,
      ),
    ],
  };

  static List<CustomQuestion> getQuestionsForPlan(String planId) {
    return questions[planId] ?? [];
  }

  static List<Map<String, dynamic>> getQuestionMapsForPlan(String planId) {
    final planQuestions = getQuestionsForPlan(planId);
    return planQuestions.map((q) => q.toMap()).toList();
  }
}