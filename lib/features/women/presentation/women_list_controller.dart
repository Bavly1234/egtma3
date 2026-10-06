import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../data/women_repository.dart';
import '../domain/woman.dart';
import '../domain/women_filter.dart';

/// The currently applied women filters (shared by list and export).
class WomenFilterController extends Notifier<WomenFilter> {
  @override
  WomenFilter build() => WomenFilter.empty;

  void set(WomenFilter f) => state = f;
  void setQuery(String q) => state = state.copyWith(query: q);
  void clear() => state = WomenFilter.empty;
}

final womenFilterProvider =
    NotifierProvider<WomenFilterController, WomenFilter>(
        WomenFilterController.new);

class WomenListState {
  const WomenListState({
    this.items = const [],
    this.cursor,
    this.hasMore = true,
    this.loadingMore = false,
  });
  final List<Woman> items;
  final DocumentSnapshot? cursor;
  final bool hasMore;
  final bool loadingMore;

  WomenListState copyWith({
    List<Woman>? items,
    DocumentSnapshot? cursor,
    bool? hasMore,
    bool? loadingMore,
  }) =>
      WomenListState(
        items: items ?? this.items,
        cursor: cursor ?? this.cursor,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

/// Paginated women list; reloads automatically when filters change.
class WomenListController extends AsyncNotifier<WomenListState> {
  @override
  Future<WomenListState> build() async {
    final filter = ref.watch(womenFilterProvider);
    final user = ref.watch(requireUserProvider);
    final page =
        await ref.read(womenRepositoryProvider).page(user, filter);
    return WomenListState(
        items: page.items, cursor: page.cursor, hasMore: page.hasMore);
  }

  Future<void> loadMore() async {
    final s = state.value;
    if (s == null || !s.hasMore || s.loadingMore) return;
    state = AsyncData(s.copyWith(loadingMore: true));
    try {
      final page = await ref.read(womenRepositoryProvider).page(
          ref.read(requireUserProvider), ref.read(womenFilterProvider),
          after: s.cursor);
      state = AsyncData(WomenListState(
        items: [...s.items, ...page.items],
        cursor: page.cursor,
        hasMore: page.hasMore,
      ));
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final womenListProvider =
    AsyncNotifierProvider<WomenListController, WomenListState>(
        WomenListController.new);
