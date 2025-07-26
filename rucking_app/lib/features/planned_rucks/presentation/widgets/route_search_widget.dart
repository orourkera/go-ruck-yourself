import 'package:flutter/material.dart';
import 'package:rucking_app/core/models/route.dart' as route_model;
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/loading_indicator.dart';

/// Widget for searching existing routes in the database
class RouteSearchWidget extends StatefulWidget {
  final Function(String, Map<String, dynamic>) onSearch;
  final bool isLoading;

  const RouteSearchWidget({
    super.key,
    required this.onSearch,
    this.isLoading = false,
  });

  @override
  State<RouteSearchWidget> createState() => _RouteSearchWidgetState();
}

class _RouteSearchWidgetState extends State<RouteSearchWidget> {
  final _searchController = TextEditingController();
  List<route_model.Route> _searchResults = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _performSearch(String query) {
    if (query.length < 3) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    // Call the search callback with query and empty filters
    widget.onSearch(query, <String, dynamic>{});
    
    // Reset search state - actual results will be provided via searchResults property
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: AppColors.surfaceLight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Search Routes',
              style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name, location, or tags...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _performSearch('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.dividerLight),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                ),
              ),
              onChanged: _performSearch,
            ),
            const SizedBox(height: 16),
            if (_isSearching)
              const Center(
                child: LoadingIndicator(
                  message: 'Searching routes...',
                ),
              )
            else if (_searchResults.isEmpty && _searchController.text.length >= 3)
              _buildEmptyState()
            else if (_searchResults.isNotEmpty)
              _buildSearchResults(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(
            Icons.search_off,
            size: 48,
            color: AppColors.greyDark,
          ),
          const SizedBox(height: 12),
          Text(
            'No routes found',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textDarkSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Try different keywords or create a new route',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.greyDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    return Column(
      children: _searchResults.map((route) => _buildRouteItem(route)).toList(),
    );
  }

  Widget _buildRouteItem(route_model.Route route) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {}, // No action needed for search results
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.dividerLight),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.route,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        route.name,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textDark,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (route.startLatitude != null && route.startLongitude != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${route.startLatitude?.toStringAsFixed(4) ?? 'N/A'}, ${route.startLongitude?.toStringAsFixed(4) ?? 'N/A'}',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textDarkSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${route.distanceKm?.toStringAsFixed(1)} km',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (route.elevationGainM != null)
                      Text(
                        '${route.elevationGainM!.toInt()}m gain',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textDarkSecondary,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
