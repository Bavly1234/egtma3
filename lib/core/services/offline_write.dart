import 'dart:async';

/// Awaits a Firestore write, but treats "no server answer within [wait]" as
/// queued-offline success: the write is already in the local cache and
/// Firestore will sync it automatically. Real errors (e.g. permission denied)
/// that arrive in time are still thrown.
///
/// Returns true when the server confirmed, false when it is queued offline.
Future<bool> commitOrQueue(Future<void> write,
    {Duration wait = const Duration(seconds: 4)}) async {
  try {
    await write.timeout(wait);
    return true;
  } on TimeoutException {
    write.ignore();
    return false;
  }
}
