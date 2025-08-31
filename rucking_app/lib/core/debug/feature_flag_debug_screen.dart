import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:rucking_app/core/config/feature_flags.dart';
import 'package:rucking_app/core/services/in_app_review_service.dart';
import 'package:rucking_app/core/services/tracking_transparency_service.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// 🛠️ DEBUG ONLY: Feature Flag Monitor & Toggle Screen
/// 
/// This screen allows developers to:
/// 1. Monitor which feature flags are active
/// 2. See the current auth implementation being used
/// 3. Understand the fallback behavior
/// 4. Access via debug drawer or special gesture
/// 
/// SAFETY: Only available in debug mode
class FeatureFlagDebugScreen extends StatefulWidget {
  const FeatureFlagDebugScreen({Key? key}) : super(key: key);

  @override
  State<FeatureFlagDebugScreen> createState() => _FeatureFlagDebugScreenState();
}

class _FeatureFlagDebugScreenState extends State<FeatureFlagDebugScreen> {
  @override
  Widget build(BuildContext context) {
    // Only show in debug mode
    if (!kDebugMode) {
      return Scaffold(
        appBar: AppBar(title: const Text('Feature Flags')),
        body: const Center(
          child: Text('Feature flags are only available in debug mode'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('🚩 Feature Flags'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          _buildAuthSection(),
          const SizedBox(height: 24),
          _buildProfileSection(),
          const SizedBox(height: 24),
          _buildSafetySection(),
          const SizedBox(height: 24),
          _buildInstructions(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final remoteConfigInfo = FeatureFlags.getRemoteConfigDebugInfo();
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🌐 Remote Config Status',
              style: AppTextStyles.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Debug Mode: ${kDebugMode ? "✅ ENABLED" : "❌ DISABLED"}',
              style: AppTextStyles.bodyMedium?.copyWith(
                color: kDebugMode ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Remote Config: ${remoteConfigInfo['isInitialized'] ? "✅ LOADED" : "❌ NOT LOADED"}',
              style: AppTextStyles.bodyMedium?.copyWith(
                color: remoteConfigInfo['isInitialized'] ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Simplified Auth: ${FeatureFlags.useSimplifiedAuth ? "✅ ENABLED" : "❌ DISABLED"}',
              style: AppTextStyles.bodyMedium?.copyWith(
                color: FeatureFlags.useSimplifiedAuth ? Colors.green : Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (remoteConfigInfo['lastFetchTime'] != null) ...[
              const SizedBox(height: 4),
              Text(
                'Last Fetch: ${_formatTime(remoteConfigInfo['lastFetchTime'])}',
                style: AppTextStyles.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAuthSection() {
    final flags = FeatureFlags.getAuthFeatureStatus();
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🔐 Auth System Flags',
              style: AppTextStyles.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...flags.entries.map((entry) => _buildFlagRow(
              entry.key,
              entry.value,
              _getAuthFlagDescription(entry.key),
            )),
            const SizedBox(height: 12),
            _buildCurrentImplementation(),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '👤 Profile Management',
              style: AppTextStyles.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildFlagRow(
              'CUSTOM_PROFILE_MANAGEMENT',
              FeatureFlags.keepCustomProfileManagement,
              'Extended user profiles (weight, height, preferences)',
            ),
            _buildFlagRow(
              'AVATAR_UPLOAD_PROCESSING',
              FeatureFlags.keepAvatarUploadProcessing,
              'Image processing and avatar uploads',
            ),
            _buildFlagRow(
              'MAILJET_INTEGRATION',
              FeatureFlags.keepMailjetIntegration,
              'Email marketing automation',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSafetySection() {
    return Card(
      color: Colors.orange.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🛡️ Safety Features',
              style: AppTextStyles.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.orange.shade800,
              ),
            ),
            const SizedBox(height: 12),
            _buildFlagRow(
              'FALLBACK_TO_LEGACY',
              FeatureFlags.ENABLE_FALLBACK_TO_LEGACY_AUTH,
              'Automatically fall back to legacy auth on errors',
              color: Colors.orange.shade700,
            ),
            _buildFlagRow(
              'DEBUG_LOGGING',
              FeatureFlags.ENABLE_AUTH_DEBUG_LOGGING,
              'Enhanced logging for debugging auth issues',
              color: Colors.orange.shade700,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentImplementation() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🎯 Current Implementation:',
            style: AppTextStyles.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          if (AuthFeatureFlags.useSimplifiedAuth) ...[
            Text(
              '🆕 SIMPLIFIED AUTH ACTIVE',
              style: AppTextStyles.bodyMedium?.copyWith(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '• Direct Supabase integration\n'
              '• Automatic token refresh\n'
              '• Auth state listeners\n'
              '• Fallback to legacy on errors',
              style: AppTextStyles.bodySmall,
            ),
          ] else ...[
            Text(
              '🏛️ LEGACY AUTH ACTIVE',
              style: AppTextStyles.bodyMedium?.copyWith(
                color: Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '• Custom backend auth flow\n'
              '• Manual token management\n'
              '• Complex retry logic\n'
              '• 950-line implementation',
              style: AppTextStyles.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInstructions() {
    return Card(
      color: Colors.blue.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '📋 How to Use',
              style: AppTextStyles.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '1. Feature flags are controlled in feature_flags.dart\n'
              '2. Currently limited to debug mode only\n'
              '3. Test simplified auth thoroughly before enabling in production\n'
              '4. Fallback to legacy auth is always enabled for safety\n'
              '5. Monitor logs for "AUTH_WRAPPER" messages to see which implementation is used',
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _testAuth,
                    icon: const Icon(Icons.bug_report),
                    label: const Text('Test Auth System'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _refreshRemoteConfig,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh Config'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade600,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _testAppTrackingTransparency,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
              child: const Text('🔍 Test ATT Permission'),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _testInAppReview,
                icon: const Icon(Icons.star_rate),
                label: const Text('Test In-App Review'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple.shade600,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlagRow(String name, bool value, String description, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            value ? Icons.check_circle : Icons.cancel,
            color: color ?? (value ? Colors.green : Colors.grey),
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTextStyles.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  description,
                  style: AppTextStyles.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getAuthFlagDescription(String flag) {
    switch (flag) {
      case 'USE_SIMPLIFIED_AUTH':
        return 'Master toggle for simplified auth system';
      case 'USE_DIRECT_SUPABASE_SIGNIN':
        return 'Use Supabase auth directly for sign-in';
      case 'USE_DIRECT_SUPABASE_SIGNUP':
        return 'Use Supabase auth directly for sign-up';
      case 'USE_AUTOMATIC_TOKEN_REFRESH':
        return 'Let Supabase handle token refresh automatically';
      case 'USE_SUPABASE_AUTH_LISTENER':
        return 'React to Supabase auth state changes';
      case 'ENABLE_FALLBACK_TO_LEGACY_AUTH':
        return 'Fall back to legacy auth on errors';
      default:
        return 'Auth system feature flag';
    }
  }

  void _testAuth() {
    AppLogger.info('🧪 [FEATURE_FLAGS] Testing auth system implementation...');
    AppLogger.info('🧪 [FEATURE_FLAGS] Current flags: ${FeatureFlags.getAuthFeatureStatus()}');
    AppLogger.info('🧪 [FEATURE_FLAGS] Remote config info: ${FeatureFlags.getRemoteConfigDebugInfo()}');
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Auth test logged - check console for details',
        ),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 2),
      ),
    );
  }
  
  void _testInAppReview() async {
    final reviewService = InAppReviewService();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Testing in-app review flow...'),
        backgroundColor: Colors.purple,
        duration: Duration(seconds: 2),
      ),
    );
    
    try {
      // Request ATT authorization
      final hasPermission = await TrackingTransparencyService.requestTrackingAuthorization();
      
      AppLogger.info('[FEATURE_FLAGS] ATT permission result: $hasPermission');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(hasPermission ? 'ATT: Tracking authorized ✅' : 'ATT: Tracking denied ❌'),
          backgroundColor: hasPermission ? Colors.green : Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      AppLogger.error('[FEATURE_FLAGS] ATT test failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ATT test failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
  
  Future<void> _testInAppReview() async {
    AppLogger.info('[FEATURE_FLAGS] Testing in-app review flow...');
    
    try {
      final reviewService = InAppReviewService();
      await reviewService.debugForceReviewDialog(context);
      AppLogger.info('[FEATURE_FLAGS] Review dialog test completed');
    } catch (e) {
      AppLogger.error('[FEATURE_FLAGS] Review dialog test failed: $e');
    }
  }
  
  void _refreshRemoteConfig() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Refreshing remote config...'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 1),
      ),
    );
    
    try {
      await FeatureFlags.forceRefreshRemoteConfig();
      setState(() {}); // Refresh the UI
      
      AppLogger.info('✅ [FEATURE_FLAGS] Remote config refreshed successfully');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Remote config refreshed successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      AppLogger.error('❌ [FEATURE_FLAGS] Failed to refresh remote config: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to refresh: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
  
  String _formatTime(String? isoTime) {
    if (isoTime == null) return 'Never';
    
    try {
      final dateTime = DateTime.parse(isoTime);
      final now = DateTime.now();
      final difference = now.difference(dateTime);
      
      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inDays < 1) {
        return '${difference.inHours}h ago';
      } else {
        return '${difference.inDays}d ago';
      }
    } catch (e) {
      return 'Unknown';
    }
  }
}
