import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ai_cheerleader/services/openai_responses_service.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/features/coaching/domain/models/coaching_plan_type.dart';
import 'package:rucking_app/features/coaching/domain/models/coaching_personality.dart';
import 'package:rucking_app/features/coaching/presentation/widgets/plan_type_card.dart';
import 'package:rucking_app/features/coaching/presentation/widgets/personality_selector.dart';
import 'package:rucking_app/features/coaching/presentation/widgets/plan_preview_card.dart';
import 'package:rucking_app/features/coaching/domain/models/plan_personalization.dart';
import 'package:rucking_app/features/coaching/domain/models/science_based_plan.dart';
import 'package:rucking_app/features/coaching/presentation/widgets/personalization_questions.dart';
import 'package:rucking_app/features/coaching/data/services/coaching_service.dart';
import 'package:rucking_app/features/coaching/presentation/screens/coaching_plan_details_screen.dart';
import 'package:rucking_app/features/profile/presentation/screens/profile_screen.dart';
import 'package:rucking_app/features/coaching/presentation/widgets/rucker_rating_widget.dart';

enum PlanCreationStep {
  greeting,
  goalSelection,
  personalization,
  planPreview,
  personalitySelection,
  commitment,
  creating,
  generatingSummary,
  complete,
}

class PlanCreationScreen extends StatefulWidget {
  const PlanCreationScreen({super.key});

  @override
  State<PlanCreationScreen> createState() => _PlanCreationScreenState();
}

