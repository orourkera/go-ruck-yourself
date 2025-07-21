import 'package:flutter/material.dart';

/// Well I'll be! This here's a blinking indicator showing folks are out rucking
class LiveRuckingIndicator extends StatefulWidget {
  final int activeRuckersCount;

  const LiveRuckingIndicator({
    super.key,
    required this.activeRuckersCount,
  });

  @override
  State<LiveRuckingIndicator> createState() => _LiveRuckingIndicatorState();
}

class _LiveRuckingIndicatorState extends State<LiveRuckingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _blinkController;
  late Animation<double> _blinkAnimation;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _blinkAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _blinkController,
      curve: Curves.easeInOut,
    ));

    // Start blinking if there are active ruckers
    if (widget.activeRuckersCount > 0) {
      _blinkController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(LiveRuckingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Start or stop blinking based on active ruckers
    if (widget.activeRuckersCount > 0 && oldWidget.activeRuckersCount == 0) {
      _blinkController.repeat(reverse: true);
    } else if (widget.activeRuckersCount == 0 && oldWidget.activeRuckersCount > 0) {
      _blinkController.stop();
      _blinkController.reset();
    }
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.activeRuckersCount == 0) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _blinkAnimation,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(_blinkAnimation.value), // Fade from transparent to fully opaque
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.green.withOpacity(_blinkAnimation.value),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.white, // White dot for contrast
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                widget.activeRuckersCount == 1
                    ? '1 rucker rucking now!'
                    : '${widget.activeRuckersCount} ruckers rucking now!',
                style: const TextStyle(
                  color: Colors.white, // White text for contrast against green background
                  fontFamily: 'Bangers', // Use Bangers font
                  fontSize: 14, // Slightly bigger for Bangers font
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
