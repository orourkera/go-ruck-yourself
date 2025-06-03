import 'package:rucking_app/features/premium/domain/models/premium_status.dart';

/// Data model for premium features
class PremiumFeature {
  final String id;
  final String name;
  final String description;
  final String iconPath;
  final PremiumTier requiredTier;
  final bool isEnabled;
  final Map<String, dynamic>? metadata;

  const PremiumFeature({
    required this.id,
    required this.name,
    required this.description,
    required this.iconPath,
    required this.requiredTier,
    this.isEnabled = true,
    this.metadata,
  });

  bool isAccessibleFor(PremiumTier userTier) {
    if (!isEnabled) return false;
    
    switch (requiredTier) {
      case PremiumTier.free:
        return true;
      case PremiumTier.pro:
        return userTier == PremiumTier.pro;
    }
  }

  factory PremiumFeature.fromJson(Map<String, dynamic> json) {
    return PremiumFeature(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      iconPath: json['iconPath'] as String,
      requiredTier: PremiumTier.values.firstWhere(
        (tier) => tier.name == json['requiredTier'],
        orElse: () => PremiumTier.pro,
      ),
      isEnabled: json['isEnabled'] as bool? ?? true,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'iconPath': iconPath,
      'requiredTier': requiredTier.name,
      'isEnabled': isEnabled,
      'metadata': metadata,
    };
  }

  PremiumFeature copyWith({
    String? id,
    String? name,
    String? description,
    String? iconPath,
    PremiumTier? requiredTier,
    bool? isEnabled,
    Map<String, dynamic>? metadata,
  }) {
    return PremiumFeature(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      iconPath: iconPath ?? this.iconPath,
      requiredTier: requiredTier ?? this.requiredTier,
      isEnabled: isEnabled ?? this.isEnabled,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PremiumFeature &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'PremiumFeature(id: $id, name: $name, tier: $requiredTier)';
  }
}

/// Predefined premium features
class PremiumFeatures {
  static const PremiumFeature stats = PremiumFeature(
    id: 'stats',
    name: 'Advanced Analytics',
    description: 'Detailed performance insights and trends',
    iconPath: 'assets/icons/stats.svg',
    requiredTier: PremiumTier.pro,
  );

  static const PremiumFeature ruckBuddies = PremiumFeature(
    id: 'ruck_buddies',
    name: 'Ruck Community',
    description: 'Connect with fellow ruckers and join challenges',
    iconPath: 'assets/icons/community.svg',
    requiredTier: PremiumTier.pro,
  );

  static const PremiumFeature engagement = PremiumFeature(
    id: 'engagement',
    name: 'Community Engagement',
    description: 'See likes, comments, and interact with others',
    iconPath: 'assets/icons/heart.svg',
    requiredTier: PremiumTier.pro,
  );

  static const PremiumFeature advancedSharing = PremiumFeature(
    id: 'sharing',
    name: 'Advanced Sharing',
    description: 'Enhanced sharing options and customizations',
    iconPath: 'assets/icons/share.svg',
    requiredTier: PremiumTier.pro,
  );

  static const List<PremiumFeature> allFeatures = [
    stats,
    ruckBuddies,
    engagement,
    advancedSharing,
  ];

  static PremiumFeature? getFeatureById(String id) {
    try {
      return allFeatures.firstWhere((feature) => feature.id == id);
    } catch (e) {
      return null;
    }
  }

  static List<PremiumFeature> getFeaturesForTier(PremiumTier tier) {
    return allFeatures.where((feature) => feature.isAccessibleFor(tier)).toList();
  }
}
