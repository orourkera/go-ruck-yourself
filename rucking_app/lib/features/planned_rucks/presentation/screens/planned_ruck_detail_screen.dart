import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rucking_app/core/models/planned_ruck.dart';
import 'package:rucking_app/core/models/route.dart' as route_model;
import 'package:rucking_app/features/planned_rucks/presentation/bloc/planned_ruck_bloc.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/planned_ruck_event.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/planned_ruck_state.dart';
import 'package:rucking_app/features/planned_rucks/presentation/widgets/route_map_preview.dart';

import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/core/models/weather.dart';
import 'package:rucking_app/core/services/weather_service.dart';
import 'package:rucking_app/shared/widgets/weather/weather_card.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/active_session_page.dart';
import 'package:latlong2/latlong.dart' as latlong;

/// Detailed view screen for a planned ruck
class PlannedRuckDetailScreen extends StatefulWidget {
  final String plannedRuckId;

  const PlannedRuckDetailScreen({
    super.key,
    required this.plannedRuckId,
  });

  @override
  State<PlannedRuckDetailScreen> createState() => _PlannedRuckDetailScreenState();
}

class _PlannedRuckDetailScreenState extends State<PlannedRuckDetailScreen> {
  late ScrollController _scrollController;
  late WeatherService _weatherService;
  bool _showAppBarTitle = false;
  PlannedRuck? _plannedRuck;
  Weather? _weather;
  bool _isLoadingWeather = false;
  String? _weatherError;

  @override
  void initState() {
    super.initState();
    // Removed tab controller since we only have overview content
    _scrollController = ScrollController();
    _weatherService = WeatherService();
    
    // Load the planned ruck using the ID
    context.read<PlannedRuckBloc>().add(
      LoadPlannedRuckById(plannedRuckId: widget.plannedRuckId),
    );
    
    _scrollController.addListener(() {
      final shouldShow = _scrollController.offset > 200;
      if (shouldShow != _showAppBarTitle) {
        setState(() {
          _showAppBarTitle = shouldShow;
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Load weather data for the planned ruck
  Future<void> _loadWeatherData() async {
    if (_plannedRuck?.route == null || _plannedRuck?.plannedDate == null) {
      return;
    }

    setState(() {
      _isLoadingWeather = true;
      _weatherError = null;
    });

    try {
      final weather = await _weatherService.getWeatherForPlannedRuck(
        startLatitude: _plannedRuck!.route!.startLatitude,
        startLongitude: _plannedRuck!.route!.startLongitude,
        plannedDate: _plannedRuck!.plannedDate!,
      );

      if (mounted) {
        setState(() {
          _weather = weather;
          _isLoadingWeather = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _weatherError = 'Unable to load weather data';
          _isLoadingWeather = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PlannedRuckBloc, PlannedRuckState>(
      listener: (context, state) {
        if (state is PlannedRuckLoading) {
          // Show loading if needed
        } else if (state is PlannedRuckError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppColors.accent,
            ),
          );
        } else if (state is PlannedRuckLoaded) {
          // Use the selectedRuck from the state (loaded by LoadPlannedRuckById)
          final plannedRuck = state.selectedRuck ?? 
              state.plannedRucks
                  .where((ruck) => ruck.id == widget.plannedRuckId)
                  .firstOrNull;
          
          if (plannedRuck != null) {
            setState(() {
              _plannedRuck = plannedRuck;
            });
            
            // Load weather data if we have route coordinates and planned date
            _loadWeatherData();
          }
        } else if (state is PlannedRuckActionSuccess && state.action == PlannedRuckAction.start) {
          // Check location and navigate to active session when ruck is successfully started
          _checkLocationAndNavigate();
        } else if (state is PlannedRuckActionError && state.action == PlannedRuckAction.start) {
          // Show error message when ruck start fails
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppColors.accent,
            ),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: AppColors.backgroundLight,
          body: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // App bar with hero image
              _buildSliverAppBar(_plannedRuck?.route),
              
              // Content
              SliverFillRemaining(
                child: _buildOverviewTab(),
              ),
            ],
          ),
          
          // Floating action buttons
          floatingActionButton: _buildFloatingActions(),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        );
      },
    );
  }

  Widget _buildSliverAppBar(route_model.Route? route) {
    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      backgroundColor: AppColors.backgroundLight,
      title: _showAppBarTitle 
          ? Text(
              route?.name ?? 'Planned Ruck',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.bold,
              ),
            )
          : null,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Background image or gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.8),
                    AppColors.primary,
                  ],
                ),
              ),
            ),
            
