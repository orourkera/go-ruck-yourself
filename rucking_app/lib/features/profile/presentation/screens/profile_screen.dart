import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/models/user.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:rucking_app/features/profile/presentation/bloc/public_profile_bloc.dart';
import 'package:rucking_app/shared/widgets/user_avatar.dart';
import 'package:rucking_app/shared/utils/image_picker_utils.dart';
import 'package:rucking_app/features/auth/presentation/screens/login_screen.dart';
import 'package:rucking_app/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:rucking_app/features/profile/presentation/screens/feedback_form_screen.dart';
import 'package:rucking_app/features/profile/presentation/screens/privacy_policy_screen.dart';
import 'package:rucking_app/features/profile/presentation/screens/terms_of_service_screen.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rucking_app/features/health_integration/bloc/health_bloc.dart';
import 'package:rucking_app/core/services/active_session_storage.dart';
import 'package:rucking_app/shared/widgets/strava_settings_widget.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/features/health_integration/presentation/screens/health_integration_intro_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:rucking_app/core/utils/push_notification_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Screen for displaying and managing user profile
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _selectedUnit;
  User? _currentUser; // Track current user to avoid losing state during loading

  // Constants for conversion
  static const double kgToLbs = 2.20462;
  static const double cmToInches = 0.393701;

  Widget _buildCountColumn(BuildContext context, {required String label, required int count, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count.toString(),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => GetIt.instance<ProfileBloc>(),
      child: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthError) {
            if (Navigator.of(context, rootNavigator: true).canPop()) {
              Navigator.of(context, rootNavigator: true).pop();
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: ${state.message}'),
                backgroundColor: Colors.red,
              ),
            );
          } else if (state is Unauthenticated) {
            Navigator.of(context).pushNamedAndRemoveUntil(
                '/login',
                (route) => false,
              );
          }
        },
        child: BlocBuilder<AuthBloc, AuthState>(
          builder: (context, state) {
            // Update current user when we have an authenticated state
            if (state is Authenticated) {
              _currentUser = state.user;
            }
            
            // Always use current user if available, even during loading
            if (_currentUser != null) {
              final user = _currentUser!;
              _selectedUnit ??= user.preferMetric ? 'Metric' : 'Standard';
              String initials = user.username.isNotEmpty ? _getInitials(user.username) : '';

              String weightDisplay = 'Not set';
              if (user.weightKg != null) {
                weightDisplay = user.preferMetric
                    ? '${user.weightKg!.toStringAsFixed(1)} kg'
                    : '${(user.weightKg! * kgToLbs).toStringAsFixed(1)} lbs';
              }

              String heightDisplay = 'Not set';
              if (user.heightCm != null) {
                if (user.preferMetric) {
                  heightDisplay = '${user.heightCm!.toStringAsFixed(1)} cm';
                } else {
                  final totalInches = user.heightCm! * cmToInches;
                  final feet = (totalInches / 12).floor();
                  final inches = (totalInches % 12).round();
                  heightDisplay = "$feet' $inches\"";
                }
              }

              // Determine if we're in lady mode
              final bool isLadyMode = user.gender == 'female';
              final Color primaryColor = isLadyMode ? AppColors.ladyPrimary : AppColors.primary;
              final bool isDark = Theme.of(context).brightness == Brightness.dark;
              
              return Scaffold(
                appBar: AppBar(
                  title: const Text('Profile'),
                  elevation: 0,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EditProfileScreen(
                              user: user,
                              preferMetric: user.preferMetric,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),
                        // Avatar + follower/following counts row
                        BlocProvider<PublicProfileBloc>(
                          create: (_) => GetIt.instance<PublicProfileBloc>()..add(LoadPublicProfile(user.userId)),
                          child: BlocBuilder<PublicProfileBloc, PublicProfileState>(
                            builder: (context, pState) {
                              int followers = 0;
                              int following = 0;
                              if (pState is PublicProfileLoaded) {
                                followers = pState.stats?.followersCount ?? 0;
                                following = pState.stats?.followingCount ?? 0;
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Editable avatar
                                  BlocListener<ProfileBloc, ProfileState>(
                                    listener: (context, profileState) {
                                      if (profileState is AvatarUploadSuccess) {
                                        StyledSnackBar.showSuccess(
                                          context: context,
                                          message: 'Avatar updated successfully!',
                                        );
                                      } else if (profileState is AvatarUploadFailure) {
                                        StyledSnackBar.showError(
                                          context: context,
                                          message: 'Failed to upload avatar: \\${profileState.error}',
                                        );
                                      }
                                    },
                                    child: BlocBuilder<ProfileBloc, ProfileState>(
                                      builder: (context, profileState) {
                                        return EditableUserAvatar(
                                          avatarUrl: user.avatarUrl,
                                          username: user.username,
                                          size: 100,
                                          isLoading: profileState is AvatarUploading,
                                          onEditPressed: () async {
                                            final imageFile = await ImagePickerUtils.pickProfileImage(context);
                                            if (imageFile != null && mounted) {
                                              context.read<ProfileBloc>().add(UploadAvatar(imageFile));
                                            }
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 24),
                                  Expanded(
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: [
                                        _buildCountColumn(context, label: 'Followers', count: followers, onTap: () {
                                          Navigator.pushNamed(context, '/profile/${user.userId}/followers');
                                        }),
                                        _buildCountColumn(context, label: 'Following', count: following, onTap: () {
                                          Navigator.pushNamed(context, '/profile/${user.userId}/following');
                                        }),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Username and email under the avatar
                        Text(
                          user.username,
                          style: AppTextStyles.headlineMedium.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFF728C69) : AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user.email,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: isDark 
                                ? const Color(0xFF728C69).withOpacity(0.8) 
                                : AppColors.textDarkSecondary,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildSection(
                          title: 'Personal Information',
                          children: [
                            _buildInfoItem(
                              icon: Icons.email_outlined,
                              label: 'Email',
                              value: user.email,
                            ),
                            const Divider(),
                            _buildInfoItem(
                              icon: Icons.monitor_weight_outlined,
                              label: 'Weight',
                              value: weightDisplay,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // Strava Integration Section
                        const StravaSettingsWidget(),
                        const SizedBox(height: 24),
                        _buildSection(
                          title: 'SETTINGS',
                          children: [
                            _buildClickableHealthKitItem(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => BlocProvider(
                                      create: (context) => HealthBloc(
                                        healthService: GetIt.instance<HealthService>(),
                                      ),
                                      child: const HealthIntegrationIntroScreen(
                                        navigateToHome: false,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            const Divider(),
                            _buildSettingItem(
                              icon: Icons.straighten,
                              label: 'Units',
                              trailing: DropdownButton<String>(
                                value: _selectedUnit,
                                dropdownColor: isDark ? Theme.of(context).cardColor : null,
                                style: TextStyle(
                                  color: isDark ? const Color(0xFF728C69) : AppColors.textDark,
                                ),
                                onChanged: (newValue) {
                                  if (newValue != null) {
                                    setState(() => _selectedUnit = newValue);
                                    context.read<AuthBloc>().add(
                                          AuthUpdateProfileRequested(
                                            preferMetric: newValue == 'Metric',
                                          ),
                                        );
                                  }
                                },
                                items: ['Metric', 'Standard']
                                    .map((value) => DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(
                                            value,
                                            style: TextStyle(
                                              color: isDark ? const Color(0xFF728C69) : AppColors.textDark,
                                            ),
                                          ),
                                        ))
                                    .toList(),
                              ),
                            ),
                            const Divider(),
                            _buildSettingItem(
                              icon: Icons.timer_off_outlined,
                              label: 'Skip Countdown',
                              trailing: FutureBuilder<bool>(
                                future: SharedPreferences.getInstance().then((p) => p.getBool('skip_countdown') ?? false),
                                builder: (context, snapshot) {
                                  final current = snapshot.data ?? false;
                                  return Switch(
                                    value: current,
                                    activeColor: isDark 
                                        ? const Color(0xFF728C69)
                                        : (isLadyMode ? AppColors.ladyPrimary : AppColors.primary),
                                    onChanged: (value) async {
                                      final prefs = await SharedPreferences.getInstance();
                                      await prefs.setBool('skip_countdown', value);
                                      setState(() {});
                                    },
                                  );
                                },
                              ),
                            ),
                            const Divider(),
                            _buildSettingItem(
                              icon: Icons.share_outlined,
                              label: 'Allow Ruck Sharing',
                              trailing: Switch(
                                value: user.allowRuckSharing,
                                activeColor: isDark 
                                    ? const Color(0xFF728C69)
                                    : (isLadyMode ? AppColors.ladyPrimary : AppColors.primary),
                                onChanged: (value) {
                                  context.read<AuthBloc>().add(
                                    AuthUpdateProfileRequested(
                                      allowRuckSharing: value,
                                    ),
                                  );
                                },
                              ),
                            ),
                            const Divider(),
                            _buildClickableItem(
                              icon: Icons.notifications_outlined,
                              label: 'Notification Settings',
                              onTap: () {
                                Navigator.pushNamed(context, '/notification_settings');
                              },
                            ),
                            // Test push notification buttons hidden after confirming backend works
                            // Uncomment for debugging if needed:
                            /*
                            const Divider(),
                            _buildClickableItem(
                              icon: Icons.bug_report_outlined,
                              label: 'Test Push Notifications',
                              onTap: () async {
                                await PushNotificationTest.testSetup();
                                if (mounted) {
                                  StyledSnackBar.showSuccess(
                                    context: context,
                                    message: 'Push notification test completed. Check logs for details.',
                                  );
                                }
                              },
                            ),
                            const Divider(),
                            _buildClickableItem(
                              icon: Icons.notifications_active_outlined,
                              label: 'Test Local Notification',
                              onTap: () async {
                                await PushNotificationTest.sendTestLocalNotification();
                                if (mounted) {
                                  StyledSnackBar.showSuccess(
                                    context: context,
                                    message: 'Local notification sent! Check your notification center.',
                                  );
                                }
                              },
                            ),
                            */
                          ],
                        ),
                        const SizedBox(height: 24),
                        _buildSection(
                          title: 'About',
                          children: [
                            _buildClickableItem(
                              icon: Icons.info_outline,
                              label: 'About App',
                              onTap: () {
                                _showCustomAboutDialog(context);
                              },
                            ),
                            const Divider(),
                            _buildClickableItem(
                              icon: Icons.privacy_tip_outlined,
                              label: 'Privacy Policy',
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const PrivacyPolicyScreen()),
                                );
                              },
                            ),
                            const Divider(),
                            _buildClickableItem(
                              icon: Icons.description_outlined,
                              label: 'Terms of Service',
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const TermsOfServiceScreen()),
                                );
                              },
                            ),
                            const Divider(),
                            _buildClickableItem(
                              icon: Icons.article_outlined,
                              label: 'Terms of Use (EULA)',
                              onTap: () async {
                                final url = Uri.parse('https://www.apple.com/legal/internet-services/itunes/dev/stdeula/');
                                if (await canLaunchUrl(url)) {
                                  await launchUrl(url);
                                }
                              },
                            ),
                            const Divider(),
                            _buildClickableItem(
                              icon: Icons.feedback,
                              label: 'Give Feedback',
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const FeedbackFormScreen()),
                                );
                              },
                            ),
                            const Divider(),
                            // Test notifications button removed for production
                            // _buildClickableItem(
                            //   icon: Icons.notifications_outlined,
                            //   label: 'Test Notifications',
                            //   onTap: () => _testNotifications(context),
                            // ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _buildSection(
                          title: 'Debug Tools',
                          children: [
                            _buildClickableItem(
                              icon: Icons.storage_outlined,
                              label: 'Clear Session Storage',
                              subtitle: 'Fix stuck session recovery issues',
                              onTap: () => _clearSessionStorage(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _buildSection(
                          title: 'Danger Zone',
                          children: [
                            _buildClickableItem(
                              icon: Icons.delete_forever_outlined,
                              label: 'Delete Account',
                              onTap: () => _showDeleteAccountDialog(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.subscriptions_outlined),
                          label: const Text('Manage Subscription'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50),
                            backgroundColor: isDark 
                                ? const Color(0xFF728C69)
                                : (isLadyMode ? AppColors.ladyPrimary : AppColors.primary),
                            foregroundColor: Colors.white,
                            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () async {
                            final url = Uri.parse(Theme.of(context).platform == TargetPlatform.iOS
                                ? 'https://apps.apple.com/account/subscriptions'
                                : 'https://play.google.com/store/account/subscriptions');
                            if (await canLaunchUrl(url)) {
                              await launchUrl(url);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Could not open subscription management page.')),
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 24),
                        CustomButton(
                          text: 'Logout',
                          icon: Icons.logout,
                          color: AppColors.error,
                          onPressed: () => _showLogoutConfirmationDialog(context),
                        ),
                        const SizedBox(height: 32),
                        FutureBuilder<PackageInfo>(
                          future: PackageInfo.fromPlatform(),
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              return Text(
                                'Version ${snapshot.data!.version} (${snapshot.data!.buildNumber})',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: isDark ? const Color(0xFF728C69).withOpacity(0.8) : AppColors.textDarkSecondary,
                                ),
                              );
                            } else {
                              return const Text('');
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            } else {
              return Scaffold(
                appBar: AppBar(
                  title: const Text('Profile'),
                  centerTitle: true,
                ),
                body: const Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  /// Builds a section with a title and children
  Widget _buildSection({
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              title,
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? const Color(0xFF728C69) : AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (subtitle != null) ...[
            Text(
              subtitle,
              style: AppTextStyles.bodyMedium.copyWith(
                color: isDark ? const Color(0xFF728C69).withOpacity(0.8) : AppColors.textDarkSecondary,
              ),
            ),
            const SizedBox(height: 8),
          ],
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  /// Builds an information item with an icon and label-value pair
  Widget _buildInfoItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icon, 
            color: isDark ? const Color(0xFF728C69) : AppColors.primary, 
            size: 24
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: isDark ? const Color(0xFF728C69).withOpacity(0.8) : AppColors.textDarkSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: isDark ? const Color(0xFF728C69) : AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a setting item with an icon, label, and trailing widget
  Widget _buildSettingItem({
    required IconData icon,
    required String label,
    required Widget trailing,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icon, 
            color: isDark ? const Color(0xFF728C69) : AppColors.primary, 
            size: 24
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodyLarge.copyWith(
                color: isDark ? const Color(0xFF728C69) : AppColors.textDark,
              ),
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  /// Builds a clickable item with an icon and label
  Widget _buildClickableItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? subtitle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              icon, 
              color: isDark ? const Color(0xFF728C69) : AppColors.primary, 
              size: 24
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: isDark ? const Color(0xFF728C69) : AppColors.textDark,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: isDark ? const Color(0xFF728C69).withOpacity(0.7) : AppColors.textDarkSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right, 
              color: isDark ? const Color(0xFF728C69).withOpacity(0.6) : Colors.grey
            ),
          ],
        ),
      ),
    );
  }

  /// Shows a confirmation dialog for logout
  void _showLogoutConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? Theme.of(context).cardColor : null,
          title: Text(
            'Logout',
            style: TextStyle(
              color: isDark ? const Color(0xFF728C69) : null,
            ),
          ),
          content: Text(
            'Are you sure you want to logout?',
            style: TextStyle(
              color: isDark ? const Color(0xFF728C69).withOpacity(0.8) : null,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                context.read<AuthBloc>().add(AuthLogoutRequested());
              },
              child: Text('Logout', style: TextStyle(color: AppColors.error)),
            ),
          ],
        );
      },
    );
  }

  /// Builds a clickable HealthKit item with the HealthKit logo and label
  Widget _buildClickableHealthKitItem({required VoidCallback onTap}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Stack(
              children: [
                const Icon(Icons.favorite, color: Colors.red, size: 24),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300, width: 0.5),
                    ),
                    child: const Icon(
                      Icons.medical_services,
                      color: Colors.green,
                      size: 10,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Row(
                children: [
                  Text(
                    'HealthKit Integration',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: isDark ? const Color(0xFF728C69) : AppColors.textDark,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: const Text(
                      'HealthKit',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right, 
              color: isDark ? const Color(0xFF728C69).withOpacity(0.6) : Colors.grey
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? Theme.of(context).cardColor : null,
        title: Text(
          'Delete Account',
          style: TextStyle(
            color: isDark ? const Color(0xFF728C69) : null,
          ),
        ),
        content: Text(
          'Are you sure you want to delete your account? This action cannot be undone.',
          style: TextStyle(
            color: isDark ? const Color(0xFF728C69).withOpacity(0.8) : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<AuthBloc>().add(const AuthDeleteAccountRequested());
            },
            child: Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  void _showCustomAboutDialog(BuildContext context) async {
    final packageInfo = await PackageInfo.fromPlatform();
    
    if (!context.mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About App'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Go Rucky Yourself App',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Track your rucking sessions, monitor your progress, and have a great rucking time',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Made by the Get Rucky team.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Version ${packageInfo.version} (${packageInfo.buildNumber})',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            const Text(
              ' 2025 Get Rucky',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Clear session storage to fix stuck recovery issues
  Future<void> _clearSessionStorage(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Clear Session Storage'),
          content: const Text(
            'This will clear any stored session data that might be causing the app to redirect to the active session screen.\n\n'
            'This is safe to do and won\'t affect your completed sessions or achievements.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Clear Storage'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        final activeSessionStorage = GetIt.instance<ActiveSessionStorage>();
        await activeSessionStorage.clearSessionData();
        
        if (context.mounted) {
          StyledSnackBar.showSuccess(
            context: context, 
            message: 'Session storage cleared successfully'
          );
        }
      } catch (e) {
        if (context.mounted) {
          StyledSnackBar.showError(
            context: context, 
            message: 'Failed to clear storage: $e'
          );
        }
      }
    }
  }

  /// Gets the initials from a name
  String _getInitials(String name) {
    if (name.isEmpty) return '';
    List<String> nameParts = name.split(' ');
    String initials = '';
    if (nameParts.length > 1 && nameParts[0].isNotEmpty && nameParts[1].isNotEmpty) {
      initials = nameParts[0][0] + nameParts[1][0];
    } else if (nameParts.isNotEmpty && nameParts[0].isNotEmpty) {
      initials = nameParts[0][0];
    }
    return initials.toUpperCase();
  }
}