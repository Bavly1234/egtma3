import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../streets/data/street_repository.dart';
import '../../users/presentation/servant_picker.dart';
import '../data/women_repository.dart';
import '../domain/woman.dart';
import '../domain/woman_validator.dart';

/// Add (womanId == null) or edit a woman. Father only (route-guarded and
/// enforced by security rules).
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
  late final _dobText = TextEditingController(
      text: widget.initial?.dateOfBirth == null
          ? ''
          : Dates.display(widget.initial!.dateOfBirth));
  late bool _active = widget.initial?.active ?? true;
  late String? _servantId = widget.initial?.assignedServantId;
  late String? _servantName = widget.initial?.assignedServantName;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _street, _address, _notes, _dobText]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime? get _dob => Dates.parseFlexible(_dobText.text);

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 40),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'تاريخ الميلاد',
    );
    if (d != null) setState(() => _dobText.text = Dates.display(d));
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _busy = true);
    final user = ref.read(requireUserProvider);
    final draft = WomanDraft(
      fullName: _name.text,
      streetName: _street.text,
      address: _address.text,
      phone: PhoneUtils.normalize(_phone.text),
      dateOfBirth: _dob,
      active: _active,
      notes: _notes.text,
      assignedServantId: _servantId,
      assignedServantName: _servantName,
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
                labelText: 'رقم التليفون', prefixIcon: Icon(Icons.phone)),
            validator: WomanValidator.phone,
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
                labelText: 'العنوان بالكامل *',
                prefixIcon: Icon(Icons.location_on)),
            validator: WomanValidator.address,
          ),
          gap,
          TextFormField(
            controller: _dobText,
            keyboardType: TextInputType.datetime,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'تاريخ الميلاد * (يوم/شهر/سنة)',
              prefixIcon: const Icon(Icons.cake),
              suffixIcon: IconButton(
                tooltip: 'اختيار من التقويم',
                icon: const Icon(Icons.calendar_month),
                onPressed: _pickDob,
              ),
            ),
            validator: (_) => _dobText.text.trim().isNotEmpty && _dob == null
                ? 'اكتبي التاريخ هكذا: 15/03/1970'
                : WomanValidator.dateOfBirth(_dob),
          ),
          gap,
          Card(
            child: ListTile(
              leading: const Icon(Icons.badge, size: 30),
              title: const Text('الخادمة المسؤولة'),
              subtitle: Text(_servantName ?? 'غير معينة'),
              trailing: const Icon(Icons.edit),
              onTap: () async {
                final c = await pickServant(context, ref, allowNone: true);
                if (c != null) {
                  setState(() {
                    _servantId = c.value?.id;
                    _servantName = c.value?.name;
                  });
                }
              },
            ),
          ),
          gap,
          SwitchListTile(
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            title: const Text('نشطة'),
            subtitle: const Text('السيدات غير النشطات لا يظهرن في الحضور'),
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
