import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/route_import_bloc.dart';
import 'package:rucking_app/features/planned_rucks/presentation/widgets/route_preview_card.dart';
import 'package:rucking_app/core/models/route.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/buttons/primary_button.dart';
import 'package:rucking_app/shared/widgets/loading_states/loading_overlay.dart';

/// 🔍 **Route Search Screen**
/// 
/// Search through imported routes and saved routes
class RouteSearchScreen extends StatefulWidget {
  const RouteSearchScreen({Key? key}) : super(key: key);
  
  @override
  State<RouteSearchScreen> createState() => _RouteSearchScreenState();
}

class _RouteSearchScreenState extends State<RouteSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'all';
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Routes'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search Header
          _buildSearchHeader(context),
          
          // Filter Chips
          _buildFilterChips(context),
          
          // Search Results
          Expanded(
            child: _buildSearchResults(context),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSearchHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Search Bar
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search AllTrails routes...',
              hintStyle: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.getSubtleTextColor(context),
              ),
              prefixIcon: Icon(
                Icons.search,
                color: AppColors.getSubtleTextColor(context),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.dividerLight),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.dividerLight),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primary),
              ),
              filled: true,
              fillColor: AppColors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
          ),
          
          const SizedBox(height: 16),
          
          // Quick Actions
          Row(
            children: [
              Expanded(
                child: _buildQuickAction(
                  context,
                  icon: Icons.location_on,
                  label: 'Near Me',
                  onTap: () => _searchNearby(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildQuickAction(
                  context,
                  icon: Icons.favorite,
                  label: 'Favorites',
                  onTap: () => _searchFavorites(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildQuickAction(
                  context,
                  icon: Icons.trending_up,
                  label: 'Popular',
                  onTap: () => _searchPopular(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildQuickAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.dividerLight),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFilterChips(BuildContext context) {
    final filters = [
      {'key': 'all', 'label': 'All Routes', 'icon': Icons.all_inclusive},
      {'key': 'imported', 'label': 'Imported', 'icon': Icons.file_download},
      {'key': 'created', 'label': 'Created', 'icon': Icons.add_circle},
      {'key': 'saved', 'label': 'Saved', 'icon': Icons.bookmark},
      {'key': 'recent', 'label': 'Recent', 'icon': Icons.history},
    ];
    
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = _selectedFilter == filter['key'];
          
          return Padding(
            padding: EdgeInsets.only(right: index < filters.length - 1 ? 8 : 0),
            child: FilterChip(
              selected: isSelected,
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    filter['icon'] as IconData,
                    size: 16,
                    color: isSelected ? Colors.white : AppColors.getSecondaryTextColor(context),
                  ),
                  const SizedBox(width: 4),
                  Text(filter['label'] as String),
                ],
              ),
              onSelected: (selected) {
                setState(() {
                  _selectedFilter = filter['key'] as String;
                });
              },
              backgroundColor: AppColors.backgroundLight,
              selectedColor: AppColors.primary,
              checkmarkColor: Colors.white,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : AppColors.getSecondaryTextColor(context),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildSearchResults(BuildContext context) {
    return BlocBuilder<RouteImportBloc, RouteImportState>(
      builder: (context, state) {
        if (_searchQuery.isEmpty) {
          return _buildEmptySearch(context);
        }
        
        if (state is RouteImportLoading) {
          return const LoadingOverlay();
        }
        
        if (state is RouteImportError) {
          return _buildErrorState(context, state.message);
        }
        
        // Mock search results for now
        final mockResults = _getMockSearchResults();
        final filteredResults = _filterResults(mockResults);
        
        if (filteredResults.isEmpty) {
          return _buildNoResults(context);
        }
        
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: filteredResults.length,
          itemBuilder: (context, index) {
            final route = filteredResults[index];
            return Padding(
              padding: EdgeInsets.only(bottom: index < filteredResults.length - 1 ? 16 : 0),
              child: _buildRouteSearchCard(context, route),
            );
          },
        );
      },
    );
  }
  
  Widget _buildEmptySearch(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search,
            size: 64,
            color: AppColors.getSubtleTextColor(context),
          ),
          const SizedBox(height: 16),
          Text(
            'Search for Routes',
            style: AppTextStyles.headlineMedium.copyWith(
              color: AppColors.getTextColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter a search term to find routes by name,\nlocation, or tags',
            style: AppTextStyles.bodyLarge.copyWith(
              color: AppColors.getSecondaryTextColor(context),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            onPressed: () => _searchNearby(context),
            text: 'Find Routes Near Me',
          ),
        ],
      ),
    );
  }
  
  Widget _buildNoResults(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: AppColors.getSubtleTextColor(context),
          ),
          const SizedBox(height: 16),
          Text(
            'No Routes Found',
            style: AppTextStyles.headlineMedium.copyWith(
              color: AppColors.getTextColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your search terms or filters',
            style: AppTextStyles.bodyLarge.copyWith(
              color: AppColors.getSecondaryTextColor(context),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () {
              _searchController.clear();
              setState(() {
                _searchQuery = '';
                _selectedFilter = 'all';
              });
            },
            child: const Text('Clear Search'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildErrorState(BuildContext context, String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            'Search Error',
            style: AppTextStyles.headlineMedium.copyWith(
              color: AppColors.getTextColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: AppTextStyles.bodyLarge.copyWith(
              color: AppColors.getSecondaryTextColor(context),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            onPressed: () {
              // Retry search
            },
            text: 'Try Again',
          ),
        ],
      ),
    );
  }
  
  Widget _buildRouteSearchCard(BuildContext context, Route route) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () => _selectRoute(context, route),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          route.name,
                          style: AppTextStyles.headlineMedium.copyWith(
                            color: AppColors.getTextColor(context),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (route.description?.isNotEmpty == true)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              route.description!,
                              style: AppTextStyles.bodyLarge.copyWith(
                                color: AppColors.getSecondaryTextColor(context),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => _showRouteOptions(context, route),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Route Stats
              Row(
                children: [
                  _buildStatChip(
                    Icons.straighten,
                    '${(route.distance / 1000).toStringAsFixed(1)} km',
                  ),
                  const SizedBox(width: 8),
                  _buildStatChip(
                    Icons.trending_up,
                    '${route.totalAscent.toInt()} m',
                  ),
                  const SizedBox(width: 8),
                  _buildStatChip(
                    Icons.bar_chart,
                    route.difficulty ?? 'Unknown',
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Tags
              if (route.tags.isNotEmpty)
                Wrap(
                  spacing: 4,
                  children: route.tags.take(3).map((tag) => Chip(
                    label: Text(
                      tag,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.getTextColor(context),
                      ),
                    ),
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  )).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildStatChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.getSecondaryTextColor(context)),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.getSecondaryTextColor(context),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  List<Route> _getMockSearchResults() {
    return [
      Route(
        id: 'route1',
        name: 'Mountain Trail Loop',
        description: 'Scenic mountain trail with great views',
        coordinatePoints: [],
        elevationProfile: [],
        pointsOfInterest: [],
        distance: 8500,
        totalAscent: 350,
        totalDescent: 350,
        difficulty: 'Moderate',
        tags: ['mountain', 'scenic', 'loop'],
        source: 'imported',
        isPublic: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      Route(
        id: 'route2',
        name: 'Riverside Walk',
        description: 'Easy walk along the river',
        coordinatePoints: [],
        elevationProfile: [],
        pointsOfInterest: [],
        distance: 5200,
        totalAscent: 80,
        totalDescent: 75,
        difficulty: 'Easy',
        tags: ['river', 'easy', 'family'],
        source: 'created',
        isPublic: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];
  }
  
  List<Route> _filterResults(List<Route> routes) {
    var filteredRoutes = routes;
    
    // Apply search query filter
    if (_searchQuery.isNotEmpty) {
      filteredRoutes = filteredRoutes.where((route) {
        final query = _searchQuery.toLowerCase();
        return route.name.toLowerCase().contains(query) ||
               (route.description?.toLowerCase().contains(query) ?? false) ||
               route.tags.any((tag) => tag.toLowerCase().contains(query));
      }).toList();
    }
    
    // Apply category filter
    if (_selectedFilter != 'all') {
      filteredRoutes = filteredRoutes.where((route) {
        switch (_selectedFilter) {
          case 'imported':
            return route.source == 'imported';
          case 'created':
            return route.source == 'created';
          case 'saved':
            return route.source == 'saved';
          case 'recent':
            return DateTime.now().difference(route.createdAt).inDays <= 7;
          default:
            return true;
        }
      }).toList();
    }
    
    return filteredRoutes;
  }
  
  void _searchNearby(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Searching for nearby routes...')),
    );
  }
  
  void _searchFavorites(BuildContext context) {
    setState(() {
      _selectedFilter = 'saved';
    });
  }
  
  void _searchPopular(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Loading popular routes...')),
    );
  }
  
  void _selectRoute(BuildContext context, Route route) {
    Navigator.of(context).pop(route);
  }
  
  void _showRouteOptions(BuildContext context, Route route) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility),
              title: const Text('Preview Route'),
              onTap: () {
                Navigator.of(context).pop();
                // Navigate to route preview
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_task),
              title: const Text('Plan Ruck'),
              onTap: () {
                Navigator.of(context).pop();
                _selectRoute(context, route);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share Route'),
              onTap: () {
                Navigator.of(context).pop();
                // Share route
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Download GPX'),
              onTap: () {
                Navigator.of(context).pop();
                // Download GPX
              },
            ),
          ],
        ),
      ),
    );
  }
}
