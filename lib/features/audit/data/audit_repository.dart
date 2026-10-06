import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../core/utils/app_logger.dart';
import '../../auth/domain/app_user.dart';
import '../domain/audit_entry.dart';

class AuditRepository {
  AuditRepository(this._db);
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(FsPaths.auditLogs);

  /// Returns the audit document so it can be added to a caller's batch,
  /// making the change and its audit entry atomic.
  void addToBatch(
    WriteBatch batch, {
    required AppUser actor,
    required AuditAction action,
    required String entityType,
    required String entityId,
    String summary = '',
  }) {
    batch.set(_col.doc(), _entry(actor, action, entityType, entityId, summary));
  }

  /// Fire-and-forget audit write (works offline; syncs later).
  void log({
    required AppUser actor,
    required AuditAction action,
    required String entityType,
    required String entityId,
    String summary = '',
  }) {
    _col
        .add(_entry(actor, action, entityType, entityId, summary))
        .catchError((Object e) {
      AppLog.w('Audit write failed', e);
      return _col.doc();
    });
  }

  Map<String, dynamic> _entry(AppUser actor, AuditAction action,
          String entityType, String entityId, String summary) =>
      {
        'action': action.wire,
        'actorId': actor.id,
        'actorName': actor.name,
        'entityType': entityType,
        'entityId': entityId,
        'summary': summary,
        'createdAt': FieldValue.serverTimestamp(),
      };

  Future<(List<AuditEntry>, DocumentSnapshot?)> page({
    DocumentSnapshot? after,
    int limit = 40,
  }) async {
    Query<Map<String, dynamic>> q =
        _col.orderBy('createdAt', descending: true).limit(limit);
    if (after != null) q = q.startAfterDocument(after);
    final snap = await q.get();
    return (
      snap.docs.map((d) => AuditEntry.fromMap(d.id, d.data())).toList(),
      snap.docs.isEmpty ? null : snap.docs.last,
    );
  }
}

final auditRepositoryProvider =
    Provider((ref) => AuditRepository(ref.watch(firestoreProvider)));
