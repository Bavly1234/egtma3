import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/utils/birth_date.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/simple_charts.dart';
import '../../../core/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../streets/data/street_repository.dart';
import '../data/women_repository.dart';
import '../domain/woman.dart';
import '../domain/woman_validator.dart';

/// Add (womanId == null) or edit a woman. Every active servant (full women
/// CRUD — route-open and enforced by security rules).
class WomanFormScreen extends ConsumerWidget {
  const WomanFormScreen({super.key, this.womanId});
  final String? womanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (womanId == null) return const _Form(initial: null);
    return AsyncBody(
      value: ref.watch(womanProvider(womanId!)),
      builder: (w) => w == null
          ? const Scaffold(
              body: EmptyState(icon: Icons.person_off, title: 'غير موجودة'))
          : _Form(initial: w),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.initial});
  final Woman? initial;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  final _key = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.fullName);
  late final _phone = TextEditingController(text: widget.initial?.phone);
  late final _street = TextEditingController(text: widget.initial?.streetName);
  late final _address = TextEditingController(text: widget.initial?.address);
  late final _notes = TextEditingController(text: widget.initial?.notes);
  late final _landline = TextEditingController(text: widget.initial?.landline);
  late int? _bDay = widget.initial?.birth.day;
  late int? _bMonth = widget.initial?.birth.month;
  late int? _bYear = widget.initial?.birth.year;
  late final bool _active = widget.initial?.active ?? true;
  late bool _isServant = widget.initial?.isServant ?? false;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _landline, _street, _address, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Landline as typed; a 7-digit local number gets the 03 area code.
  String get _landlineValue {
    final d = PhoneUtils.normalize(_landline.text);
    return RegExp(r'^\d{7}$').hasMatch(d) ? '${PhoneUtils.localAreaCode}$d' : d;
  }

  /// Birthday as three simple lists: day, month and (optional) year.
  Widget _birthPicker() {
    final now = DateTime.now();
    Widget box<T>(String label, T? value, List<(T?, String)> items,
            ValueChanged<T?> onChanged) =>
        Expanded(
          child: DropdownButtonFormField<T?>(
            initialValue: value,
            isExpanded: true,
            decoration: InputDecoration(
                labelText: label,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 16)),
            items: [
              for (final (v, l) in items)
                DropdownMenuItem(value: v, child: Text(l)),
            ],
            onChanged: onChanged,
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text('🎂 عيد الميلاد (السنة مش ضرورية)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      Row(children: [
        box<int>('اليوم', _bDay, [(null, '—'), for (var d = 1; d <= 31; d++) (d, '$d')],
            (v) => setState(() => _bDay = v)),
        const SizedBox(width: 8),
        box<int>('الشهر', _bMonth,
            [(null, '—'), for (var m = 1; m <= 12; m++) (m, kMonthNamesAr[m - 1])],
            (v) => setState(() => _bMonth = v)),
        const SizedBox(width: 8),
        box<int>('السنة', _bYear,
            [(null, '—'), for (var y = now.year; y >= now.year - 110; y--) (y, '$y')],
            (v) => setState(() => _bYear = v)),
      ]),
    ]);
  }

  /// Day without month, or an impossible date (31 فبراير).
  String? get _birthError {
    if (_bMonth == null) {
      return _bDay != null || _bYear != null ? 'اختاري الشهر' : null;
    }
    if (_bDay != null) {
      final y = _bYear ?? 2000;
      if (DateTime(y, _bMonth!, _bDay!).month != _bMonth) {
        return 'التاريخ ده مش موجود';
      }
    }
    return null;
  }

  Future<void> _save() async {
    final birthError = _birthError;
    if (birthError != null) {
      AppToast.error(context, birthError);
      return;
    }
    if (!_key.currentState!.validate()) return;
    setState(() => _busy = true);
    final user = ref.read(requireUserProvider);
    final draft = WomanDraft(
      fullName: _name.text,
      streetName: _street.text,
      address: _address.text,
      phone: PhoneUtils.normalize(_phone.text),
      landline: _landlineValue,
      birth: BirthDate(day: _bDay, month: _bMonth, year: _bYear),
      active: _active,
      isServant: _isServant,
      notes: _notes.text,
    );
    final repo = ref.read(womenRepositoryProvider);
    String? newId;
    final ok = await runGuarded(context, () async {
      if (widget.initial == null) {
        newId = await repo.create(draft, user);
      } else {
        await repo.update(widget.initial!.id, draft, user);
      }
    }, successMessage: 'تم الحفظ ✅');
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    if (newId != null) {
      context.pushReplacement(Routes.woman(newId!));
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final streets = ref.watch(streetsProvider).value ?? const [];
    const gap = SizedBox(height: 16);
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.initial == null ? 'إضافة سيدة' : 'تعديل البيانات')),
      body: Form(
        key: _key,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(
                labelText: 'الاسم بالكامل *', prefixIcon: Icon(Icons.person)),
            validator: WomanValidator.name,
          ),
          gap,
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
                labelText: 'رقم الموبايل', prefixIcon: Icon(Icons.phone_android)),
            validator: WomanValidator.phone,
          ),
          gap,
          TextFormField(
            controller: _landline,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
                labelText: 'التليفون الأرضي (لو موجود)',
                prefixIcon: Icon(Icons.phone)),
          ),
          gap,
          Autocomplete<String>(
            initialValue: TextEditingValue(text: _street.text),
            optionsBuilder: (v) => streets
                .map((s) => s.name)
                .where((n) => v.text.isEmpty || n.contains(v.text)),
            onSelected: (v) => _street.text = v,
            fieldViewBuilder: (ctx, ctrl, focus, onSubmit) {
              return TextFormField(
                controller: ctrl,
                focusNode: focus,
                onChanged: (v) => _street.text = v,
                decoration: const InputDecoration(
                    labelText: 'الشارع *', prefixIcon: Icon(Icons.signpost)),
                validator: (_) => WomanValidator.street(_street.text),
              );
            },
          ),
          gap,
          TextFormField(
            controller: _address,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'العنوان بالكامل',
                prefixIcon: Icon(Icons.location_on)),
          ),
          gap,
          _birthPicker(),
          const SizedBox(height: 16),
          Card(
            child: SwitchListTile(
              value: _isServant,
              onChanged: (v) => setState(() => _isServant = v),
              secondary: const Icon(Icons.badge, size: 30),
              title: const Text('خادمة'),
              subtitle: const Text('أبونا بياخد حضورها في صفحة "حضور الخادمات"'),
            ),
          ),
          gap,
          TextFormField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'ملاحظات', prefixIcon: Icon(Icons.notes)),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save),
            label: const Text('حفظ'),
          ),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }
}
