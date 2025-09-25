/// Central toggles for social sharing features that aren't currently remote
/// controlled. Update these values when enabling/disabling experiences that
/// rely on external services.
class SocialFeatureToggles {
  SocialFeatureToggles._();

  /// Instagram sharing is fully disabled. UI entry points should hide or show
  /// a friendly message and no background services should attempt to run.
  static const bool instagramSharingEnabled = true;
}

