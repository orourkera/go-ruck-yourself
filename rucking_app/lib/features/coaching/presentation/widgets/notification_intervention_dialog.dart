import 'package:flutter/material.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

class NotificationInterventionDialog extends StatefulWidget {
  final VoidCallback? onNotificationsKept;
  final VoidCallback? onNotificationsDisabled;

  const NotificationInterventionDialog({
    super.key,
    this.onNotificationsKept,
    this.onNotificationsDisabled,
  });

  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const NotificationInterventionDialog(),
    );
    return result ?? true; // Default to keeping notifications on
  }

  @override
  State<NotificationInterventionDialog> createState() =>
      _NotificationInterventionDialogState();
}

class _NotificationInterventionDialogState
    extends State<NotificationInterventionDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  Map<String, dynamic>? _interventionData;
  bool _isLoading = true;
  bool _showProgress = false;
  double _progressValue = 0.0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));
    _animationController.forward();
    _fetchIntervention();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _fetchIntervention() async {
    try {
      final apiClient = GetIt.instance<ApiClient>();
      final response = await apiClient.post(
        '/api/coaching-notification-intervention',
        {'action': 'attempt_disable'},
      );

      if (mounted) {
        setState(() {
          _interventionData = response;
          _isLoading = false;
          if (response['context'] != null) {
            _progressValue = (response['context']['progress'] ?? 0) / 100;
            _showProgress = response['intervention']?['show_progress'] == true;
          }
        });
      }
    } catch (e) {
      AppLogger.error('Failed to fetch intervention: $e');
      if (mounted) {
        Navigator.of(context).pop(true); // Keep notifications on error
      }
    }
  }

  Future<void> _handleButtonAction(String action) async {
    try {
      final apiClient = GetIt.instance<ApiClient>();
      final response = await apiClient.post(
        '/api/coaching-notification-intervention',
        {'action': action},
      );

      if (!mounted) return;

      switch (response['action']) {
        case 'close_dialog':
          Navigator.of(context).pop(true);
          widget.onNotificationsKept?.call();
          break;

        case 'show_timing_settings':
          Navigator.of(context).pop(true);
          // Navigate to timing settings
          Navigator.of(context).pushNamed('/settings/notifications');
          break;

        case 'show_stats':
          // Show stats in a bottom sheet
          _showStatsBottomSheet(response['stats']);
          break;

        case 'notifications_snoozed':
          Navigator.of(context).pop(true);
          _showSnackBar('Notifications paused for 24 hours');
          break;

        case 'one_more_session':
          Navigator.of(context).pop(true);
          _showSnackBar('Great! See you tomorrow! 💪');
          break;

        case 'reduced_notifications':
          Navigator.of(context).pop(true);
          _showSnackBar('Notifications reduced to evening only');
          break;

        case 'show_personality_selector':
          Navigator.of(context).pop(true);
          Navigator.of(context).pushNamed('/settings/coaching-personality');
          break;

        case 'notifications_disabled':
          Navigator.of(context).pop(false);
          widget.onNotificationsDisabled?.call();
          if (response['penalties_applied'] == true) {
            _showPenaltiesDialog();
          }
          break;

        default:
          Navigator.of(context).pop(true);
      }
    } catch (e) {
      AppLogger.error('Failed to handle action $action: $e');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showStatsBottomSheet(Map<String, dynamic> stats) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Your Progress',
              style: AppTextStyles.headlineSmall.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            _buildStatRow('Sessions Completed', '${stats['completed']}'),
            _buildStatRow('Total Sessions', '${stats['total']}'),
            _buildStatRow(
              'Completion Rate',
              '${stats['percentage'].toStringAsFixed(0)}%',
            ),
            _buildStatRow('Days Active', '${stats['days_active']}'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.bodyLarge),
          Text(
            value,
            style: AppTextStyles.bodyLarge.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  void _showPenaltiesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Penalties Applied'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The following penalties have been applied:',
                style: AppTextStyles.bodyMedium),
            const SizedBox(height: 12),
            _buildPenaltyItem('Streak reset to 0'),
            _buildPenaltyItem('Committed badge removed'),
            _buildPenaltyItem('Excluded from leaderboards'),
            _buildPenaltyItem('Plan marked as abandoned'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('I Understand'),
          ),
        ],
      ),
    );
  }

  Widget _buildPenaltyItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.close, color: Colors.red, size: 16),
          const SizedBox(width: 8),
          Text(text, style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final intervention = _interventionData?['intervention'];
    if (intervention == null) {
      Navigator.of(context).pop(true);
      return const SizedBox.shrink();
    }

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with image/icon
              if (intervention['image'] != null)
                _buildHeaderImage(intervention['image']),

              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title
                    Text(
                      intervention['title'] ?? '',
                      style: AppTextStyles.headlineSmall.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _getTitleColor(intervention['title']),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),

                    // Message
                    Text(
                      intervention['message'] ?? '',
                      style: AppTextStyles.bodyMedium,
                      textAlign: TextAlign.center,
                    ),

                    // Progress indicator if requested
                    if (_showProgress) ...[
                      const SizedBox(height: 24),
                      _buildProgressIndicator(),
                    ],

                    // Warning message
                    if (intervention['warning'] != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.orange.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: Colors.orange, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                intervention['warning'],
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: Colors.orange[800],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Consequences list
                    if (intervention['consequences'] != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Consequences:',
                              style: AppTextStyles.labelMedium.copyWith(
                                color: Colors.red[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...List<Widget>.from(
                              intervention['consequences'].map(
                                (consequence) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('• ',
                                          style: TextStyle(
                                              color: Colors.red[700])),
                                      Expanded(
                                        child: Text(
                                          consequence,
                                          style:
                                              AppTextStyles.bodySmall.copyWith(
                                            color: Colors.red[700],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Action buttons
                    ..._buildActionButtons(intervention['buttons'] ?? []),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderImage(String imageType) {
    IconData icon;
    Color color;

    switch (imageType) {
      case 'drill_sergeant_disappointed':
      case 'drill_sergeant_angry':
        icon = Icons.military_tech;
        color = Colors.red;
        break;
      case 'supportive_concerned':
      case 'supportive_encouraging':
        icon = Icons.favorite;
        color = AppColors.primary;
        break;
      case 'data_chart_down':
        icon = Icons.trending_down;
        color = Colors.orange;
        break;
      case 'last_chance':
        icon = Icons.warning;
        color = Colors.amber;
        break;
      case 'contract_torn':
        icon = Icons.description;
        color = Colors.red;
        break;
      default:
        icon = Icons.notifications_off;
        color = Colors.grey;
    }

    return Container(
      width: double.infinity,
      height: 120,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Icon(
        icon,
        size: 60,
        color: color,
      ),
    );
  }

  Color _getTitleColor(String? title) {
    if (title == null) return Colors.black;
    if (title.contains('NEGATIVE') || title.contains('GIVING UP')) {
      return Colors.red;
    }
    if (title.contains('Wait') || title.contains('Statistical')) {
      return AppColors.primary;
    }
    return Colors.black87;
  }

  Widget _buildProgressIndicator() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Your Progress',
              style: AppTextStyles.labelMedium,
            ),
            Text(
              '${(_progressValue * 100).toInt()}%',
              style: AppTextStyles.labelMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: _progressValue,
            minHeight: 20,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(
              _progressValue > 0.7
                  ? Colors.green
                  : _progressValue > 0.4
                      ? AppColors.primary
                      : Colors.orange,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _progressValue > 0.7
              ? 'So close to your goal!'
              : _progressValue > 0.4
                  ? 'You\'re making great progress!'
                  : 'Every session counts!',
          style: AppTextStyles.bodySmall.copyWith(
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildActionButtons(List<dynamic> buttons) {
    return buttons.map((button) {
      final style = button['style'] ?? 'secondary';
      final isDestructive = style == 'danger';
      final isPrimary = style == 'primary';

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => _handleButtonAction(button['action']),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDestructive
                  ? Colors.red
                  : isPrimary
                      ? AppColors.primary
                      : Colors.grey[300],
              foregroundColor: isDestructive || isPrimary
                  ? Colors.white
                  : Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: isPrimary ? 2 : 0,
            ),
            child: Text(
              button['text'],
              style: AppTextStyles.buttonMedium.copyWith(
                fontWeight: isPrimary ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }
}