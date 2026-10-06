import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/dates.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/states.dart';
import '../data/audit_repository.dart';
import '../domain/audit_entry.dart';

/// سجل التغييرات (father only).
class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  final _items = <AuditEntry>[];
  DocumentSnapshot? _cursor;
  bool _loading = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading || _done) return;
    setState(() => _loading = true);
    try {
      final (items, cursor) =
          await ref.read(auditRepositoryProvider).page(after: _cursor);
      setState(() {
        _items.addAll(items);
        _cursor = cursor ?? _cursor;
        _done = items.length < 40;
      });
    } catch (e) {
      if (mounted) AppToast.error(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('سجل التغييرات')),
        body: _items.isEmpty
            ? (_loading
                ? const LoadingView()
                : const EmptyState(icon: Icons.history, title: 'لا توجد تغييرات مسجلة'))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _items.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  if (i == _items.length) {
                    return _done
                        ? const SizedBox(height: 24)
                        : Center(
                            child: _loading
                                ? const CircularProgressIndicator()
                                : OutlinedButton(
                                    onPressed: _load, child: const Text('عرض المزيد')),
                          );
                  }
                  final a = _items[i];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.history_edu, size: 30),
                      title: Text(a.actionLabel),
                      subtitle: Text(
                          '${a.summary.isEmpty ? '' : '${a.summary}\n'}${a.actorName} • ${Dates.displayDateTime(a.createdAt)}'),
                      isThreeLine: a.summary.isNotEmpty,
                    ),
                  );
                },
              ),
      );
}
