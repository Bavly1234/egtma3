import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Structured logger. Verbose output only in debug; errors go to Crashlytics
/// in release. Never pass personal data (names, phones, addresses) here.
abstract final class AppLog {
  static final _logger = Logger(
    level: kReleaseMode ? Level.warning : Level.debug,
    printer: PrettyPrinter(methodCount: 0, noBoxingByDefault: true),
  );

  static void d(String msg) => _logger.d(msg);
  static void i(String msg) => _logger.i(msg);
  static void w(String msg, [Object? e]) => _logger.w(msg, error: e);

  static void e(String msg, Object error, [StackTrace? st]) {
    _logger.e(msg, error: error, stackTrace: st);
    if (kReleaseMode && !kIsWeb) {
      FirebaseCrashlytics.instance.recordError(error, st, reason: msg);
    }
  }
}
