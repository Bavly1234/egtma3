import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


enum SyncState {
  online('متصل'),
  offline('غير متصل'),
  syncing('جارٍ المزامنة'),
  synced('تمت المزامنة');

  const SyncState(this.label);
  final String label;
}

/// Tracks connectivity plus locally-pending Firestore writes.
///
/// Writes are never awaited for UI flow (Firestore queues them offline and
/// persists them); the controller only counts them so the user sees
/// "جارٍ المزامنة" until the server acknowledges.
class SyncController extends Notifier<SyncState> {
  int _pending = 0;
  bool _online = true;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _syncedTimer;

  @override
  SyncState build() {
    _sub = Connectivity().onConnectivityChanged.listen(_onConnectivity);
    Connectivity().checkConnectivity().then(_onConnectivity);
    ref.onDispose(() {
      _sub?.cancel();
      _syncedTimer?.cancel();
    });
    return SyncState.online;
  }

  void _onConnectivity(List<ConnectivityResult> r) {
    _online = r.any((c) => c != ConnectivityResult.none);
    _emit();
  }

  /// Registers a write; the returned future is not meant to be awaited by UI.
  void track(Future<void> write) {
    _pending++;
    _emit();
    write.whenComplete(() {
      _pending = (_pending - 1).clamp(0, 1 << 30);
      if (_pending == 0 && _online) {
        state = SyncState.synced;
        _syncedTimer?.cancel();
        _syncedTimer = Timer(const Duration(seconds: 3), _emit);
      } else {
        _emit();
      }
    }).ignore();
  }

  void _emit() {
    if (!_online) {
      state = SyncState.offline;
    } else if (_pending > 0) {
      state = SyncState.syncing;
    } else if (state != SyncState.synced) {
      state = SyncState.online;
    } else if (!(_syncedTimer?.isActive ?? false)) {
      state = SyncState.online;
    }
  }

  int get pending => _pending;
}

final syncControllerProvider =
    NotifierProvider<SyncController, SyncState>(SyncController.new);

/// Enables offline persistence where supported.
/// Enables offline persistence on phones. On the web it stays off: the
/// browser cache is single-tab, and with the app open in a second tab reads
/// can hang forever ("loading all the time").
void configureFirestoreOffline(FirebaseFirestore db) {
  db.settings = const Settings(
    persistenceEnabled: !kIsWeb,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
}
