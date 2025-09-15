/// Time range options for social media posts
enum TimeRange {
  lastRuck('last_ruck', 'My Last Ruck'),
  week('week', 'This Week'),
  month('month', 'This Month'),
  allTime('all_time', 'Since I Started');

  final String value;
  final String displayName;

  const TimeRange(this.value, this.displayName);

  /// Get icon for the time range
  String get icon {
    switch (this) {
      case TimeRange.lastRuck:
        return '🎯';
      case TimeRange.week:
        return '📅';
      case TimeRange.month:
        return '📆';
      case TimeRange.allTime:
        return '🚀';
    }
  }

  /// Get description for the time range
  String get description {
    switch (this) {
      case TimeRange.lastRuck:
        return 'Share details from your most recent ruck';
      case TimeRange.week:
        return 'Summarize your weekly progress';
      case TimeRange.month:
        return 'Showcase your monthly achievements';
      case TimeRange.allTime:
        return 'Tell your complete rucking journey';
    }
  }
}