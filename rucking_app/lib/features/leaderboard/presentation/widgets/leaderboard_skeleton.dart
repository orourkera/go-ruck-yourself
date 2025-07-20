import 'package:flutter/material.dart';
import '../../../../shared/widgets/skeleton/skeleton_loader.dart';

/// Skeleton loading for the leaderboard screen
class LeaderboardSkeleton extends StatelessWidget {
  const LeaderboardSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header skeleton
        const LeaderboardHeaderSkeleton(),
        
        // User list skeleton
        Expanded(
          child: ListView.builder(
            itemCount: 10, // Show 10 skeleton rows
            itemBuilder: (context, index) => LeaderboardRowSkeleton(
              rank: index + 1,
            ),
          ),
        ),
      ],
    );
  }
}

/// Skeleton for leaderboard header with sort controls
class LeaderboardHeaderSkeleton extends StatelessWidget {
  const LeaderboardHeaderSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return SkeletonLoader(
      isLoading: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: theme.dividerColor,
              width: 1,
            ),
          ),
        ),
        child: const Row(
          children: [
            // Rank column
            SizedBox(width: 40),
            
            // User column
            SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: SkeletonLine(width: 80, height: 16),
            ),
            
            // Distance column
            Expanded(
              child: Center(
                child: SkeletonLine(width: 60, height: 16),
              ),
            ),
            
            // Power Points column
            Expanded(
              child: Center(
                child: SkeletonLine(width: 80, height: 16),
              ),
            ),
            
            // Sessions column
            Expanded(
              child: Center(
                child: SkeletonLine(width: 70, height: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton for individual leaderboard row
class LeaderboardRowSkeleton extends StatelessWidget {
  final int rank;
  
  const LeaderboardRowSkeleton({
    Key? key,
    required this.rank,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return SkeletonLoader(
      isLoading: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: theme.dividerColor.withOpacity(0.3),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            // Rank
            SizedBox(
              width: 40,
              child: Center(
                child: SkeletonLine(
                  width: rank < 10 ? 12 : 20, // Shorter width for single digits
                  height: 16,
                ),
              ),
            ),
            
            // User info (avatar + username)
            const SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  // Avatar
                  const SkeletonCircle(size: 32),
                  const SizedBox(width: 12),
                  
                  // Username and location
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Username - vary width for realism
                        SkeletonLine(
                          width: 60 + (rank % 3) * 20.0, // 60-100px width
                          height: 16,
                        ),
                        const SizedBox(height: 4),
                        // Location
                        SkeletonLine(
                          width: 40 + (rank % 4) * 15.0, // 40-85px width
                          height: 12,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Distance
            Expanded(
              child: Center(
                child: SkeletonLine(
                  width: 45 + (rank % 2) * 10.0, // 45-55px width
                  height: 16,
                ),
              ),
            ),
            
            // Power Points
            Expanded(
              child: Center(
                child: SkeletonLine(
                  width: 50 + (rank % 3) * 15.0, // 50-80px width
                  height: 16,
                ),
              ),
            ),
            
            // Sessions
            Expanded(
              child: Center(
                child: SkeletonLine(
                  width: 20 + (rank % 2) * 10.0, // 20-30px width
                  height: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton for "loading more" indicator at bottom of list
class LeaderboardLoadingMoreSkeleton extends StatelessWidget {
  const LeaderboardLoadingMoreSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      isLoading: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SkeletonCircle(size: 24),
              SizedBox(height: 8),
              SkeletonLine(width: 120, height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
