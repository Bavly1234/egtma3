import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/services/sync_status.dart';
import 'core/utils/app_logger.dart';
import 'firebase_options.dart';

/// Background FCM handler (must be top-level). The OS shows the notification;
/// the in-app notification center reads the Firestore copy.
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initializeDateFormatting('ar');

  configureFirestoreOffline(FirebaseFirestore.instance);

  if (!kIsWeb) {
    FlutterError.onError =
        FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(kReleaseMode);
    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
  }

  await _activateAppCheck();

  runApp(const ProviderScope(child: Egtma3App()));
}

Future<void> _activateAppCheck() async {
  try {
    if (kIsWeb) {
      const siteKey = String.fromEnvironment('RECAPTCHA_SITE_KEY');
      if (siteKey.isEmpty) return; // Web App Check optional; see README.
      await FirebaseAppCheck.instance
          .activate(providerWeb: ReCaptchaV3Provider(siteKey));
      return;
    }
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
  } catch (e) {
    AppLog.w('App Check activation failed', e);
  }
}
