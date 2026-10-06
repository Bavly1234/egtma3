import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/feedback.dart';
import '../../auth/data/auth_repository.dart';
import '../../women/domain/woman.dart';
import '../data/follow_up_repository.dart';
import '../domain/follow_up.dart';

/// Records a call / home visit / note. When [completes] is given, the
/// suggestion is marked done in the same atomic write ("تم الافتقاد").
Future<bool> showRecordFollowUpSheet(
  BuildContext context, {
  required Woman woman,
  required FollowUpType type,
  FollowUpSuggestion? completes,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _RecordSheet(woman: woman, type: type, completes: completes),
  );
  return saved ?? false;
}

class _RecordSheet extends ConsumerStatefulWidget {
  const _RecordSheet(
      {required this.woman, required this.type, this.completes});
  final Woman woman;
  final FollowUpType type;
  final FollowUpSuggestion? completes;

  @override
  ConsumerState<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends ConsumerState<_RecordSheet> {
  late FollowUpResult _result = FollowUpResult.forType(widget.type).first;
  final _notes = TextEditingController();
  DateTime _when = DateTime.now();
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime.now().subtract(const Duration(days: 60)),
      lastDate: DateTime.now(),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_when));
    setState(() => _when = DateTime(
        d.year, d.month, d.day, t?.hour ?? _when.hour, t?.minute ?? _when.minute));
  }

  Future<void> _save() async {
    if (widget.type == FollowUpType.note && _notes.text.trim().isEmpty) {
      AppToast.error(context, 'اكتبي الملاحظة أولاً');
      return;
    }
    setState(() => _busy = true);
    final ok = await runGuarded(
      context,
      () => ref.read(followUpRepositoryProvider).record(
            woman: widget.woman,
            type: widget.type,
            result: _result,
            notes: _notes.text,
            actor: ref.read(requireUserProvider),
            occurredAt: _when,
            completes: widget.completes,
          ),
      successMessage: widget.completes != null ? 'تم الافتقاد ✅' : 'تم الحفظ ✅',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.type) {
      FollowUpType.phoneCall => 'تسجيل مكالمة',
      FollowUpType.homeVisit => 'تسجيل زيارة منزلية',
      FollowUpType.note => 'إضافة ملاحظة',
    };
    final results = FollowUpResult.forType(widget.type);
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            Text(widget.woman.fullName,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            if (results.length > 1) ...[
              const Text('النتيجة', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final r in results)
                  ChoiceChip(
                    label: Text(r.label),
                    selected: _result == r,
                    onSelected: (_) => setState(() => _result = r),
                  ),
              ]),
              const SizedBox(height: 16),
            ],
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.schedule),
              label: Text('الوقت: ${Dates.displayDateTime(_when)}'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notes,
              maxLines: 4,
              decoration: const InputDecoration(
                  labelText: 'ملاحظات', alignLabelWithHint: true),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save),
              label: Text(widget.completes != null ? 'حفظ — تم الافتقاد' : 'حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}
