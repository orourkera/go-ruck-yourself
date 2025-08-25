import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/models/goal_with_progress.dart';
import 'package:rucking_app/core/services/goals_api_service.dart';
import 'package:rucking_app/features/goals/presentation/screens/goal_chat_screen.dart';

class GoalsListScreen extends StatefulWidget {
  const GoalsListScreen({super.key});

  @override
  State<GoalsListScreen> createState() => _GoalsListScreenState();
}

class _GoalsListScreenState extends State<GoalsListScreen> {
  final _goalsApi = GetIt.I<GoalsApiService>();
  late Future<List<GoalWithProgress>> _future;

  @override
  void initState() {
    super.initState();
    _future = _goalsApi.listGoalsWithProgress(page: 1, pageSize: 25);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Goals')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.of(context).push<GoalWithProgress>(
            MaterialPageRoute(builder: (_) => const GoalChatScreen()),
          );
          if (created != null) {
            if (!mounted) return;
            setState(() {
              _future = _goalsApi.listGoalsWithProgress(page: 1, pageSize: 25);
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Goal created')),
            );
          }
        },
        icon: const Icon(Icons.flag),
        label: const Text('Set a Personal Goal'),
      ),
      body: FutureBuilder<List<GoalWithProgress>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('Failed to load goals: ${snapshot.error}'),
              ),
            );
          }
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return const Center(child: Text('No goals yet'));
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = items[index];
              final goal = item.goal;
              final progress = item.progress;
              final subtitle = progress != null
                  ? 'Progress: ${progress.currentValue?.toStringAsFixed(2) ?? '-'} / ${goal.targetValue?.toStringAsFixed(2) ?? '-'}'
                  : 'No progress yet';
              return ListTile(
                title: Text(goal.title ?? 'Untitled Goal'),
                subtitle: Text(subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).pushNamed(
                    '/goal_detail',
                    arguments: goal.id,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
