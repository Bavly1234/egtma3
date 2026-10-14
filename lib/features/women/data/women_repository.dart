import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/business_rules.dart';
import '../../../core/constants/enums.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../core/utils/arabic_text.dart';
import '../../audit/data/audit_repository.dart';
import '../../audit/domain/audit_entry.dart';
import '../../auth/domain/app_user.dart';
import '../../excel/domain/duplicate_detector.dart';
import '../../streets/data/street_repository.dart';
import '../domain/woman.dart';
import '../domain/women_filter.dart';

class WomenPage {
  const WomenPage(this.items, this.cursor, this.hasMore);
  final List<Woman> items;
  final DocumentSnapshot? cursor;
  final bool hasMore;
}

class WomenRepository {
  WomenRepository(this._db, this._streets, this._audit);
  final FirebaseFirestore _db;
  final StreetRepository _streets;
  final AuditRepository _audit;

  CollectionReference<Map<String, dynamic>> get col =>
      _db.collection(FsPaths.women);

  /// All active staff see all women. Assignment to a servant is optional and
  /// only used as a filter / label.
  Query<Map<String, dynamic>> scoped(AppUser user) => col;

  Query<Map<String, dynamic>> buildQuery(AppUser user, WomenFilter f) {
    var q = scoped(user);
    if (f.streetId != null) q = q.where('streetId', isEqualTo: f.streetId);
    if (f.active != null) q = q.where('active', isEqualTo: f.active);
    if (f.birthMonth != null) {
      q = q.where('birthMonth', isEqualTo: f.birthMonth);
    }
    final fu = f.followUp.wire;
    if (fu != null) q = q.where('activeSuggestionType', isEqualTo: fu);
    final tokens = f.queryTokens;
    if (tokens.isNotEmpty) {
      // Longest token is the most selective prefix.
      final t = tokens.reduce((a, b) => a.length >= b.length ? a : b);
      q = q.where('searchKeywords', arrayContains: t);
    }
    // With only the role scope we can order by name (composite index exists).
    // With extra filters we rely on Firestore's index merging and sort the
    // page in memory, avoiding an index per filter combination.
    final onlyScope = !f.hasServerFilters;
    return onlyScope ? q.orderBy('nameNormalized') : q;
  }

