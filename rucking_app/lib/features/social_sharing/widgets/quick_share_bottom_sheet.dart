import 'package:flutter/material.dart';
import 'package:rucking_app/features/social_sharing/screens/share_preview_screen.dart';
import 'package:rucking_app/features/social_sharing/models/time_range.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bottom sheet that prompts users to share their ruck
class QuickShareBottomSheet extends StatelessWidget {
  final String sessionId;
  final double distanceKm;
  final Duration duration;
  final String? achievement;
  final VoidCallback onDismiss;

  const QuickShareBottomSheet({
    Key? key,
    required this.sessionId,
    required this.distanceKm,
    required this.duration,
    this.achievement,
    required this.onDismiss,
  }) : super(key: key);

  static Future<void> show({
    required BuildContext context,
    required String sessionId,
    required double distanceKm,
    required Duration duration,
    String? achievement,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Check if user has dismissed too many times
    final dismissCount = prefs.getInt('share_prompt_dismiss_count') ?? 0;
    final lastDismiss = prefs.getString('share_prompt_last_dismiss');

    if (dismissCount >= 3) {
      if (lastDismiss != null) {
        final lastDismissDate = DateTime.parse(lastDismiss);
        final daysSinceDismiss = DateTime.now().difference(lastDismissDate).inDays;
        if (daysSinceDismiss < 30) {
          // User has dismissed 3 times in last 30 days, don't show
          return;
        } else {
          // Reset counter after 30 days
          await prefs.setInt('share_prompt_dismiss_count', 0);
        }
      }
    }

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => QuickShareBottomSheet(
        sessionId: sessionId,
        distanceKm: distanceKm,
        duration: duration,
        achievement: achievement,
        onDismiss: () async {
          // Track dismissal
          await prefs.setInt(
            'share_prompt_dismiss_count',
            dismissCount + 1,
          );
          await prefs.setString(
            'share_prompt_last_dismiss',
            DateTime.now().toIso8601String(),
          );
          Navigator.pop(context);
        },
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(20),
          bottom: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Icon and title
            if (achievement != null) ...[
              const Text(
                '🏆',
                style: TextStyle(fontSize: 48),
              ),
              const SizedBox(height: 12),
              Text(
                'Achievement Unlocked!',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                achievement!,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
            ] else ...[
              const Text(
                '💪',
                style: TextStyle(fontSize: 48),
              ),
              const SizedBox(height: 12),
              Text(
                'Great Ruck!',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Stats
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStat(
                  context,
                  label: 'Distance',
                  value: '${distanceKm.toStringAsFixed(1)} km',
                  icon: Icons.straighten,
                ),
                _buildStat(
                  context,
                  label: 'Duration',
                  value: _formatDuration(duration),
                  icon: Icons.timer_outlined,
                ),
                _buildStat(
                  context,
                  label: 'Pace',
                  value: '${(duration.inMinutes / distanceKm).toStringAsFixed(1)} min/km',
                  icon: Icons.speed,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Share button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SharePreviewScreen(
                        sessionId: sessionId,
                        initialTimeRange: TimeRange.lastRuck,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.share),
                label: const Text('Share This Ruck'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Not now button
            TextButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString(
                  'share_prompt_snoozed_until',
                  DateTime.now().add(const Duration(days: 7)).toIso8601String(),
                );
                Navigator.pop(context);
              },
              child: Text(
                'Not Now (Snooze for 7 days)',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),

            // Dismiss button
            TextButton(
              onPressed: onDismiss,
              child: Text(
                'Dismiss',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
  }) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Icon(
          icon,
          size: 24,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}