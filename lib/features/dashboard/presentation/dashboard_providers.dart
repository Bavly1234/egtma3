import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../core/utils/dates.dart';
import '../../auth/data/auth_repository.dart';
import '../../conferences/data/conference_repository.dart';
import '../../conferences/domain/conference.dart';
import '../../followups/data/follow_up_repository.dart';
import '../../followups/domain/follow_up.dart';
import '../../statistics/data/stats_repository.dart';
import '../../statistics/domain/stats_models.dart';
import '../../users/data/users_repository.dart';

/// Overview numbers for the dashboard (aggregation queries, refreshed on
/// pull-to-refresh).
final overviewProvider = FutureProvider.autoDispose<OverviewStats>((ref) async {
  final user = ref.watch(requireUserProvider);
  final now = ref.watch(clockProvider)();
  var servants = 0;
  if (user.isFather) {
    final all = await ref.watch(allUsersProvider.future);
    servants = all.where((u) => u.isServant && u.active).length;
  }
  return ref.watch(statsRepositoryProvider).overview(
        user,
        now,
        range: DateRange.thisMonth(now),
        servants: servants,
      );
});

/// Live active suggestions split by type.
final activePhoneSuggestionsProvider =
    Provider<AsyncValue<List<FollowUpSuggestion>>>((ref) => ref.watch(
        suggestionsProvider(
            const SuggestionQuery(type: SuggestionType.phone))));

final activeHomeSuggestionsProvider =
    Provider<AsyncValue<List<FollowUpSuggestion>>>((ref) => ref.watch(
        suggestionsProvider(
            const SuggestionQuery(type: SuggestionType.homeVisit))));

/// The next (or ongoing) conference, if any.
final upcomingConferenceProvider = Provider<Conference?>((ref) {
  final list = ref.watch(conferencesProvider).value ?? const [];
  final today = Dates.dateOnly(ref.watch(clockProvider)());
  final upcoming = list
      .where((c) => c.lastDate != null && !c.lastDate!.isBefore(today))
      .toList()
    ..sort((a, b) => a.firstDate!.compareTo(b.firstDate!));
  return upcoming.isEmpty ? null : upcoming.first;
});
