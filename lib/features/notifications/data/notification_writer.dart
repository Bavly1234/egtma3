import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../core/utils/app_logger.dart';
import '../../women/domain/woman.dart';

/// Writes in-app notifications from the device (no server).
/// Every notification id is deterministic, so the same event processed on
/// two phones — or twice on one — produces a single notification.
class NotificationWriter {
  NotificationWriter(this._db);
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(FsPaths.notifications);

  /// Creates the notification only if it does not exist yet. No read is
  /// needed: security rules allow `create` but never `update`, so writing an
  /// id that already exists is rejected by the server — that rejection is
  /// the de-duplication.
  Future<bool> createOnce({
    required String id,
    required String recipientId,
    required String title,
    required String message,
    required NotificationType type,
    String? relatedEntityId,
    String? relatedEntityType,
  }) async {
    try {
      _col.doc(id).set({
        'recipientId': recipientId,
        'title': title,
        'message': message,
        'type': type.wire,
        'relatedEntityId': relatedEntityId,
        'relatedEntityType': relatedEntityType,
        'createdAt': FieldValue.serverTimestamp(),
        'readAt': null,
      }).catchError((Object e) => AppLog.d('Notification $id already exists'));
      return true;
    } catch (e) {
      AppLog.w('Notification not created ($id)', e);
      return false;
    }
  }

  /// Father ids are kept in settings/app so servants can notify them
  /// without being allowed to list users.
  Future<List<String>> fatherIds() async {
    final s = await _db.collection(FsPaths.settings).doc(FsPaths.settingsAppDoc).get();
    return ((s.data()?['fatherIds'] as List?) ?? const []).cast<String>();
  }

  Future<void> suggestionCreated({
    required String suggestionId,
    required Woman woman,
    required SuggestionType type,
    required int count,
  }) async {
    final isHome = type == SuggestionType.homeVisit;
    final recipients = <String>{
      ?woman.assignedServantId,
      if (isHome || woman.assignedServantId == null) ...await fatherIds(),
    };
    for (final r in recipients) {
      await createOnce(
        id: 'suggestion_${suggestionId}_$r',
        recipientId: r,
        title: isHome ? '🏠 افتقاد منزلي مطلوب' : '📞 افتقاد تليفوني مطلوب',
        message: 'السيدة ${woman.fullName} — '
            '${isHome ? 'غائبة منذ $count اجتماعات متتالية.' : 'غابت $count اجتماعات متتالية.'}',
        type: NotificationType.followUp,
        relatedEntityId: woman.id,
        relatedEntityType: 'woman',
      );
    }
  }
}

final notificationWriterProvider =
    Provider((ref) => NotificationWriter(ref.watch(firestoreProvider)));
