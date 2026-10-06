import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/firebase_providers.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/app_notification.dart';

/// In-app notification center. Notifications are created server-side by
/// Cloud Functions (which also push them via FCM); the client only reads them
/// and sets `readAt`.
class NotificationRepository {
  NotificationRepository(this._db);
  final FirebaseFirestore _db;

  Query<Map<String, dynamic>> _mine(String uid) => _db
      .collection(FsPaths.notifications)
      .where('recipientId', isEqualTo: uid);

  Stream<List<AppNotification>> watch(String uid, {int limit = 100}) =>
      _mine(uid)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) => s.docs
              .map((d) => AppNotification.fromMap(d.id, d.data()))
              .toList());

  Stream<int> watchUnreadCount(String uid) => _mine(uid)
      .where('readAt', isNull: true)
      .limit(99)
      .snapshots()
      .map((s) => s.size);

  Future<void> markRead(String id) async {
    try {
      await _db
          .collection(FsPaths.notifications)
          .doc(id)
          .update({'readAt': FieldValue.serverTimestamp()});
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  Future<void> markAllRead(String uid) async {
    try {
      final snap = await _mine(uid).where('readAt', isNull: true).get();
      for (var i = 0; i < snap.docs.length; i += 400) {
        final batch = _db.batch();
        for (final d in snap.docs.skip(i).take(400)) {
          batch.update(d.reference, {'readAt': FieldValue.serverTimestamp()});
        }
        await batch.commit();
      }
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }
}

final notificationRepositoryProvider =
    Provider((ref) => NotificationRepository(ref.watch(firestoreProvider)));

final myNotificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final u = ref.watch(currentUserProvider).value;
  if (u == null) return Stream.value(const []);
  return ref.watch(notificationRepositoryProvider).watch(u.id);
});

final unreadCountProvider = StreamProvider<int>((ref) {
  final u = ref.watch(currentUserProvider).value;
  if (u == null) return Stream.value(0);
  return ref.watch(notificationRepositoryProvider).watchUnreadCount(u.id);
});
