import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/firebase_providers.dart';
import '../../audit/data/audit_repository.dart';
import '../../audit/domain/audit_entry.dart';
import '../../auth/domain/app_user.dart';

/// User management. Accounts are created by the users themselves with the
/// join code (see AuthRepository.signUp); the father can then disable /
/// enable accounts, change roles and send password-reset emails.
/// Disabling sets `active: false`: security rules then deny the account
/// every read and write, and the app shows "الحساب غير مفعّل".
class UsersRepository {
  UsersRepository(this._db, this._auth, this._audit);
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final AuditRepository _audit;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection(FsPaths.users);
  DocumentReference<Map<String, dynamic>> get _settings =>
      _db.collection(FsPaths.settings).doc(FsPaths.settingsAppDoc);

  Stream<List<AppUser>> watchAll() => _users.orderBy('name').snapshots().map(
      (s) => s.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList());

  Future<void> sendAccessReset(String email) async {
    try {
      await _auth.setLanguageCode('ar');
      await _auth.sendPasswordResetEmail(email: email.trim());
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  Future<void> setActive(AppUser user, bool active, AppUser actor) async {
    if (user.id == actor.id) {
      throw const AppFailure('لا يمكنك إيقاف حسابك.');
    }
    try {
      final batch = _db.batch();
      batch.update(_users.doc(user.id),
          {'active': active, 'updatedAt': FieldValue.serverTimestamp()});
      if (user.isFather) {
        batch.set(
            _settings,
            {
              'fatherIds': active
                  ? FieldValue.arrayUnion([user.id])
                  : FieldValue.arrayRemove([user.id])
            },
            SetOptions(merge: true));
      }
      _audit.addToBatch(batch,
          actor: actor,
          action: AuditAction.userChanged,
          entityType: 'user',
          entityId: user.id,
          summary: '${active ? 'تفعيل' : 'إيقاف'}: ${user.name}');
      await batch.commit();
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  Future<void> setRole(AppUser user, UserRole role, AppUser actor) async {
    if (user.id == actor.id) {
      throw const AppFailure('لا يمكنك تغيير صلاحيتك.');
    }
    try {
      final batch = _db.batch();
      batch.update(_users.doc(user.id),
          {'role': role.wire, 'updatedAt': FieldValue.serverTimestamp()});
      batch.set(
          _settings,
          {
            'fatherIds': role == UserRole.father && user.active
                ? FieldValue.arrayUnion([user.id])
                : FieldValue.arrayRemove([user.id])
          },
          SetOptions(merge: true));
      _audit.addToBatch(batch,
          actor: actor,
          action: AuditAction.userChanged,
          entityType: 'user',
          entityId: user.id,
          summary: '${user.name}: ${role.label}');
      await batch.commit();
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }
}

final usersRepositoryProvider = Provider((ref) => UsersRepository(
      ref.watch(firestoreProvider),
      ref.watch(firebaseAuthProvider),
      ref.watch(auditRepositoryProvider),
    ));

/// All users (father only — rules deny servants listing users).
final allUsersProvider = StreamProvider<List<AppUser>>(
    (ref) => ref.watch(usersRepositoryProvider).watchAll());

final activeServantsProvider = Provider<AsyncValue<List<AppUser>>>((ref) =>
    ref.watch(allUsersProvider).whenData(
        (l) => l.where((u) => u.isServant && u.active).toList()));
