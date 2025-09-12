import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rucking_app/core/models/route.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Widget for searching imported routes with filters
class RouteSearchWidget extends StatefulWidget {
  final Function(String query, Map<String, dynamic> filters) onSearch;
  final bool isLoading;

  const RouteSearchWidget({
    super.key,
    required this.onSearch,
    this.isLoading = false,
  });

  @override
  State<AllTrailsSearchWidget> createState() => _AllTrailsSearchWidgetState();
}

class _RouteSearchWidgetState extends State<RouteSearchWidget>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();

  bool _showAdvancedFilters = false;
  bool _useCurrentLocation = false;
  double? _currentLatitude;
  double? _currentLongitude;
  int _maxDistance = 10; // miles
  RouteDifficulty? _selectedDifficulty;
  RouteType? _selectedRouteType;

  late AnimationController _animationController;
  late Animation<double> _expansionAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expansionAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _locationController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search input
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            labelText: 'Search routes',
            hintText: 'Enter route name or location...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _buildSearchSuffixIcon(),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _performSearch(),
        ),

        const SizedBox(height: 12),

        // Advanced filters toggle
        Row(
          children: [
            TextButton.icon(
              onPressed: _toggleAdvancedFilters,
              icon: Icon(
                _showAdvancedFilters ? Icons.expand_less : Icons.expand_more,
                size: 20,
              ),
              label: Text(
                _showAdvancedFilters ? 'Hide Filters' : 'Show Filters',
                style: AppTextStyles.body2,
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                minimumSize: const Size(0, 32),
              ),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: widget.isLoading ? null : _performSearch,
              icon: widget.isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.search, size: 18),
              label: Text(widget.isLoading ? 'Searching...' : 'Search Routes'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(100, 36),
              ),
            ),
          ],
        ),

        // Advanced filters
        SizeTransition(
          sizeFactor: _expansionAnimation,
          child: _buildAdvancedFilters(),
        ),
      ],
    );
  }

  Widget _buildSearchSuffixIcon() {
    if (_searchController.text.isNotEmpty) {
      return IconButton(
        onPressed: () {
          _searchController.clear();
        },
        icon: const Icon(Icons.clear),
        tooltip: 'Clear search',
      );
    }
    return null;
  }

  Widget _buildAdvancedFilters() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.divider,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Location section
          Row(
            children: [
              Icon(
                Icons.location_on,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Location',
                style: AppTextStyles.subtitle2.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Current location toggle
          Row(
            children: [
              Checkbox(
                value: _useCurrentLocation,
                onChanged: (value) {
                  setState(() {
                    _useCurrentLocation = value ?? false;
                  });
                  if (_useCurrentLocation) {
                    _getCurrentLocation();
                  }
                },
                activeColor: AppColors.primary,
              ),
              Expanded(
                child: Text(
                  'Use current location',
                  style: AppTextStyles.body2,
                ),
              ),
              if (_useCurrentLocation && _currentLatitude != null)
                Icon(
                  Icons.check_circle,
                  size: 20,
                  color: AppColors.success,
                ),
            ],
          ),

          // Manual location input
          if (!_useCurrentLocation) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _locationController,
              decoration: InputDecoration(
                labelText: 'Location',
                hintText: 'City, State or coordinates',
                prefixIcon: const Icon(Icons.location_city),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Distance slider
          if (_useCurrentLocation || _locationController.text.isNotEmpty) ...[
            Text(
              'Distance: ${_maxDistance} miles',
              style: AppTextStyles.subtitle2.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Slider(
              value: _maxDistance.toDouble(),
              min: 1,
              max: 50,
              divisions: 49,
              activeColor: AppColors.primary,
              onChanged: (value) {
                setState(() {
                  _maxDistance = value.round();
                });
              },
            ),
            const SizedBox(height: 16),
          ],

          // Difficulty filter
          Row(
            children: [
              Icon(
                Icons.trending_up,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Difficulty',
                style: AppTextStyles.subtitle2.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _buildFilterChip(
                'Any',
                _selectedDifficulty == null,
                () => setState(() => _selectedDifficulty = null),
              ),
              ...RouteDifficulty.values.map((difficulty) {
                return _buildFilterChip(
                  _getDifficultyLabel(difficulty),
                  _selectedDifficulty == difficulty,
                  () => setState(() {
                    _selectedDifficulty =
                        _selectedDifficulty == difficulty ? null : difficulty;
                  }),
                  color: _getDifficultyColor(difficulty),
                );
              }),
            ],
          ),

          const SizedBox(height: 16),

          // Route type filter
          Row(
            children: [
              Icon(
                Icons.route,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Route Type',
                style: AppTextStyles.subtitle2.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _buildFilterChip(
                'Any',
                _selectedRouteType == null,
                () => setState(() => _selectedRouteType = null),
              ),
              ...RouteType.values.map((type) {
                return _buildFilterChip(
                  _getRouteTypeLabel(type),
                  _selectedRouteType == type,
                  () => setState(() {
                    _selectedRouteType =
                        _selectedRouteType == type ? null : type;
                  }),
                );
              }),
            ],
          ),

          const SizedBox(height: 16),

          // Clear filters button
          if (_hasActiveFilters())
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _clearFilters,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.error,
                  minimumSize: const Size(0, 32),
                ),
                child: const Text('Clear All Filters'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    bool isSelected,
    VoidCallback onTap, {
    Color? color,
  }) {
    final chipColor = color ?? AppColors.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? chipColor : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? chipColor : chipColor.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: isSelected ? Colors.white : chipColor,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  void _toggleAdvancedFilters() {
    setState(() {
      _showAdvancedFilters = !_showAdvancedFilters;
    });

    if (_showAdvancedFilters) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showLocationError('Location permissions are denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showLocationError('Location permissions are permanently denied');
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentLatitude = position.latitude;
        _currentLongitude = position.longitude;
      });
    } catch (e) {
      _showLocationError('Failed to get current location: $e');
      setState(() {
        _useCurrentLocation = false;
      });
    }
  }

  void _performSearch() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _showErrorSnackBar('Please enter a search term');
      return;
    }

    final filters = <String, dynamic>{};

    if (_useCurrentLocation &&
        _currentLatitude != null &&
        _currentLongitude != null) {
      filters['latitude'] = _currentLatitude;
      filters['longitude'] = _currentLongitude;
      filters['maxDistance'] = _maxDistance;
    } else if (_locationController.text.isNotEmpty) {
      // TODO: Geocode location string to coordinates
      filters['location'] = _locationController.text.trim();
      filters['maxDistance'] = _maxDistance;
    }

    if (_selectedDifficulty != null) {
      filters['difficulty'] = _selectedDifficulty;
    }

    if (_selectedRouteType != null) {
      filters['routeType'] = _selectedRouteType;
    }

    widget.onSearch(query, filters);
  }

  bool _hasActiveFilters() {
    return _useCurrentLocation ||
        _locationController.text.isNotEmpty ||
        _selectedDifficulty != null ||
        _selectedRouteType != null;
  }

  void _clearFilters() {
    setState(() {
      _useCurrentLocation = false;
      _currentLatitude = null;
      _currentLongitude = null;
      _locationController.clear();
      _maxDistance = 10;
      _selectedDifficulty = null;
      _selectedRouteType = null;
    });
  }

  String _getDifficultyLabel(RouteDifficulty difficulty) {
    switch (difficulty) {
      case RouteDifficulty.easy:
        return 'Easy';
      case RouteDifficulty.moderate:
        return 'Moderate';
      case RouteDifficulty.hard:
        return 'Hard';
    }
  }

  Color _getDifficultyColor(RouteDifficulty difficulty) {
    switch (difficulty) {
      case RouteDifficulty.easy:
        return AppColors.success;
      case RouteDifficulty.moderate:
        return AppColors.warning;
      case RouteDifficulty.hard:
        return AppColors.error;
    }
  }

  String _getRouteTypeLabel(RouteType type) {
    switch (type) {
      case RouteType.loop:
        return 'Loop';
      case RouteType.outAndBack:
        return 'Out & Back';
      case RouteType.pointToPoint:
        return 'Point to Point';
    }
  }

  void _showLocationError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
          action: SnackBarAction(
            label: 'Settings',
            textColor: Colors.white,
            onPressed: () => Geolocator.openAppSettings(),
          ),
        ),
      );
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}
