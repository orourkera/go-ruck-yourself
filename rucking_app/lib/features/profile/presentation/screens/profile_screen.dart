import 'package:flutter/material.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/auth/presentation/screens/login_screen.dart';
import 'package:rucking_app/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:rucking_app/features/profile/presentation/screens/feedback_form_screen.dart';
import 'package:rucking_app/features/profile/presentation/screens/privacy_policy_screen.dart';
import 'package:rucking_app/features/profile/presentation/screens/terms_of_service_screen.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen for displaying and managing user profile
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _selectedUnit;

  // Constants for conversion
  static const double kgToLbs = 2.20462;
  static const double cmToInches = 0.393701;

  @override
  void initState() {
    super.initState();
    // Initialize _selectedUnit based on current state when widget builds
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthError) {
          // Hide loading indicator if shown before error
          if (Navigator.of(context, rootNavigator: true).canPop()) {
            Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading if any
          }
          StyledSnackBar.showError(
            context: context,
            message: 'Error: ${state.message}',
            duration: const Duration(seconds: 3),
          );
        } else if (state is Unauthenticated) {
          // User successfully deleted or logged out elsewhere
          // Navigate to login screen if logged out
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
      },
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          if (state is Authenticated) {
            final user = state.user;
            
            // Initialize dropdown value if not already set
            // Do this within build or didChangeDependencies for safety with Bloc state
            _selectedUnit ??= user.preferMetric ? 'Metric' : 'Standard';
            
            // Safely get initials, checking for null or empty values
            String initials = '';
            if (user.username.isNotEmpty) {
              initials = _getInitials(user.username);
            }
            
            // --- Calculate Display Values ---
            String weightDisplay = 'Not set';
            if (user.weightKg != null) {
              if (user.preferMetric) {
                weightDisplay = '${user.weightKg!.toStringAsFixed(1)} kg';
              } else {
                final lbs = user.weightKg! * kgToLbs;
                weightDisplay = '${lbs.toStringAsFixed(1)} lbs';
              }
            }

            String heightDisplay = 'Not set';
            if (user.heightCm != null) {
              if (user.preferMetric) {
                heightDisplay = '${user.heightCm!.toStringAsFixed(1)} cm';
              } else {
                final totalInches = user.heightCm! * cmToInches;
                final feet = (totalInches / 12).floor();
                final inches = (totalInches % 12).round(); // Round remaining inches
                heightDisplay = '$feet\' $inches"'; // Format as 5' 11"
              }
            }
            // --- End Calculate Display Values ---
            
            return Scaffold(
              appBar: AppBar(
                title: const Text('Profile'),
                centerTitle: true,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditProfileScreen(
                            user: user, 
                            // Pass the preference
                            preferMetric: user.preferMetric, 
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
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
                    
                    // Personal Info section
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
                    
                    // App settings section
                    _buildSection(
                      title: 'App Settings',
                      children: [
                        _buildSettingItem(
                          icon: Icons.language_outlined,
                          label: 'Units',
                          trailing: DropdownButton<String>(
                            value: _selectedUnit,
                            underline: const SizedBox(),
                            items: ['Metric', 'Standard']
                                .map((String value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(value),
                                  );
                                })
                                .toList(),
                            onChanged: (String? newValue) {
                              if (newValue != null && newValue != _selectedUnit) {
                                setState(() {
                                  _selectedUnit = newValue;
                                });
                                // Dispatch update event
                                bool newPreferMetric = newValue == 'Metric';
                                context.read<AuthBloc>().add(AuthUpdateProfileRequested(
                                  preferMetric: newPreferMetric,
                                  username: user.username,
                                  weightKg: user.weightKg,
                                  heightCm: user.heightCm,
                                ));
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildSettingItem(
                          icon: Icons.people_outline,
                          label: 'Share Rucks with Others',
                          trailing: Switch(
                            value: user.allowRuckSharing,
                            activeColor: AppColors.primary,
                            onChanged: (bool newValue) {
                              // Dispatch update event
                              context.read<AuthBloc>().add(AuthUpdateProfileRequested(
                                allowRuckSharing: newValue,
                                preferMetric: user.preferMetric,
                                username: user.username,
                                weightKg: user.weightKg,
                                heightCm: user.heightCm,
                              ));
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // About section
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

                    // Delete account section
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
                    
                    // Manage Subscription button
                    ElevatedButton.icon(
                      icon: const Icon(Icons.subscriptions_outlined),
                      label: const Text('Manage Subscription'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        backgroundColor: AppColors.primary,
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
                          StyledSnackBar.showError(
                            context: context,
                            message: 'Could not open subscription management page.',
                            duration: const Duration(seconds: 3),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 24),

                    // Logout button
                    CustomButton(
                      text: 'Logout',
                      icon: Icons.logout,
                      color: AppColors.error,
                      onPressed: () {
                        _showLogoutConfirmationDialog(context);
                      },
                    ),
                    const SizedBox(height: 16),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            );
          }
          
          // Loading, error, or initial state
          return Scaffold(
            appBar: AppBar(
              title: const Text('Profile'),
              centerTitle: true,
            ),
            body: const Center(
              child: CircularProgressIndicator(),
            ),
          );
        },
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
                color: isDark ? Color(0xFF728C69) : AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (subtitle != null) ...[
            Text(
              subtitle!,
              style: AppTextStyles.bodyMedium.copyWith(
                color: isDark ? Color(0xFF728C69).withOpacity(0.8) : AppColors.textDarkSecondary,
              ),
            ),
            const SizedBox(height: 8),
          ],
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: children,
            ),
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
            color: AppColors.primary,
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: isDark ? Color(0xFF728C69).withOpacity(0.8) : AppColors.textDarkSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: isDark ? Color(0xFF728C69) : AppColors.textDark,
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
            color: AppColors.primary,
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodyLarge.copyWith(
                color: isDark ? Color(0xFF728C69) : AppColors.textDark,
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
            Icon(
              icon,
              color: AppColors.primary,
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: isDark ? Color(0xFF728C69) : AppColors.textDark,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Colors.grey,
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
          title: const Text('Logout'),
          content: Text(
            'Are you sure you want to logout?',
            style: TextStyle(
              color: isDark ? Colors.black : null,
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
              child: Text(
                'Logout',
                style: TextStyle(color: AppColors.error),
              ),
            ),
          ],
        );
      },
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