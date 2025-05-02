import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';

/// Screen that displays detailed information about a completed session
class SessionDetailScreen extends StatelessWidget {
  final RuckSession session;
  
  const SessionDetailScreen({
    Key? key,
    required this.session,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    // Get user preferences for metric/imperial
    final authState = context.read<AuthBloc>().state;
    final bool preferMetric = authState is Authenticated ? authState.user.preferMetric : true;
    
    // Format date
    final dateFormat = DateFormat('MMMM d, yyyy');
    final timeFormat = DateFormat('h:mm a');
    final formattedDate = dateFormat.format(session.startTime);
    final formattedStartTime = timeFormat.format(session.startTime);
    final formattedEndTime = timeFormat.format(session.endTime);
    
    // Format distance
    final distanceValue = preferMetric 
        ? '${session.distance.toStringAsFixed(2)} km'
        : '${(session.distance * 0.621371).toStringAsFixed(2)} mi';
    
    // Format pace
    final paceValue = session.formattedPace;
    
    // Format elevation
    final elevationGain = preferMetric
        ? '${session.elevationGain.toStringAsFixed(0)} m'
        : '${(session.elevationGain * 3.28084).toStringAsFixed(0)} ft';
    
    final elevationLoss = preferMetric
        ? '${session.elevationLoss.toStringAsFixed(0)} m'
        : '${(session.elevationLoss * 3.28084).toStringAsFixed(0)} ft';
    
    // Format weight
    final weight = preferMetric
        ? '${session.ruckWeightKg.toStringAsFixed(1)} kg'
        : '${(session.ruckWeightKg * 2.20462).toStringAsFixed(1)} lb';
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _shareSession(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header section with date and overview
            Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formattedDate,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$formattedStartTime - $formattedEndTime',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildHeaderStat(
                        context, 
                        Icons.straighten, 
                        'Distance', 
                        distanceValue,
                      ),
                      _buildHeaderStat(
                        context, 
                        Icons.timer, 
                        'Duration', 
                        session.formattedDuration,
                      ),
                      _buildHeaderStat(
                        context, 
                        Icons.speed, 
                        'Pace', 
                        '$paceValue min/km',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Detail stats
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Stats',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  _buildDetailRow(
                    context,
                    'Calories Burned',
                    '${session.caloriesBurned}',
                    Icons.local_fire_department,
                  ),
                  _buildDetailRow(
                    context,
                    'Ruck Weight',
                    weight,
                    Icons.fitness_center,
                  ),
                  _buildDetailRow(
                    context,
                    'Elevation Gain',
                    elevationGain,
                    Icons.trending_up,
                  ),
                  _buildDetailRow(
                    context,
                    'Elevation Loss',
                    elevationLoss,
                    Icons.trending_down,
                  ),
                  
                  // Rating display if available
                  if (session.rating != null) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Rating',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: List.generate(5, (index) {
                        return Icon(
                          index < (session.rating ?? 0) 
                              ? Icons.star 
                              : Icons.star_border,
                          color: Theme.of(context).primaryColor,
                          size: 28,
                        );
                      }),
                    ),
                  ],
                  
                  // Notes display if available
                  if (session.notes?.isNotEmpty == true) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Notes',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Text(
                        session.notes!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildHeaderStat(
    BuildContext context, 
    IconData icon, 
    String label, 
    String value,
  ) {
    return Column(
      children: [
        Icon(
          icon,
          color: Theme.of(context).primaryColor,
          size: 24,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium!.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
  
  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(
            icon,
            color: Theme.of(context).primaryColor,
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium!.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
  
  void _shareSession(BuildContext context) {
    AppLogger.info('Sharing session ${session.id}');
    
    // Format a shareable text
    final dateFormat = DateFormat('MMMM d, yyyy');
    final formattedDate = dateFormat.format(session.startTime);
    
    final shareText = '''
🏋️ Go Rucky Yourself - Session Completed!
📅 $formattedDate
🔄 ${session.formattedDuration}
📏 ${session.distance.toStringAsFixed(2)} km
🔥 ${session.caloriesBurned} calories
⚖️ ${session.ruckWeightKg.toStringAsFixed(1)} kg weight

Download Go Rucky Yourself from the App Store!
''';

    // This would use a share plugin in a real implementation
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sharing not implemented in this version'),
      ),
    );
  }
}
