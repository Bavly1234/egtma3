import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/feedback.dart';
import '../../auth/data/auth_repository.dart';
import '../../women/presentation/women_list_controller.dart';
import '../data/excel_import_service.dart';
import 'import_preview.dart';

/// Excel import: choose file → preview (new / duplicate / invalid) → confirm.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  ImportPreview? _preview;
  String? _fileName;
  bool _busy = false;
  String? _progress;

  Future<void> _pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );
    if (file == null) return;
    setState(() {
      _busy = true;
      _preview = null;
      _fileName = file.name;
    });
    try {
      final rows = ExcelImportService.readRows(await file.readAsBytes());
      final preview = await ref.read(excelImportServiceProvider).preview(rows);
      if (mounted) setState(() => _preview = preview);
    } catch (e) {
      if (mounted) AppToast.error(context, AppFailure.from(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commit() async {
    final p = _preview!;
    final ok = await confirmAction(context,
        title: 'تأكيد الاستيراد',
        message: 'سيتم إضافة ${p.valid.length} سيدة جديدة.\n'
            'لن يتم استيراد ${p.duplicates.length} مكررة و ${p.invalid.length} غير صالحة.',
        confirmLabel: 'استيراد');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    await runGuarded(context, () async {
      final n = await ref.read(excelImportServiceProvider).commit(
            p,
            ref.read(requireUserProvider),
            onProgress: (d, t) => mounted ? setState(() => _progress = '$d / $t') : null,
          );
      ref.invalidate(womenListProvider);
      if (mounted) {
        AppToast.success(context, 'تم استيراد $n سيدة بنجاح');
        setState(() => _preview = null);
      }
    });
    if (mounted) {
      setState(() {
        _busy = false;
        _progress = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('استيراد من Excel')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          color: AppColors.primaryLight,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'الأعمدة (الصف الأول):\n'
              'الاسم كامل — رقم التليفون — الشارع — '
              'العنوان بالكامل — تاريخ الميلاد\n\n'
              '📞 التليفون: ممكن موبايل وأرضي مع بعض زي 01222545908/5916219 '
              '— الموبايل بيتحط لوحده والأرضي لوحده، وأي رقم زيادة بيتحفظ في الملاحظات.\n'
              '🎂 تاريخ الميلاد: يوم/شهر زي 30/4، أو الشهر بس زي /6، والسنة مش ضرورية.\n'
              '✍️ الاسم بس هو المطلوب، والباقي ممكن يكون فاضي.\n\n'
              'السيدات المكررات مش بيتضافوا، وهتشوفي معاينة قبل الحفظ.',
              style: TextStyle(fontSize: 17),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _pick,
          icon: const Icon(Icons.upload_file),
          label: Text(_fileName == null ? 'اختيار ملف Excel' : 'اختيار ملف آخر'),
        ),
        if (_busy) ...[
          const SizedBox(height: 24),
          const Center(child: CircularProgressIndicator()),
          if (_progress != null)
            Center(child: Text('جارٍ الحفظ $_progress', style: const TextStyle(fontSize: 18))),
        ],
        if (p != null && !_busy) ...[
          const SizedBox(height: 16),
          Text('الملف: $_fileName', style: const TextStyle(fontSize: 17)),
          const SizedBox(height: 8),
          ImportPreviewView(preview: p),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: p.valid.isEmpty ? null : _commit,
            icon: const Icon(Icons.check),
            label: Text('استيراد ${p.valid.length} سيدة جديدة'),
          ),
        ],
        const SizedBox(height: 32),
      ]),
    );
  }
}