class _PlanCreationScreenState extends State<PlanCreationScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  PlanCreationStep _currentStep = PlanCreationStep.greeting;
  String _streamingText = '';
  bool _isStreaming = false;
  bool _showGoalPills = false;
  String _planPreviewSummary = '';
  bool _isGeneratingPreview = false;
  CoachingPlanType? _selectedPlanType;
  CoachingPersonality? _selectedPersonality;
  CoachingPersonality? _hoveredPersonality;
  PlanPersonalization? _personalization;
  String _generatedSummary = '';
  Map<String, dynamic>? _userInsights;

  late OpenAIResponsesService _openAiService;
  late CoachingService _coachingService;

  // Define the 6 coaching plan types
  final List<CoachingPlanType> _planTypes = [
    CoachingPlanType(
      id: 'fat-loss',
      name: 'Fat Loss & Feel Better',
      description:
          'Build a steady calorie deficit and improve everyday energy with low-impact, progressive rucking plus complementary cardio/strength. We keep it safe, sustainable, and data-driven—no crash tactics.',
      duration: '12 weeks',
      icon: Icons.favorite,
      color: AppColors.error,
      emoji: '❤️',
    ),
    CoachingPlanType(
      id: 'get-faster',
      name: 'Get Faster at Rucking',
      description:
          'Improve your 60-minute ruck pace at a fixed load using aerobic base, controlled tempo work, and smart hills—without trashing your legs.',
      duration: '10 weeks',
      icon: Icons.speed,
      color: AppColors.primary,
      emoji: '⚡',
    ),
    CoachingPlanType(
      id: 'event-prep',
      name: '12-Mile Under 3:00',
      description:
          'Arrive prepared for your event with focused quality sessions, a long-ruck progression, and a taper that respects your feet and recovery.',
      duration: '16 weeks',
      icon: Icons.flag,
      color: AppColors.secondary,
      emoji: '🏁',
    ),
    CoachingPlanType(
      id: 'daily-discipline',
      name: 'Daily Discipline Streak',
      description:
          'Build an unbreakable habit with bite-size sessions, flexible scheduling, and gentle accountability—movement every day, without overuse.',
      duration: '8 weeks',
      icon: Icons.calendar_today,
      color: AppColors.success,
      emoji: '🗓️',
    ),
    CoachingPlanType(
      id: 'age-strong',
      name: 'Posture/Balance & Age-Strong',
      description:
          'Move taller and steadier with light loaded walks plus simple balance/strength work that supports joints and confidence.',
      duration: '12 weeks',
      icon: Icons.accessibility_new,
      color: AppColors.accent,
      emoji: '🧘',
    ),
    CoachingPlanType(
      id: 'load-capacity',
      name: 'Load Capacity Builder',
      description:
          'Safely increase how much weight you can carry. We progress one knob at a time (time → hills → small load bumps) with readiness checks so feet, knees, and back adapt without flare-ups.',
      duration: '14 weeks',
      icon: Icons.fitness_center,
      color: AppColors.brown,
      emoji: '💪',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _initializeServices();
    _startGreetingSequence();
  }

  void _initializeServices() {
    _openAiService = GetIt.I<OpenAIResponsesService>();
    _coachingService = GetIt.I<CoachingService>();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    // Multiple aggressive approaches to ensure keyboard is dismissed
    try {
      // Method 1: Platform-level keyboard dismissal
      SystemChannels.textInput.invokeMethod('TextInput.hide');

      // Method 2: Focus-based dismissal
      FocusScope.of(context).unfocus();
      FocusManager.instance.primaryFocus?.unfocus();

      // Method 3: Widget tree level unfocus
      WidgetsBinding.instance.focusManager.primaryFocus?.unfocus();
    } catch (e) {
      // If anything fails, at least try the basic approaches
      try {
        SystemChannels.textInput.invokeMethod('TextInput.hide');
        FocusScope.of(context).unfocus();
      } catch (_) {}
    }
  }

  void _startGreetingSequence() {
    _animationController.forward();

    // Start streaming the greeting after a short delay
    Future.delayed(const Duration(milliseconds: 500), () {
      _streamGreeting();
    });
  }

  void _streamGreeting() async {
    if (!mounted) return;

    setState(() {
      _isStreaming = true;
      _streamingText = '';
    });

    final authState = context.read<AuthBloc>().state;
    final username =
        authState is Authenticated ? authState.user.username : 'Rucker';

    try {
      await _openAiService.stream(
        model: 'gpt-4.1',
        instructions:
            'You are a friendly, enthusiastic AI fitness coach for a rucking app. Your job is to greet users warmly and get them excited about creating a training plan.',
        input:
            'Greet the user named "$username" and ask them what kind of goal they want to set. Keep it brief, friendly, and motivating. End with asking what kind of goal they want to set.',
        temperature: 0.7,
        maxOutputTokens: 150,
        onDelta: (delta) {
          if (mounted) {
            setState(() {
              _streamingText += delta;
            });
          }
        },
        onComplete: (fullText) {
          if (mounted) {
            setState(() {
              _isStreaming = false;
              _streamingText = fullText;
              _showGoalPills = true; // Show goal pills in same screen
            });
          }
        },
        onError: (error) {
          AppLogger.error('[PLAN_CREATION] Streaming error: $error');
          if (mounted) {
            setState(() {
              _isStreaming = false;
              _streamingText =
                  "Hi $username! I'm your AI coach, and I'm excited to help you create the perfect rucking plan. What kind of goal do you want to set?";
              _showGoalPills = true;
            });
          }
        },
      );
    } catch (e) {
      AppLogger.error('[PLAN_CREATION] Failed to stream greeting: $e');
      // Fallback to static greeting
      if (mounted) {
        setState(() {
          _isStreaming = false;
          _streamingText =
              "Hi $username! I'm your AI coach, and I'm excited to help you create the perfect rucking plan. What kind of goal do you want to set?";
          _showGoalPills = true;
        });
      }
    }
  }

  void _onPlanTypeSelected(CoachingPlanType planType) async {
    // Show goal summary and confirmation dialog
    final confirmed = await _showGoalConfirmationDialog(planType);
    if (confirmed == true) {
      // Dismiss keyboard before moving to personalization step
      _dismissKeyboard();

      setState(() {
        _selectedPlanType = planType;
        _currentStep = PlanCreationStep.personalization;
      });
    }
  }

  Future<bool?> _showGoalConfirmationDialog(CoachingPlanType planType) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Text(planType.emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                planType.name,
                style: AppTextStyles.headlineMedium.copyWith(
                  color: planType.color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: planType.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Text(
                planType.duration,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: planType.color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              planType.description,
              style: AppTextStyles.bodyMedium.copyWith(height: 1.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Is this the goal you want to work towards?',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: planType.color,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Not quite',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Yes, let\'s do it!'),
          ),
        ],
      ),
    );
  }

  void _onPersonalizationComplete(PlanPersonalization personalization) {
    // Dismiss keyboard when moving to next step
    _dismissKeyboard();

    // Add a small delay and dismiss again to ensure it works
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _dismissKeyboard();
      }
    });

    setState(() {
      _personalization = personalization;
      _currentStep = PlanCreationStep.planPreview;
    });

    // Generate AI plan preview summary
    _generatePlanPreviewSummary();
  }

  Future<void> _generatePlanPreviewSummary() async {
    if (_selectedPlanType == null || _personalization == null) return;

    final authState = context.read<AuthBloc>().state;
    final username =
        authState is Authenticated ? authState.user.username : 'Rucker';

    // Special handling for Daily Discipline
    if (_selectedPlanType!.id == 'daily-discipline') {
      await _generateDailyDisciplinePreview(username);
      return;
    }

    // Get custom responses if available
    final customResponses = _personalization!.customResponses ?? {};

    // Build personalized prompt based on plan type
    String planSpecificDetails = '';

    switch (_selectedPlanType!.id) {
      case 'load-capacity':
        final targetLoad = customResponses['target_load'] ?? 20;
        final currentLoad = customResponses['current_max_load'] ?? 10;
        final injuryConcerns = customResponses['injury_concerns'] ?? [];
        planSpecificDetails = '''
- Target Load: ${targetLoad}kg (working up from ${currentLoad}kg)
- Injury Concerns: ${injuryConcerns.isNotEmpty ? injuryConcerns.join(', ') : 'None'}
- Building from ${currentLoad}kg to ${targetLoad}kg safely''';
        break;

      case 'fat-loss':
        // Weight loss target is always stored in kg internally
        final weightLossTargetKg = customResponses['weight_loss_target'] ?? 5;
        final currentActivity = customResponses['current_activity'] ?? 'moderate';
        final complementary = customResponses['complementary_activities'] ?? [];

        // Get user's metric preference for display
        final prefs = await SharedPreferences.getInstance();
        final useMetric = prefs.getBool('prefer_metric') ?? prefs.getBool('preferMetric') ?? true;
        final weightLossTarget = useMetric ? weightLossTargetKg : weightLossTargetKg * 2.20462;
        final weightUnit = useMetric ? 'kg' : 'lbs';

        // Calculate calorie requirements (using kg for calculation)
        // 1kg fat loss = ~7,700 calories deficit
        final totalCaloriesNeeded = (weightLossTargetKg * 7700).round();
        final weeklyCaloriesNeeded = (totalCaloriesNeeded / 12).round();
        final dailyDeficitNeeded = (weeklyCaloriesNeeded / 7).round();

        // Estimate calories from rucking (based on 4 sessions/week avg)
        final sessionsPerWeek = _personalization!.trainingDaysPerWeek ?? 4;
        // Rough estimate: 400-500 calories per 45-min ruck session
        final weeklyRuckCalories = sessionsPerWeek * 450;
        final remainingWeeklyDeficit = weeklyCaloriesNeeded - weeklyRuckCalories;
        final remainingDailyDeficit = (remainingWeeklyDeficit / 7).round();

        planSpecificDetails = '''
- Weight Loss Goal: ${weightLossTarget.toStringAsFixed(1)}$weightUnit over 12 weeks
- Current Activity Level: $currentActivity
- Complementary Activities: ${complementary.isNotEmpty ? complementary.join(', ') : 'Rucking only'}

📊 CALORIE MATH:
- Total deficit needed: ${totalCaloriesNeeded.toStringAsFixed(0)} calories
- Weekly deficit target: ${weeklyCaloriesNeeded.toStringAsFixed(0)} calories
- Daily deficit target: ${dailyDeficitNeeded.toStringAsFixed(0)} calories

🔥 YOUR BURN PLAN:
- Rucking ($sessionsPerWeek sessions/week): ~${weeklyRuckCalories} cal/week
- From diet/other activity: ~${remainingWeeklyDeficit > 0 ? remainingWeeklyDeficit : 0} cal/week
- Daily nutrition deficit needed: ~${remainingDailyDeficit > 0 ? remainingDailyDeficit : 0} calories

💡 REALITY CHECK:
${remainingDailyDeficit > 500 ? "This is aggressive - consider a longer timeline or adding more activity" :
  remainingDailyDeficit > 300 ? "This is achievable with moderate dietary changes" :
  "Your activity level makes this very achievable!"}''';
        break;

      case 'get-faster':
        final currentPace = customResponses['current_pace'] ?? '8:00';
        final targetPace = customResponses['target_pace'] ?? '7:00';
        final speedExperience = customResponses['speed_work_experience'] ?? 'some';
        planSpecificDetails = '''
- Current Pace: $currentPace min/km
- Target Pace: $targetPace min/km
- Speed Work Experience: $speedExperience''';
        break;

      case 'event-prep':
        final eventDate = customResponses['event_date'] ??
            customResponses['eventDate'];
        final eventDistance = customResponses['event_distance'] ??
            customResponses['eventDistanceKm'] ??
            19.3;
        final eventLoad = customResponses['event_load'] ??
            customResponses['eventLoadKg'] ??
            20;
        final timeGoal = customResponses['time_goal'] ?? 'Finish strong';
        planSpecificDetails = '''
- Event Date: ${eventDate != null ? DateTime.parse(eventDate).toLocal().toString().split(' ')[0] : 'TBD'}
- Event Distance: ${eventDistance}km
- Event Load: ${eventLoad}kg
- Time Goal: $timeGoal''';
        break;

      case 'age-strong':
        final primaryGoals = customResponses['primary_goals'] ?? [];
        final mobilityConcerns = customResponses['mobility_concerns'] ?? [];
        final terrain = customResponses['preferred_terrain'] ?? 'flat';
        planSpecificDetails = '''
- Primary Goals: ${primaryGoals.isNotEmpty ? primaryGoals.join(', ') : 'Stay active'}
- Mobility Concerns: ${mobilityConcerns.isNotEmpty ? mobilityConcerns.join(', ') : 'None'}
- Preferred Terrain: $terrain''';
        break;
    }

    // Add user insights context if available
    String userInsightsContext = '';
    if (_userInsights != null) {
      final experienceLevel = _userInsights!['experience_level'] ?? 'Unknown';
      final avgDistance = _userInsights!['avg_distance'] ?? 0.0;
      final avgPace = _userInsights!['avg_pace'] ?? 0.0;
      final weeklyAvg = _userInsights!['weekly_avg'] ?? 0.0;
      final ruckWeight = _userInsights!['ruck_weight'];

      userInsightsContext = '''

USER'S CURRENT FITNESS PROFILE:
- Experience Level: $experienceLevel
- Current Weekly Frequency: ${weeklyAvg.toStringAsFixed(1)} sessions/week
- Average Distance: ${avgDistance.toStringAsFixed(1)} km per session
- Average Pace: ${avgPace > 0 ? '${avgPace.toStringAsFixed(1)} min/km' : 'N/A'}
- Typical Ruck Weight: ${ruckWeight != null ? '${ruckWeight.toStringAsFixed(0)} kg' : 'N/A'}
''';
    }

    final prompt = '''
Create a PERSONALIZED ${_selectedPlanType!.name} rucking plan for $username based on their specific inputs.

USER'S PERSONALIZATION:
- Why: ${_personalization!.why?.join(', ') ?? 'Personal growth'}
- Success: ${_personalization!.successDefinition ?? 'Complete the program'}
- Training Days: ${_personalization!.trainingDaysPerWeek} days/week on ${_personalization!.preferredDays?.join(', ') ?? 'flexible schedule'}
- Challenges: ${_personalization!.challenges?.join(', ') ?? 'Consistency'}
- Minimum Session: ${_personalization!.minimumSessionMinutes} minutes${(_personalization!.unloadedOk ?? false) ? ' (unloaded OK on recovery days)' : ''}
$userInsightsContext
PLAN-SPECIFIC DETAILS:
$planSpecificDetails

Create a personalized plan that directly addresses THEIR inputs:

## 🎯 YOUR MISSION
• **Goal**: ${_selectedPlanType!.name} specifically for YOUR situation
• **Why**: ${_personalization!.why?.join(', ') ?? 'Personal growth'}
• **Win**: ${_personalization!.successDefinition ?? 'Complete successfully'}
• **Timeline**: ${_getDynamicDuration()}
${_selectedPlanType!.id == 'fat-loss' ? '\n## 🔥 CALORIE BURN STRATEGY\n[Include the calorie calculations and what else they need to do beyond rucking to hit their deficit goals]' : ''}

## 📅 YOUR WEEKLY TRAINING
Design a week that fits ${_personalization!.trainingDaysPerWeek} days on ${_personalization!.preferredDays?.join(', ') ?? 'your schedule'}:
[Create specific workouts for THEIR available days, respecting their minimum session time of ${_personalization!.minimumSessionMinutes} minutes]

## 🚧 MANAGING YOUR CHALLENGES
${_personalization!.challenges?.map((challenge) => '''
**$challenge Strategy**:
• Prevention: [specific preventive measures]
• During Session: [how to handle if it comes up]
• Recovery: [post-session protocol]''').join('\n\n') ?? 'Create protocols for consistency and motivation'}

## 📈 YOUR PROGRESSION PATH
Based on your goals and current fitness, here's your personalized progression:

**Weeks 1-2: Foundation**
[Build base specific to their current level and goals]

**Weeks 3-4: Building**
[Progressive overload tailored to their targets]

**Weeks 5-6: Pushing**
[Peak training adapted to their timeline]

**Final Weeks: Peak & Taper**
[Final preparation for their specific goal: ${_personalization!.successDefinition}]

## 🔧 MINIMUM SESSION PROTOCOL
When you only have ${_personalization!.minimumSessionMinutes} minutes:
[Create 2-3 specific options they can do in their minimum time]

Keep it concise, specific to THEIR inputs, and actionable. Focus on practical rucking workouts they can actually do.
''';

    setState(() {
      _planPreviewSummary = '';
      _isGeneratingPreview = true;
    });

    try {
      await _openAiService.stream(
        model: 'gpt-4.1',
        instructions:
            'You are a rucking coach creating a PERSONALIZED plan for $username. Take their specific inputs (days available, challenges, goals, custom answers) and create a plan that addresses THEIR situation. Do NOT show generic templates. Every recommendation should tie back to what THEY told you. Use markdown formatting with bullets (•), bold text, and ## headers. Be specific with weights, distances, and paces based on their current fitness and goals.',
        input: prompt,
        temperature: 0.7,
        maxOutputTokens: 3000,
        onDelta: (delta) {
          if (mounted) {
            setState(() {
              _planPreviewSummary += delta;
            });
          }
        },
        onComplete: (fullText) {
          if (mounted) {
            setState(() {
              _isGeneratingPreview = false;
              _planPreviewSummary = fullText;
            });
          }
        },
      );
    } catch (e) {
      AppLogger.error('Failed to generate plan preview summary: $e');
      setState(() {
        _planPreviewSummary =
            'I\'m so excited about your ${_selectedPlanType!.name} journey! This ${_getDynamicDuration()} plan is perfectly tailored to your goals and schedule. With ${_personalization!.trainingDaysPerWeek} training days per week, you\'re going to see incredible progress toward ${_personalization!.successDefinition}. Let\'s make this happen!';
        _isGeneratingPreview = false;
      });
    }
  }

  Future<void> _generateDailyDisciplinePreview(String username) async {
    // Get custom responses for Daily Discipline
    final customResponses = _personalization!.customResponses ?? {};
    final streakDays = customResponses['streak_days'] ?? 30;
    final restData = customResponses['rest_days'] ?? {};
    final restCount = restData['count'] ?? 0;
    final restPeriod = restData['period'] ?? 'per_week';
    final minSessionTime = customResponses['minimum_time'] ?? 20;

    // Build rest days description
    String restDescription = '';
    if (restCount == 0) {
      restDescription = 'Every single day - no rest days!';
    } else if (restPeriod == 'per_week') {
      restDescription = '$restCount rest ${restCount == 1 ? "day" : "days"} per week';
    } else if (restPeriod == 'per_month') {
      restDescription = '$restCount rest ${restCount == 1 ? "day" : "days"} per month';
    } else {
      restDescription = '$restCount rest ${restCount == 1 ? "day" : "days"} total';
    }

    // Add user insights context if available
    String userInsightsContext = '';
    if (_userInsights != null) {
      final experienceLevel = _userInsights!['experience_level'] ?? 'Unknown';
      final avgDistance = _userInsights!['avg_distance'] ?? 0.0;
      final weeklyAvg = _userInsights!['weekly_avg'] ?? 0.0;
      final ruckWeight = _userInsights!['ruck_weight'];

      userInsightsContext = '''

USER'S CURRENT FITNESS PROFILE:
- Experience Level: $experienceLevel
- Current Weekly Frequency: ${weeklyAvg.toStringAsFixed(1)} sessions/week
- Average Distance: ${avgDistance.toStringAsFixed(1)} km per session
- Typical Ruck Weight: ${ruckWeight != null ? '${ruckWeight.toStringAsFixed(0)} kg' : 'N/A'}
''';
    }

    final prompt = '''
Create a PERSONALIZED $streakDays-day rucking plan for $username. DO NOT use generic templates or mention "8 weeks" - this is specifically a $streakDays-day streak.

USER'S ACTUAL INPUTS (USE THESE EXACT VALUES):
- Streak Duration: $streakDays days (NOT 8 weeks!)
- Rest Plan: $restDescription
- Why: ${_personalization!.why?.join(', ') ?? 'Personal growth'}$userInsightsContext
- Success: ${_personalization!.successDefinition ?? 'Complete the streak'}
- Challenges: ${_personalization!.challenges?.join(', ') ?? 'Consistency'}
- Minimum Session: $minSessionTime minutes

CRITICAL: Every number and detail must match their inputs above. Do not use generic timeframes.

## 🎯 YOUR MISSION
• **Goal**: Complete YOUR $streakDays-day streak
• **Why**: ${_personalization!.why?.join(', ') ?? 'Build discipline'}
• **Win**: ${_personalization!.successDefinition ?? 'Streak complete'}
• **Timeline**: $streakDays days (${(streakDays / 7).round()} weeks)

## 📅 YOUR DAILY RHYTHM
Based on $restDescription, here's your sustainable pattern:
${restCount == 0 ? '''
• Every single day for $streakDays days straight
• Vary intensity to prevent burnout
• Minimum $minSessionTime minutes keeps streak alive''' : '''
• Ruck days and rest days based on: $restDescription
• Active days need minimum $minSessionTime minutes
• Rest days can be complete rest or light movement'''}

## 🏃 SESSION ROTATION
Rotate these throughout your $streakDays days:
• **Easy Recovery**: ${minSessionTime}-${minSessionTime + 10} min @ comfortable pace, light weight
• **Steady State**: ${minSessionTime + 10}-${minSessionTime + 20} min @ moderate pace, moderate weight
• **Push Session**: ${minSessionTime + 15}-${minSessionTime + 30} min @ challenging pace or weight
${restCount > 0 ? "• **Rest/Recovery**: Complete rest or gentle walk (unweighted optional)" : ""}

## 🚧 DEALING WITH ${(_personalization!.challenges?.first ?? 'CHALLENGES').toUpperCase()}
${_personalization!.challenges?.map((challenge) => '''
**$challenge Protocol**:
• Green (all good): [specific advice]
• Yellow (adjust): [modification strategy]
• Red (at risk): [minimum viable session to keep streak alive]
''').join('\n') ?? '''
• Green: Keep going as planned
• Yellow: Reduce intensity but maintain consistency
• Red: Do minimum $minSessionTime minutes to keep streak alive
'''}

## 📈 STREAK MILESTONES
• **Day 7**: First week done - momentum building
• **Day 14**: Two weeks - habit forming
• **Day 21**: Three weeks - identity shifting
• **Day ${(streakDays * 0.5).round()}**: Halfway - unstoppable now
• **Day ${streakDays - 1}**: Final day tomorrow - victory in sight
• **Day $streakDays**: MISSION COMPLETE! 🎯

Keep it concise, specific to their inputs, and motivating. Use bullet points and clear formatting.
''';

    setState(() {
      _planPreviewSummary = '';
      _isGeneratingPreview = true;
    });

    try {
      await _openAiService.stream(
        model: 'gpt-4.1',
        instructions:
            'You are creating a PERSONALIZED $streakDays-day rucking streak plan. Use ONLY the specific numbers provided - this is a $streakDays-day plan, NOT 8 weeks. Every detail must match their actual inputs. Do not use generic templates. Make it specific to their $streakDays-day goal with $restDescription.',
        input: prompt,
        temperature: 0.7,
        maxOutputTokens: 3000,
        onDelta: (delta) {
          if (mounted) {
            setState(() {
              _planPreviewSummary += delta;
            });
          }
        },
        onComplete: (fullText) {
          if (mounted) {
            setState(() {
              _isGeneratingPreview = false;
              _planPreviewSummary = fullText;
            });
          }
        },
      );
    } catch (e) {
      AppLogger.error('Failed to generate Daily Discipline preview: $e');
      setState(() {
        _planPreviewSummary =
            'Your $streakDays-day Daily Discipline streak is ready! With $restDescription and a minimum of $minSessionTime minutes on tough days, you\'re set up for success. This journey will ${_personalization!.why?.join(", ") ?? "build unshakeable discipline"} and help you ${_personalization!.successDefinition ?? "achieve your goals"}. Let\'s start strong!';
        _isGeneratingPreview = false;
      });
    }
  }

  void _onPersonalitySelected(CoachingPersonality personality) {
    // Dismiss keyboard when moving to next step
    _dismissKeyboard();

    setState(() {
      _selectedPersonality = personality;
      _currentStep = PlanCreationStep.commitment;
    });
  }

  Future<void> _generatePlanSummary(Map<String, dynamic> planData) async {
    try {
      final prompt = """
You are a fitness coach. Generate a motivational and detailed summary of this personalized rucking plan.

Plan Type: ${_selectedPlanType!.name}
Duration: ${_getDynamicDuration()}
Description: ${_selectedPlanType!.description}

User's Personalization:
- Why: ${_personalization!.why}
- Success Definition: ${_personalization!.successDefinition}
- Training Days/Week: ${_personalization!.trainingDaysPerWeek}
- Preferred Days: ${_personalization!.preferredDays?.join(', ')}
- Challenges: ${_personalization!.challenges?.join(', ')}
- Minimum Session: ${_personalization!.minimumSessionMinutes} minutes
- Unloaded OK: ${_personalization!.unloadedOk}

Coaching Style: ${_selectedPersonality!.name}

Generate a personalized, motivating 2-3 paragraph summary that:
1. Acknowledges their 'why' and success goals
2. Explains how this plan addresses their specific challenges
3. Gives them confidence about achieving their goals
4. Matches the ${_selectedPersonality!.name} coaching style

Keep it under 200 words, motivational, and specific to their answers.
""";

      setState(() {
        _generatedSummary = '';
        _isStreaming = true;
      });

      await _openAiService.stream(
        model: 'gpt-4.1',
        instructions:
            'You are a fitness coach. Generate a motivational and detailed summary of this personalized rucking plan. Use markdown formatting with headers, bullet points, and emphasis for better readability.',
        input: prompt,
        temperature: 0.7,
        maxOutputTokens: 1000,
        onDelta: (delta) {
          if (mounted) {
            setState(() {
              _generatedSummary += delta;
              _isStreaming = true;
            });
          }
        },
        onComplete: (fullText) {
          if (mounted) {
            setState(() {
              _isStreaming = false;
              _generatedSummary = fullText;
            });
          }
        },
      );
    } catch (e) {
      AppLogger.error('Failed to generate plan summary: $e');
      setState(() {
        _generatedSummary =
            'Your personalized ${_selectedPlanType!.name} plan is ready! Let\'s crush those goals together.';
        _isStreaming = false;
      });
    }
  }

  void _onCommitToPlan() async {
    if (_selectedPlanType == null ||
        _selectedPersonality == null ||
        _personalization == null) {
      AppLogger.error('Missing required data for plan creation');
      return;
    }

    setState(() {
      _currentStep = PlanCreationStep.creating;
    });

    try {
      // Add the AI-generated plan to the personalization
      final personalizationWithAIPlan = _personalization!.copyWith(
        aiGeneratedPlan: _planPreviewSummary,
      );

      // Create the personalized coaching plan via API
      final planData = await _coachingService.createCoachingPlan(
        basePlanId: _selectedPlanType!.id,
        coachingPersonality: _selectedPersonality!.id,
        personalization: personalizationWithAIPlan,
      );

      // The planData is the response data from backend: {plan_id, message, start_date, duration_weeks}
      final planId = planData['plan_id'];
      AppLogger.info('Successfully created coaching plan: $planId');

      if (mounted) {
        setState(() {
          _currentStep = PlanCreationStep.generatingSummary;
        });

        // Generate AI summary of the plan
        await _generatePlanSummary(planData);

        if (mounted) {
          setState(() {
            _currentStep = PlanCreationStep.complete;
          });
        }
      }
    } catch (e) {
      AppLogger.error('Failed to create coaching plan: $e');

      if (mounted) {
        // Show error and go back to commitment step
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create plan: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );

        setState(() {
          _currentStep = PlanCreationStep.commitment;
        });
      }
    }
  }

  void _onBackPressed() {
    // Always dismiss keyboard when navigating
    _dismissKeyboard();

    switch (_currentStep) {
      case PlanCreationStep.goalSelection:
        Navigator.of(context).pop();
        break;
      case PlanCreationStep.personalization:
        setState(() {
          _currentStep = PlanCreationStep.goalSelection;
          _selectedPlanType = null;
        });
        break;
      case PlanCreationStep.planPreview:
        setState(() {
          _currentStep = PlanCreationStep.personalization;
          _personalization = null;
        });
        break;
      case PlanCreationStep.personalitySelection:
        setState(() {
          _currentStep = PlanCreationStep.planPreview;
        });
        break;
      case PlanCreationStep.commitment:
        setState(() {
          _currentStep = PlanCreationStep.personalitySelection;
          _selectedPersonality = null;
        });
        break;
      default:
        // Can't go back from greeting, creating, or complete
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final statusBarHeight = mediaQuery.padding.top;
    final statusBarColor = _getStatusBarColor();
    final overlayStyle =
        statusBarColor.computeLuminance() > 0.5
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light;

    return GestureDetector(
      onTap: () {
        // Dismiss keyboard when tapping anywhere
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: Scaffold(
          backgroundColor: AppColors.backgroundLight,
          appBar: _currentStep != PlanCreationStep.greeting &&
                  _currentStep != PlanCreationStep.creating &&
                  _currentStep != PlanCreationStep.generatingSummary &&
                  _currentStep != PlanCreationStep.complete &&
                  _currentStep != PlanCreationStep.personalization
              ? AppBar(
                  title: const Text('AI Coaching Plan'),
                  elevation: 0,
                  systemOverlayStyle: overlayStyle,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _onBackPressed,
                  ),
                )
              : null,
          body: Stack(
            children: [
              if (statusBarHeight > 0)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: statusBarHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: statusBarColor),
                  ),
                ),
              SafeArea(
                child: _buildCurrentStep(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusBarColor() {
    if (_currentStep == PlanCreationStep.commitment &&
        _selectedPersonality != null) {
      return _selectedPersonality!.color;
    }
    return AppColors.primary;
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case PlanCreationStep.greeting:
        return _buildGreetingStep();
      case PlanCreationStep.goalSelection:
        return _buildGoalSelectionStep();
      case PlanCreationStep.personalization:
        return _buildPersonalizationStep();
      case PlanCreationStep.planPreview:
        return _buildPlanPreviewStep();
      case PlanCreationStep.personalitySelection:
        return _buildPersonalitySelectionStep();
      case PlanCreationStep.commitment:
        return _buildCommitmentStep();
      case PlanCreationStep.creating:
        return _buildCreatingStep();
      case PlanCreationStep.generatingSummary:
        return _buildGeneratingSummaryStep();
      case PlanCreationStep.complete:
        return _buildCompleteStep();
    }
  }

  Widget _buildGreetingStep() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                const SizedBox(height: 16),
                // Streaming text bubble
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        _streamingText + (_isStreaming ? '▌' : ''),
                        style: AppTextStyles.bodyLarge.copyWith(
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                  if (_isStreaming)
                    Container(
                      margin: const EdgeInsets.only(top: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.primary),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'AI Coach is typing...',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Rucker Rating Widget - show after greeting
            if (_showGoalPills) ...[
              const SizedBox(height: 24),
              const RuckerRatingWidget(),
              const SizedBox(height: 24),
            ],

            // Goal selection pills (shown after streaming completes)
            if (_showGoalPills) ...[
              const SizedBox(height: 8),
              AnimatedOpacity(
                opacity: _showGoalPills ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 600),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: _planTypes.map((planType) {
                    return GestureDetector(
                      onTap: () => _onPlanTypeSelected(planType),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(
                            color: AppColors.primary.withOpacity(0.3),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: planType.color.withOpacity(0.1),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              planType.emoji,
                              style: const TextStyle(fontSize: 20),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              planType.name,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
          // Close button positioned at top right
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: Icon(
                Icons.close,
                color: Colors.grey[600],
                size: 28,
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalSelectionStep() {
    print('🎯🎯🎯 [GOAL_SELECTION] Building goal selection step');
    return AnimatedOpacity(
      opacity: _currentStep == PlanCreationStep.goalSelection ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 600),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // AI message bubble
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.psychology,
                    color: AppColors.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Choose your goal and I\'ll create a personalized plan just for you!',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Rucker Rating Widget
            RuckerRatingWidget(
              onInsightsLoaded: (insights) {
                setState(() {
                  _userInsights = insights;
                });
              },
            ),
            const SizedBox(height: 24),

            // Plan type cards
            Expanded(
              child: ListView.builder(
                itemCount: _planTypes.length,
                itemBuilder: (context, index) {
                  final planType = _planTypes[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: PlanTypeCard(
                      planType: planType,
                      onTap: () => _onPlanTypeSelected(planType),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalizationStep() {
    return PersonalizationQuestions(
      onPersonalizationComplete: _onPersonalizationComplete,
      planType: _selectedPlanType,
      userInsights: _userInsights,
    );
  }

  Widget _buildPlanPreviewStep() {
    if (_selectedPlanType == null || _personalization == null)
      return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          // Goal title with emoji
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _selectedPlanType!.emoji,
                style: const TextStyle(fontSize: 32),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _selectedPlanType!.name,
                  style: AppTextStyles.headlineMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // AI-generated personalized summary
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MarkdownBody(
                  data: _planPreviewSummary + (_isGeneratingPreview ? '▌' : ''),
                  styleSheet: MarkdownStyleSheet(
                    p: AppTextStyles.bodyLarge.copyWith(height: 1.6),
                    h2: AppTextStyles.titleLarge.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                    strong: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    tableHead: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    tableBody: AppTextStyles.bodyMedium,
                    listBullet: AppTextStyles.bodyLarge,
                  ),
                ),
                if (_isGeneratingPreview) ...[
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(AppColors.primary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'AI Coach is creating your plan...',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: !_isGeneratingPreview
                  ? () {
                      // Dismiss keyboard when moving to next step
                      _dismissKeyboard();

                      setState(() {
                        _currentStep = PlanCreationStep.personalitySelection;
                      });
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _isGeneratingPreview
                    ? 'Creating your plan...'
                    : 'Perfect! Let\'s choose coaching style',
                style: AppTextStyles.titleMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalitySelectionStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose Your Coaching Style',
            style: AppTextStyles.headlineMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'How would you like me to motivate you?',
            style: AppTextStyles.bodyLarge.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          PersonalitySelector(
            onPersonalitySelected: _onPersonalitySelected,
          ),
        ],
      ),
    );
  }

  Widget _buildCommitmentStep() {
    if (_selectedPlanType == null ||
        _selectedPersonality == null ||
        _personalization == null) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI Coach avatar with personality
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  _selectedPersonality!.color,
                  _selectedPersonality!.color.withOpacity(0.7)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: _selectedPersonality!.color.withOpacity(0.3),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              _selectedPersonality!.icon,
              size: 40,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 24),

          // Conversational greeting based on personality
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _selectedPersonality!.color.withOpacity(0.1),
                  _selectedPersonality!.color.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _selectedPersonality!.color.withOpacity(0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getPersonalizedGreeting(),
                  style: AppTextStyles.headlineMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _selectedPersonality!.color,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _getPersonalizedEncouragement(),
                  style: AppTextStyles.bodyLarge.copyWith(
                    height: 1.5,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Plan overview in conversational style
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Plan header
                Row(
                  children: [
                    Text(
                      _selectedPlanType!.emoji,
                      style: const TextStyle(fontSize: 32),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedPlanType!.name,
                            style: AppTextStyles.titleLarge.copyWith(
                              fontWeight: FontWeight.bold,
                              color: _selectedPersonality!.color,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color:
                                  _selectedPersonality!.color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _getDynamicDuration(),
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: _selectedPersonality!.color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Conversational plan details
                Text(
                  _getPersonalizedPlanSummary(),
                  style: AppTextStyles.bodyLarge.copyWith(
                    height: 1.6,
                    color: Colors.grey[700],
                  ),
                ),

                const SizedBox(height: 20),

                // Key details in a more conversational format
                _buildConversationalDetails(),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Motivational call to action
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _selectedPersonality!.color.withOpacity(0.15),
                  _selectedPersonality!.color.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _selectedPersonality!.color.withOpacity(0.2),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.rocket_launch,
                  size: 48,
                  color: _selectedPersonality!.color,
                ),
                const SizedBox(height: 16),
                Text(
                  _getPersonalizedCallToAction(),
                  style: AppTextStyles.titleLarge.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _selectedPersonality!.color,
                    height: 1.3,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Action button with personality-based text
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _onCommitToPlan,
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedPersonality!.color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
                shadowColor: _selectedPersonality!.color.withOpacity(0.3),
              ),
              child: Text(
                _getPersonalizedButtonText(),
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreatingStep() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Creating your personalized plan...',
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'This will just take a moment',
            style: AppTextStyles.bodyLarge.copyWith(
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratingSummaryStep() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Generating your personalized plan summary...',
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Our AI coach is crafting your motivational summary',
            style: AppTextStyles.bodyLarge.copyWith(
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          // Success icon
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.withOpacity(0.1),
            ),
            child: Icon(
              Icons.check_circle,
              size: 50,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 24),

          // Title
          Text(
            'Your Plan is Ready!',
            style: AppTextStyles.headlineMedium.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // AI-generated summary
          Container(
            width: double.infinity,
            constraints: BoxConstraints(
              minHeight: 200,
              maxHeight: 400,
            ),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        color: AppColors.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Your AI Coach Says:',
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _generatedSummary.isNotEmpty
                      ? MarkdownBody(
                          data: _generatedSummary,
                          styleSheet: MarkdownStyleSheet(
                            p: AppTextStyles.bodyLarge.copyWith(height: 1.5),
                            h1: AppTextStyles.headlineLarge.copyWith(
                              color: AppColors.primary,
                              fontSize: 24,
                            ),
                            h2: AppTextStyles.headlineMedium.copyWith(
                              color: AppColors.primary,
                              fontSize: 20,
                            ),
                            h3: AppTextStyles.titleLarge.copyWith(
                              color: AppColors.primary,
                              fontSize: 18,
                            ),
                            listBullet: AppTextStyles.bodyLarge.copyWith(
                              color: AppColors.primary,
                              height: 1.5,
                            ),
                            strong: AppTextStyles.bodyLarge.copyWith(
                              fontWeight: FontWeight.bold,
                              height: 1.5,
                            ),
                            em: AppTextStyles.bodyLarge.copyWith(
                              fontStyle: FontStyle.italic,
                              height: 1.5,
                            ),
                          ),
                        )
                      : Text(
                          'Your personalized ${_selectedPlanType?.name ?? "training"} plan is ready! Let\'s crush those goals together.',
                          style: AppTextStyles.bodyLarge.copyWith(
                            height: 1.5,
                          ),
                        ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Action buttons
          Column(
            children: [
              // Primary button - Go to Homepage
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // Navigate to homepage
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 4,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.home, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Go to Homepage',
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Secondary button - View Your Plan
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (context) => const ProfileScreen(),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(
                      color: AppColors.primary,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.calendar_month, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'View Your Plan',
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Bottom message
          Text(
            'Your next scheduled activity will appear on the homepage.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalizationItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  String _getStreakTargetDescription() {
    if (_personalization!.streakTargetDays != null) {
      return '\n- Streak Target: ${_personalization!.streakTargetDays} days in a row';
    } else if (_personalization!.streakTargetRucks != null &&
        _personalization!.streakTimeframeDays != null) {
      return '\n- Streak Target: ${_personalization!.streakTargetRucks} rucks in ${_personalization!.streakTimeframeDays} days';
    }
    return '';
  }

  String _getStreakTargetInstruction() {
    if (_personalization!.streakTargetDays != null) {
      return '\n\n7. STREAK TARGET: How to build toward their ${_personalization!.streakTargetDays}-day consecutive streak goal with strategies for streak protection and recovery.';
    } else if (_personalization!.streakTargetRucks != null &&
        _personalization!.streakTimeframeDays != null) {
      return '\n\n7. STREAK TARGET: How to achieve ${_personalization!.streakTargetRucks} rucks in ${_personalization!.streakTimeframeDays} days with flexible scheduling and recovery strategies.';
    }
    return '';
  }

  String _getPersonalizedGreeting() {
    final personality = _selectedPersonality!;
    final planName = _selectedPlanType!.name.toLowerCase();

    switch (personality.id) {
      case 'Supportive Friend':
        return 'I\'m so excited for you! 🌟\nYou\'ve created something amazing here.';
      case 'Drill Sergeant':
        return 'Outstanding work, recruit!\nYou\'ve built a mission-ready plan.';
      case 'Southern Redneck':
        return 'Well butter my biscuit!\nYou just cooked up a fine plan there.';
      case 'Yoga Instructor':
        return 'Beautiful energy, beautiful plan.\nYou\'ve found your path to balance.';
      case 'British Butler':
        return 'I must say, quite impressive!\nYour plan is rather well-crafted indeed.';
      case 'Sports Commentator':
        return 'What a spectacular game plan!\nThis could be championship material!';
      case 'Cowboy/Cowgirl':
        return 'Well partner, you\'ve got yourself\na trail map worth ridin\'!';
      case 'Nature Lover':
        return 'Like a perfect sunrise,\nyour plan has natural beauty.';
      case 'Session Analyst':
        return 'Excellent optimization detected!\nYour plan shows strategic planning.';
      default:
        return 'This looks fantastic!\nYou\'ve created something special.';
    }
  }

  String _getPersonalizedEncouragement() {
    final personality = _selectedPersonality!;
    final why = _personalization!.why?.isNotEmpty == true
        ? _personalization!.why!.first
        : 'your goals';

    switch (personality.id) {
      case 'Supportive Friend':
        return 'I can see how much $why means to you, and honestly? You\'ve got this. This plan is going to help you feel stronger and more confident every single day.';
      case 'Drill Sergeant':
        return 'Listen up! You want $why? This plan will deliver results. No excuses, no shortcuts - just disciplined execution toward your objective.';
      case 'Southern Redneck':
        return 'Honey, when you\'re chasin\' $why, you need a plan tougher than a two-dollar steak. This here plan\'s gonna get you there faster than greased lightning!';
      case 'Yoga Instructor':
        return 'Your intention around $why is beautiful. This plan will help you flow toward that goal with mindful progress and inner strength.';
      case 'British Butler':
        return 'Your pursuit of $why is quite admirable, if I may say so. This plan shall serve you well on your journey to excellence.';
      case 'Sports Commentator':
        return 'Ladies and gentlemen, this athlete is going for $why! With this training plan, we could see some incredible performances ahead!';
      case 'Cowboy/Cowgirl':
        return 'Partner, when you\'re ridin\' toward $why, you need a steady horse and a clear trail. This plan\'s got both - now let\'s ride!';
      case 'Nature Lover':
        return 'Your connection to $why flows like a river toward the sea. This plan will guide you naturally toward that beautiful destination.';
      case 'Session Analyst':
        return 'Data shows strong correlation between structured planning and achieving $why. Your plan metrics indicate high probability of success.';
      default:
        return 'Your commitment to $why shows through in every choice you made. This plan will help you get there step by step.';
    }
  }

  String _getDynamicDuration() {
    // For Daily Discipline, use the actual streak days
    if (_selectedPlanType?.id == 'daily-discipline' &&
        _personalization?.customResponses != null) {
      final streakDays = _personalization!.customResponses!['streak_days'];
      if (streakDays != null && streakDays != 'custom') {
        return '$streakDays days';
      } else if (streakDays == 'custom' && _personalization!.customResponses!['custom_days'] != null) {
        final customDays = _personalization!.customResponses!['custom_days'];
        return '$customDays days';
      }
    }
    // For other plans, use the default duration
    return _selectedPlanType?.duration ?? '8 weeks';
  }

  String _getPersonalizedPlanSummary() {
    final personality = _selectedPersonality!;
    final planName = _selectedPlanType!.name;
    final days = _personalization!.trainingDaysPerWeek ?? 3;
    final minutes = _personalization!.minimumSessionMinutes ?? 30;

    switch (personality.id) {
      case 'Supportive Friend':
        return 'Here\'s what we\'re going to do together: $days days a week of $planName training, starting with just $minutes minutes. It\'s going to be so manageable, and I\'ll be cheering you on every step!';
      case 'Drill Sergeant':
        return 'Your mission: Execute $planName protocol $days days per week, minimum $minutes minutes per session. This is your commitment to excellence - no compromises!';
      case 'Southern Redneck':
        return 'Alright sugar, here\'s the deal: $days days a week we\'re gonna do this $planName business for at least $minutes minutes. Ain\'t gonna kill ya, and it\'s gonna make ya stronger than a garlic milkshake!';
      case 'Yoga Instructor':
        return 'We\'ll flow through $planName practice $days days each week, honoring at least $minutes minutes of mindful movement. Each session is a meditation in motion.';
      case 'British Butler':
        return 'Your regimen shall consist of $planName training $days days per week, with sessions of no less than $minutes minutes. Quite reasonable, I\'d say.';
      case 'Sports Commentator':
        return 'Here\'s the game plan: $planName training $days days a week, $minutes minutes minimum! This training schedule is built for champions!';
      case 'Cowboy/Cowgirl':
        return 'Here\'s how we\'re gonna ride this trail: $planName training $days days a week, spendin\' at least $minutes minutes in the saddle each time. Steady as she goes!';
      case 'Nature Lover':
        return 'We\'ll embrace $planName practice $days days each week, spending at least $minutes minutes connecting with your strength and the earth beneath your feet.';
      case 'Session Analyst':
        return 'Protocol: $planName training frequency of $days sessions weekly, minimum $minutes-minute duration per session. Optimal parameters for measurable progress.';
      default:
        return 'You\'ll be doing $planName training $days days per week, with each session lasting at least $minutes minutes. It\'s perfectly tailored to fit your life.';
    }
  }

  Widget _buildConversationalDetails() {
    final challenges =
        _personalization!.challenges?.join(' and ') ?? 'your busy schedule';
    final preferredDays =
        _personalization!.preferredDays?.join(', ') ?? 'flexible days';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _selectedPersonality!.color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.schedule,
                    color: _selectedPersonality!.color,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Your Schedule',
                    style: AppTextStyles.titleSmall.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _selectedPersonality!.color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'We\'ll focus on $preferredDays, working around $challenges. Everything\'s designed to fit your real life.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
        if (_personalization!.unloadedOk == true) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.directions_walk,
                  color: Colors.green[600],
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Great news! Since you\'re okay with unloaded sessions, we have extra flexibility for those busy days.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Colors.grey[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _getPersonalizedCallToAction() {
    final personality = _selectedPersonality!;

    switch (personality.id) {
      case 'Supportive Friend':
        return 'Ready to start this amazing journey together? I believe in you completely!';
      case 'Drill Sergeant':
        return 'Time to execute, soldier! Are you ready to earn your victory?';
      case 'Southern Redneck':
        return 'Time to quit yakkin\' and start walkin\'! You ready to get after it?';
      case 'Yoga Instructor':
        return 'Are you ready to step into this beautiful practice of strength and mindfulness?';
      case 'British Butler':
        return 'Shall we commence this rather excellent adventure in fitness?';
      case 'Sports Commentator':
        return 'The crowd is on their feet! Are you ready to take the field?';
      case 'Cowboy/Cowgirl':
        return 'Time to saddle up, partner! Ready to ride this trail to success?';
      case 'Nature Lover':
        return 'The path is calling you forward. Are you ready to walk with purpose?';
      case 'Session Analyst':
        return 'All systems optimized and ready for deployment. Shall we initiate the program?';
      default:
        return 'Everything\'s set up perfectly for you. Ready to begin?';
    }
  }

  String _getPersonalizedButtonText() {
    final personality = _selectedPersonality!;

    switch (personality.id) {
      case 'Supportive Friend':
        return 'Yes, let\'s do this together! 💪';
      case 'Drill Sergeant':
        return 'Sir, yes sir! Deploy the plan!';
      case 'Southern Redneck':
        return 'Heck yeah, let\'s get started!';
      case 'Yoga Instructor':
        return 'I\'m ready to begin this journey';
      case 'British Butler':
        return 'Indeed, let\'s proceed forthwith';
      case 'Sports Commentator':
        return 'Game time! Let\'s go!';
      case 'Cowboy/Cowgirl':
        return 'Saddle up - let\'s ride!';
      case 'Nature Lover':
        return 'I\'m ready to walk this path';
      case 'Session Analyst':
        return 'Initialize training protocol';
      default:
        return 'Yes, coach me through this plan!';
    }
  }
}
