/// String constants for notification types
class NotificationType {
  /// Like notification
  static const String like = 'like';

  /// Comment notification
  static const String comment = 'comment';

  /// Follow notification
  static const String follow = 'follow';

  /// System notification
  static const String system = 'system';

  /// Duel comment notification
  static const String duelComment = 'duel_comment';

  /// Duel invitation notification
  static const String duelInvitation = 'duel_invitation';

  /// Duel joined notification
  static const String duelJoined = 'duel_joined';

  /// Duel completed notification
  static const String duelCompleted = 'duel_completed';

  /// Duel progress notification (when participant completes a ruck)
  static const String duelProgress = 'duel_progress';

  /// Club event created notification
  static const String clubEventCreated = 'club_event_created';

  /// Club membership request notification
  static const String clubMembershipRequest = 'club_membership_request';

  /// Club membership approved notification
  static const String clubMembershipApproved = 'club_membership_approved';

  /// Club membership rejected notification
  static const String clubMembershipRejected = 'club_membership_rejected';

  /// Session completion prompt notification
  static const String sessionCompletionPrompt = 'session_completion_prompt';

  /// First ruck celebration notification for new users
  static const String firstRuckCelebration = 'first_ruck_celebration';

  /// First ruck global notification (sent to all users when someone completes their first ruck)
  static const String firstRuckGlobal = 'first_ruck_global';

  /// Ruck comment notification (when someone comments on your ruck)
  static const String ruckComment = 'ruck_comment';

  /// Ruck like notification (when someone likes your ruck)
  static const String ruckLike = 'ruck_like';

  /// Ruck activity notification (when someone interacts with a ruck you've also interacted with)
  static const String ruckActivity = 'ruck_activity';

  /// Achievement notification
  static const String achievement = 'achievement';
}
