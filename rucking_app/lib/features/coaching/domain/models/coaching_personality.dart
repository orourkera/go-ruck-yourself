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

  // Pre-defined coaching personalities (matching AI cheerleader personalities)
  static const supportiveFriend = CoachingPersonality(
    id: 'Supportive Friend',
    name: 'Supportive Friend',
    description: 'Caring, supportive friend who\'s genuinely excited about their fitness journey. Warm, understanding, and always ready with encouragement.',
    example: 'You\'ve got this! Remember why you started - every step matters and I believe in you.',
    icon: Icons.favorite,
    color: Colors.pink,
  );

  static const drillSergeant = CoachingPersonality(
    id: 'Drill Sergeant',
    name: 'Drill Sergeant',
    description: 'Tough military drill sergeant who demands excellence. Uses firm, direct language to push you beyond your limits.',
    example: 'Drop and give me 20! No excuses today - you committed to this plan!',
    icon: Icons.military_tech,
    color: Colors.red,
  );

  static const southernRedneck = CoachingPersonality(
    id: 'Southern Redneck',
    name: 'Southern Redneck',
    description: 'Colorful Southern character with folksy wisdom and great sense of humor. Uses Southern expressions and country charm.',
    example: 'Well butter my biscuit, you\'re tougher than a two-dollar steak! Keep on truckin\'!',
    icon: Icons.agriculture,
    color: Colors.brown,
  );

  static const yogaInstructor = CoachingPersonality(
    id: 'Yoga Instructor',
    name: 'Yoga Instructor',
    description: 'Peaceful yoga instructor who emphasizes breath, mindfulness, and inner strength. See rucking as moving meditation.',
    example: 'Breathe into this challenge, find your center. Each step is a meditation in motion.',
    icon: Icons.self_improvement,
    color: Colors.purple,
  );

  static const britishButler = CoachingPersonality(
    id: 'British Butler',
    name: 'British Butler',
    description: 'Distinguished British butler with impeccable manners and dry wit. Encouragement with proper etiquette and subtle humor.',
    example: 'I do say, your performance today was rather exemplary. Shall we proceed with tomorrow\'s training?',
    icon: Icons.account_balance,
    color: Colors.indigo,
  );

  static const sportsCommentator = CoachingPersonality(
    id: 'Sports Commentator',
    name: 'Sports Commentator',
    description: 'Energetic sports commentator providing live coverage of your performance. Makes you feel like you\'re in the Olympics.',
    example: 'And there they go! What incredible form! The crowd is going wild for this phenomenal display!',
    icon: Icons.sports,
    color: Colors.orange,
  );

  static const cowboyCowgirl = CoachingPersonality(
    id: 'Cowboy/Cowgirl',
    name: 'Cowboy/Cowgirl',
    description: 'Rugged cowhand who sees rucking as trail riding preparation. Uses Western expressions and talks about grit.',
    example: 'Keep ridin\' toward that sunset, partner. You\'ve got the grit to make it through.',
    icon: Icons.landscape,
    color: Colors.amber,
  );

  static const natureLover = CoachingPersonality(
    id: 'Nature Lover',
    name: 'Nature Lover',
    description: 'Passionate nature lover who finds deep connection with the natural world. Gentle yet inspiring voice.',
    example: 'Feel the earth beneath your feet, breathe in that natural energy. You\'re part of something beautiful.',
    icon: Icons.eco,
    color: Colors.green,
  );

  static const sessionAnalyst = CoachingPersonality(
    id: 'Session Analyst',
    name: 'Session Analyst',
    description: 'Expert fitness analyst providing insightful analysis. Encouraging but analytical, highlighting specific accomplishments.',
    example: 'Your pace improved 12% this week. The data shows consistent heart rate efficiency gains.',
    icon: Icons.analytics,
    color: Colors.blue,
  );

  static const allPersonalities = [
    supportiveFriend,
    drillSergeant,
    southernRedneck,
    yogaInstructor,
    britishButler,
    sportsCommentator,
    cowboyCowgirl,
    natureLover,
    sessionAnalyst,
  ];
}