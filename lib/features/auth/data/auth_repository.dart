import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/firebase_providers.dart';
import '../domain/app_user.dart';

class AuthRepository {
  AuthRepository(this._auth, this._db);
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  Stream<User?> authChanges() => _auth.authStateChanges();

  Stream<AppUser?> profile(String uid) => _db
      .collection(FsPaths.users)
      .doc(uid)
      .snapshots()
      .map((s) => s.exists ? AppUser.fromMap(s.id, s.data()!) : null);

  Future<void> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
          email: email.trim(), password: password);
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.setLanguageCode('ar');
      await _auth.sendPasswordResetEmail(email: email.trim());
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> updatePrefs(String uid, NotificationPrefs prefs) async {
    try {
      await _db.collection(FsPaths.users).doc(uid).update({
        'notificationPrefs': prefs.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) =>
    AuthRepository(ref.watch(firebaseAuthProvider), ref.watch(firestoreProvider)));

final authStateProvider = StreamProvider<User?>(
    (ref) => ref.watch(authRepositoryProvider).authChanges());

/// The signed-in user's profile (role, active flag). null when signed out
/// or when no profile document exists yet.
final currentUserProvider = StreamProvider<AppUser?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);
  return ref.watch(authRepositoryProvider).profile(user.uid);
});

/// Convenience for screens that are only reachable when signed in.
final requireUserProvider = Provider<AppUser>((ref) {
  final u = ref.watch(currentUserProvider).value;
  if (u == null) throw const AppFailure('يجب تسجيل الدخول أولاً.');
  return u;
});
