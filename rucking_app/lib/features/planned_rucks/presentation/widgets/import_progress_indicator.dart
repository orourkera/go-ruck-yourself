import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Widget for showing import progress with animated indicators
class ImportProgressIndicator extends StatefulWidget {
  final String message;
  final double? progress; // 0.0 to 1.0
  final bool isIndeterminate;

  const ImportProgressIndicator({
    super.key,
    required this.message,
    this.progress,
    this.isIndeterminate = false,
  });

  @override
  State<ImportProgressIndicator> createState() =>
      _ImportProgressIndicatorState();
}

class _ImportProgressIndicatorState extends State<ImportProgressIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.05),
          border: Border(
            bottom: BorderSide(
              color: AppColors.primary.withOpacity(0.1),
              width: 1,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress bar
            if (widget.progress != null)
              _buildDeterminateProgress()
            else
              _buildIndeterminateProgress(),

            const SizedBox(height: 12),

            // Progress message
            Text(
              widget.message,
              style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),

            // Progress percentage
            if (widget.progress != null) ...[
              const SizedBox(height: 4),
              Text(
                '${(widget.progress! * 100).toInt()}%',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.primary.withOpacity(0.8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeterminateProgress() {
    return Container(
      height: 4,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.2),
        borderRadius: BorderRadius.circular(2),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: widget.progress ?? 0.0,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _buildIndeterminateProgress() {
    return SizedBox(
      height: 4,
      width: double.infinity,
      child: LinearProgressIndicator(
        backgroundColor: AppColors.primary.withOpacity(0.2),
        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
      ),
    );
  }
}

/// Circular progress indicator with steps
class SteppedProgressIndicator extends StatefulWidget {
  final List<String> steps;
  final int currentStep;
  final bool isLoading;

  const SteppedProgressIndicator({
    super.key,
    required this.steps,
    required this.currentStep,
    this.isLoading = false,
  });

  @override
  State<SteppedProgressIndicator> createState() =>
      _SteppedProgressIndicatorState();
}

class _SteppedProgressIndicatorState extends State<SteppedProgressIndicator>
    with TickerProviderStateMixin {
  late AnimationController _progressController;
  late AnimationController _pulseController;
  late Animation<double> _progressAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _progressAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeInOut,
    ));

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _updateProgress();
    if (widget.isLoading) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(SteppedProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentStep != widget.currentStep) {
      _updateProgress();
    }
    if (widget.isLoading && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isLoading && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _updateProgress() {
    final progress = widget.currentStep / (widget.steps.length - 1);
    _progressController.animateTo(progress);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Circular progress
          AnimatedBuilder(
            animation: Listenable.merge([_progressAnimation, _pulseAnimation]),
            builder: (context, child) {
              return Transform.scale(
                scale: widget.isLoading ? _pulseAnimation.value : 1.0,
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    value: _progressAnimation.value,
                    backgroundColor: AppColors.primary.withOpacity(0.2),
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.primary),
                    strokeWidth: 6,
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 20),

          // Current step
          Text(
            widget.currentStep < widget.steps.length
                ? widget.steps[widget.currentStep]
                : 'Complete',
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 8),

          // Step counter
          Text(
            'Step ${widget.currentStep + 1} of ${widget.steps.length}',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textDarkSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact progress indicator for smaller spaces
class CompactProgressIndicator extends StatelessWidget {
  final String message;
  final double? progress;

  const CompactProgressIndicator({
    super.key,
    required this.message,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: progress,
              backgroundColor: AppColors.primary.withOpacity(0.3),
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            message,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (progress != null) ...[
            const SizedBox(width: 8),
            Text(
              '${(progress! * 100).toInt()}%',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.primary.withOpacity(0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Progress indicator with custom icon
class IconProgressIndicator extends StatefulWidget {
  final IconData icon;
  final String message;
  final Color? color;
  final bool isAnimating;

  const IconProgressIndicator({
    super.key,
    required this.icon,
    required this.message,
    this.color,
    this.isAnimating = true,
  });

  @override
  State<IconProgressIndicator> createState() => _IconProgressIndicatorState();
}

class _IconProgressIndicatorState extends State<IconProgressIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_animationController);

    if (widget.isAnimating) {
      _animationController.repeat();
    }
  }

  @override
  void didUpdateWidget(IconProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAnimating && !_animationController.isAnimating) {
      _animationController.repeat();
    } else if (!widget.isAnimating && _animationController.isAnimating) {
      _animationController.stop();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppColors.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _rotationAnimation,
            builder: (context, child) {
              return Transform.rotate(
                angle: widget.isAnimating
                    ? _rotationAnimation.value * 2 * 3.14159
                    : 0,
                child: Icon(
                  widget.icon,
                  size: 48,
                  color: color,
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            widget.message,
            style: AppTextStyles.bodyLarge.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
