import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
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
import 'package:rucking_app/features/coaching/presentation/widgets/personalization_questions.dart';
import 'package:rucking_app/features/coaching/data/services/coaching_service.dart';

enum PlanCreationStep {
  greeting,
  goalSelection,
  personalization,
  planPreview,
  personalitySelection,
  commitment,
  creating,
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
  CoachingPlanType? _selectedPlanType;
  CoachingPersonality? _selectedPersonality;
  PlanPersonalization? _personalization;
  
  late OpenAIResponsesService _openAiService;
  late CoachingService _coachingService;

  // Define the 6 coaching plan types
  final List<CoachingPlanType> _planTypes = [
    CoachingPlanType(
      id: 'fat-loss',
      name: 'Fat Loss & Feel Better',
      description: 'Build a steady calorie deficit and improve everyday energy with low-impact, progressive rucking plus complementary cardio/strength. We keep it safe, sustainable, and data-driven—no crash tactics.',
      duration: '12 weeks',
      icon: Icons.favorite,
      color: Colors.red,
      emoji: '❤️',
    ),
    CoachingPlanType(
      id: 'get-faster',
      name: 'Get Faster at Rucking',
      description: 'Improve your 60-minute ruck pace at a fixed load using aerobic base, controlled tempo work, and smart hills—without trashing your legs.',
      duration: '10 weeks',
      icon: Icons.speed,
      color: Colors.blue,
      emoji: '⚡',
    ),
    CoachingPlanType(
      id: 'event-prep',
      name: '12-Mile Under 3:00',
      description: 'Arrive prepared for your event with focused quality sessions, a long-ruck progression, and a taper that respects your feet and recovery.',
      duration: '16 weeks',
      icon: Icons.flag,
      color: Colors.orange,
      emoji: '🏁',
    ),
    CoachingPlanType(
      id: 'daily-discipline',
      name: 'Daily Discipline Streak',
      description: 'Build an unbreakable habit with bite-size sessions, flexible scheduling, and gentle accountability—movement every day, without overuse.',
      duration: '8 weeks',
      icon: Icons.calendar_today,
      color: Colors.green,
      emoji: '🗓️',
    ),
    CoachingPlanType(
      id: 'age-strong',
      name: 'Posture/Balance & Age-Strong',
      description: 'Move taller and steadier with light loaded walks plus simple balance/strength work that supports joints and confidence.',
      duration: '12 weeks',
      icon: Icons.accessibility_new,
      color: Colors.purple,
      emoji: '🧘',
    ),
    CoachingPlanType(
      id: 'load-capacity',
      name: 'Load Capacity Builder',
      description: 'Safely increase how much weight you can carry. We progress one knob at a time (time → hills → small load bumps) with readiness checks so feet, knees, and back adapt without flare-ups.',
      duration: '14 weeks',
      icon: Icons.fitness_center,
      color: Colors.brown,
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
    final username = authState is Authenticated ? authState.user.username : 'Rucker';

    try {
      await _openAiService.stream(
        model: 'o3-mini',
        instructions: 'You are a friendly, enthusiastic AI fitness coach for a rucking app. Your job is to greet users warmly and get them excited about creating a training plan.',
        input: 'Greet the user named "$username" and ask them what kind of goal they want to set. Keep it brief, friendly, and motivating. End with asking what kind of goal they want to set.',
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
            });
            
            // After greeting is complete, show goal selection buttons
            Future.delayed(const Duration(milliseconds: 1000), () {
              if (mounted) {
                setState(() {
                  _currentStep = PlanCreationStep.goalSelection;
                });
              }
            });
          }
        },
        onError: (error) {
          AppLogger.error('[PLAN_CREATION] Streaming error: $error');
          if (mounted) {
            setState(() {
              _isStreaming = false;
              _streamingText = "Hi $username! I'm your AI coach, and I'm excited to help you create the perfect rucking plan. What kind of goal do you want to set?";
              _currentStep = PlanCreationStep.goalSelection;
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
          _streamingText = "Hi $username! I'm your AI coach, and I'm excited to help you create the perfect rucking plan. What kind of goal do you want to set?";
          _currentStep = PlanCreationStep.goalSelection;
        });
      }
    }
  }

  void _onPlanTypeSelected(CoachingPlanType planType) {
    setState(() {
      _selectedPlanType = planType;
      _currentStep = PlanCreationStep.personalization;
    });
  }

  void _onPersonalizationComplete(PlanPersonalization personalization) {
    setState(() {
      _personalization = personalization;
      _currentStep = PlanCreationStep.planPreview;
    });
  }

  void _onPersonalitySelected(CoachingPersonality personality) {
    setState(() {
      _selectedPersonality = personality;
      _currentStep = PlanCreationStep.commitment;
    });
  }

  void _onCommitToPlan() async {
    if (_selectedPlanType == null || _selectedPersonality == null || _personalization == null) {
      AppLogger.error('Missing required data for plan creation');
      return;
    }

    setState(() {
      _currentStep = PlanCreationStep.creating;
    });
    
    try {
      // Create the personalized coaching plan via API
      final planData = await _coachingService.createCoachingPlan(
        basePlanId: _selectedPlanType!.id,
        coachingPersonality: _selectedPersonality!.id,
        personalization: _personalization!,
      );
      
      AppLogger.info('Successfully created coaching plan: ${planData['coaching_plan']['id']}');
      
      if (mounted) {
        setState(() {
          _currentStep = PlanCreationStep.complete;
        });
        
        // Navigate back with success after a brief delay
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.of(context).pop(true);
          }
        });
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
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: _currentStep != PlanCreationStep.greeting && 
              _currentStep != PlanCreationStep.creating &&
              _currentStep != PlanCreationStep.complete
          ? AppBar(
              title: const Text('AI Coaching Plan'),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _onBackPressed,
              ),
            )
          : null,
      body: SafeArea(
        child: _buildCurrentStep(),
      ),
    );
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
      case PlanCreationStep.complete:
        return _buildCompleteStep();
    }
  }

  Widget _buildGreetingStep() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // AI Coach avatar
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: const Icon(
                Icons.psychology,
                size: 60,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 32),
            
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
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
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
          ],
        ),
      ),
    );
  }

  Widget _buildGoalSelectionStep() {
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
    );
  }

  Widget _buildPlanPreviewStep() {
    if (_selectedPlanType == null || _personalization == null) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Personalized Plan',
            style: AppTextStyles.headlineMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  PlanPreviewCard(planType: _selectedPlanType!),
                  const SizedBox(height: 16),
                  
                  // Personalization summary
                  Card(
                    elevation: 2,
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
                                Icons.person,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Your Personalization',
                                style: AppTextStyles.titleMedium.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          _buildPersonalizationSummaryItem('Why', _personalization!.why ?? ''),
                          _buildPersonalizationSummaryItem('Success Looks Like', _personalization!.successDefinition ?? ''),
                          _buildPersonalizationSummaryItem('Training Days', '${_personalization!.trainingDaysPerWeek ?? 0} days per week'),
                          _buildPersonalizationSummaryItem('Preferred Days', _personalization!.preferredDays?.join(', ') ?? ''),
                          _buildPersonalizationSummaryItem('Challenges to Overcome', _personalization!.challenges?.join(', ') ?? ''),
                          _buildPersonalizationSummaryItem('Minimum Session', '${_personalization!.minimumSessionMinutes ?? 0} minutes${(_personalization!.unloadedOk ?? false) ? ' (unloaded OK)' : ''}'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _currentStep = PlanCreationStep.personalitySelection;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Perfect! Let\'s choose coaching style',
                style: AppTextStyles.titleMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalizationSummaryItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: AppTextStyles.bodySmall.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalitySelectionStep() {
    return Padding(
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
          
          Expanded(
            child: PersonalitySelector(
              onPersonalitySelected: _onPersonalitySelected,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommitmentStep() {
    if (_selectedPlanType == null || _selectedPersonality == null || _personalization == null) {
      return const SizedBox.shrink();
    }
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ready to Start?',
            style: AppTextStyles.headlineMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Here\'s your personalized plan summary:',
            style: AppTextStyles.bodyLarge.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Plan Type Card
                  Container(
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _selectedPlanType!.emoji,
                              style: const TextStyle(fontSize: 32),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedPlanType!.name,
                                    style: AppTextStyles.titleLarge.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    _selectedPlanType!.duration,
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _selectedPersonality!.color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _selectedPersonality!.icon,
                                color: _selectedPersonality!.color,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${_selectedPersonality!.name} Coaching Style',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: _selectedPersonality!.color,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Personalization Summary Card
                  Container(
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.person,
                              color: AppColors.primary,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Your Personalization',
                              style: AppTextStyles.titleMedium.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        if (_personalization!.why != null)
                          _buildPersonalizationItem(
                            'Your Why',
                            _personalization!.why!,
                          ),
                        
                        if (_personalization!.successDefinition != null)
                          _buildPersonalizationItem(
                            'Success Definition',
                            _personalization!.successDefinition!,
                          ),
                        
                        if (_personalization!.trainingDaysPerWeek != null)
                          _buildPersonalizationItem(
                            'Training Days',
                            '${_personalization!.trainingDaysPerWeek} days per week',
                          ),
                        
                        if (_personalization!.preferredDays != null && _personalization!.preferredDays!.isNotEmpty)
                          _buildPersonalizationItem(
                            'Preferred Days',
                            _personalization!.preferredDays!.join(', '),
                          ),
                        
                        if (_personalization!.challenges != null && _personalization!.challenges!.isNotEmpty)
                          _buildPersonalizationItem(
                            'Key Challenges',
                            _personalization!.challenges!.join(', '),
                          ),
                        
                        if (_personalization!.minimumSessionMinutes != null)
                          _buildPersonalizationItem(
                            'Minimum Session',
                            '${_personalization!.minimumSessionMinutes} minutes${_personalization!.unloadedOk == true ? " (unloaded OK)" : ""}',
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _onCommitToPlan,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Yes, coach me through this plan!',
                style: AppTextStyles.titleMedium,
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

  Widget _buildCompleteStep() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.withOpacity(0.1),
            ),
            child: Icon(
              Icons.check_circle,
              size: 60,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Your plan is ready!',
            style: AppTextStyles.headlineMedium.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Check your homepage for personalized insights and your next session recommendation.',
            style: AppTextStyles.bodyLarge.copyWith(
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}