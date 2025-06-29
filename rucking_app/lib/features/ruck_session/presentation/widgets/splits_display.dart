import 'package:flutter/material.dart';
import 'package:rucking_app/features/ruck_session/domain/models/session_split.dart';

/// Widget to display splits in a horizontal scrollable list above the heart rate graph
class SplitsDisplay extends StatelessWidget {
  final List<SessionSplit> splits;
  final bool isMetric;

  const SplitsDisplay({
    super.key,
    required this.splits,
    this.isMetric = true,
  });

  @override
  Widget build(BuildContext context) {
    if (splits.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'Splits',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: splits.length,
            itemBuilder: (context, index) {
              final split = splits[index];
              return _SplitCard(
                split: split,
                isMetric: isMetric,
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _SplitCard extends StatelessWidget {
  final SessionSplit split;
  final bool isMetric;

  const _SplitCard({
    required this.split,
    required this.isMetric,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: 120,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Split number and distance
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Split ${split.splitNumber}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${split.splitDistance.toStringAsFixed(0)}${isMetric ? 'km' : 'mi'}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Split time
          Text(
            split.formattedDuration,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          // Split pace
          Text(
            '${split.formattedPace}/${isMetric ? 'km' : 'mi'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          // Calories and elevation (if available)
          if (split.caloriesBurned > 0 || split.elevationGainM > 0) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (split.caloriesBurned > 0)
                  Text(
                    '${split.caloriesBurned.toStringAsFixed(0)} cal',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.secondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                if (split.elevationGainM > 0)
                  Text(
                    '+${split.elevationGainM.toStringAsFixed(0)}m',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.tertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
