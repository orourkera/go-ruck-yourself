import 'leaderboard_user_model.dart';

/// Well I'll be! This here's the leaderboard response model
class LeaderboardResponseModel {
  final List<LeaderboardUserModel> users;
  final int total;
  final bool hasMore;
  final int activeRuckersCount;

  const LeaderboardResponseModel({
    required this.users,
    required this.total,
    required this.hasMore,
    required this.activeRuckersCount,
  });

  factory LeaderboardResponseModel.fromJson(Map<String, dynamic> json) {
    final List<dynamic> usersJson = json['users'] ?? [];

    return LeaderboardResponseModel(
      users: usersJson
          .map((userJson) => LeaderboardUserModel.fromJson(userJson))
          .toList(),
      total: json['total'] ?? 0,
      hasMore: json['hasMore'] ?? false,
      activeRuckersCount: json['activeRuckersCount'] ?? 0,
    );
  }
}
