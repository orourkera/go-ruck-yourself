import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/auth/presentation/screens/login_screen.dart';
import 'package:rucking_app/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';

/// Screen for displaying and managing user profile
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({Key? key}) : super(key: key);

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
          
          // Safely get initials, checking for null or empty values
          String initials = '';
          if (user.name.isNotEmpty) {
            initials = _getInitials(user.name);
          }
          
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
                        builder: (context) => EditProfileScreen(user: user),
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
                  // Profile header
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: AppColors.primary,
                    child: Text(
                      initials,
                      style: AppTextStyles.headline4.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
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
                        value: user.weightKg != null
                            ? '${user.weightKg} kg'
                            : 'Not set',
                      ),
                      const Divider(),
                      _buildInfoItem(
                        icon: Icons.height_outlined,
                        label: 'Height',
                        value: user.heightCm != null
                            ? '${user.heightCm} cm'
                            : 'Not set',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // App settings section
                  _buildSection(
                    title: 'App Settings',
                    children: [
                      _buildSettingItem(
                        icon: Icons.dark_mode_outlined,
                        label: 'Dark Mode',
                        trailing: Switch(
                          value: false, // TODO: Implement theme switching
                          onChanged: (value) {
                            // TODO: Implement theme switching
                          },
                          activeColor: AppColors.primary,
                        ),
                      ),
                      const Divider(),
                      _buildSettingItem(
                        icon: Icons.notifications_outlined,
                        label: 'Notifications',
                        trailing: Switch(
                          value: true, // TODO: Implement notifications
                          onChanged: (value) {
                            // TODO: Implement notifications
                          },
                          activeColor: AppColors.primary,
                        ),
                      ),
                      const Divider(),
                      _buildSettingItem(
                        icon: Icons.language_outlined,
                        label: 'Units',
                        trailing: DropdownButton<String>(
                          value: 'Metric',
                          underline: const SizedBox(),
                          items: ['Metric', 'Imperial']
                              .map((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                );
                              })
                              .toList(),
                          onChanged: (String? newValue) {
                            // TODO: Implement unit switching
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Health integration section
                  _buildSection(
                    title: 'Health Integration',
                    children: [
                      _buildSettingItem(
                        icon: Icons.favorite_outline,
                        label: 'Apple Health',
                        trailing: Switch(
                          value: true, // TODO: Implement Apple Health integration
                          onChanged: (value) {
                            // TODO: Implement Apple Health integration
                          },
                          activeColor: AppColors.primary,
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
                          // TODO: Open privacy policy
                        },
                      ),
                      const Divider(),
                      _buildClickableItem(
                        icon: Icons.description_outlined,
                        label: 'Terms of Service',
                        onTap: () {
                          // TODO: Open terms of service
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  
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