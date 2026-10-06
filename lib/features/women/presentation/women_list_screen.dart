import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/permissions.dart';
import 'filters_sheet.dart';
import 'woman_tile.dart';
import 'women_list_controller.dart';

class WomenListScreen extends ConsumerStatefulWidget {
  const WomenListScreen({super.key});

  @override
  ConsumerState<WomenListScreen> createState() => _WomenListScreenState();
}

class _WomenListScreenState extends ConsumerState<WomenListScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(womenFilterProvider).query;
    _scroll.addListener(() {
      if (_scroll.position.pixels >
          _scroll.position.maxScrollExtent - 400) {
        ref.read(womenListProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400),
        () => ref.read(womenFilterProvider.notifier).setQuery(q));
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(requireUserProvider);
    final filter = ref.watch(womenFilterProvider);
    final list = ref.watch(womenListProvider);
    final canManage = Permissions.canManageWomen(user);

    return Scaffold(
      appBar: AppBar(
        title: const Text('السيدات'),
        actions: [
          if (Permissions.canImportExport(user))
            IconButton(
              tooltip: 'تصدير Excel',
              icon: const Icon(Icons.file_download),
              onPressed: () => context.push(Routes.export),
            ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => context.push(Routes.womanNew),
              icon: const Icon(Icons.person_add),
              label: const Text('إضافة سيدة', style: TextStyle(fontSize: 18)),
            )
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: _onSearch,
                decoration: InputDecoration(
                  hintText: 'ابحثي بالاسم أو التليفون أو الشارع',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'مسح البحث',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _search.clear();
                            _onSearch('');
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Badge(
              isLabelVisible: filter.activeCount > 0,
              label: Text('${filter.activeCount}'),
              child: OutlinedButton.icon(
                onPressed: () => showWomenFilters(context),
                icon: const Icon(Icons.filter_list),
                label: const Text('فلاتر'),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilterChip(
              avatar: const Icon(Icons.badge, size: 20),
              label: const Text('المعيّنات لي فقط'),
              selected: filter.servantId == user.id,
              onSelected: (on) => ref.read(womenFilterProvider.notifier).set(
                  filter.copyWith(servantId: () => on ? user.id : null)),
            ),
          ),
        ),
        if (!filter.isEmpty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () {
                _search.clear();
                ref.read(womenFilterProvider.notifier).clear();
              },
              icon: const Icon(Icons.filter_alt_off),
              label: const Text('مسح كل الفلاتر'),
            ),
          ),
        Expanded(
          child: AsyncBody(
            value: list,
            onRetry: () => ref.invalidate(womenListProvider),
            builder: (s) {
              if (s.items.isEmpty && !s.hasMore) {
                return EmptyState(
                  icon: Icons.group_off,
                  title: filter.isEmpty ? 'لا توجد سيدات بعد' : 'لا توجد نتائج',
                  message: filter.isEmpty
                      ? (canManage
                          ? 'أضيفي سيدة جديدة أو استوردي ملف Excel.'
                          : 'لم يتم تعيين سيدات لك بعد.')
                      : 'جربي تغيير البحث أو الفلاتر.',
                );
              }
              return RefreshIndicator(
                onRefresh: () => ref.refresh(womenListProvider.future),
                child: ListView.separated(
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: s.items.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    if (i == s.items.length) {
                      if (s.hasMore) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: s.loadingMore
                                ? const CircularProgressIndicator()
                                : OutlinedButton(
                                    onPressed: () => ref
                                        .read(womenListProvider.notifier)
                                        .loadMore(),
                                    child: const Text('عرض المزيد'),
                                  ),
                          ),
                        );
                      }
                      return const SizedBox(height: 8);
                    }
                    final w = s.items[i];
                    return WomanTile(
                      woman: w,
                      highlightServantId: user.id,
                      onTap: () => context.push(Routes.woman(w.id)),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
