import 'package:flutter/material.dart';
import 'package:rucking_app/core/models/goal_with_progress.dart';

class GoalConfirmationSheet extends StatefulWidget {
  final Map<String, dynamic> draft;
  final Future<GoalWithProgress> Function(Map<String, dynamic> confirmedDraft)
      onConfirm;

  const GoalConfirmationSheet({
    super.key,
    required this.draft,
    required this.onConfirm,
  });

  @override
  State<GoalConfirmationSheet> createState() => _GoalConfirmationSheetState();
}

class _GoalConfirmationSheetState extends State<GoalConfirmationSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _targetCtrl;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleCtrl =
        TextEditingController(text: widget.draft['title']?.toString() ?? '');
    _descCtrl = TextEditingController(
        text: widget.draft['description']?.toString() ?? '');
    _targetCtrl = TextEditingController(
        text: widget.draft['target_value']?.toString() ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      final confirmed = Map<String, dynamic>.from(widget.draft);
      if (_titleCtrl.text.trim().isNotEmpty)
        confirmed['title'] = _titleCtrl.text.trim();
      confirmed['description'] = _descCtrl.text.trim();
      final targetVal = double.tryParse(_targetCtrl.text.trim());
      if (targetVal != null) confirmed['target_value'] = targetVal;

      final created = await widget.onConfirm(confirmed);
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (e) {
      setState(() {
        _error = 'Failed to create goal. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String v(String k) => (widget.draft[k])?.toString() ?? '-';
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Confirm Goal',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).maybePop(),
                  )
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _descCtrl,
                decoration:
                    const InputDecoration(labelText: 'Description (optional)'),
                minLines: 1,
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _targetCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Target value'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Unit'),
                      child: Text(v('unit')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Metric'),
                child: Text(v('metric')),
              ),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Window'),
                child: Text(v('window')),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child:
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
              ElevatedButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: const Text('Create Goal'),
              ),
              const SizedBox(height: 8),
              Text(
                'By creating, notifications and progress tracking will start based on your goal window.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
