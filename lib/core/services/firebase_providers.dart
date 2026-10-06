import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/firestore_paths.dart';

/// Overridable in tests (e.g. with FakeFirebaseFirestore).
final firestoreProvider =
    Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

final firebaseAuthProvider =
    Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

final functionsProvider = Provider<FirebaseFunctions>(
    (ref) => FirebaseFunctions.instanceFor(region: kFunctionsRegion));

/// Injectable clock so date logic is testable — never call DateTime.now()
/// directly in repositories.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
