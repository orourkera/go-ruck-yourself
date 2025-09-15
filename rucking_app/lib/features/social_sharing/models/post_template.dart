/// Post template styles for social media
enum PostTemplate {
  beastMode('beast_mode', 'Beast Mode', '💪'),
  journey('journey', 'Journey', '🌄'),
  community('community', 'Community', '👥');

  final String value;
  final String name;
  final String emoji;

  const PostTemplate(this.value, this.name, this.emoji);

  /// Get the full display name with emoji
  String get displayName => '$emoji $name';

  /// Get description for the template
  String get description {
    switch (this) {
      case PostTemplate.beastMode:
        return 'Intense and motivational - focus on PRs and crushing goals';
      case PostTemplate.journey:
        return 'Reflective and inspirational - tell your story';
      case PostTemplate.community:
        return 'Friendly and inclusive - connect with others';
    }
  }

  /// Get example opening lines for preview
  String get exampleOpening {
    switch (this) {
      case PostTemplate.beastMode:
        return 'DEMOLISHED my morning ruck! 💪🔥';
      case PostTemplate.journey:
        return 'Every step tells a story...';
      case PostTemplate.community:
        return 'Grateful for another amazing ruck with the crew!';
    }
  }
}