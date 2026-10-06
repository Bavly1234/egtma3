import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/feedback.dart';
import '../../auth/data/auth_repository.dart';
import '../data/conference_repository.dart';
import '../domain/conference.dart';

/// Create a conference with exactly three user-chosen (possibly
/// non-consecutive) dates.
class CreateConferenceScreen extends ConsumerStatefulWidget {
  const CreateConferenceScreen({super.key});

  @override
  ConsumerState<CreateConferenceScreen> createState() => _State();
}

class _State extends ConsumerState<CreateConferenceScreen> {
  final _name = TextEditingController(text: 'مؤتمر السيدات ${DateTime.now().year}');
  final List<DateTime?> _dates = [null, null, null];
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick(int i) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _dates[i] ?? (i > 0 && _dates[i - 1] != null
          ? _dates[i - 1]!.add(const Duration(days: 1))
          : now),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      helpText: ConferenceDay.labels[i],
    );
    if (d != null) setState(() => _dates[i] = d);
  }

  Future<void> _save() async {
    if (_dates.any((d) => d == null)) {
      AppToast.error(context, 'اختاري تواريخ الأيام الثلاثة');
      return;
    }
    setState(() => _busy = true);
    String? id;
    final ok = await runGuarded(context, () async {
      id = await ref.read(conferenceRepositoryProvider).create(
          _name.text, _dates.cast<DateTime>(), ref.read(requireUserProvider));
    }, successMessage: 'تم إنشاء المؤتمر');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok && id != null) context.pushReplacement(Routes.conference(id!));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('مؤتمر جديد')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
                labelText: 'اسم المؤتمر', prefixIcon: Icon(Icons.event)),
          ),
          const SizedBox(height: 20),
          const Text('أيام المؤتمر (3 أيام — ليس شرطاً أن تكون متتالية)',
              style: TextStyle(fontSize: 18)),
          const SizedBox(height: 12),
          for (var i = 0; i < 3; i++) ...[
            OutlinedButton.icon(
              onPressed: () => _pick(i),
              icon: const Icon(Icons.calendar_month),
              label: Text(_dates[i] == null
                  ? '${ConferenceDay.labels[i]}: اختاري التاريخ'
                  : '${ConferenceDay.labels[i]}: ${Dates.weekdayAr(_dates[i]!)} ${Dates.display(_dates[i])}'),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save),
            label: const Text('إنشاء المؤتمر'),
          ),
        ]),
      );
}
