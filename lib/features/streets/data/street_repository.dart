import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../core/utils/arabic_text.dart';
import '../domain/street.dart';

class StreetRepository {
  StreetRepository(this._db);
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(FsPaths.streets);

  Stream<List<Street>> watchAll() => _col.orderBy('nameNormalized').snapshots().map(
      (s) => s.docs.map((d) => Street.fromMap(d.id, d.data())).toList());

  /// Adds the street upsert to [batch] and returns its id.
  String upsertInBatch(WriteBatch batch, String name) {
    final id = Street.idFor(name);
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
}

final streetRepositoryProvider =
    Provider((ref) => StreetRepository(ref.watch(firestoreProvider)));

final streetsProvider = StreamProvider<List<Street>>(
    (ref) => ref.watch(streetRepositoryProvider).watchAll());
