import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/app_logger.dart';

/// A user-safe failure with an Arabic message. Raw exceptions never reach the UI.
class AppFailure implements Exception {
  const AppFailure(this.message);
  final String message;

  @override
  String toString() => message;

  static AppFailure from(Object error, [StackTrace? st]) {
    if (error is AppFailure) return error;
    AppLog.e('Operation failed', error, st);
    if (error is FirebaseAuthException) return AppFailure(_auth(error.code));
    if (error is FirebaseException) return AppFailure(_code(error.code));
    if (error is FormatException) {
      return const AppFailure('البيانات غير صحيحة.');
    }
    return const AppFailure('حدث خطأ غير متوقع. حاولي مرة أخرى.');
  }

  static String _auth(String code) => switch (code) {
        'invalid-email' => 'البريد الإلكتروني غير صحيح.',
        'user-disabled' => 'هذا الحساب موقوف. تواصلي مع الأب الكاهن.',
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' =>
          'البريد الإلكتروني أو كلمة المرور غير صحيحة.',
        'too-many-requests' =>
          'محاولات كثيرة. انتظري قليلاً ثم حاولي مرة أخرى.',
        'network-request-failed' => 'لا يوجد اتصال بالإنترنت.',
        'email-already-in-use' => 'هذا البريد مستخدم بالفعل.',
        'weak-password' => 'كلمة المرور ضعيفة (6 أحرف على الأقل).',
        _ => 'تعذر تسجيل الدخول. حاولي مرة أخرى.',
      };

  static String _code(String code) => switch (code) {
        'permission-denied' => 'ليس لديك صلاحية لهذا الإجراء.',
        'unavailable' ||
        'deadline-exceeded' =>
          'تعذر الاتصال بالخادم. تأكدي من الإنترنت وحاولي مرة أخرى.',
        'not-found' => 'البيانات المطلوبة غير موجودة.',
        'already-exists' => 'هذا السجل موجود بالفعل.',
        'unauthenticated' => 'يجب تسجيل الدخول أولاً.',
        'invalid-argument' ||
        'failed-precondition' =>
          'البيانات المدخلة غير صحيحة.',
        _ => 'حدث خطأ. حاولي مرة أخرى.',
      };

  /// Guards a Firestore read so a stalled network can never spin a loading
  /// indicator forever: after [timeout] the caller gets an [AppFailure]
  /// (shown with a retry button) instead of hanging.
  static Future<T> guard<T>(
    Future<T> future, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    try {
      return await future.timeout(timeout);
    } on TimeoutException {
      throw const AppFailure(
          'انتهت المهلة — تحققي من الإنترنت وحاولي مجدداً.');
    }
  }
}

/// Maps Firestore Timestamp/DateTime safely.
DateTime? tsToDate(Object? v) => switch (v) {
      Timestamp t => t.toDate(),
      DateTime d => d,
      _ => null,
    };
