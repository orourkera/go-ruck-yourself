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
  late ConfettiController _confettiController;
  late Animation<double> _scaleAnimation;
  late PageController _pageController;
  
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
    
    _pageController = PageController();
    
    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));

    // Start animations
    _animationController.forward();
    _confettiController.play();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _confettiController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _dismiss() {
    widget.onDismiss?.call();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
              numberOfParticles: 30,
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
          
          // Close button
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: IconButton(
                  onPressed: _dismiss,
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 30,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withOpacity(0.5),
                  ),
                ),
              ),
            ),
          ),
          
          // Main content - Achievement Carousel
          Center(
            child: AnimatedBuilder(
              animation: _scaleAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Text(
                        widget.newAchievements.length > 1 
                          ? 'Achievements Unlocked!' 
                          : 'Achievement Unlocked!',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      
                      const SizedBox(height: 32.0),
                      
                      // Achievement cards carousel
                      SizedBox(
                        height: 450,
                        child: PageView.builder(
                          controller: _pageController,
                          onPageChanged: (index) {
                            setState(() {
                              _currentIndex = index;
                            });
                          },
                          itemCount: widget.newAchievements.length,
                          itemBuilder: (context, index) {
                            final achievement = widget.newAchievements[index];
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Card(
                                elevation: 8.0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20.0),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Achievement badge
                                      AchievementBadge(
                                        achievement: achievement,
                                        isEarned: true,
                                        size: 120.0,
                                      ),
                                      
                                      const SizedBox(height: 24.0),
                                      
                                      // Achievement details
                                      Text(
                                        achievement.name,
                                        style: theme.textTheme.titleLarge?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: _getCategoryColor(achievement),
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      
                                      const SizedBox(height: 12.0),
                                      
                                      Text(
                                        achievement.description,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      
                                      const SizedBox(height: 20.0),
                                      
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
                                      
                                      // Celebrate button
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          onPressed: _dismiss,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _getCategoryColor(achievement),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 16.0),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12.0),
                                            ),
                                          ),
                                          child: const Text(
                                            'Awesome!',
                                            style: TextStyle(
                                              fontSize: 16.0,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      
                      const SizedBox(height: 24.0),
                      
                      // Progress indicator for multiple achievements
                      if (widget.newAchievements.length > 1) ...
                        [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ...List.generate(
                                widget.newAchievements.length,
                                (index) => Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4.0),
                                  width: 10.0,
                                  height: 10.0,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: index == _currentIndex
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16.0),
                          Text(
                            'Swipe to see more achievements',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ),
                        ],
                    ],
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
