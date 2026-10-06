import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Overridable in tests (e.g. with FakeFirebaseFirestore).
final firestoreProvider =
    Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

final firebaseAuthProvider =
    Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

/// Injectable clock so date logic is testable — never call DateTime.now()
/// directly in repositories.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
