import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/models/goal_details.dart';
import 'package:rucking_app/core/models/goal_message.dart';
import 'package:rucking_app/core/models/goal_schedule.dart';
import 'package:rucking_app/core/services/goals_api_service.dart';

class GoalDetailScreen extends StatefulWidget {
  final String goalId;
  const GoalDetailScreen({super.key, required this.goalId});

  @override
  State<GoalDetailScreen> createState() => _GoalDetailScreenState();
}

class _GoalDetailScreenState extends State<GoalDetailScreen> {
  final _api = GetIt.I<GoalsApiService>();
  Future<GoalDetails>? _future;

  @override
  void initState() {
    super.initState();
    _future = _api.getGoalDetails(widget.goalId);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _api.getGoalDetails(widget.goalId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Goal Details')),
      body: FutureBuilder<GoalDetails>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('Failed to load goal: ${snapshot.error}'),
              ),
            );
          }
          final details = snapshot.data;
          if (details == null) {
            return const Center(child: Text('Goal not found'));
          }

          final goal = details.goal;
          final progress = details.progress;
          final schedule = details.schedule;
          final messages = details.messages ?? const <GoalMessage>[];

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(goal.title ?? 'Untitled Goal',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                if (goal.description != null && goal.description!.isNotEmpty)
                  Text(goal.description!),
                const SizedBox(height: 16),
                if (progress != null)
                  Card(
                    child: ListTile(
                      title: const Text('Progress'),
                      subtitle: Text(
                          '${progress.currentValue ?? 0} / ${goal.targetValue ?? '-'}'),
                    ),
                  ),
                if (schedule != null)
                  _ScheduleCard(schedule: schedule, onEdit: _openEditSchedule),
                const SizedBox(height: 8),
                Card(
                  child: ExpansionTile(
                    title: const Text('Recent Messages'),
                    children: messages.take(20).map((m) {
                      return ListTile(
                        title: Text(m.content ?? '-'),
                        subtitle:
                            Text('${m.channel ?? ''} • ${m.messageType ?? ''}'),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    await _api.evaluateGoal(widget.goalId, force: true);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Evaluation triggered')));
                    }
                  },
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Evaluate Now'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openEditSchedule(GoalSchedule current) async {
    final String? currentCron =
        (current.rules != null && current.rules!['cron'] != null)
            ? current.rules!['cron'].toString()
            : '';
    final controller = TextEditingController(text: currentCron);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Schedule (cron)'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'e.g. 0 9 * * *'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (result != null) {
      final updated = GoalSchedule(
        goalId: current.goalId,
        enabled: current.enabled ?? true,
        status: current.status,
        nextRunAt: current.nextRunAt,
        lastSentAt: current.lastSentAt,
        rules: {
          ...?current.rules,
          if (result.isNotEmpty) 'cron': result,
        },
      );
      await _api.upsertGoalSchedule(widget.goalId, updated);
      await _refresh();
    }
  }
}

class _ScheduleCard extends StatelessWidget {
  final GoalSchedule schedule;
  final void Function(GoalSchedule) onEdit;
  const _ScheduleCard({required this.schedule, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: const Text('Notification Schedule'),
        subtitle: Text(
          'Enabled: ${schedule.enabled == true ? 'Yes' : 'No'}\nStatus: ${schedule.status ?? '-'}\nNext Run: ${schedule.nextRunAt?.toIso8601String() ?? '-'}\nLast Sent: ${schedule.lastSentAt?.toIso8601String() ?? '-'}\nCron: ${(schedule.rules != null && schedule.rules!['cron'] != null) ? schedule.rules!['cron'].toString() : '-'}',
        ),
        isThreeLine: true,
        trailing: IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () => onEdit(schedule),
        ),
      ),
    );
  }
}
