import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/firebase_providers.dart';
import '../../audit/data/audit_repository.dart';
import '../../audit/domain/audit_entry.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../women/domain/woman.dart';
import '../domain/follow_up.dart';

class SuggestionQuery {
  const SuggestionQuery({
    this.type,
    this.activeOnly = true,
    this.servantId,
    this.streetId,
  });
  final SuggestionType? type;
  final bool activeOnly;
  final String? servantId;
  final String? streetId;

  @override
  bool operator ==(Object other) =>
      other is SuggestionQuery &&
      other.type == type &&
      other.activeOnly == activeOnly &&
      other.servantId == servantId &&
      other.streetId == streetId;

  @override
  int get hashCode => Object.hash(type, activeOnly, servantId, streetId);
}

class FollowUpRepository {
  FollowUpRepository(this._db, this._audit);
  final FirebaseFirestore _db;
  final AuditRepository _audit;

  CollectionReference<Map<String, dynamic>> get _followUps =>
      _db.collection(FsPaths.followUps);
  CollectionReference<Map<String, dynamic>> get _suggestions =>
      _db.collection(FsPaths.suggestions);

  // ---------- Suggestions ----------

  Stream<List<FollowUpSuggestion>> watchSuggestions(
      AppUser user, SuggestionQuery q) {
    Query<Map<String, dynamic>> query = _suggestions;
    if (!user.isFather) {
      query = query.where('assignedServantId', isEqualTo: user.id);
    } else if (q.servantId != null) {
      query = query.where('assignedServantId', isEqualTo: q.servantId);
    }
    if (q.type != null) query = query.where('type', isEqualTo: q.type!.wire);
    if (q.streetId != null) {
      query = query.where('streetId', isEqualTo: q.streetId);
    }
    if (q.activeOnly) {
      query = query.where('status', whereIn: SuggestionStatus.activeWires);
    }
    return query
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .map((s) => s.docs
            .map((d) => FollowUpSuggestion.fromMap(d.id, d.data()))
            .toList());
  }

  Stream<List<FollowUpSuggestion>> watchForWoman(String womanId, AppUser user) {
    var q = _suggestions.where('womanId', isEqualTo: womanId);
    if (!user.isFather) q = q.where('assignedServantId', isEqualTo: user.id);
    return q.orderBy('createdAt', descending: true).limit(20).snapshots().map(
        (s) => s.docs
            .map((d) => FollowUpSuggestion.fromMap(d.id, d.data()))
            .toList());
  }

  Future<void> setSuggestionStatus(
    FollowUpSuggestion s,
    SuggestionStatus status,
    AppUser actor,
  ) async {
    try {
      await _suggestions.doc(s.id).update({
        'status': status.wire,
        'updatedAt': FieldValue.serverTimestamp(),
        if (status == SuggestionStatus.completed) ...{
          'completedAt': FieldValue.serverTimestamp(),
          'completedBy': actor.id,
        },
      });
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  // ---------- Follow-up records ----------

  /// Records a call/visit/note. If it resolves a suggestion, the suggestion is
  /// completed in the same atomic batch. Counters on the woman are updated by
  /// Cloud Functions from these records (never incremented blindly here).
  Future<void> record({
    required Woman woman,
    required FollowUpType type,
    required FollowUpResult result,
    required String notes,
    required AppUser actor,
    DateTime? occurredAt,
    FollowUpSuggestion? completes,
  }) async {
    try {
      final batch = _db.batch();
      final ref = _followUps.doc();
      batch.set(ref, {
        'womanId': woman.id,
        'womanName': woman.fullName,
        'servantId': actor.id,
        'servantName': actor.name,
        'assignedServantId': woman.assignedServantId,
        'streetId': woman.streetId,
        'type': type.wire,
        'result': result.wire,
        'notes': notes.trim(),
        'occurredAt': occurredAt != null
            ? Timestamp.fromDate(occurredAt)
            : FieldValue.serverTimestamp(),
        'suggestionId': completes?.id,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (completes != null) {
        batch.update(_suggestions.doc(completes.id), {
          'status': SuggestionStatus.completed.wire,
          'completedAt': FieldValue.serverTimestamp(),
          'completedBy': actor.id,
          'followUpId': ref.id,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      _audit.addToBatch(batch,
          actor: actor,
          action: completes != null
              ? AuditAction.followUpCompleted
              : AuditAction.followUpRecorded,
          entityType: 'woman',
          entityId: woman.id,
          summary: '${type.label} — ${woman.fullName}');
      await batch.commit();
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  Stream<List<FollowUp>> watchHistory(String womanId, AppUser user) {
    var q = _followUps.where('womanId', isEqualTo: womanId);
    if (!user.isFather) {
      q = q.where('assignedServantId', isEqualTo: user.id);
    }
    return q.orderBy('occurredAt', descending: true).limit(100).snapshots().map(
        (s) => s.docs.map((d) => FollowUp.fromMap(d.id, d.data())).toList());
  }

  /// Follow-ups in a date range (export + statistics).
  Future<List<FollowUp>> inRange(
    AppUser user, {
    required DateTime from,
    required DateTime to,
    String? servantId,
    FollowUpType? type,
  }) async {
    try {
      Query<Map<String, dynamic>> q = _followUps;
      if (!user.isFather) {
        q = q.where('servantId', isEqualTo: user.id);
      } else if (servantId != null) {
        q = q.where('servantId', isEqualTo: servantId);
      }
      if (type != null) q = q.where('type', isEqualTo: type.wire);
      final snap = await q
          .where('occurredAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
          .where('occurredAt', isLessThan: Timestamp.fromDate(to))
          .orderBy('occurredAt', descending: true)
          .get();
      return snap.docs.map((d) => FollowUp.fromMap(d.id, d.data())).toList();
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }
}

final followUpRepositoryProvider = Provider((ref) => FollowUpRepository(
    ref.watch(firestoreProvider), ref.watch(auditRepositoryProvider)));

final suggestionsProvider = StreamProvider.family<List<FollowUpSuggestion>,
    SuggestionQuery>((ref, q) {
  final user = ref.watch(currentUserProvider).value;
  if (user == null) return Stream.value(const []);
  return ref.watch(followUpRepositoryProvider).watchSuggestions(user, q);
});
