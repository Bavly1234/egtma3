import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/firebase_providers.dart';
import '../../auth/domain/app_user.dart';

/// User management. Account creation/disable/role changes go through Cloud
/// Functions because they need the Admin SDK and must be authorised
/// server-side.
class UsersRepository {
  UsersRepository(this._db, this._fns, this._auth);
  final FirebaseFirestore _db;
  final FirebaseFunctions _fns;
  final FirebaseAuth _auth;

  Stream<List<AppUser>> watchAll() => _db
      .collection(FsPaths.users)
      .orderBy('name')
      .snapshots()
      .map((s) => s.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList());

  Future<T?> _call<T>(String name, Map<String, dynamic> data) async {
    try {
      final r = await _fns.httpsCallable(name).call<T>(data);
      return r.data;
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  /// Creates the account with a random password, then emails the servant a
  /// link to choose her own password (no shared passwords).
  Future<void> createServant({
    required String name,
    required String email,
    required String phone,
  }) async {
    await _call<Object?>(FnNames.createServant,
        {'name': name.trim(), 'email': email.trim(), 'phone': phone.trim()});
    await sendAccessReset(email);
  }

  Future<void> sendAccessReset(String email) async {
    try {
      await _auth.setLanguageCode('ar');
      await _auth.sendPasswordResetEmail(email: email.trim());
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  Future<void> setActive(String uid, bool active) =>
      _call<Object?>(FnNames.setUserActive, {'uid': uid, 'active': active});

  Future<void> setRole(String uid, UserRole role) =>
      _call<Object?>(FnNames.setUserRole, {'uid': uid, 'role': role.wire});

  Future<void> bootstrapFather(String code, String name) =>
      _call<Object?>(FnNames.bootstrapFather, {'code': code, 'name': name});

  Future<String> seedDemo() async =>
      (await _call<Object?>(FnNames.seedDemoData, {}))?.toString() ?? '';

  Future<String> removeDemo() async =>
      (await _call<Object?>(FnNames.removeDemoData, {}))?.toString() ?? '';
}

final usersRepositoryProvider = Provider((ref) => UsersRepository(
      ref.watch(firestoreProvider),
      ref.watch(functionsProvider),
      ref.watch(firebaseAuthProvider),
    ));

/// All users (father only — rules deny servants listing users).
final allUsersProvider = StreamProvider<List<AppUser>>(
    (ref) => ref.watch(usersRepositoryProvider).watchAll());

final activeServantsProvider = Provider<AsyncValue<List<AppUser>>>((ref) =>
    ref.watch(allUsersProvider).whenData(
        (l) => l.where((u) => u.isServant && u.active).toList()));
