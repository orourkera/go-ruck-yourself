class Achievement {
  final String id;
  final String achievementKey;
  final String name;
  final String description;
  final String category;
  final String tier;
  final Map<String, dynamic> criteria;
  final String iconName;
  final bool isActive;
  final String? unitPreference; // null = universal, 'metric' or 'standard'
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Achievement({
    required this.id,
    required this.achievementKey,
    required this.name,
    required this.description,
    required this.category,
    required this.tier,
    required this.criteria,
    required this.iconName,
    required this.isActive,
    this.unitPreference,
    this.createdAt,
    this.updatedAt,
  });

  factory Achievement.fromJson(Map<String, dynamic> json) {
    return Achievement(
      id: json['id']?.toString() ?? '',
      achievementKey: json['achievement_key'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      category: json['category'] ?? '',
      tier: json['tier'] ?? '',
      criteria: json['criteria'] as Map<String, dynamic>? ?? {},
      iconName: json['icon_name'] ?? '',
      isActive: json['is_active'] ?? true,
      unitPreference: json['unit_preference'],
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'achievement_key': achievementKey,
      'name': name,
      'description': description,
      'category': category,
      'tier': tier,
      'criteria': criteria,
      'icon_name': iconName,
      'is_active': isActive,
      'unit_preference': unitPreference,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Achievement copyWith({
    String? id,
    String? achievementKey,
    String? name,
    String? description,
    String? category,
    String? tier,
    Map<String, dynamic>? criteria,
    String? iconName,
    bool? isActive,
    String? unitPreference,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Achievement(
      id: id ?? this.id,
      achievementKey: achievementKey ?? this.achievementKey,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      tier: tier ?? this.tier,
      criteria: criteria ?? this.criteria,
      iconName: iconName ?? this.iconName,
      isActive: isActive ?? this.isActive,
      unitPreference: unitPreference ?? this.unitPreference,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Achievement &&
        other.id == id &&
        other.achievementKey == achievementKey &&
        other.name == name &&
        other.description == description &&
        other.category == category &&
        other.tier == tier &&
        other.iconName == iconName &&
        other.isActive == isActive &&
        other.unitPreference == unitPreference;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        achievementKey.hashCode ^
        name.hashCode ^
        description.hashCode ^
        category.hashCode ^
        tier.hashCode ^
        iconName.hashCode ^
        isActive.hashCode ^
        unitPreference.hashCode;
  }

  @override
  String toString() {
    return 'Achievement(id: $id, name: $name, category: $category, tier: $tier)';
  }
}

class UserAchievement {
  final String id;
  final String userId;
  final String achievementId;
  final int? sessionId;
  final DateTime earnedAt;
  final Map<String, dynamic>? metadata;
  final Achievement? achievement;

  const UserAchievement({
    required this.id,
    required this.userId,
    required this.achievementId,
    this.sessionId,
    required this.earnedAt,
    this.metadata,
    this.achievement,
  });

  factory UserAchievement.fromJson(Map<String, dynamic> json) {
    return UserAchievement(
      id: json['id']?.toString() ?? '',
      userId: json['user_id'] ?? '',
      achievementId: json['achievement_id']?.toString() ?? '',
      sessionId: json['session_id'],
      earnedAt: DateTime.parse(json['earned_at']),
      metadata: json['metadata'] as Map<String, dynamic>?,
      achievement: json['achievements'] != null 
          ? Achievement.fromJson(json['achievements']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'achievement_id': achievementId,
      'session_id': sessionId,
      'earned_at': earnedAt.toIso8601String(),
      'metadata': metadata,
      'achievements': achievement?.toJson(),
    };
  }

  UserAchievement copyWith({
    String? id,
    String? userId,
    String? achievementId,
    int? sessionId,
    DateTime? earnedAt,
    Map<String, dynamic>? metadata,
    Achievement? achievement,
  }) {
    return UserAchievement(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      achievementId: achievementId ?? this.achievementId,
      sessionId: sessionId ?? this.sessionId,
      earnedAt: earnedAt ?? this.earnedAt,
      metadata: metadata ?? this.metadata,
      achievement: achievement ?? this.achievement,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserAchievement &&
        other.id == id &&
        other.userId == userId &&
        other.achievementId == achievementId &&
        other.sessionId == sessionId &&
        other.earnedAt == earnedAt;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        userId.hashCode ^
        achievementId.hashCode ^
        sessionId.hashCode ^
        earnedAt.hashCode;
  }

  @override
  String toString() {
    return 'UserAchievement(id: $id, achievementId: $achievementId, earnedAt: $earnedAt)';
  }
}

class AchievementProgress {
  final String id;
  final String userId;
  final String achievementId;
  final double currentValue;
  final double targetValue;
  final DateTime lastUpdated;
  final Map<String, dynamic>? metadata;
  final Achievement? achievement;

  const AchievementProgress({
    required this.id,
    required this.userId,
    required this.achievementId,
    required this.currentValue,
    required this.targetValue,
    required this.lastUpdated,
    this.metadata,
    this.achievement,
  });

  double get progressPercentage {
    if (targetValue <= 0) return 0.0;
    return (currentValue / targetValue * 100).clamp(0.0, 100.0);
  }

  bool get isCompleted => currentValue >= targetValue;

  factory AchievementProgress.fromJson(Map<String, dynamic> json) {
    return AchievementProgress(
      id: json['id']?.toString() ?? '',
      userId: json['user_id'] ?? '',
      achievementId: json['achievement_id']?.toString() ?? '',
      currentValue: (json['current_value'] ?? 0).toDouble(),
      targetValue: (json['target_value'] ?? 0).toDouble(),
      lastUpdated: DateTime.parse(json['last_updated']),
      metadata: json['metadata'] as Map<String, dynamic>?,
      achievement: json['achievements'] != null 
          ? Achievement.fromJson(json['achievements']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'achievement_id': achievementId,
      'current_value': currentValue,
      'target_value': targetValue,
      'last_updated': lastUpdated.toIso8601String(),
      'metadata': metadata,
      'achievements': achievement?.toJson(),
    };
  }

  AchievementProgress copyWith({
    String? id,
    String? userId,
    String? achievementId,
    double? currentValue,
    double? targetValue,
    DateTime? lastUpdated,
    Map<String, dynamic>? metadata,
    Achievement? achievement,
  }) {
    return AchievementProgress(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      achievementId: achievementId ?? this.achievementId,
      currentValue: currentValue ?? this.currentValue,
      targetValue: targetValue ?? this.targetValue,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      metadata: metadata ?? this.metadata,
      achievement: achievement ?? this.achievement,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AchievementProgress &&
        other.id == id &&
        other.userId == userId &&
        other.achievementId == achievementId &&
        other.currentValue == currentValue &&
        other.targetValue == targetValue;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        userId.hashCode ^
        achievementId.hashCode ^
        currentValue.hashCode ^
        targetValue.hashCode;
  }

  @override
  String toString() {
    return 'AchievementProgress(id: $id, progress: ${progressPercentage.toStringAsFixed(1)}%)';
  }
}

class AchievementStats {
  final int totalEarned;
  final int totalAvailable;
  final double completionPercentage;
  final int powerPoints;
  final Map<String, int> byCategory;
  final Map<String, int> byTier;

  const AchievementStats({
    required this.totalEarned,
    required this.totalAvailable,
    required this.completionPercentage,
    required this.powerPoints,
    required this.byCategory,
    required this.byTier,
  });

  factory AchievementStats.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] as Map<String, dynamic>? ?? json;
    
    return AchievementStats(
      totalEarned: stats['total_earned'] ?? 0,
      totalAvailable: stats['total_available'] ?? 0,
      completionPercentage: (stats['completion_percentage'] ?? 0.0).toDouble(),
      powerPoints: stats['power_points'] ?? 0,
      byCategory: Map<String, int>.from(stats['by_category'] ?? {}),
      byTier: Map<String, int>.from(stats['by_tier'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_earned': totalEarned,
      'total_available': totalAvailable,
      'completion_percentage': completionPercentage,
      'power_points': powerPoints,
      'by_category': byCategory,
      'by_tier': byTier,
    };
  }

  AchievementStats copyWith({
    int? totalEarned,
    int? totalAvailable,
    double? completionPercentage,
    int? powerPoints,
    Map<String, int>? byCategory,
    Map<String, int>? byTier,
  }) {
    return AchievementStats(
      totalEarned: totalEarned ?? this.totalEarned,
      totalAvailable: totalAvailable ?? this.totalAvailable,
      completionPercentage: completionPercentage ?? this.completionPercentage,
      powerPoints: powerPoints ?? this.powerPoints,
      byCategory: byCategory ?? this.byCategory,
      byTier: byTier ?? this.byTier,
    );
  }

  @override
  String toString() {
    return 'AchievementStats(earned: $totalEarned/$totalAvailable, completion: ${completionPercentage.toStringAsFixed(1)}%, powerPoints: $powerPoints)';
  }
}
