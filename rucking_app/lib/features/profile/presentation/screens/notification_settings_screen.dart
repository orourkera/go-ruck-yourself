import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';

/// Screen for managing notification preferences
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  // Local state for notification preferences (will sync with user model)
  bool _clubsEnabled = true;
  bool _buddiesEnabled = true;
  bool _eventsEnabled = true;
  bool _duelsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  void _loadCurrentSettings() {
    final authState = context.read<AuthBloc>().state;
    if (authState is Authenticated) {
      final user = authState.user;
      setState(() {
        _clubsEnabled = user.notificationClubs ?? true;
        _buddiesEnabled = user.notificationBuddies ?? true;
        _eventsEnabled = user.notificationEvents ?? true;
        _duelsEnabled = user.notificationDuels ?? true;
      });
    }
  }

  void _updateNotificationSetting({
    required String type,
    required bool enabled,
  }) {
    // Update auth bloc with new notification preferences
    Map<String, bool> updates = {};
    
    switch (type) {
      case 'clubs':
        updates['clubs'] = enabled;
        break;
      case 'buddies':
        updates['buddies'] = enabled;
        break;
      case 'events':
        updates['events'] = enabled;
        break;
      case 'duels':
        updates['duels'] = enabled;
        break;
    }

    context.read<AuthBloc>().add(
      AuthUpdateNotificationPreferences(updates),
    );

    // Show confirmation
    StyledSnackBar.show(
      context: context,
      message: enabled
          ? '${_getNotificationTypeName(type)} notifications enabled'
          : '${_getNotificationTypeName(type)} notifications disabled',
      type: SnackBarType.success,
    );
  }

  String _getNotificationTypeName(String type) {
    switch (type) {
      case 'clubs':
        return 'Club';
      case 'buddies':
        return 'Ruck Buddies';
      case 'events':
        return 'Event';
      case 'duels':
        return 'Duel';
      default:
        return type;
    }
  }

  Color _getLadyModeColor(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    if (authState is Authenticated && authState.user.gender == 'female') {
      return AppColors.ladyPrimary; // Sky blue for female users
    }
    return AppColors.primary; // Default orange
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ladyModeColor = _getLadyModeColor(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: ladyModeColor,
        title: Text(
          'Notification Settings',
          style: AppTextStyles.headlineMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is Authenticated) {
            // Update local state when auth state changes
            _loadCurrentSettings();
          }
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header description
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
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
                    Row(
                      children: [
                        Icon(
                          Icons.notifications_active,
                          color: ladyModeColor,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Notification Preferences',
                          style: AppTextStyles.titleMedium.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFF728C69) : AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Choose which types of notifications you want to receive. You can change these settings at any time.',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: isDark ? const Color(0xFF728C69).withOpacity(0.8) : AppColors.textDarkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),

              // Notification settings
              Container(
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
                  children: [
                    _buildNotificationToggle(
                      icon: Icons.groups,
                      title: 'Club Notifications',
                      subtitle: 'Membership updates, club events, and discussions',
                      value: _clubsEnabled,
                      onChanged: (value) {
                        setState(() => _clubsEnabled = value);
                        _updateNotificationSetting(type: 'clubs', enabled: value);
                      },
                      ladyModeColor: ladyModeColor,
                      isDark: isDark,
                    ),
                    const Divider(height: 1),
                    _buildNotificationToggle(
                      icon: Icons.people,
                      title: 'Ruck Buddies Notifications',
                      subtitle: 'Likes and comments on your ruck sessions',
                      value: _buddiesEnabled,
                      onChanged: (value) {
                        setState(() => _buddiesEnabled = value);
                        _updateNotificationSetting(type: 'buddies', enabled: value);
                      },
                      ladyModeColor: ladyModeColor,
                      isDark: isDark,
                    ),
                    const Divider(height: 1),
                    _buildNotificationToggle(
                      icon: Icons.event,
                      title: 'Event Notifications',
                      subtitle: 'Event invitations, updates, and comments',
                      value: _eventsEnabled,
                      onChanged: (value) {
                        setState(() => _eventsEnabled = value);
                        _updateNotificationSetting(type: 'events', enabled: value);
                      },
                      ladyModeColor: ladyModeColor,
                      isDark: isDark,
                    ),
                    const Divider(height: 1),
                    _buildNotificationToggle(
                      icon: Icons.emoji_events,
                      title: 'Duel Notifications',
                      subtitle: 'Duel invitations, progress updates, and completion',
                      value: _duelsEnabled,
                      onChanged: (value) {
                        setState(() => _duelsEnabled = value);
                        _updateNotificationSetting(type: 'duels', enabled: value);
                      },
                      ladyModeColor: ladyModeColor,
                      isDark: isDark,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Additional info
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800]?.withOpacity(0.3) : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: isDark ? const Color(0xFF728C69).withOpacity(0.8) : AppColors.textDarkSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Push notifications will still be delivered to your device, but these settings control which types you receive. You can also manage notification permissions in your device settings.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: isDark ? const Color(0xFF728C69).withOpacity(0.8) : AppColors.textDarkSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationToggle({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color ladyModeColor,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(
            icon,
            color: isDark ? const Color(0xFF728C69) : ladyModeColor,
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFF728C69) : AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: isDark ? const Color(0xFF728C69).withOpacity(0.8) : AppColors.textDarkSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: ladyModeColor,
            activeTrackColor: ladyModeColor.withOpacity(0.3),
            inactiveThumbColor: isDark ? Colors.grey[400] : Colors.grey[300],
            inactiveTrackColor: isDark ? Colors.grey[700] : Colors.grey[200],
          ),
        ],
      ),
    );
  }
}
