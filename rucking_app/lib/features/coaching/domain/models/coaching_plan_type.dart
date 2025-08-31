import 'package:flutter/material.dart';

class CoachingPlanType {
  final String id;
  final String name;
  final String description;
  final String duration;
  final IconData icon;
  final Color color;
  final String emoji;

  const CoachingPlanType({
    required this.id,
    required this.name,
    required this.description,
    required this.duration,
    required this.icon,
    required this.color,
    required this.emoji,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CoachingPlanType &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}