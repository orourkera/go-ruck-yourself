import 'package:equatable/equatable.dart';

class EventProgress extends Equatable {
  final String id;
  final String eventId;
  final String userId;
  final int? ruckSessionId;
  final double totalDistance;
  final int totalTime;
  final int sessionCount;
  final DateTime lastUpdated;
  final EventProgressUser? user;

  const EventProgress({
    required this.id,
    required this.eventId,
    required this.userId,
    this.ruckSessionId,
    required this.totalDistance,
    required this.totalTime,
    required this.sessionCount,
    required this.lastUpdated,
    this.user,
  });

  factory EventProgress.fromJson(Map<String, dynamic> json) {
    return EventProgress(
      id: json['id'] as String? ?? '',
      eventId: json['event_id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      ruckSessionId: json['ruck_session_id'] as int?,
      totalDistance: (json['total_distance'] as num?)?.toDouble() ?? 0.0,
      totalTime: json['total_time'] as int? ?? 0,
      sessionCount: json['session_count'] as int? ?? 0,
      lastUpdated: DateTime.tryParse(json['last_updated'] as String? ?? '') ?? DateTime.now(),
      user: json['user'] != null 
          ? EventProgressUser.fromJson(json['user'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'event_id': eventId,
      'user_id': userId,
      'ruck_session_id': ruckSessionId,
      'total_distance': totalDistance,
      'total_time': totalTime,
      'session_count': sessionCount,
      'last_updated': lastUpdated.toIso8601String(),
      'user': user?.toJson(),
    };
  }

  // Computed properties
  double get averageDistance => sessionCount > 0 ? totalDistance / sessionCount : 0.0;
  double get averageTimeMinutes => sessionCount > 0 ? totalTime / sessionCount / 60.0 : 0.0;
  double get averagePaceMinutesPerKm => totalDistance > 0 ? (totalTime / 60.0) / totalDistance : 0.0;

  String get formattedTotalTime {
    final hours = (totalTime / 3600).floor();
    final minutes = ((totalTime % 3600) / 60).floor();
    final seconds = totalTime % 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  String get formattedTotalDistance {
    if (totalDistance >= 1000) {
      return '${(totalDistance / 1000).toStringAsFixed(1)} km';
    } else {
      return '${totalDistance.toStringAsFixed(0)} m';
    }
  }

  @override
  List<Object?> get props => [
        id,
        eventId,
        userId,
        ruckSessionId,
        totalDistance,
        totalTime,
        sessionCount,
        lastUpdated,
        user,
      ];
}

class EventProgressUser extends Equatable {
  final String id;
  final String username;
  final String? avatar;

  const EventProgressUser({
    required this.id,
    required this.username,
    this.avatar,
  });

  factory EventProgressUser.fromJson(Map<String, dynamic> json) {
    return EventProgressUser(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? 'Unknown User',
      avatar: json['avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'avatar': avatar,
    };
  }

  String get fullName => username.isNotEmpty ? username : 'Unknown User';

  @override
  List<Object?> get props => [id, username, avatar];
}

class EventLeaderboard extends Equatable {
  final String eventId;
  final List<EventProgress> entries;
  final DateTime lastUpdated;

  const EventLeaderboard({
    required this.eventId,
    required this.entries,
    required this.lastUpdated,
  });

  factory EventLeaderboard.fromJson(Map<String, dynamic> json) {
    return EventLeaderboard(
      eventId: json['event_id'] as String? ?? '',
      entries: (json['entries'] as List<dynamic>?)
          ?.map((entry) => EventProgress.fromJson(entry as Map<String, dynamic>))
          .toList() ?? [],
      lastUpdated: DateTime.tryParse(json['last_updated'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'event_id': eventId,
      'entries': entries.map((e) => e.toJson()).toList(),
      'last_updated': lastUpdated.toIso8601String(),
    };
  }

  // Get sorted leaderboard by distance
  List<EventProgress> get leaderboardByDistance {
    final sorted = List<EventProgress>.from(entries);
    sorted.sort((a, b) => b.totalDistance.compareTo(a.totalDistance));
    return sorted;
  }

  // Get sorted leaderboard by time
  List<EventProgress> get leaderboardByTime {
    final sorted = List<EventProgress>.from(entries);
    sorted.sort((a, b) => b.totalTime.compareTo(a.totalTime));
    return sorted;
  }

  // Get sorted leaderboard by session count
  List<EventProgress> get leaderboardBySessionCount {
    final sorted = List<EventProgress>.from(entries);
    sorted.sort((a, b) => b.sessionCount.compareTo(a.sessionCount));
    return sorted;
  }

  // Get user's rank in distance leaderboard
  int getUserRankByDistance(String userId) {
    final sorted = leaderboardByDistance;
    return sorted.indexWhere((entry) => entry.userId == userId) + 1;
  }

  // Get user's entry
  EventProgress? getUserProgress(String userId) {
    try {
      return entries.firstWhere((entry) => entry.userId == userId);
    } catch (e) {
      return null;
    }
  }

  @override
  List<Object?> get props => [eventId, entries, lastUpdated];
}
