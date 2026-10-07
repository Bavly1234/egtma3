import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/dates.dart';
import '../../auth/domain/app_user.dart';
import '../../followups/data/absence_processor.dart';
import '../../women/domain/woman.dart';
import 'attendance_repository.dart';

/// Wednesday 9pm rule without a server: whichever phone opens the app first
/// after the cutoff marks every still-unmarked woman absent (once per
/// meeting — `autoAbsentDone` prevents double counting) and then runs the
/// افتقاد rules for them.
class AutoAbsenceService {
  AutoAbsenceService(this._db, this._attendance, this._processor);
  final FirebaseFirestore _db;
  final AttendanceRepository _attendance;
  final AbsenceProcessor _processor;
  final _running = <String>{};

  /// The most recent Wednesday whose 9pm cutoff has already passed.
  static DateTime lastClosedMeeting(DateTime now) {
    final m = Dates.currentOrLastMeeting(now);
    return Dates.cutoffPassed(m, now) ? m : m.subtract(const Duration(days: 7));
  }

  Future<void> runIfDue(AppUser user, {DateTime? meeting}) async {
    final now = DateTime.now();
    final date = meeting ?? lastClosedMeeting(now);
    if (!Dates.cutoffPassed(date, now)) return;
    final meetingId = Dates.dayId(date);
    if (!_running.add(meetingId)) return;
    try {
      final ids = await _attendance.autoFillAbsent(meetingId, user);
      for (var i = 0; i < ids.length; i += 30) {
        final chunk = ids.sublist(i, (i + 30).clamp(0, ids.length));
        final snap = await _db
            .collection(FsPaths.women)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final d in snap.docs) {
          await _processor.process(Woman.fromMap(d.id, d.data()), user);
        }
      }
      if (ids.isNotEmpty) {
        AppLog.i('Auto-marked ${ids.length} absent for $meetingId');
      }
    } catch (e, st) {
      AppLog.e('Auto absence failed', e, st);
      _running.remove(meetingId); // allow a retry later
    }
  }
}

final autoAbsenceServiceProvider = Provider((ref) => AutoAbsenceService(
      ref.watch(firestoreProvider),
      ref.watch(attendanceRepositoryProvider),
      ref.watch(absenceProcessorProvider),
    ));
