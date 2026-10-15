import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../users/data/users_repository.dart';
import '../data/follow_up_repository.dart';
import 'suggestion_card.dart';

/// Follow-up dashboard: phone and home-visit tabs, active or full history.
class FollowUpsScreen extends ConsumerStatefulWidget {
  const FollowUpsScreen({super.key});

  @override
  ConsumerState<FollowUpsScreen> createState() => _FollowUpsScreenState();
}

class _FollowUpsScreenState extends ConsumerState<FollowUpsScreen> {
  bool _activeOnly = true;

  /// Servants start on "the follow-ups of my streets"; the father on all.
  bool? _mineOnly;
  String? _servantId;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(requireUserProvider);
    _mineOnly ??= !me.isFather;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الافتقاد'),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            indicatorWeight: 4,
            labelStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            tabs: [
              Tab(icon: Icon(Icons.phone_in_talk), text: 'افتقاد تليفوني'),
              Tab(icon: Icon(Icons.home), text: 'افتقاد منزلي'),
            ],
          ),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: me.isFather
                ? _servantFilter()
                : SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                          value: true,
                          icon: Icon(Icons.signpost),
                          label: Text('المطلوب منكِ')),
                      ButtonSegment(
                          value: false,
                          icon: Icon(Icons.groups),
                          label: Text('الكل')),
                    ],
                    selected: {_mineOnly!},
                    onSelectionChanged: (v) =>
                        setState(() => _mineOnly = v.first),
                  ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() => _activeOnly = !_activeOnly),
              icon: Icon(_activeOnly ? Icons.history : Icons.pending_actions),
              label: Text(_activeOnly
                  ? 'عرض الافتقاد اللي اتعمل قبل كده'
                  : 'رجوع للافتقاد المطلوب'),
            ),
          ),
          Expanded(
            child: TabBarView(children: [
              _list(SuggestionType.phone),
              _list(SuggestionType.homeVisit),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _servantFilter() {
    final servants = ref.watch(activeServantsProvider).value ?? const [];
    return DropdownButtonFormField<String?>(
      initialValue: _servantId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'الخادمة'),
      items: [
        const DropdownMenuItem(value: null, child: Text('كل الخادمات')),
        for (final s in servants) DropdownMenuItem(value: s.id, child: Text(s.name)),
      ],
      onChanged: (v) => setState(() => _servantId = v),
    );
  }

  Widget _list(SuggestionType type) {
    final me = ref.read(requireUserProvider);
    final q = SuggestionQuery(
      type: type,
      activeOnly: _activeOnly,
      servantId: me.isFather ? _servantId : (_mineOnly! ? me.id : null),
    );
    return AsyncBody(
      value: ref.watch(suggestionsProvider(q)),
      onRetry: () => ref.invalidate(suggestionsProvider(q)),
      builder: (items) => items.isEmpty
          ? EmptyState(
              icon: Icons.celebration,
              title: _activeOnly ? 'مفيش افتقاد مطلوب دلوقتي 👍' : 'لا يوجد سجل',
              message: _activeOnly
                  ? 'سيظهر هنا تلقائياً عند غياب سيدة مرتين متتاليتين أو أكثر.'
                  : null,
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => SuggestionCard(suggestion: items[i]),
            ),
    );
  }
}
