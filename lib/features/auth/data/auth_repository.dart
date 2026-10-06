import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../core/constants/enums.dart';
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

  /// Self sign-up with the join code (same approach as eftekad_app).
  /// The code is checked by Firestore security rules — it is not stored in
  /// the app. If the rules reject the profile (wrong code), the new Auth
  /// account is deleted again.
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    required String code,
  }) async {
    final UserCredential cred;
    try {
      cred = await _auth.createUserWithEmailAndPassword(
          email: email.trim(), password: password);
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
    final uid = cred.user!.uid;
    try {
      await _db.collection(FsPaths.users).doc(uid).set({
        'name': name.trim(),
        'email': email.trim().toLowerCase(),
        'phone': '',
        'role': role.wire,
        'active': true,
        'code': code.trim(),
        'notificationPrefs': const NotificationPrefs().toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      await cred.user!.delete().catchError((Object _) {});
      throw const AppFailure('كود الانضمام غلط');
    }
    if (role == UserRole.father) {
      // Lets servants' phones notify the father(s) about home visits.
      await _db
          .collection(FsPaths.settings)
          .doc(FsPaths.settingsAppDoc)
          .set({'fatherIds': FieldValue.arrayUnion([uid])}, SetOptions(merge: true))
          .catchError((Object _) {});
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

  Future<void> updateTextScale(String uid, double scale) async {
    try {
      await _db.collection(FsPaths.users).doc(uid).update({
        'textScale': scale,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

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
