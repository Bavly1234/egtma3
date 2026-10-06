import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../firebase_options.dart';
import '../../audit/data/audit_repository.dart';
import '../../audit/domain/audit_entry.dart';
import '../../auth/domain/app_user.dart';

const _defaultPrefs = {
  'meetingReminder': true,
  'attendanceReminder': true,
  'followUp': true,
  'birthday': true,
  'conference': true,
  'dailyVerse': true,
};

/// User management without a server (free Spark plan).
///
/// * New servant accounts are created through a *secondary* Firebase app, so
///   the father stays signed in. The account gets a random password and the
///   servant receives a reset email to choose her own (no shared passwords).
/// * Disabling sets `active: false`; security rules then deny the account
///   every read and write, and the app shows "الحساب غير مفعّل".
/// * Roles are enforced by firestore.rules (only the father can change them).
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

  static String _randomPassword() {
    final r = Random.secure();
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#%';
    return List.generate(24, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<FirebaseAuth> _secondaryAuth() async {
    const name = 'egtma3-user-admin';
    final app = Firebase.apps.where((a) => a.name == name).firstOrNull ??
        await Firebase.initializeApp(
            name: name, options: DefaultFirebaseOptions.currentPlatform);
    return FirebaseAuth.instanceFor(app: app);
  }

  Future<void> createServant({
    required String name,
    required String email,
    required String phone,
    required AppUser actor,
  }) async {
    try {
      final secondary = await _secondaryAuth();
      final cred = await secondary.createUserWithEmailAndPassword(
          email: email.trim().toLowerCase(), password: _randomPassword());
      final uid = cred.user!.uid;
      await secondary.signOut();
      final batch = _db.batch();
      batch.set(_users.doc(uid), {
        'name': name.trim(),
        'email': email.trim().toLowerCase(),
        'phone': phone.trim(),
        'role': UserRole.servant.wire,
        'active': true,
        'notificationPrefs': _defaultPrefs,
        'createdBy': actor.id,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _audit.addToBatch(batch,
          actor: actor,
          action: AuditAction.userChanged,
          entityType: 'user',
          entityId: uid,
          summary: 'إضافة خادمة: ${name.trim()}');
      await batch.commit();
      await sendAccessReset(email);
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

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

  /// One-time creation of the first father account. The [code] must match
  /// the setup code embedded in firestore.rules, and the rules allow this
  /// only while `settings/bootstrap` does not exist — so it works exactly once.
  Future<void> bootstrapFather({
    required String uid,
    required String email,
    required String name,
    required String code,
  }) async {
    try {
      final batch = _db.batch();
      batch.set(
          _db.collection(FsPaths.settings).doc(FsPaths.settingsBootstrapDoc), {
        'fatherId': uid,
        'code': code,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(_users.doc(uid), {
        'name': name.trim(),
        'email': email,
        'phone': '',
        'role': UserRole.father.wire,
        'active': true,
        'notificationPrefs': _defaultPrefs,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(_settings, {'fatherIds': [uid]}, SetOptions(merge: true));
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const AppFailure(
            'رمز الإعداد غير صحيح، أو تم إعداد حساب الأب الكاهن من قبل.');
      }
      throw AppFailure.from(e);
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
