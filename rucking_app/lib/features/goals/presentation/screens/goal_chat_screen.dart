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
  Map<String, dynamic>?
      _userHistory; // optional: AI cheerleader history/context

  @override
  void initState() {
    super.initState();
    _loadUserHistory();
  }

  Future<void> _loadUserHistory() async {
    try {
      final hist = await _api.getAICheerleaderUserHistory(
          rucksLimit: 15, achievementsLimit: 25);
      if (mounted) {
        setState(() {
          _userHistory = hist;
        });
      }
    } catch (_) {
      // Non-fatal; continue without history
    }
  }

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
      final parsed = await _api.parseGoal(text, userHistory: _userHistory);
      // Conversational response may include assistant_message and optional draft
      final assistantMessage = parsed['assistant_message'] as String?;
      final needsClarification = parsed['needs_clarification'] == true;

      Map<String, dynamic>? draftMap;
      if (parsed['draft'] is Map) {
        draftMap = Map<String, dynamic>.from(parsed['draft'] as Map);
      } else if (parsed['draft_goal'] is Map) {
        draftMap = Map<String, dynamic>.from(parsed['draft_goal'] as Map);
      } else if (parsed is Map<String, dynamic> &&
          parsed.containsKey('metric')) {
        // Some servers may return the draft object directly
        draftMap = Map<String, dynamic>.from(parsed);
      }

      if (assistantMessage != null && assistantMessage.isNotEmpty) {
        _turns.add(_ChatTurn.assistantText(assistantMessage));
      }

      if (draftMap != null) {
        _turns.add(_ChatTurn.assistantDraft(draftMap));
        setState(() {});

        if (!mounted) return;
        final created = await showModalBottomSheet<GoalWithProgress>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (ctx) => GoalConfirmationSheet(
            draft: draftMap!,
            onConfirm: (confirmedDraft) async {
              final res = await _api.createGoal(confirmedDraft);
              return res;
            },
          ),
        );

        if (created != null && mounted) {
          Navigator.of(context).pop(created);
        }
      } else {
        // No draft returned (clarification). Keep chat open for user to refine
        if (assistantMessage == null && needsClarification) {
          _turns.add(_ChatTurn.assistantText(
              'Can you add more detail, like units or timeframe?'));
        }
        setState(() {});
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Set a Personal Goal')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  Text(
                    'What do you want to achieve, rucker?',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _PromptBar(
                    controller: _controller,
                    onSubmit: _loading ? null : _onSend,
                    loading: _loading,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                itemCount: _turns.length + (_error != null ? 1 : 0),
                itemBuilder: (context, index) {
                  if (_error != null && index == _turns.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.red)),
                    );
                  }
                  if (_turns.isEmpty) {
                    return const SizedBox.shrink();
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
                    // Assistant turn: either a natural message or a draft preview
                    if (turn.draft == null) {
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(turn.text ?? ''),
                        ),
                      );
                    }
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
                            const Text(
                                'Submit again to refine your intent, or confirm in the sheet.'),
                          ],
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),
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

  _ChatTurn.assistantText(this.text)
      : role = _Role.assistant,
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

class _PromptBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onSubmit;
  final bool loading;

  const _PromptBar({
    required this.controller,
    required this.onSubmit,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: TextField(
        controller: controller,
        minLines: 1,
        maxLines: 4,
        textInputAction: TextInputAction.send,
        decoration: InputDecoration(
          hintText: 'Ask anything',
          border: InputBorder.none,
          suffixIcon: loading
              ? const Padding(
                  padding: EdgeInsets.only(right: 8.0),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
        ),
        onSubmitted: (_) => onSubmit?.call(),
      ),
    );
  }
}