  Future<WomenPage> page(
    AppUser user,
    WomenFilter filter, {
    DocumentSnapshot? after,
    int limit = BusinessRules.pageSize,
  }) async {
    try {
      var q = buildQuery(user, filter).limit(limit);
      if (after != null) q = q.startAfterDocument(after);
      final snap = await AppFailure.guard(q.get());
      final items = snap.docs
          .map((d) => Woman.fromMap(d.id, d.data()))
          .where(filter.matchesClientSide)
          .toList();
      if (filter.hasServerFilters) {
        items.sort((a, b) => ArabicText.normalizeName(a.fullName)
            .compareTo(ArabicText.normalizeName(b.fullName)));
      }
      return WomenPage(items, snap.docs.isEmpty ? after : snap.docs.last,
          snap.docs.length == limit);
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  /// Loads every woman matching [filter] (used by export and attendance).
  /// Bounded by [max] to protect against runaway reads.
  Future<List<Woman>> all(AppUser user, WomenFilter filter,
      {int max = 5000}) async {
    final out = <Woman>[];
    DocumentSnapshot? cursor;
    while (out.length < max) {
      final p = await page(user, filter, after: cursor, limit: 300);
      out.addAll(p.items);
      if (!p.hasMore) break;
      cursor = p.cursor;
    }
    return out;
  }

  DocumentReference<Map<String, dynamic>> _street(String id) =>
      _db.collection(FsPaths.streets).doc(id);

  void _countStreet(WriteBatch b, String? streetId, int delta) {
    if (streetId == null || streetId.isEmpty) return;
    b.set(_street(streetId), {'womenCount': FieldValue.increment(delta)},
        SetOptions(merge: true));
  }

  /// Active suggestions of the given women (used when deactivating/deleting).
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _activeSuggestions(
      List<String> womanIds) async {
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (var i = 0; i < womanIds.length; i += 30) {
      final chunk = womanIds.sublist(i, (i + 30).clamp(0, womanIds.length));
      final snap = await AppFailure.guard(_db
          .collection(FsPaths.suggestions)
          .where('womanId', whereIn: chunk)
          .where('status', whereIn: SuggestionStatus.activeWires)
          .get());
      out.addAll(snap.docs);
    }
    return out;
  }

  Future<void> _cancelSuggestions(WriteBatch b, String womanId, String reason) async {
    for (final d in await _activeSuggestions([womanId])) {
      b.update(d.reference, {
        'status': SuggestionStatus.cancelled.wire,
        'cancelReason': reason,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    b.update(col.doc(womanId), {'activeSuggestionType': 'none'});
  }

  Stream<Woman?> watch(String id) => col.doc(id).snapshots().map(
      (s) => s.exists ? Woman.fromMap(s.id, s.data()!) : null);

  Future<String> create(WomanDraft draft, AppUser actor) async {
    try {
      final resolved = await _streets.resolveId(draft.streetName);
      final batch = _db.batch();
      final streetId =
          _streets.upsertInBatch(batch, draft.streetName, id: resolved);
      _countStreet(batch, streetId, 1);
      final ref = col.doc();
      batch.set(ref, {
        ...draft.toFields(streetId),
        'consecutiveAbsences': 0,
        'totalPresent': 0,
        'totalAbsent': 0,
        'phoneCalls': 0,
        'homeVisits': 0,
        'activeSuggestionType': 'none',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': actor.id,
      });
      _audit.addToBatch(batch,
          actor: actor,
          action: AuditAction.womanCreated,
          entityType: 'woman',
          entityId: ref.id,
          summary: draft.fullName);
      await batch.commit();
      return ref.id;
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  Future<void> update(String id, WomanDraft draft, AppUser actor) async {
    try {
      final old = (await AppFailure.guard(col.doc(id).get())).data();
      final resolved = await _streets.resolveId(draft.streetName);
      final batch = _db.batch();
      final streetId =
          _streets.upsertInBatch(batch, draft.streetName, id: resolved);
      final oldStreet = old?['streetId'] as String?;
      if (oldStreet != streetId) {
        _countStreet(batch, oldStreet, -1);
        _countStreet(batch, streetId, 1);
      }
      batch.update(col.doc(id), {
        ...draft.toFields(streetId),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _audit.addToBatch(batch,
          actor: actor,
          action: AuditAction.womanUpdated,
          entityType: 'woman',
          entityId: id,
          summary: draft.fullName);
      await batch.commit();
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  /// Edits notes (any active staff — servants have full women CRUD).
  Future<void> updateNotes(String id, String notes, AppUser actor) async {
    try {
      await col.doc(id).update({
        'notes': notes.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _audit.log(
          actor: actor,
          action: AuditAction.womanUpdated,
          entityType: 'woman',
          entityId: id,
          summary: 'تعديل الملاحظات');
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  Future<void> setActive(String id, bool active, AppUser actor) async {
    try {
      final batch = _db.batch();
      batch.update(col.doc(id),
          {'active': active, 'updatedAt': FieldValue.serverTimestamp()});
      if (!active) await _cancelSuggestions(batch, id, 'deactivated');
      _audit.addToBatch(batch,
          actor: actor,
          action: active ? AuditAction.womanUpdated : AuditAction.womanDisabled,
          entityType: 'woman',
          entityId: id,
          summary: active ? 'تفعيل' : 'إيقاف');
      await batch.commit();
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  /// Hard delete (any active staff — servants have full women CRUD).
  /// History records stay for statistics.
  Future<void> delete(String id, String name, AppUser actor) async {
    try {
      final old = (await AppFailure.guard(col.doc(id).get())).data();
      final batch = _db.batch();
      for (final d in await _activeSuggestions([id])) {
        batch.update(d.reference, {
          'status': SuggestionStatus.cancelled.wire,
          'cancelReason': 'deleted',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      _countStreet(batch, old?['streetId'] as String?, -1);
      batch.delete(col.doc(id));
      _audit.addToBatch(batch,
          actor: actor,
          action: AuditAction.womanDeleted,
          entityType: 'woman',
          entityId: id,
          summary: name);
      await batch.commit();
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  /// Existing identities that may collide with imported rows. Uses `whereIn`
  /// on indexed fields instead of downloading every woman.
  Future<List<PersonIdentity>> identitiesMatching({
    required Iterable<String> phones,
    required Iterable<String> normalizedNames,
  }) async {
    final out = <String, PersonIdentity>{};
    Future<void> run(String field, List<String> values) async {
      for (var i = 0; i < values.length; i += 30) {
        final chunk = values.sublist(i, (i + 30).clamp(0, values.length));
        final snap =
            await AppFailure.guard(col.where(field, whereIn: chunk).get());
        for (final d in snap.docs) {
          final w = Woman.fromMap(d.id, d.data());
          out[d.id] = PersonIdentity(
              name: w.fullName,
              phone: w.phone,
              address: w.address,
              dateOfBirth: w.dateOfBirth);
        }
      }
    }

    await run('phone', phones.where((p) => p.isNotEmpty).toSet().toList());
    await run('nameNormalized',
        normalizedNames.where((n) => n.isNotEmpty).toSet().toList());
    return out.values.toList();
  }

  /// Women whose birthday falls in [month] (optionally on [day]).
  Future<List<Woman>> birthdays(AppUser user, int month, {int? day}) async {
    try {
      var q = scoped(user)
          .where('active', isEqualTo: true)
          .where('birthMonth', isEqualTo: month);
      if (day != null) q = q.where('birthDay', isEqualTo: day);
      final snap = await AppFailure.guard(q.get());
      return snap.docs.map((d) => Woman.fromMap(d.id, d.data())).toList();
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  Future<int> count(AppUser user, {bool? active}) async {
    var q = scoped(user);
    if (active != null) q = q.where('active', isEqualTo: active);
    final agg = await AppFailure.guard(q.count().get());
    return agg.count ?? 0;
  }

  Future<List<Woman>> topBy(AppUser user, String field,
      {int limit = 10}) async {
    final snap = await AppFailure.guard(scoped(user)
        .where('active', isEqualTo: true)
        .orderBy(field, descending: true)
        .limit(limit)
        .get());
    return snap.docs.map((d) => Woman.fromMap(d.id, d.data())).toList();
  }
}

final womenRepositoryProvider = Provider((ref) => WomenRepository(
      ref.watch(firestoreProvider),
      ref.watch(streetRepositoryProvider),
      ref.watch(auditRepositoryProvider),
    ));

final womanProvider = StreamProvider.family<Woman?, String>(
    (ref, id) => ref.watch(womenRepositoryProvider).watch(id));
