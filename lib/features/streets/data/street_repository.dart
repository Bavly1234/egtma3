import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../core/utils/arabic_text.dart';
import '../../auth/domain/app_user.dart';
import '../domain/street.dart';

class StreetRepository {
  StreetRepository(this._db);
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(FsPaths.streets);

  Stream<List<Street>> watchAll() => _col.orderBy('nameNormalized').snapshots().map(
      (s) => s.docs.map((d) => Street.fromMap(d.id, d.data())).toList());

  /// The id of the street with this name. A renamed street keeps its old id,
  /// so look it up by normalised name instead of deriving the id from the
  /// name (otherwise women of a renamed street would be split into a new,
  /// unassigned street).
  Future<String> resolveId(String name) async {
    final n = ArabicText.normalize(name);
    final snap = await AppFailure.guard(
        _col.where('nameNormalized', isEqualTo: n).limit(1).get());
    return snap.docs.isNotEmpty ? snap.docs.first.id : Street.idFor(name);
  }

  /// Upserts the street in [batch]. Pass [id] from [resolveId].
  String upsertInBatch(WriteBatch batch, String name, {String? id}) {
    id ??= Street.idFor(name);
    batch.set(
      _col.doc(id),
      {
        'name': name.trim(),
        'nameNormalized': ArabicText.normalize(name),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    return id;
  }

  Future<void> rename(String id, String newName) async {
    try {
      await _col.doc(id).update({
        'name': newName.trim(),
        'nameNormalized': ArabicText.normalize(newName),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // Women keep a denormalised streetName: propagate the rename.
      final women =
          await _db.collection(FsPaths.women).where('streetId', isEqualTo: id).get();
      for (var i = 0; i < women.docs.length; i += 400) {
        final b = _db.batch();
        for (final d in women.docs.skip(i).take(400)) {
          b.update(d.reference, {'streetName': newName.trim()});
        }
        await b.commit();
      }
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  Future<void> add(String name) async {
    try {
      final b = _db.batch();
      upsertInBatch(b, name);
      await b.commit();
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  /// Assigns (or unassigns with null) a servant responsible for a whole street.
  /// This is the ONLY assignment in the app: every woman belongs to her
  /// street's servant. Managed from the Streets screen (father).
  Future<void> setServant(
      String streetId, AppUser? servant, AppUser actor) async {
    try {
      await _col.doc(streetId).set({
        'servantId': servant?.id,
        'servantName': servant?.name,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      // Open افتقاد tasks of this street move to the new servant.
      final open = await AppFailure.guard(_db
          .collection(FsPaths.suggestions)
          .where('streetId', isEqualTo: streetId)
          .where('status', whereIn: SuggestionStatus.activeWires)
          .get());
      for (var i = 0; i < open.docs.length; i += 400) {
        final b = _db.batch();
        for (final d in open.docs.skip(i).take(400)) {
          b.update(d.reference, {
            'assignedServantId': servant?.id,
            'assignedServantName': servant?.name,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await b.commit();
      }
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }
}

final streetRepositoryProvider =
    Provider((ref) => StreetRepository(ref.watch(firestoreProvider)));

final streetsProvider = StreamProvider<List<Street>>(
    (ref) => ref.watch(streetRepositoryProvider).watchAll());

/// Streets keyed by id — the single source of street→servant assignment.
final streetMapProvider = Provider<Map<String, Street>>((ref) {
  final streets = ref.watch(streetsProvider).value ?? const [];
  return {for (final s in streets) s.id: s};
});
