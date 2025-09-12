import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Widget to display when there are no planned rucks
class EmptyRucksState extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? actionText;
  final VoidCallback? onActionPressed;
  final IconData? icon;
  final Widget? customIllustration;

  const EmptyRucksState({
    super.key,
    required this.title,
    required this.subtitle,
    this.actionText,
    this.onActionPressed,
    this.icon,
    this.customIllustration,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Illustration or icon
            if (customIllustration != null)
              customIllustration!
            else
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon ?? Icons.hiking_outlined,
                  size: 60,
                  color: AppColors.primary.withOpacity(0.6),
                ),
              ),

            const SizedBox(height: 24),

            // Title
            Text(
              title,
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            // Subtitle
            Text(
              subtitle,
              style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.textDarkSecondary,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            // Action button
            if (actionText != null && onActionPressed != null)
              ElevatedButton.icon(
                onPressed: onActionPressed,
                icon: const Icon(Icons.add),
                label: Text(actionText!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Empty state specifically for search results
class EmptySearchState extends StatelessWidget {
  final String query;
  final VoidCallback? onClearSearch;

  const EmptySearchState({
    super.key,
    required this.query,
    this.onClearSearch,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyRucksState(
      title: 'No rucks found',
      subtitle: 'No rucks match "$query".\nTry adjusting your search terms.',
      actionText: 'Clear Search',
      onActionPressed: onClearSearch,
      icon: Icons.search_off,
    );
  }
}

/// Empty state for filtered results
class EmptyFilteredState extends StatelessWidget {
  final String filterDescription;
  final VoidCallback? onClearFilters;

  const EmptyFilteredState({
    super.key,
    required this.filterDescription,
    this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyRucksState(
      title: 'No rucks found',
      subtitle:
          'No rucks match your current filters ($filterDescription).\nTry adjusting your filters.',
      actionText: 'Clear Filters',
      onActionPressed: onClearFilters,
      icon: Icons.filter_list_off,
    );
  }
}

/// Empty state with loading animation
class EmptyStateWithLoading extends StatefulWidget {
  final String title;
  final String subtitle;
  final bool isLoading;
  final String? actionText;
  final VoidCallback? onActionPressed;

  const EmptyStateWithLoading({
    super.key,
    required this.title,
    required this.subtitle,
    this.isLoading = false,
    this.actionText,
    this.onActionPressed,
  });

  @override
  State<EmptyStateWithLoading> createState() => _EmptyStateWithLoadingState();
}

class _EmptyStateWithLoadingState extends State<EmptyStateWithLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    if (widget.isLoading) {
      _animationController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(EmptyStateWithLoading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoading && !oldWidget.isLoading) {
      _animationController.repeat(reverse: true);
    } else if (!widget.isLoading && oldWidget.isLoading) {
      _animationController.stop();
      _animationController.reset();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated illustration
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Opacity(
                  opacity: widget.isLoading ? _pulseAnimation.value : 1.0,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.isLoading ? Icons.refresh : Icons.hiking_outlined,
                      size: 60,
                      color: AppColors.primary.withOpacity(0.6),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // Title
            Text(
              widget.isLoading ? 'Loading...' : widget.title,
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            // Subtitle
            if (!widget.isLoading)
              Text(
                widget.subtitle,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.textDarkSecondary,
                ),
                textAlign: TextAlign.center,
              ),

            const SizedBox(height: 32),

            // Action button
            if (!widget.isLoading &&
                widget.actionText != null &&
                widget.onActionPressed != null)
              ElevatedButton.icon(
                onPressed: widget.onActionPressed,
                icon: const Icon(Icons.add),
                label: Text(widget.actionText!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Illustrated empty state with custom graphics
class IllustratedEmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? actionText;
  final VoidCallback? onActionPressed;
  final String illustrationAsset;

  const IllustratedEmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    this.actionText,
    this.onActionPressed,
    required this.illustrationAsset,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyRucksState(
      title: title,
      subtitle: subtitle,
      actionText: actionText,
      onActionPressed: onActionPressed,
      customIllustration: Image.asset(
        illustrationAsset,
        width: 200,
        height: 200,
        fit: BoxFit.contain,
      ),
    );
  }
}

/// Empty state for specific contexts
class ContextualEmptyState extends StatelessWidget {
  final EmptyStateContext context;
  final VoidCallback? onActionPressed;

  const ContextualEmptyState({
    super.key,
    required this.context,
    this.onActionPressed,
  });

  @override
  Widget build(BuildContext context) {
    final config = _getContextConfig(this.context);

    return EmptyRucksState(
      title: config.title,
      subtitle: config.subtitle,
      actionText: config.actionText,
      onActionPressed: onActionPressed,
      icon: config.icon,
    );
  }

  _EmptyStateConfig _getContextConfig(EmptyStateContext context) {
    switch (context) {
      case EmptyStateContext.todaysRucks:
        return _EmptyStateConfig(
          title: 'No rucks today',
          subtitle:
              'You have no rucks planned for today.\nEnjoy your free time or plan a new adventure!',
          actionText: 'Plan a Ruck',
          icon: Icons.today,
        );

      case EmptyStateContext.upcomingRucks:
        return _EmptyStateConfig(
          title: 'No upcoming rucks',
          subtitle:
              'You have no rucks planned for the coming days.\nPlan some adventures ahead!',
          actionText: 'Plan a Ruck',
          icon: Icons.calendar_month,
        );

      case EmptyStateContext.completedRucks:
        return _EmptyStateConfig(
          title: 'No completed rucks',
          subtitle:
              'You haven\'t completed any rucks yet.\nStart your first ruck to see it here!',
          actionText: 'Start Rucking',
          icon: Icons.check_circle_outline,
        );

      case EmptyStateContext.allRucks:
        return _EmptyStateConfig(
          title: 'No planned rucks',
          subtitle:
              'You haven\'t planned any rucks yet.\nImport a route or create your first planned ruck!',
          actionText: 'Plan Your First Ruck',
          icon: Icons.hiking_outlined,
        );

      case EmptyStateContext.overdueRucks:
        return _EmptyStateConfig(
          title: 'No overdue rucks',
          subtitle:
              'Great job staying on track!\nAll your planned rucks are up to date.',
          actionText: null,
          icon: Icons.schedule,
        );
    }
  }
}

enum EmptyStateContext {
  todaysRucks,
  upcomingRucks,
  completedRucks,
  allRucks,
  overdueRucks,
}

class _EmptyStateConfig {
  final String title;
  final String subtitle;
  final String? actionText;
  final IconData icon;

  _EmptyStateConfig({
    required this.title,
    required this.subtitle,
    this.actionText,
    required this.icon,
  });
}
