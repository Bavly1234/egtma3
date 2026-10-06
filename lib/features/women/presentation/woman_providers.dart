import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../attendance/data/attendance_repository.dart';
import '../../attendance/domain/attendance_record.dart';
import '../../auth/data/auth_repository.dart';
import '../../followups/data/follow_up_repository.dart';
import '../../followups/domain/follow_up.dart';

final womanAttendanceProvider = FutureProvider.autoDispose
    .family<List<AttendanceRecord>, String>((ref, womanId) => ref
        .watch(attendanceRepositoryProvider)
        .history(womanId, ref.watch(requireUserProvider)));

final womanSuggestionsProvider = StreamProvider.autoDispose
    .family<List<FollowUpSuggestion>, String>((ref, womanId) => ref
        .watch(followUpRepositoryProvider)
        .watchForWoman(womanId, ref.watch(requireUserProvider)));

final womanFollowUpsProvider = StreamProvider.autoDispose
    .family<List<FollowUp>, String>((ref, womanId) => ref
        .watch(followUpRepositoryProvider)
        .watchHistory(womanId, ref.watch(requireUserProvider)));
