import 'package:flutter/material.dart';

/// An animated counter widget that counts up from 0 to a target value
class AnimatedCounter extends StatefulWidget {
  final int targetValue;
  final Duration duration;
  final TextStyle? textStyle;
  final String suffix;
  final bool autoStart;

  const AnimatedCounter({
    Key? key,
    required this.targetValue,
    this.duration = const Duration(milliseconds: 1500),
    this.textStyle,
    this.suffix = '',
    this.autoStart = true,
  }) : super(key: key);

  @override
  State<AnimatedCounter> createState() => _AnimatedCounterState();
}

class _AnimatedCounterState extends State<AnimatedCounter>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _scaleController;
  late Animation<double> _animation;
  late Animation<double> _scaleAnimation;
  int _currentValue = 0;

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _scaleController = AnimationController(
      duration: Duration(milliseconds: widget.duration.inMilliseconds + 300),
      vsync: this,
    );

    _animation = Tween<double>(
      begin: 0.0,
      end: widget.targetValue.toDouble(),
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    // Scale animation - grows to 1.3x, then back to 1.0
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.3)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 60.0,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.3, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 40.0,
      ),
    ]).animate(_scaleController);

    _animation.addListener(() {
      setState(() {
        _currentValue = _animation.value.round();
      });
    });

    if (widget.autoStart) {
      // Add a small delay to make the animation more noticeable
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _controller.forward();
          _scaleController.forward();
        }
      });
    }
  }

  @override
  void didUpdateWidget(AnimatedCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (oldWidget.targetValue != widget.targetValue) {
      _animation = Tween<double>(
        begin: _currentValue.toDouble(),
        end: widget.targetValue.toDouble(),
      ).animate(CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ));
      
      _controller.reset();
      _scaleController.reset();
      if (widget.autoStart) {
        _controller.forward();
        _scaleController.forward();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  void startAnimation() {
    if (!_controller.isAnimating) {
      _controller.reset();
      _scaleController.reset();
      _controller.forward();
      _scaleController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_animation, _scaleAnimation]),
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Text(
            '$_currentValue${widget.suffix}',
            style: widget.textStyle,
          ),
        );
      },
    );
  }
}
