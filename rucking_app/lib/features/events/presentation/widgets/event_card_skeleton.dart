import 'package:flutter/material.dart';
import 'package:rucking_app/shared/widgets/skeleton/skeleton_widgets.dart';

class EventCardSkeleton extends StatelessWidget {
  const EventCardSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with club logo and title
              Row(
                children: [
                  const SkeletonCircle(size: 32),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonLine(width: 200),
                        SizedBox(height: 4),
                        SkeletonLine(width: 120),
                      ],
                    ),
                  ),
                  const SkeletonRectangle(width: 60, height: 24),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Description
              const SkeletonLine(width: double.infinity),
              const SizedBox(height: 4),
              const SkeletonLine(width: 250),
              
              const SizedBox(height: 12),
              
              // Details row
              Row(
                children: [
                  const SkeletonLine(width: 80),
                  const SizedBox(width: 16),
                  const SkeletonLine(width: 60),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Participant count and action button
              Row(
                children: [
                  const SkeletonLine(width: 100),
                  const Spacer(),
                  const SkeletonRectangle(width: 80, height: 32),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
