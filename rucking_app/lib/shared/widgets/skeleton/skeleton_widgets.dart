import 'package:flutter/material.dart';
import 'package:rucking_app/shared/widgets/skeleton/skeleton_loader.dart';

/// Skeleton for session cards in history and home screen
class SessionCardSkeleton extends StatelessWidget {
  const SessionCardSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      isLoading: true,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with date and type
              Row(
                children: [
                  const SkeletonLine(width: 120, height: 18),
                  const Spacer(),
                  const SkeletonLine(width: 80, height: 16),
                ],
              ),
              const SizedBox(height: 16),
              
              // Stats grid
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SkeletonLine(width: 60, height: 12),
                        const SizedBox(height: 4),
                        const SkeletonLine(width: 80, height: 16),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SkeletonLine(width: 60, height: 12),
                        const SizedBox(height: 4),
                        const SkeletonLine(width: 70, height: 16),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SkeletonLine(width: 60, height: 12),
                        const SizedBox(height: 4),
                        const SkeletonLine(width: 60, height: 16),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SkeletonLine(width: 70, height: 12),
                        const SizedBox(height: 4),
                        const SkeletonLine(width: 90, height: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton for ruck buddy cards
class RuckBuddyCardSkeleton extends StatelessWidget {
  const RuckBuddyCardSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      isLoading: true,
      child: Card(
        margin: const EdgeInsets.all(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User info row
              Row(
                children: [
                  const SkeletonCircle(size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SkeletonLine(width: 120, height: 16),
                        const SizedBox(height: 4),
                        const SkeletonLine(width: 80, height: 14),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Map placeholder
              const SkeletonBox(
                width: double.infinity,
                height: 200,
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              const SizedBox(height: 16),
              
              // Stats row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const SkeletonLine(width: 40, height: 12),
                      const SizedBox(height: 4),
                      const SkeletonLine(width: 50, height: 16),
                    ],
                  ),
                  Column(
                    children: [
                      const SkeletonLine(width: 40, height: 12),
                      const SizedBox(height: 4),
                      const SkeletonLine(width: 45, height: 16),
                    ],
                  ),
                  Column(
                    children: [
                      const SkeletonLine(width: 50, height: 12),
                      const SizedBox(height: 4),
                      const SkeletonLine(width: 40, height: 16),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Social actions row
              Row(
                children: [
                  const SkeletonLine(width: 60, height: 32),
                  const SizedBox(width: 12),
                  const SkeletonLine(width: 80, height: 32),
                  const Spacer(),
                  const SkeletonLine(width: 40, height: 14),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton for photo carousel
class PhotoCarouselSkeleton extends StatelessWidget {
  final double height;
  
  const PhotoCarouselSkeleton({
    Key? key,
    this.height = 240,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      isLoading: true,
      child: SizedBox(
        height: height,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: 3,
          itemBuilder: (context, index) {
            return Container(
              width: 200,
              margin: const EdgeInsets.only(right: 12),
              child: const SkeletonBox(
                width: double.infinity,
                height: double.infinity,
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Skeleton for home screen stats
class HomeStatsSkeleton extends StatelessWidget {
  const HomeStatsSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      isLoading: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonLine(width: 150, height: 20),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        const SkeletonLine(width: 80, height: 14),
                        const SizedBox(height: 8),
                        const SkeletonLine(width: 60, height: 24),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        const SkeletonLine(width: 70, height: 14),
                        const SizedBox(height: 8),
                        const SkeletonLine(width: 80, height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton for user avatar
class UserAvatarSkeleton extends StatelessWidget {
  final double size;
  
  const UserAvatarSkeleton({
    Key? key,
    this.size = 50,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      isLoading: true,
      child: SkeletonCircle(size: size),
    );
  }
}

/// Generic list skeleton for various loading states
class ListSkeleton extends StatelessWidget {
  final int itemCount;
  final Widget Function(int index) itemBuilder;
  
  const ListSkeleton({
    Key? key,
    this.itemCount = 5,
    required this.itemBuilder,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: itemCount,
      itemBuilder: (context, index) => SkeletonLoader(
        isLoading: true,
        child: itemBuilder(index),
      ),
    );
  }
}

/// Skeleton for achievements summary widget
class AchievementSummarySkeleton extends StatelessWidget {
  const AchievementSummarySkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      isLoading: true,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with title and view all button
              Row(
                children: [
                  const SkeletonCircle(size: 24),
                  const SizedBox(width: 8),
                  const SkeletonLine(width: 120, height: 20),
                  const Spacer(),
                  const SkeletonLine(width: 60, height: 16),
                ],
              ),
              const SizedBox(height: 16),
              
              // Stats row
              const AchievementStatsSkeleton(),
              
              const SizedBox(height: 16),
              
              // Recent achievement/next challenge
              const RecentAchievementSkeleton(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton for achievement stats row
class AchievementStatsSkeleton extends StatelessWidget {
  const AchievementStatsSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      isLoading: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Column(
            children: [
              const SkeletonLine(width: 40, height: 24),
              const SizedBox(height: 4),
              const SkeletonLine(width: 50, height: 14),
            ],
          ),
          Column(
            children: [
              const SkeletonLine(width: 40, height: 24),
              const SizedBox(height: 4),
              const SkeletonLine(width: 60, height: 14),
            ],
          ),
          Column(
            children: [
              const SkeletonLine(width: 40, height: 24),
              const SizedBox(height: 4),
              const SkeletonLine(width: 70, height: 14),
            ],
          ),
        ],
      ),
    );
  }
}

/// Skeleton for recent achievement section
class RecentAchievementSkeleton extends StatelessWidget {
  const RecentAchievementSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      isLoading: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const SkeletonCircle(size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonLine(width: double.infinity, height: 16),
                  const SizedBox(height: 4),
                  const SkeletonLine(width: 150, height: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
