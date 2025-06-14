import 'package:flutter/material.dart';
import 'package:rucking_app/features/duels/presentation/screens/duels_list_screen.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Events screen that initially shows duels data in Phase 1
/// Will be enhanced in Phase 2 to show proper events functionality
class EventsScreen extends StatelessWidget {
  const EventsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Events',
          style: AppTextStyles.titleLarge.copyWith(
            color: Theme.of(context).brightness == Brightness.dark ? Colors.white : AppColors.textDark,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          // Future: Add filter/search options
          IconButton(
            icon: Icon(
              Icons.search,
              color: Theme.of(context).brightness == Brightness.dark ? Colors.white : AppColors.textDark,
            ),
            onPressed: () {
              // TODO: Implement search functionality in Phase 2
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Phase 1: Show existing duels as events
          // Phase 2: Will be replaced with proper events functionality
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Currently showing duels. Events feature coming soon!',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Show existing duels list for now
          Expanded(
            child: DuelsListScreen(),
          ),
        ],
      ),
    );
  }
}
