import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../streets/data/street_repository.dart';
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
  String? _servantId;
  String? _streetId;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(requireUserProvider);
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
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(
                label: const Text('المطلوب الآن'),
                selected: _activeOnly,
                onSelected: (_) => setState(() => _activeOnly = true),
              ),
              ChoiceChip(
                label: const Text('السجل الكامل'),
                selected: !_activeOnly,
                onSelected: (_) => setState(() => _activeOnly = false),
              ),
              if (user.isFather) _servantFilter(),
              _streetFilter(),
            ]),
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
    return DropdownButton<String?>(
      value: _servantId,
      hint: const Text('كل الخادمات'),
      items: [
        const DropdownMenuItem(value: null, child: Text('كل الخادمات')),
        for (final s in servants) DropdownMenuItem(value: s.id, child: Text(s.name)),
      ],
      onChanged: (v) => setState(() => _servantId = v),
    );
  }

  Widget _streetFilter() {
    final streets = ref.watch(streetsProvider).value ?? const [];
    return DropdownButton<String?>(
      value: _streetId,
      hint: const Text('كل الشوارع'),
      items: [
        const DropdownMenuItem(value: null, child: Text('كل الشوارع')),
        for (final s in streets) DropdownMenuItem(value: s.id, child: Text(s.name)),
      ],
      onChanged: (v) => setState(() => _streetId = v),
    );
  }

  Widget _list(SuggestionType type) {
    final q = SuggestionQuery(
      type: type,
      activeOnly: _activeOnly,
      servantId: _servantId,
      streetId: _streetId,
    );
    return AsyncBody(
      value: ref.watch(suggestionsProvider(q)),
      onRetry: () => ref.invalidate(suggestionsProvider(q)),
      builder: (items) => items.isEmpty
          ? EmptyState(
              icon: Icons.celebration,
              title: _activeOnly ? 'لا يوجد افتقاد مطلوب الآن' : 'لا يوجد سجل',
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
