import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/models/route.dart' as route_model;
import 'package:rucking_app/features/planned_rucks/presentation/bloc/route_import_bloc.dart';
import 'package:rucking_app/features/planned_rucks/presentation/widgets/gpx_file_picker.dart';
import 'package:rucking_app/features/planned_rucks/presentation/widgets/url_import_form.dart';
import 'package:rucking_app/features/planned_rucks/presentation/widgets/route_search_widget.dart';
import 'package:rucking_app/features/planned_rucks/presentation/widgets/route_preview_card.dart';
import 'package:rucking_app/features/planned_rucks/presentation/widgets/import_progress_indicator.dart';
import 'package:rucking_app/shared/widgets/loading_indicator.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Screen for importing routes from various sources
class RouteImportScreen extends StatefulWidget {
  final String? initialUrl;
  final String? importType;
  final String? platform;
  
  const RouteImportScreen({
    super.key,
    this.initialUrl,
    this.importType,
    this.platform,
  });

  @override
  State<RouteImportScreen> createState() => _RouteImportScreenState();
}

class _RouteImportScreenState extends State<RouteImportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final PageController _pageController = PageController();
  
  // Route name editing
  final TextEditingController _routeNameController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // If we have an initial URL from a deep link, switch to URL tab and start import
    if (widget.initialUrl != null && widget.importType == 'url') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Switch to URL tab
        _tabController.animateTo(1);
        _pageController.animateToPage(
          1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        
        // Trigger URL import
        context.read<RouteImportBloc>().add(ImportGpxFromUrl(
          url: widget.initialUrl!,
        ));
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    _routeNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark 
          ? AppColors.backgroundDark 
          : AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Theme.of(context).brightness == Brightness.dark 
            ? AppColors.surfaceDark 
            : AppColors.primary,
        foregroundColor: Theme.of(context).brightness == Brightness.dark 
            ? AppColors.textLight 
            : Colors.white,
        elevation: 2,
        title: Text(
          'Import Route',
          style: AppTextStyles.titleLarge.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).brightness == Brightness.dark 
                ? AppColors.textLight 
                : Colors.white,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).brightness == Brightness.dark 
              ? AppColors.primary 
              : Colors.white,
          unselectedLabelColor: Theme.of(context).brightness == Brightness.dark 
              ? AppColors.getSecondaryTextColor(context) 
              : Colors.white70,
          indicatorColor: Theme.of(context).brightness == Brightness.dark 
              ? AppColors.primary 
              : Colors.white,
          onTap: (index) {
            _pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          },
          tabs: const [
            Tab(
              icon: Icon(Icons.file_upload),
              text: 'GPX File',
            ),
            Tab(
              icon: Icon(Icons.link),
              text: 'URL',
            ),
            Tab(
              icon: Icon(Icons.search),
              text: 'Search',
            ),
          ],
        ),
      ),
      body: BlocConsumer<RouteImportBloc, RouteImportState>(
        listener: (context, state) {
          if (state is RouteImportSuccess) {
            _showSuccessDialog(state);
          } else if (state is RouteImportError) {
            _showErrorSnackBar(state);
          } else if (state is RouteImportValidated) {
            // Pre-populate the route name from GPX metadata
            if (_routeNameController.text.isEmpty && state.route.name.isNotEmpty) {
              _routeNameController.text = state.route.name;
            }
          } else if (state is RouteImportPreview) {
            // Pre-populate the route name from preview data
            if (_routeNameController.text.isEmpty && state.route.name.isNotEmpty) {
              _routeNameController.text = state.route.name;
            }
          }
        },
        builder: (context, state) {
          return Column(
            children: [
              // Progress indicator
              if (state is RouteImportInProgress)
                ImportProgressIndicator(
                  message: state.message,
                  progress: state.progress,
                ),

              // Main content - show either tabs or route preview
              Expanded(
                child: (state is RouteImportValidated || state is RouteImportPreview)
                    ? _buildRoutePreview(state)
                    : PageView(
                        controller: _pageController,
                        onPageChanged: (index) {
                          _tabController.animateTo(index);
                        },
                        children: [
                          _buildGpxFileTab(state),
                          _buildUrlTab(state),
                          _buildRouteSearchTab(state),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Build GPX file import tab
  Widget _buildGpxFileTab(RouteImportState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Import from GPX File',
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select a GPX file from your device to import the route.',
            style: AppTextStyles.bodyLarge.copyWith(
              color: AppColors.getSecondaryTextColor(context),
            ),
          ),
          const SizedBox(height: 24),

          if (state is RouteImportValidating)
            const Center(
              child: Column(
                children: [
                  LoadingIndicator(),
                  SizedBox(height: 16),
                  Text('Validating GPX file...'),
                ],
              ),
            )
          else
            GpxFilePicker(
              onFileSelected: (file) {
                context.read<RouteImportBloc>().add(ValidateGpxFile(
                  gpxFile: file,
                ));
              },
            ),

          const SizedBox(height: 24),

          // Tips
          _buildTipsCard([
            'GPX files should contain track or route data',
            'Files exported from AllTrails, Strava, or Garmin work best',
            'Make sure the file contains waypoints for better results',
          ]),
        ],
      ),
    );
  }

  /// Build URL import tab
  Widget _buildUrlTab(RouteImportState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Import from URL',
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Paste a URL to a GPX file or AllTrails route.',
            style: AppTextStyles.bodyLarge.copyWith(
              color: AppColors.getSecondaryTextColor(context),
            ),
          ),
          const SizedBox(height: 24),

          UrlImportForm(
            onSubmit: (url) {
              context.read<RouteImportBloc>().add(ImportGpxFromUrl(
                url: url,
              ));
            },
            isLoading: state is RouteImportInProgress,
          ),

          const SizedBox(height: 24),

          // Tips
          _buildTipsCard([
            'URLs should point directly to GPX files',
            'AllTrails URLs are automatically supported',
            'Make sure the URL is publicly accessible',
          ]),
        ],
      ),
    );
  }

  /// Build route search tab
  Widget _buildRouteSearchTab(RouteImportState state) {
    return Column(
      children: [
        // Search form
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? AppColors.surfaceDark : AppColors.surfaceLight,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: RouteSearchWidget(
            onSearch: (query, filters) {
              context.read<RouteImportBloc>().add(SearchAllTrailsRoutes(
                query: query,
                nearLatitude: filters['latitude'],
                nearLongitude: filters['longitude'],
                maxDistance: filters['maxDistance'],
                difficulty: filters['difficulty'],
                routeType: filters['routeType'],
              ));
            },
            isLoading: state is RouteImportSearching,
          ),
        ),

        // Search results
        Expanded(
          child: _buildSearchResults(state),
        ),
      ],
    );
  }

  /// Build search results
  Widget _buildSearchResults(RouteImportState state) {
    if (state is RouteImportSearching) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LoadingIndicator(),
            SizedBox(height: 16),
            Text('Searching routes...'),
          ],
        ),
      );
    }

    if (state is RouteImportSearchResults) {
      if (state.routes.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off,
                size: 64,
                color: AppColors.getSecondaryTextColor(context),
              ),
              const SizedBox(height: 16),
              Text(
                'No routes found',
                style: AppTextStyles.titleLarge.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try adjusting your search criteria.',
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.getSecondaryTextColor(context),
                ),
              ),
            ],
          ),
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: state.routes.length,
        itemBuilder: (context, index) {
          final route = state.routes[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: RoutePreviewCard(
              route: route,
              onTap: () {
                if (route.id != null) {
                  context.read<RouteImportBloc>().add(ImportAllTrailsRoute(
                    routeId: route.id!,
                  ));
                }
              },
              showImportButton: true,
            ),
          );
        },
      );
    }

    // Default empty state
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search,
            size: 64,
            color: AppColors.getSecondaryTextColor(context),
          ),
          const SizedBox(height: 16),
          Text(
            'Search Routes',
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Search through previously imported routes.',
            style: AppTextStyles.bodyLarge.copyWith(
              color: AppColors.getSecondaryTextColor(context),
            ),
          ),
        ],
      ),
    );
  }

  /// Build route preview section
  Widget _buildRoutePreview(RouteImportState state) {
    route_model.Route? originalRoute;
    List<String> warnings = [];

    if (state is RouteImportPreview) {
      originalRoute = state.route;
      warnings = state.warnings;
    } else if (state is RouteImportValidated) {
      originalRoute = state.route;
      warnings = state.warnings;
    }

    if (originalRoute == null) return const SizedBox.shrink();

    // Create updated route with current name from text field
    final currentName = _routeNameController.text.trim();
    final displayRoute = originalRoute.copyWith(
      name: currentName.isNotEmpty ? currentName : originalRoute.name,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back button
          Row(
            children: [
              IconButton(
                onPressed: () {
                  context.read<RouteImportBloc>().add(const ClearImportState());
                },
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 8),
              Text(
                'Route Preview',
                style: AppTextStyles.titleLarge.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Route name field
          TextField(
            controller: _routeNameController,
            decoration: const InputDecoration(
              labelText: 'Route Name',
              hintText: 'Enter a name for this route...',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.route),
            ),
            textInputAction: TextInputAction.next,
            onChanged: (value) {
              // Trigger rebuild to update the route preview card
              setState(() {});
            },
          ),
          const SizedBox(height: 24),
          
          // Route map and details
          RoutePreviewCard(
            route: displayRoute,
            warnings: warnings,
            showImportButton: false,
          ),
          
          const SizedBox(height: 24),
          
          // Import button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: state is RouteImportInProgress ? null : () {
                _confirmImport(originalRoute);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                state is RouteImportInProgress ? 'Importing...' : 'Import Route',
                style: AppTextStyles.titleMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build tips card
  Widget _buildTipsCard(List<String> tips) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: 20,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 8),
                Text(
                  'Tips',
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.warning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...tips.map((tip) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.only(top: 8, right: 8),
                    decoration: BoxDecoration(
                      color: AppColors.getSecondaryTextColor(context),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      tip,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.getSecondaryTextColor(context),
                      ),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  // Helper methods

  bool _shouldShowPlannedRuckForm(RouteImportState state) {
    return state is RouteImportPreview || state is RouteImportValidated;
  }

  void _confirmImport(route_model.Route route) {
    // Use custom route name if provided, otherwise use the original name
    final customName = _routeNameController.text.trim();
    final updatedRoute = route.copyWith(
      name: customName.isNotEmpty ? customName : route.name,
    );
    
    context.read<RouteImportBloc>().add(ConfirmImport(
      route: updatedRoute,
    ));
  }

  void _showSuccessDialog(RouteImportSuccess state) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Import Successful!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(state.message),
            if (state.plannedRuck != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: AppColors.success,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Planned ruck created for ${state.plannedRuck!.formattedPlannedDate}',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.success,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Close import screen
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(RouteImportError state) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(state.message),
        backgroundColor: AppColors.error,
        action: state.canRetry
            ? SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: () {
                  // TODO: Implement retry logic
                },
              )
            : null,
      ),
    );
  }
}
