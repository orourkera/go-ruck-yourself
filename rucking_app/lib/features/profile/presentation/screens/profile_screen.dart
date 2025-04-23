import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/auth/presentation/screens/login_screen.dart';
import 'package:rucking_app/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:rucking_app/features/profile/presentation/screens/privacy_policy_screen.dart';
import 'package:rucking_app/features/profile/presentation/screens/terms_of_service_screen.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';
import 'package:http/http.dart' as http;

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
    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is Unauthenticated) {
          // Navigate to login screen if logged out
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
      },
      builder: (context, state) {
        if (state is Authenticated) {
          final user = state.user;
          
          // Initialize dropdown value if not already set
          // Do this within build or didChangeDependencies for safety with Bloc state
          _selectedUnit ??= user.preferMetric ? 'Metric' : 'Standard';
          
          // Safely get initials, checking for null or empty values
          String initials = '';
          if (user.name.isNotEmpty) {
            initials = _getInitials(user.name);
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
                    user.name,
                    style: AppTextStyles.headline5.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.email,
                    style: AppTextStyles.body2.copyWith(
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
                              context.read<AuthBloc>().add(AuthProfileUpdateRequested(
                                preferMetric: newPreferMetric,
                                name: user.name,
                                weightKg: user.weightKg,
                                heightCm: user.heightCm,
                                email: user.email,
                              ));
                            }
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
                          // TODO: Show about dialog
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
                        onTap: () => _showDeleteAccountDialog(context, user.userId),
                      ),
                    ],
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
                  TextButton(
                    onPressed: () {
                      // TODO: Implement account deletion
                    },
                    child: Text(
                      'Delete Account',
                      style: AppTextStyles.button.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
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
    );
  }

  /// Builds a section with a title and children
  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
              style: AppTextStyles.subtitle1.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
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
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textDarkSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AppTextStyles.body1,
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
              style: AppTextStyles.body1,
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
                style: AppTextStyles.body1,
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
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
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
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context, String userId) {
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
            onPressed: () async {
              Navigator.pop(context);
              // Call backend to delete account
              final success = await _deleteAccount(userId, context);
              if (success && mounted) {
                // Log out and redirect to login
                context.read<AuthBloc>().add(AuthLogoutRequested());
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to delete account. Please try again.')),
                  );
                }
              }
            },
            child: Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  Future<bool> _deleteAccount(String userId, BuildContext context) async {
    try {
      final response = await http.delete(
        Uri.parse('https://getrucky.com/api/users/$userId'),
      );
      if (response.statusCode == 200) {
        return true;
      }
      return false;
    } catch (e) {
      return false;
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