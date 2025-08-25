import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/services/goals_api_service.dart';
import 'package:rucking_app/core/api/api_exceptions.dart';
import 'package:rucking_app/core/models/goal_with_progress.dart';
import 'package:rucking_app/features/goals/presentation/widgets/goal_confirmation_sheet.dart';

class GoalChatScreen extends StatefulWidget {
  const GoalChatScreen({super.key});

  @override
  State<GoalChatScreen> createState() => _GoalChatScreenState();
}

class _GoalChatScreenState extends State<GoalChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _api = GetIt.I<GoalsApiService>();

  bool _loading = false;
  String? _error;
  final List<_ChatTurn> _turns = <_ChatTurn>[];

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _onSend() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;
    setState(() {
      _error = null;
      _loading = true;
      _turns.add(_ChatTurn.user(text));
      _controller.clear();
    });

    try {
      final parsed = await _api.parseGoal(text);
      // Support backend shape: { draft: {...}, input_preview, parser }
      // Also keep compatibility for { draft_goal: {...} } or flat draft objects.
      Map<String, dynamic>? draftMap;
      if (parsed['draft'] is Map) {
        draftMap = Map<String, dynamic>.from(parsed['draft'] as Map);
      } else if (parsed['draft_goal'] is Map) {
        draftMap = Map<String, dynamic>.from(parsed['draft_goal'] as Map);
      } else if (parsed is Map<String, dynamic> && parsed.containsKey('metric')) {
        // Some servers may return the draft object directly
        draftMap = Map<String, dynamic>.from(parsed);
      }

      if (draftMap == null) {
        throw Exception('Invalid parse response');
      }

      _turns.add(_ChatTurn.assistantDraft(draftMap));
      setState(() {});

      if (!mounted) return;
      final created = await showModalBottomSheet<GoalWithProgress>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (ctx) => GoalConfirmationSheet(
          draft: draftMap,
          onConfirm: (confirmedDraft) async {
            final res = await _api.createGoal(confirmedDraft);
            return res;
          },
        ),
      );

      if (created != null && mounted) {
        Navigator.of(context).pop(created);
      }
    } catch (e) {
      setState(() {
        if (e is ApiException) {
          _error = e.message;
        } else {
          _error = 'Failed to parse goal. Please try again.';
        }
      });
    } finally {
      setState(() {
        _loading = false;
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set a Personal Goal')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _turns.length + (_error != null ? 1 : 0),
              itemBuilder: (context, index) {
                if (_error != null && index == _turns.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  );
                }
                final turn = _turns[index];
                if (turn.role == _Role.user) {
                  return Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(turn.text ?? ''),
                    ),
                  );
                } else {
                  // Assistant draft preview chip
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Draft goal ready. Review & confirm.',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          _DraftSummary(draft: turn.draft ?? const {}),
                          const SizedBox(height: 4),
                          const Text('Tap Send again to refine your intent, or confirm in the sheet.'),
                        ],
                      ),
                    ),
                  );
                }
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Describe your goal (e.g., 50 km this month with 9kg pack)'
                      ),
                      onSubmitted: (_) => _onSend(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _loading ? null : _onSend,
                    icon: _loading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                    label: const Text('Send'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Role { user, assistant }

class _ChatTurn {
  final _Role role;
  final String? text;
  final Map<String, dynamic>? draft;

  _ChatTurn.user(this.text)
      : role = _Role.user,
        draft = null;

  _ChatTurn.assistantDraft(this.draft)
      : role = _Role.assistant,
        text = null;
}

class _DraftSummary extends StatelessWidget {
  final Map<String, dynamic> draft;
  const _DraftSummary({required this.draft});

  @override
  Widget build(BuildContext context) {
    String v(String k) => (draft[k])?.toString() ?? '-';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Title: ${v('title')}'),
        Text('Metric: ${v('metric')}'),
        Text('Target: ${v('target_value')} ${v('unit')}'),
        Text('Window: ${v('window')}'),
      ],
    );
  }
}
