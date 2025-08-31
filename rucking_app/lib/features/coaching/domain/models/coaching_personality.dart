import 'package:flutter/material.dart';

class CoachingPersonality {
  final String id;
  final String name;
  final String description;
  final String example;
  final IconData icon;
  final Color color;

  const CoachingPersonality({
    required this.id,
    required this.name,
    required this.description,
    required this.example,
    required this.icon,
    required this.color,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CoachingPersonality &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  // Pre-defined coaching personalities
  static const drillSergeant = CoachingPersonality(
    id: 'drill-sergeant',
    name: 'Drill Sergeant',
    description: 'Direct, challenging, no-nonsense coaching',
    example: 'Drop and give me 20! No excuses today - you committed to this plan!',
    icon: Icons.military_tech,
    color: Colors.red,
  );

  static const supportiveFriend = CoachingPersonality(
    id: 'supportive-friend',
    name: 'Supportive Friend',
    description: 'Encouraging, empathetic, understanding',
    example: 'You\'ve got this! Remember why you started - every step matters.',
    icon: Icons.favorite,
    color: Colors.pink,
  );

  static const dataNerd = CoachingPersonality(
    id: 'data-nerd',
    name: 'Data Nerd',
    description: 'Analytical, metrics-focused, optimization-oriented',
    example: 'Your pace improved 12% this week based on heart rate zones. Let\'s dial in your Zone 2 training.',
    icon: Icons.analytics,
    color: Colors.blue,
  );

  static const minimalist = CoachingPersonality(
    id: 'minimalist',
    name: 'Minimalist',
    description: 'Brief, actionable, efficient guidance',
    example: '2.5 miles. 20 lbs. Go.',
    icon: Icons.remove_circle_outline,
    color: Colors.grey,
  );

  static const allPersonalities = [
    drillSergeant,
    supportiveFriend,
    dataNerd,
    minimalist,
  ];
}