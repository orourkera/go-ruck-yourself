import 'package:flutter/material.dart';
import 'package:rucking_app/features/achievements/data/models/achievement_model.dart';
import 'package:rucking_app/features/achievements/presentation/widgets/achievement_badge.dart';
import 'package:confetti/confetti.dart';

class AchievementUnlockPopup extends StatefulWidget {
  final List<Achievement> newAchievements;
  final VoidCallback? onDismiss;

  const AchievementUnlockPopup({
    super.key,
    required this.newAchievements,
    this.onDismiss,
  });

  @override
  State<AchievementUnlockPopup> createState() => _AchievementUnlockPopupState();
}

class _AchievementUnlockPopupState extends State<AchievementUnlockPopup>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _slideController;
  late ConfettiController _confettiController;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;
  
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 2),
    );
    
    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeInOut,
    ));

    // Start animations
    _animationController.forward();
    _confettiController.play();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _slideController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  void _nextAchievement() {
    if (_currentIndex < widget.newAchievements.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _slideController.forward().then((_) {
        _slideController.reset();
      });
    } else {
      _dismiss();
    }
  }

  void _dismiss() {
    widget.onDismiss?.call();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final achievement = widget.newAchievements[_currentIndex];
    final isLastAchievement = _currentIndex == widget.newAchievements.length - 1;

    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.8),
      body: Stack(
        children: [
          // Confetti
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirection: 1.5708, // Pi/2 - downward
              emissionFrequency: 0.05,
              numberOfParticles: 20,
              gravity: 0.1,
              shouldLoop: false,
              colors: const [
                Colors.yellow,
                Colors.orange,
                Colors.red,
                Colors.blue,
                Colors.green,
                Colors.purple,
              ],
            ),
          ),
          
          // Main content
          Center(
            child: AnimatedBuilder(
              animation: _scaleAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Card(
                    margin: const EdgeInsets.all(32.0),
                    elevation: 8.0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20.0),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(24.0),
                      constraints: const BoxConstraints(maxWidth: 350.0),
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Header
                            Text(
                              'Achievement Unlocked!',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: _getCategoryColor(achievement),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            
                            const SizedBox(height: 24.0),
                            
                            // Achievement badge
                            AchievementBadge(
                              achievement: achievement,
                              isEarned: true,
                              size: 100.0,
                            ),
                            
                            const SizedBox(height: 24.0),
                            
                            // Achievement details
                            Text(
                              achievement.name,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            
                            const SizedBox(height: 8.0),
                            
                            Text(
                              achievement.description,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            
                            const SizedBox(height: 16.0),
                            
                            // Tier chip
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 8.0,
                              ),
                              decoration: BoxDecoration(
                                color: _getTierColor(achievement),
                                borderRadius: BorderRadius.circular(20.0),
                              ),
                              child: Text(
                                '${achievement.tier.toUpperCase()} TIER',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            
                            const SizedBox(height: 24.0),
                            
                            // Progress indicator
                            if (widget.newAchievements.length > 1)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(
                                  widget.newAchievements.length,
                                  (index) => Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 4.0),
                                    width: 8.0,
                                    height: 8.0,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: index == _currentIndex
                                          ? _getCategoryColor(achievement)
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                ),
                              ),
                            
                            if (widget.newAchievements.length > 1)
                              const SizedBox(height: 24.0),
                            
                            // Action buttons
                            Row(
                              children: [
                                if (!isLastAchievement)
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _dismiss,
                                      child: const Text('Skip'),
                                    ),
                                  ),
                                
                                if (!isLastAchievement)
                                  const SizedBox(width: 16.0),
                                
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _nextAchievement,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _getCategoryColor(achievement),
                                      foregroundColor: Colors.white,
                                    ),
                                    child: Text(
                                      isLastAchievement ? 'Awesome!' : 'Next',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _getCategoryColor(Achievement achievement) {
    switch (achievement.category.toLowerCase()) {
      case 'distance':
        return Colors.blue;
      case 'weight':
        return Colors.red;
      case 'power':
        return Colors.orange;
      case 'pace':
        return Colors.green;
      case 'time':
        return Colors.purple;
      case 'consistency':
        return Colors.teal;
      case 'special':
        return Colors.pink;
      default:
        return Colors.grey;
    }
  }

  Color _getTierColor(Achievement achievement) {
    switch (achievement.tier.toLowerCase()) {
      case 'bronze':
        return const Color(0xFFCD7F32);
      case 'silver':
        return const Color(0xFFC0C0C0);
      case 'gold':
        return const Color(0xFFFFD700);
      case 'platinum':
        return const Color(0xFFE5E4E2);
      default:
        return Colors.grey;
    }
  }
}