            // Route map preview (if available)
            if (route != null)
              Positioned.fill(
                child: RouteMapPreview(
                  route: route,
                  isHeroImage: true,
                  showOverlay: true,
                ),
              ),
            
            // Overlay content
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Route name
                  Text(
                    route?.name ?? 'Unnamed Route',
                    style: AppTextStyles.headlineMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          color: Colors.grey.shade600.withAlpha(128),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Status and badges
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(26),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _plannedRuck?.status.name.toLowerCase() ?? '',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (route?.trailDifficulty != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.secondary.withAlpha(26),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            route?.trailDifficulty ?? 'Unknown',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.secondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Quick stats
                  if (route != null)
                    Row(
                      children: [
                        _buildQuickStat(Icons.straighten, route.formattedDistance),
                        if (route.elevationGainM != null) ...[
                          const SizedBox(width: 16),
                          _buildQuickStat(Icons.trending_up, route.formattedElevationGain),
                        ],
                        if (route.estimatedDurationMinutes != null) ...[
                          const SizedBox(width: 16),
                          _buildQuickStat(Icons.access_time, route.formattedEstimatedDuration),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStat(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: Colors.white.withValues(alpha: 0.9),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(
            color: Colors.white.withValues(alpha: 0.9),
            fontWeight: FontWeight.w600,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewTab() {
    final route = _plannedRuck?.route;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Planned ruck info card
          _buildInfoCard(
            'Planned Ruck Details',
            Icons.calendar_today,
            [
              _buildInfoRow('Planned Date', _plannedRuck?.formattedPlannedDate ?? ''),
              _buildInfoRow('Status', _plannedRuck?.status.value ?? ''),
              if (_plannedRuck?.notes?.isNotEmpty == true)
                _buildInfoRow('Notes', _plannedRuck?.notes ?? ''),
              if (_plannedRuck?.completedAt != null)
                _buildInfoRow('Completed', '${_plannedRuck?.completedAt?.day ?? 0}/${_plannedRuck?.completedAt?.month ?? 0}/${_plannedRuck?.completedAt?.year ?? 0}'),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Route overview
          if (route != null) ...[
            _buildInfoCard(
              'Route Overview',
              Icons.route,
              [
                _buildInfoRow('Location', '${route.startLatitude.toStringAsFixed(4)}, ${route.startLongitude.toStringAsFixed(4)}'),
                _buildInfoRow('Distance', route.formattedDistance),
                if (route.elevationGainM != null)
                  _buildInfoRow('Elevation Gain', route.formattedElevationGain),
                if (route.estimatedDurationMinutes != null)
                  _buildInfoRow('Estimated Duration', route.formattedEstimatedDuration),
                if (route.routeType != null)
                  _buildInfoRow('Route Type', _getRouteTypeLabel(route.routeType!)),
              ],
            ),
            
            const SizedBox(height: 16),
          ],
          
          // Route description
          if (route?.description?.isNotEmpty == true) ...[
            _buildInfoCard(
              'Description',
              Icons.description,
              [
                Text(
                  route?.description ?? '',
                  style: AppTextStyles.bodyLarge,
                ),
              ],
            ),
            
            const SizedBox(height: 16),
          ],
          
          // Ratings and reviews
          if (route?.averageRating != null || route?.totalCompletedCount != null) ...[
            _buildRatingsCard(route!),
            const SizedBox(height: 16),
          ],
          
          // Weather info (placeholder)
          _buildWeatherCard(),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, IconData icon, List<Widget> children) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textDarkSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingsCard(route_model.Route route) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.star, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Ratings & Reviews',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            Row(
              children: [
                // Star rating
                Row(
                  children: List.generate(5, (index) {
                    final rating = route.averageRating ?? 0.0;
                    return Icon(
                      index < rating.floor()
                          ? Icons.star
                          : index < rating
                              ? Icons.star_half
                              : Icons.star_border,
                      color: Colors.amber,
                      size: 20,
                    );
                  }),
                ),
                const SizedBox(width: 8),
                Text(
                  (route.averageRating ?? 0.0).toStringAsFixed(1),
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (route.totalCompletedCount != null) ...[
                  Text(
                    ' (${route.totalCompletedCount} reviews)',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textDarkSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPOICard(route_model.Route route) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.place, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Points of Interest',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            ...route.pointsOfInterest.take(5).map((poi) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      _getPOIIcon(poi.poiType),
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        poi.name,
                        style: AppTextStyles.bodyMedium,
                      ),
                    ),
                    Text(
                        '${poi.distanceFromStartKm.toStringAsFixed(1)} km',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textDarkSecondary,
                        ),
                      ),
                  ],
                ),
              );
            }),
            
            if (route.pointsOfInterest.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '+${route.pointsOfInterest.length - 5} more points of interest',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textDarkSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeatherCard() {
    return WeatherCard(
      weather: _weather,
      isLoading: _isLoadingWeather,
      errorMessage: _weatherError,
      onRetry: _loadWeatherData,
    );
  }

  Widget _buildFloatingActions() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Share button
        FloatingActionButton(
          heroTag: 'share',
          onPressed: _shareRoute,
          backgroundColor: AppColors.backgroundLight,
          foregroundColor: AppColors.primary,
          child: const Icon(Icons.share),
        ),
        
        const SizedBox(height: 16),
        
        // Primary action button
        FloatingActionButton.extended(
          heroTag: 'primary',
          onPressed: _performPrimaryAction,
          backgroundColor: _getPrimaryActionColor(),
          foregroundColor: Colors.white,
          icon: Icon(_getPrimaryActionIcon()),
          label: Text(_getPrimaryActionLabel()),
        ),
      ],
    );
  }

  // Helper methods

  String _getRouteTypeLabel(route_model.RouteType type) {
    switch (type) {
      case route_model.RouteType.loop:
        return 'Loop';
      case route_model.RouteType.outAndBack:
        return 'Out & Back';
      case route_model.RouteType.pointToPoint:
        return 'Point to Point';
    }
  }

  IconData _getPOIIcon(String type) {
    switch (type.toLowerCase()) {
      case 'water':
        return Icons.water_drop;
      case 'restroom':
        return Icons.wc;
      case 'viewpoint':
        return Icons.visibility;
      case 'parking':
        return Icons.local_parking;
      default:
        return Icons.place;
    }
  }

  Color _getPrimaryActionColor() {
    if (_plannedRuck == null) return AppColors.textDarkSecondary;
    
    switch (_plannedRuck!.status) {
      case PlannedRuckStatus.planned:
        return _plannedRuck!.canStart ? AppColors.primary : AppColors.textDarkSecondary;
      case PlannedRuckStatus.inProgress:
        return AppColors.info;
      default:
        return AppColors.textDarkSecondary;
    }
  }

  IconData _getPrimaryActionIcon() {
    if (_plannedRuck == null) return Icons.edit;
    
    switch (_plannedRuck!.status) {
      case PlannedRuckStatus.planned:
        return Icons.play_arrow;
      case PlannedRuckStatus.inProgress:
        return Icons.visibility;
      default:
        return Icons.edit;
    }
  }

  String _getPrimaryActionLabel() {
    if (_plannedRuck == null) return 'Edit';
    
    switch (_plannedRuck!.status) {
      case PlannedRuckStatus.planned:
        return _plannedRuck!.canStart ? 'Start Ruck' : 'Edit';
      case PlannedRuckStatus.inProgress:
        return 'View Session';
      default:
        return 'Edit';
    }
  }

  void _performPrimaryAction() {
    if (_plannedRuck == null) return;
    
    switch (_plannedRuck!.status) {
      case PlannedRuckStatus.planned:
        if (_plannedRuck!.canStart) {
          context.read<PlannedRuckBloc>().add(
            StartPlannedRuck(plannedRuckId: _plannedRuck!.id ?? ''),
          );
        }
        break;
      case PlannedRuckStatus.inProgress:
        // Navigate to active session
        break;
      default:
        // Navigate to edit screen
        break;
    }
  }

  void _shareRoute() {
    // TODO: Implement route sharing
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sharing functionality coming soon!')),
    );
  }

  /// Calculate distance between two coordinates in meters
  double _calculateDistance(latlong.LatLng point1, latlong.LatLng point2) {
    const double earthRadius = 6371000; // Earth radius in meters
    double lat1Rad = point1.latitude * (pi / 180);
    double lat2Rad = point2.latitude * (pi / 180);
    double deltaLatRad = (point2.latitude - point1.latitude) * (pi / 180);
    double deltaLngRad = (point2.longitude - point1.longitude) * (pi / 180);

    double a = sin(deltaLatRad / 2) * sin(deltaLatRad / 2) +
        cos(lat1Rad) * cos(lat2Rad) *
        sin(deltaLngRad / 2) * sin(deltaLngRad / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  /// Check distance to route start and potentially show warning
  Future<void> _checkLocationAndNavigate() async {
    if (_plannedRuck?.route == null) return;

    final route = _plannedRuck!.route!;
    
    // Create initial center from route start coordinates
    latlong.LatLng? routeStart;
    if (route.startLatitude != null && route.startLongitude != null) {
      routeStart = latlong.LatLng(route.startLatitude!, route.startLongitude!);
    }

    // If we have a route start, check user's distance to it
    if (routeStart != null) {
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
        
        final currentLocation = latlong.LatLng(position.latitude, position.longitude);
        final distanceToStart = _calculateDistance(currentLocation, routeStart);
        
        // Show warning if more than 500m from route start
        if (distanceToStart > 500) {
          _showStartLocationWarning(distanceToStart);
          return; // Don't navigate yet, let user decide
        }
      } catch (e) {
        debugPrint('Could not check start location: $e');
        // Continue anyway if location check fails
      }
    }

    // If we're close enough or couldn't check, proceed with navigation
    _navigateToActiveSession();
  }

  /// Show warning when user is far from planned route start
  void _showStartLocationWarning(double distanceMeters) {
    final distanceText = distanceMeters > 1000 
        ? '${(distanceMeters / 1000).toStringAsFixed(1)} km'
        : '${distanceMeters.round()} m';
        
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Far from Trailhead'),
        content: Text(
          'You are $distanceText away from this route\'s starting point. '
          'For the best experience, consider getting closer to the trailhead first.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: Could implement navigation to trailhead here
            },
            child: const Text('Navigate There'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _navigateToActiveSession(); // Continue anyway
            },
            child: const Text('Start Anyway'),
          ),
        ],
      ),
    );
  }

  void _navigateToActiveSession() {
    if (_plannedRuck?.route == null) return;

    final route = _plannedRuck!.route!;
    
    // Create initial center from route start coordinates
    latlong.LatLng? initialCenter;
    if (route.startLatitude != null && route.startLongitude != null) {
      initialCenter = latlong.LatLng(route.startLatitude!, route.startLongitude!);
    }

    // Parse planned route polyline for background reference
    List<latlong.LatLng>? plannedRoutePoints;
    if (route.routePolyline?.isNotEmpty == true) {
      try {
        final polylinePoints = <latlong.LatLng>[];
        final coordinates = route.routePolyline!.split(';');
        for (final coord in coordinates) {
          final parts = coord.trim().split(',');
          if (parts.length == 2) {
            final lat = double.tryParse(parts[0]);
            final lng = double.tryParse(parts[1]);
            if (lat != null && lng != null) {
              polylinePoints.add(latlong.LatLng(lat, lng));
            }
          }
        }
        if (polylinePoints.isNotEmpty) {
          plannedRoutePoints = polylinePoints;
        }
      } catch (e) {
        debugPrint('Error parsing planned route polyline: $e');
      }
    }

    // Navigate to active session page
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => ActiveSessionPage(
          args: ActiveSessionArgs(
            ruckWeight: _plannedRuck!.targetWeight ?? 0.0,
            userWeightKg: 70.0, // TODO: Get actual user weight from user profile
            notes: _plannedRuck!.notes,
            plannedDuration: route.estimatedDurationMinutes * 60,
            initialCenter: initialCenter,
            plannedRoute: plannedRoutePoints, // Pass the planned route
          ),
        ),
      ),
    );
  }
}

