import '../../../core/constants/enums.dart';
import '../../../core/utils/arabic_text.dart';
import 'woman.dart';

enum FollowUpFilter {
  any('الكل'),
  none('بدون افتقاد'),
  phone('افتقاد تليفوني'),
  homeVisit('افتقاد منزلي');

  const FollowUpFilter(this.label);
  final String label;

  /// Value stored in `women.activeSuggestionType`.
  String? get wire => switch (this) {
        any => null,
        none => 'none',
        phone => SuggestionType.phone.wire,
        homeVisit => SuggestionType.homeVisit.wire,
      };
}

enum LastAttendanceFilter {
  any('الكل'),
  present('حضرت آخر اجتماع'),
  absent('غابت آخر اجتماع');

  const LastAttendanceFilter(this.label);
  final String label;
}

/// All women filters. Equality filters run in Firestore; the rest are applied
/// in memory on the loaded page (see [matchesClientSide]).
class WomenFilter {
  const WomenFilter({
    this.query = '',
    this.streetId,
    this.active,
    this.birthMonth,
    this.followUp = FollowUpFilter.any,
    this.lastAttendance = LastAttendanceFilter.any,
    this.minConsecutiveAbsences = 0,
    this.maxAttendanceRate,
    this.streetIds,
  });

  final String query;
  final String? streetId;
  final bool? active;
  final int? birthMonth;
  final FollowUpFilter followUp;
  final LastAttendanceFilter lastAttendance;
  final int minConsecutiveAbsences;

  /// 0..1 — e.g. 0.5 shows women attending at most 50% of meetings.
  final double? maxAttendanceRate;

  /// "My streets": only women living in these streets (a servant is
  /// assigned by street). Applied in memory.
  final Set<String>? streetIds;

  static const empty = WomenFilter();

  bool get hasServerFilters =>
      streetId != null ||
      active != null ||
      birthMonth != null ||
      followUp != FollowUpFilter.any ||
      query.trim().isNotEmpty;

  bool get isEmpty =>
      !hasServerFilters &&
      lastAttendance == LastAttendanceFilter.any &&
      minConsecutiveAbsences == 0 &&
      maxAttendanceRate == null &&
      streetIds == null;

  int get activeCount => [
        query.trim().isNotEmpty,
        streetId != null,
        active != null,
        birthMonth != null,
        followUp != FollowUpFilter.any,
        lastAttendance != LastAttendanceFilter.any,
        minConsecutiveAbsences > 0,
        maxAttendanceRate != null,
        streetIds != null,
      ].where((b) => b).length;

  List<String> get queryTokens => ArabicText.normalize(query)
      .split(' ')
      .where((t) => t.length >= 2)
      .map((t) => t.length > 15 ? t.substring(0, 15) : t)
      .toList();

  /// Filters that cannot be expressed in a single Firestore query.
  bool matchesClientSide(Woman w, {Map<String, String>? lastStatusById}) {
    final tokens = queryTokens;
    if (tokens.isNotEmpty) {
      final hay = ArabicText.normalize(
          '${w.fullName} ${w.streetName} ${w.address} ${w.phone}');
      if (!tokens.every(hay.contains)) return false;
    }
    if (streetIds != null && !streetIds!.contains(w.streetId)) return false;
    if (w.consecutiveAbsences < minConsecutiveAbsences) return false;
    if (maxAttendanceRate != null) {
      final r = w.attendanceRate;
      if (r == null || r > maxAttendanceRate!) return false;
    }
    switch (lastAttendance) {
      case LastAttendanceFilter.any:
        break;
      case LastAttendanceFilter.present:
        if (w.consecutiveAbsences != 0 || w.lastAttendanceDate == null) {
          return false;
        }
      case LastAttendanceFilter.absent:
        if (w.consecutiveAbsences == 0) return false;
    }
    return true;
  }

  WomenFilter copyWith({
    String? query,
    String? Function()? streetId,
    bool? Function()? active,
    int? Function()? birthMonth,
    FollowUpFilter? followUp,
    LastAttendanceFilter? lastAttendance,
    int? minConsecutiveAbsences,
    double? Function()? maxAttendanceRate,
    Set<String>? Function()? streetIds,
  }) =>
      WomenFilter(
        query: query ?? this.query,
        streetId: streetId != null ? streetId() : this.streetId,
        active: active != null ? active() : this.active,
        birthMonth: birthMonth != null ? birthMonth() : this.birthMonth,
        followUp: followUp ?? this.followUp,
        lastAttendance: lastAttendance ?? this.lastAttendance,
        minConsecutiveAbsences:
            minConsecutiveAbsences ?? this.minConsecutiveAbsences,
        maxAttendanceRate: maxAttendanceRate != null
            ? maxAttendanceRate()
            : this.maxAttendanceRate,
        streetIds: streetIds != null ? streetIds() : this.streetIds,
      );
}
