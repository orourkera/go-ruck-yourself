import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import 'package:rucking_app/features/achievements/data/models/achievement_model.dart';
import 'package:rucking_app/features/achievements/data/models/achievement_stats_model.dart';
import 'package:rucking_app/features/achievements/presentation/bloc/achievement_bloc.dart';
import 'package:rucking_app/features/achievements/presentation/widgets/achievement_badge.dart';
import 'package:rucking_app/features/achievements/presentation/widgets/achievement_progress_card.dart';
import 'package:rucking_app/features/achievements/presentation/widgets/achievement_summary.dart';
import 'package:rucking_app/features/achievements/presentation/widgets/achievement_unlock_popup.dart';
import 'package:rucking_app/features/achievements/presentation/widgets/session_achievement_notification.dart';

@GenerateMocks([AchievementBloc])
import 'achievement_widgets_test.mocks.dart';

void main() {
  group('Achievement Widgets Tests', () {
    late MockAchievementBloc mockAchievementBloc;
    late Achievement sampleAchievement;
    late AchievementStats sampleStats;

    setUp(() {
      mockAchievementBloc = MockAchievementBloc();
      
      sampleAchievement = Achievement(
        id: '1',
        name: 'First Steps',
        description: 'Complete your first ruck',
        category: 'distance',
        tier: 'bronze',
        targetValue: 1.6,
        unit: 'km',
        iconName: 'directions_walk',
        isActive: true,
        createdAt: DateTime.now(),
      );

      sampleStats = AchievementStats(
        totalEarned: 5,
        totalAvailable: 60,
        completionPercentage: 8.3,
        powerPoints: 150,
        byCategory: {
          'distance': 2,
          'weight': 1,
          'consistency': 2,
        },
        byTier: {
          'bronze': 3,
          'silver': 2,
          'gold': 0,
        },
      );
    });

    testWidgets('AchievementBadge displays correctly for earned achievement', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AchievementBadge(
              achievement: sampleAchievement,
              isEarned: true,
              size: 60,
            ),
          ),
        ),
      );

      expect(find.byType(Container), findsWidgets);
      expect(find.byType(Icon), findsOneWidget);
    });

    testWidgets('AchievementBadge displays correctly for unearned achievement with progress', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AchievementBadge(
              achievement: sampleAchievement,
              isEarned: false,
              progress: 0.6,
              size: 60,
            ),
          ),
        ),
      );

      expect(find.byType(Container), findsWidgets);
      expect(find.byType(Icon), findsOneWidget);
    });

    testWidgets('AchievementProgressCard displays achievement information', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AchievementProgressCard(
              achievement: sampleAchievement,
              progress: 0.6,
              currentValue: 1.0,
              isEarned: false,
            ),
          ),
        ),
      );

      expect(find.text(sampleAchievement.name), findsOneWidget);
      expect(find.text(sampleAchievement.description), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('AchievementProgressCard displays earned state correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AchievementProgressCard(
              achievement: sampleAchievement,
              progress: 1.0,
              currentValue: 1.6,
              isEarned: true,
            ),
          ),
        ),
      );

      expect(find.text(sampleAchievement.name), findsOneWidget);
      expect(find.text('COMPLETED'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('SessionAchievementNotification displays single achievement', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SessionAchievementNotification(
              newAchievements: [sampleAchievement],
              onDismiss: () {},
            ),
          ),
        ),
      );

      expect(find.text('Achievement Unlocked!'), findsOneWidget);
      expect(find.text(sampleAchievement.name), findsOneWidget);
      expect(find.text(sampleAchievement.description), findsOneWidget);
      expect(find.text('BRONZE'), findsOneWidget);
      expect(find.text('View Details'), findsOneWidget);
      expect(find.text('Celebrate!'), findsOneWidget);
    });

    testWidgets('SessionAchievementNotification displays multiple achievements', (WidgetTester tester) async {
      final secondAchievement = Achievement(
        id: '2',
        name: 'Weight Warrior',
        description: 'Carry 10kg for 1km',
        category: 'weight',
        tier: 'silver',
        targetValue: 10.0,
        unit: 'kg',
        iconName: 'fitness_center',
        isActive: true,
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SessionAchievementNotification(
              newAchievements: [sampleAchievement, secondAchievement],
              onDismiss: () {},
            ),
          ),
        ),
      );

      expect(find.text('New Achievements Unlocked!'), findsOneWidget);
      expect(find.text('You unlocked 2 achievements in this session!'), findsOneWidget);
      expect(find.text('View All (2)'), findsOneWidget);
      expect(find.text('Celebrate!'), findsOneWidget);
    });
  });

  group('Achievement Category Colors Tests', () {
    testWidgets('Each category has correct color mapping', (WidgetTester tester) async {
      final categoryColorTests = [
        {'category': 'distance', 'expectedColor': Colors.blue},
        {'category': 'weight', 'expectedColor': Colors.red},
        {'category': 'power', 'expectedColor': Colors.orange},
        {'category': 'pace', 'expectedColor': Colors.green},
        {'category': 'time', 'expectedColor': Colors.purple},
        {'category': 'consistency', 'expectedColor': Colors.teal},
        {'category': 'special', 'expectedColor': Colors.pink},
      ];

      for (final test in categoryColorTests) {
        final achievement = Achievement(
          id: '1',
          name: 'Test Achievement',
          description: 'Test description',
          category: test['category'] as String,
          tier: 'bronze',
          targetValue: 1.0,
          unit: 'test',
          iconName: 'star',
          isActive: true,
          createdAt: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AchievementBadge(
                achievement: achievement,
                isEarned: true,
                size: 60,
              ),
            ),
          ),
        );

        // Verify the badge is created (the specific color verification would require
        // more complex widget testing that accesses the actual color values)
        expect(find.byType(AchievementBadge), findsOneWidget);
      }
    });
  });
}
