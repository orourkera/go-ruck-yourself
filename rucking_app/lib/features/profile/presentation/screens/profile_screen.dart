import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/models/user.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/profile/presentation/bloc/profile_bloc.dart';
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
import 'package:url_launcher/url_launcher.dart';
import 'package:rucking_app/features/health_integration/bloc/health_bloc.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/features/health_integration/presentation/screens/health_integration_intro_screen.dart';

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
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => LoginScreen()),
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
              
              return Scaffold(
                backgroundColor: isLadyMode ? primaryColor.withOpacity(0.05) : Colors.white,
                appBar: AppBar(
                  backgroundColor: isLadyMode ? primaryColor : Colors.white,
                  elevation: 0,
                  title: Text(
                    'Profile',
                    style: TextStyle(
                      color: isLadyMode ? Colors.white : Colors.black,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  actions: [
                    IconButton(
                      icon: Icon(Icons.edit, color: isLadyMode ? Colors.white : Colors.black),
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
                        // Avatar section with upload functionality
                        BlocListener<ProfileBloc, ProfileState>(
                          listener: (context, profileState) {
                            if (profileState is AvatarUploadSuccess) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Avatar updated successfully!')),
                              );
                            } else if (profileState is AvatarUploadFailure) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to upload avatar: ${profileState.error}')),
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
                                  final imageFile = await ImagePickerUtils.pickImage(context);
                                  if (imageFile != null) {
                                    context.read<ProfileBloc>().add(UploadAvatar(imageFile));
                                  }
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          user.username,
                          style: AppTextStyles.headlineMedium.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user.email,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textDarkSecondary,
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
                                          child: Text(value),
                                        ))
                                    .toList(),
                              ),
                            ),
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
                                showAboutDialog(
                                  context: context,
                                  applicationName: 'Go Rucky Yourself App',
                                  applicationVersion: '1.0.0',
                                  applicationIcon: Image.asset(
                                    'assets/images/app_icon.png',
                                    width: 48,
                                    height: 48,
                                  ),
                                  applicationLegalese: ' 2025 Get Rucky',
                                  children: [
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Track your rucking sessions, monitor your progress, and have a great rucking time',
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Made by the Get Rucky team.',
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                );
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
                            backgroundColor: isLadyMode ? AppColors.ladyPrimary : AppColors.primary,
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
          Icon(icon, color: AppColors.primary, size: 24),
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
          Icon(icon, color: AppColors.primary, size: 24),
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
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: isDark ? const Color(0xFF728C69) : AppColors.textDark,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
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
          title: const Text('Logout'),
          content: Text(
            'Are you sure you want to logout?',
            style: TextStyle(color: isDark ? Colors.black : null),
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
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text('Are you sure you want to delete your account? This action cannot be undone.'),
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