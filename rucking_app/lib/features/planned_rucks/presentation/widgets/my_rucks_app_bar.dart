import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Custom app bar for My Routes screen with search functionality
class MyRucksAppBar extends StatefulWidget implements PreferredSizeWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onImportPressed;

  const MyRucksAppBar({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.onImportPressed,
  });

  @override
  State<MyRucksAppBar> createState() => _MyRucksAppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _MyRucksAppBarState extends State<MyRucksAppBar>
    with SingleTickerProviderStateMixin {
  bool _isSearching = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
    });

    if (_isSearching) {
      _animationController.forward();
    } else {
      _animationController.reverse();
      widget.searchController.clear();
      widget.onSearchChanged('');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.primary,
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.1),
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white),
      centerTitle: true,
      title: _isSearching ? _buildSearchField() : _buildTitle(),
      actions: [
        if (!_isSearching) ...[
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _toggleSearch,
            tooltip: 'Search rucks',
          ),
          IconButton(
            icon: const Icon(Icons.add_box_outlined),
            onPressed: widget.onImportPressed,
            tooltip: 'Import route',
          ),
        ] else ...[
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: _toggleSearch,
            tooltip: 'Close search',
          ),
        ],
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildTitle() {
    return Text(
      'MY RUCKS',
      style: AppTextStyles.titleLarge.copyWith(
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  Widget _buildSearchField() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: TextField(
        controller: widget.searchController,
        autofocus: true,
        onChanged: widget.onSearchChanged,
        style: AppTextStyles.bodyLarge.copyWith(
          color: Colors.white,
        ),
        decoration: InputDecoration(
          hintText: 'Search rucks by name or notes...',
          hintStyle: AppTextStyles.bodyLarge.copyWith(
            color: Colors.white70,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 0),
          suffixIcon: widget.searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    widget.searchController.clear();
                    widget.onSearchChanged('');
                  },
                  tooltip: 'Clear search',
                )
              : null,
        ),
      ),
    );
  }
}

/// Simple app bar version for when search functionality is not needed
class SimpleMyRucksAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;

  const SimpleMyRucksAppBar({
    super.key,
    this.title = 'My Routes',
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.primary,
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.1),
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white),
      centerTitle: true,
      title: Text(
        title.toUpperCase(),
        style: AppTextStyles.titleLarge.copyWith(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      actions: actions,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

/// App bar with statistics display
class MyRucksStatsAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final String title;
  final int totalRucks;
  final int completedRucks;
  final int overdueRucks;
  final VoidCallback? onStatsPressed;
  final List<Widget>? actions;

  const MyRucksStatsAppBar({
    super.key,
    this.title = 'My Routes',
    required this.totalRucks,
    required this.completedRucks,
    required this.overdueRucks,
    this.onStatsPressed,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.primary,
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.1),
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white),
      centerTitle: true,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title.toUpperCase(),
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              _buildStatChip(
                context,
                icon: Icons.list_alt,
                label: totalRucks.toString(),
                color: AppColors.textDarkSecondary,
              ),
              const SizedBox(width: 8),
              _buildStatChip(
                context,
                icon: Icons.check_circle,
                label: completedRucks.toString(),
                color: AppColors.success,
              ),
              if (overdueRucks > 0) ...[
                const SizedBox(width: 8),
                _buildStatChip(
                  context,
                  icon: Icons.warning,
                  label: overdueRucks.toString(),
                  color: AppColors.error,
                ),
              ],
            ],
          ),
        ],
      ),
      actions: [
        if (onStatsPressed != null)
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            onPressed: onStatsPressed,
            tooltip: 'View statistics',
          ),
        ...?actions,
      ],
    );
  }

  Widget _buildStatChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 12);
}
