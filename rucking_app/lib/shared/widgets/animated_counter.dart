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
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  int _currentValue = 0;

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _animation = Tween<double>(
      begin: 0.0,
      end: widget.targetValue.toDouble(),
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

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
      if (widget.autoStart) {
        _controller.forward();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void startAnimation() {
    if (!_controller.isAnimating) {
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Text(
          '$_currentValue${widget.suffix}',
          style: widget.textStyle,
        );
      },
    );
  }
}
