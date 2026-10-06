import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/firestore_paths.dart';
import '../utils/app_logger.dart';
import 'firebase_providers.dart';

/// Registers this device's FCM token on the user's profile so Cloud Functions
/// can push to it, and surfaces foreground messages to the UI.
class MessagingService {
  MessagingService(this._db);
  final FirebaseFirestore _db;
  final _foreground = StreamController<RemoteMessage>.broadcast();
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _msgSub;

  Stream<RemoteMessage> get foregroundMessages => _foreground.stream;

  /// Stream of notification taps that opened the app (data payload).
  Stream<RemoteMessage> get openedMessages =>
      FirebaseMessaging.onMessageOpenedApp;

  Future<void> registerFor(String uid) async {
    try {
      final fm = FirebaseMessaging.instance;
      final settings = await fm.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        AppLog.i('Push permission denied');
        return;
      }
      // Web push requires a VAPID key; see README. Skip on web if missing.
      const vapid = String.fromEnvironment('FCM_VAPID_KEY');
      if (kIsWeb && vapid.isEmpty) return;
      final token = await fm.getToken(vapidKey: kIsWeb ? vapid : null);
      if (token != null) await _saveToken(uid, token);
      await _tokenSub?.cancel();
      _tokenSub = fm.onTokenRefresh.listen((t) => _saveToken(uid, t));
      await _msgSub?.cancel();
      _msgSub = FirebaseMessaging.onMessage.listen(_foreground.add);
    } catch (e, st) {
      AppLog.e('FCM registration failed', e, st);
    }
  }

  Future<void> unregister(String uid) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _db.collection(FsPaths.users).doc(uid).update({
          'fcmTokens': FieldValue.arrayRemove([token]),
        });
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      AppLog.w('FCM unregister failed', e);
    }
  }

  Future<void> _saveToken(String uid, String token) =>
      _db.collection(FsPaths.users).doc(uid).update({
        'fcmTokens': FieldValue.arrayUnion([token]),
      });
}

final messagingServiceProvider =
    Provider((ref) => MessagingService(ref.watch(firestoreProvider)));
