import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/excel_import_service.dart';
import '../domain/import_models.dart';

/// Excel preview: tabs for new / duplicate / invalid rows.
class ImportPreviewView extends StatefulWidget {
  const ImportPreviewView({super.key, required this.preview});
  final ImportPreview preview;

  @override
  State<ImportPreviewView> createState() => _ImportPreviewViewState();
}

class _ImportPreviewViewState extends State<ImportPreviewView> {
  RowCategory _tab = RowCategory.valid;

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    final rows = switch (_tab) {
      RowCategory.valid => p.valid,
      RowCategory.duplicate => p.duplicates,
      RowCategory.invalid => p.invalid,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        _chip(RowCategory.valid, 'جديدة', p.valid.length, AppColors.present),
        _chip(RowCategory.duplicate, 'مكررة', p.duplicates.length, AppColors.warning),
        _chip(RowCategory.invalid, 'غير صالحة', p.invalid.length, AppColors.absent),
      ]),
      const SizedBox(height: 12),
      if (rows.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('لا يوجد', style: TextStyle(fontSize: 18)),
        ),
      for (final r in rows.take(300))
        Card(
          child: ListTile(
            leading: CircleAvatar(child: Text('${r.rowNumber}')),
            title: Text(r.rawName.isEmpty ? '(بدون اسم)' : r.rawName),
            subtitle: Text(switch (r.category) {
              RowCategory.valid => _describe(r),
              RowCategory.duplicate => r.duplicateReason ?? '',
              RowCategory.invalid => r.errors.join('، '),
            }),
          ),
        ),
      if (rows.length > 300)
        Text('... و ${rows.length - 300} صف آخر', style: const TextStyle(fontSize: 16)),
    ]);
  }

  Widget _chip(RowCategory c, String label, int n, Color color) => ChoiceChip(
        label: Text('$label ($n)'),
        selected: _tab == c,
        selectedColor: color.withValues(alpha: .2),
        side: BorderSide(color: color),
        onSelected: (_) => setState(() => _tab = c),
      );
}

/// How a valid row was understood, one fact per line.
String _describe(ImportRow r) {
  final d = r.draft!;
  return [
    'الشارع: ${d.streetName}',
    if (d.phone.isNotEmpty) 'موبايل: ${d.phone}',
    if (d.landline.isNotEmpty) 'أرضي: ${d.landline}',
    if (!d.birth.isEmpty) 'عيد الميلاد: ${d.birth.display}',
    if (d.notes.isNotEmpty) 'ملاحظات: ${d.notes}',
  ].join('\n');
}
