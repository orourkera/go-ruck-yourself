import 'package:flutter/material.dart';

/// A dialog that explains why the app needs location permissions
/// This is required by Apple App Store guidelines
class LocationPermissionDialog extends StatelessWidget {
  final VoidCallback onAllow;
  final VoidCallback onDeny;
  final bool isPreciseLocationAvailable;

  const LocationPermissionDialog({
    Key? key,
    required this.onAllow,
    required this.onDeny,
    this.isPreciseLocationAvailable = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Location Access'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Go Rucky Yourself needs your location to:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildPermissionItem(
              context,
              Icons.route,
              'Track your routes',
              'Record the path you take during your ruck sessions',
            ),
            const SizedBox(height: 12),
            _buildPermissionItem(
              context,
              Icons.speed,
              'Measure distance and pace',
              'Calculate accurate distance traveled and your pace',
            ),
            const SizedBox(height: 12),
            _buildPermissionItem(
              context,
              Icons.terrain,
              'Calculate elevation',
              'Determine elevation gain and loss during your rucks',
            ),
            const SizedBox(height: 16),
            const Text(
              'Location precision options:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildPrecisionOption(
              context,
              true,
              'Precise: For accurate tracking (recommended)'
            ),
            const SizedBox(height: 4),
            _buildPrecisionOption(
              context,
              false,
              'Approximate: Less accurate but more private'
            ),
            const SizedBox(height: 16),
            const Text(
              'Your privacy matters:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '• Location data is only used while the app is in use\n'
              '• Your routes are stored securely on your device\n'
              '• You can revoke access anytime in Settings',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: onDeny,
          child: const Text('Deny'),
        ),
        ElevatedButton(
          onPressed: onAllow,
          child: const Text('Allow'),
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
  
  Widget _buildPrecisionOption(
    BuildContext context,
    bool isPrecise,
    String description,
  ) {
    final bool isSelected = isPrecise == isPreciseLocationAvailable;
    
    return Row(
      children: [
        Icon(
          isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: Theme.of(context).primaryColor,
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: isSelected ? Theme.of(context).primaryColor : Colors.grey[700],
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}
