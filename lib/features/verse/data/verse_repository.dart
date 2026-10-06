import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/dates.dart';
import '../domain/daily_verse.dart';
import 'fallback_verses.dart';

/// Reads `daily_verses/{yyyy-MM-dd}`, which the `publishDailyVerse` Cloud
/// Function fills every morning from `verse_pool`. To use an external API
/// instead, implement [VerseSource] and swap [verseSourceProvider].
class FirestoreVerseSource implements VerseSource {
  FirestoreVerseSource(this._db);
  final FirebaseFirestore _db;

  @override
  Future<DailyVerse?> verseFor(DateTime day) async {
    final id = Dates.dayId(day);
    final snap = await _db.collection(FsPaths.dailyVerses).doc(id).get();
    return snap.exists ? DailyVerse.fromMap(id, snap.data()!) : null;
  }
}

/// Decorator that never fails: falls back to a bundled verse (deterministic
/// per day) when offline or before the function has run.
class ResilientVerseSource implements VerseSource {
  ResilientVerseSource(this._primary);
  final VerseSource _primary;

  @override
  Future<DailyVerse?> verseFor(DateTime day) async {
    try {
      final v = await _primary.verseFor(day);
      if (v != null && v.text.isNotEmpty) return v;
    } catch (e) {
      AppLog.w('Verse source failed, using fallback', e);
    }
    return fallbackVerseFor(day);
  }
}

final verseSourceProvider = Provider<VerseSource>((ref) =>
    ResilientVerseSource(FirestoreVerseSource(ref.watch(firestoreProvider))));

final todayVerseProvider = FutureProvider<DailyVerse?>((ref) {
  final now = ref.watch(clockProvider)();
  return ref.watch(verseSourceProvider).verseFor(now);
});
