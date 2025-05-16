import 'package:flutter/material.dart';

/// A dialog that explains why the app needs health permissions
/// This is required by Apple App Store guidelines
/// Updated to comply with Apple's guidance on permission flows
class HealthPermissionDialog extends StatelessWidget {
  final VoidCallback onContinue;

  const HealthPermissionDialog({
    Key? key,
    required this.onContinue,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Health Data Access'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Go Rucky Yourself would like to access your health data to:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildPermissionItem(
              context,
              Icons.directions_walk,
              'Record your workouts',
              'Save your ruck sessions to Apple Health as workouts',
            ),
            const SizedBox(height: 12),
            _buildPermissionItem(
              context,
              Icons.local_fire_department,
              'Track calories burned',
              'Calculate and record calories burned during rucks',
            ),
            const SizedBox(height: 12),
            _buildPermissionItem(
              context,
              Icons.monitor_heart,
              'Monitor heart rate',
              'Read heart rate during workouts if available',
            ),
            const SizedBox(height: 16),
            const Text(
              'Your privacy matters:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '• All health data stays on your device\n'
              '• We never share your health data with third parties\n'
              '• You can revoke access anytime in Settings',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: onContinue,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
          ),
          child: const Text('Continue'),
        ),
      ],
    );
  }

  Widget _buildPermissionItem(
    BuildContext context,
    IconData icon,
    String title,
    String description,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: Theme.of(context).primaryColor,
          size: 24,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
