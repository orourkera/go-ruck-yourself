import 'package:flutter/material.dart';
import 'package:rucking_app/core/models/terrain_segment.dart';
import 'package:rucking_app/core/services/terrain_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';

class TerrainInfoWidget extends StatelessWidget {
  final List<TerrainSegment> terrainSegments;
  final bool isExpanded;
  final bool preferMetric;
  final VoidCallback? onToggle;

  const TerrainInfoWidget({
    Key? key,
    required this.terrainSegments,
    required this.preferMetric,
    this.isExpanded = false,
    this.onToggle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    print('[TERRAIN_WIDGET] BUILD METHOD CALLED - ${terrainSegments.length} segments');
    AppLogger.debug('[TERRAIN_WIDGET] Building with ${terrainSegments.length} terrain segments');
    
    final stats = TerrainSegment.getTerrainStats(terrainSegments);
    final terrainBreakdown = stats['surface_breakdown'] as Map<String, double>? ?? <String, double>{};
    final weightedMultiplier = stats['weighted_multiplier'] as double? ?? 1.0;
    final totalDistance = stats['total_distance_km'] as double? ?? 0.0;
    final mostCommonSurface = stats['most_common_surface'] as String? ?? 'paved';
    
    AppLogger.debug('[TERRAIN_WIDGET] Showing terrain data: ${terrainSegments.length} segments, ${totalDistance.toStringAsFixed(3)}km total');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      color: terrainSegments.isEmpty ? Colors.grey[50] : null,
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              Icons.terrain,
              color: terrainSegments.isEmpty ? Colors.grey : _getTerrainColor(weightedMultiplier),
            ),
            title: Text(
              terrainSegments.isEmpty ? 'Terrain' : _formatSurfaceType(mostCommonSurface),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              terrainSegments.isEmpty 
                ? 'Tracking terrain - data will appear as you move'
                : '${weightedMultiplier.toStringAsFixed(2)}x multiplier',
              style: TextStyle(
                color: terrainSegments.isEmpty ? Colors.grey : _getTerrainColor(weightedMultiplier),
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: onToggle != null
                ? IconButton(
                    icon: Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    onPressed: onToggle,
                  )
                : null,
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (terrainSegments.isEmpty) 
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      child: Center(
                        child: Text(
                          'Terrain data will appear as you move',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    )
                  else ...[
                    Text(
                      'Surface Breakdown',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...terrainBreakdown.entries
                        .where((entry) => entry.value > 0)
                        .map((entry) => _buildTerrainRow(
                              context,
                              entry.key,
                              entry.value,
                              totalDistance,
                            )),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTerrainRow(
    BuildContext context,
    String surfaceType,
    double distance,
    double totalDistance,
  ) {
    final percentage = totalDistance > 0 ? (distance / totalDistance) * 100 : 0;
    final multiplier = TerrainService.getEnergyMultiplier(surfaceType);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: _getSurfaceColor(surfaceType),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _formatSurfaceType(surfaceType),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Text(
            MeasurementUtils.formatDistance(distance, metric: preferMetric),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '(${percentage.toStringAsFixed(0)}%)',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _getMultiplierColor(multiplier).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${multiplier.toStringAsFixed(1)}x',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _getMultiplierColor(multiplier),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatSurfaceType(String surfaceType) {
    return surfaceType
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  Color _getTerrainColor(double multiplier) {
    if (multiplier <= 1.0) return Colors.green;
    if (multiplier <= 1.2) return Colors.orange;
    return Colors.red;
  }

  Color _getSurfaceColor(String surfaceType) {
    switch (surfaceType.toLowerCase()) {
      case 'paved':
      case 'asphalt':
      case 'concrete':
        return Colors.grey[700]!;
      case 'gravel':
        return Colors.grey[500]!;
      case 'dirt':
      case 'earth':
        return Colors.brown;
      case 'grass':
        return Colors.green;
      case 'sand':
        return Colors.orange;
      case 'mud':
        return Colors.brown[800]!;
      case 'snow':
        return Colors.blue[100]!;
      case 'rock':
      case 'stone':
        return Colors.grey[800]!;
      default:
        return Colors.grey;
    }
  }

  Color _getMultiplierColor(double multiplier) {
    if (multiplier <= 1.0) return Colors.green;
    if (multiplier <= 1.2) return Colors.orange;
    if (multiplier <= 1.5) return Colors.deepOrange;
    return Colors.red;
  }
}
