enum PremiumTier {
  free,
  pro,
}

class PremiumStatus {
  final PremiumTier tier;
  final bool isActive;
  final List<String> unlockedFeatures;
  final DateTime? expiryDate;
  final String? subscriptionId;

  const PremiumStatus({
    required this.tier,
    required this.isActive,
    this.unlockedFeatures = const [],
    this.expiryDate,
    this.subscriptionId,
  });

  // Core feature access getters
  bool get canShare => tier != PremiumTier.free;
  bool get canViewCommunity => tier != PremiumTier.free;
  bool get hasAdsRemoved => tier != PremiumTier.free;
  bool get canAccessStats => tier != PremiumTier.free;
  bool get canAccessRuckBuddies => tier != PremiumTier.free;
  bool get canSeeEngagement => tier != PremiumTier.free;
  bool get canInteractWithCommunity => tier != PremiumTier.free;

  // Feature-specific access control
  bool canAccessFeature(String feature) {
    if (!isActive) return false;
    
    switch (feature) {
      case 'stats':
      case 'analytics':
        return canAccessStats;
      case 'ruck_buddies':
      case 'community':
        return canAccessRuckBuddies;
      case 'engagement':
      case 'likes':
      case 'comments':
        return canSeeEngagement;
      case 'sharing':
        return canShare;
      default:
        return tier != PremiumTier.free;
    }
  }

  // Factory constructors
  factory PremiumStatus.free() {
    return const PremiumStatus(
      tier: PremiumTier.free,
      isActive: true,
    );
  }

  factory PremiumStatus.pro({
    DateTime? expiryDate,
    String? subscriptionId,
  }) {
    return PremiumStatus(
      tier: PremiumTier.pro,
      isActive: true,
      unlockedFeatures: const [
        'stats',
        'analytics', 
        'ruck_buddies',
        'community',
        'engagement',
        'likes',
        'comments',
        'sharing',
      ],
      expiryDate: expiryDate,
      subscriptionId: subscriptionId,
    );
  }

  // Copy with method
  PremiumStatus copyWith({
    PremiumTier? tier,
    bool? isActive,
    List<String>? unlockedFeatures,
    DateTime? expiryDate,
    String? subscriptionId,
  }) {
    return PremiumStatus(
      tier: tier ?? this.tier,
      isActive: isActive ?? this.isActive,
      unlockedFeatures: unlockedFeatures ?? this.unlockedFeatures,
      expiryDate: expiryDate ?? this.expiryDate,
      subscriptionId: subscriptionId ?? this.subscriptionId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PremiumStatus &&
          runtimeType == other.runtimeType &&
          tier == other.tier &&
          isActive == other.isActive;

  @override
  int get hashCode => tier.hashCode ^ isActive.hashCode;

  @override
  String toString() {
    return 'PremiumStatus(tier: $tier, isActive: $isActive, features: ${unlockedFeatures.length})';
  }
}