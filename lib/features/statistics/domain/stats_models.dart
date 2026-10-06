import '../../../core/constants/enums.dart';
import '../../../core/utils/dates.dart';

class DateRange {
  const DateRange(this.from, this.to);
  final DateTime from; // inclusive
  final DateTime to; // exclusive

  factory DateRange.lastDays(DateTime now, int days) => DateRange(
      Dates.dateOnly(now).subtract(Duration(days: days - 1)),
      Dates.dateOnly(now).add(const Duration(days: 1)));

  factory DateRange.thisMonth(DateTime now) => DateRange(
      DateTime(now.year, now.month), DateTime(now.year, now.month + 1));

  factory DateRange.today(DateTime now) => DateRange(
      Dates.dateOnly(now), Dates.dateOnly(now).add(const Duration(days: 1)));

  factory DateRange.thisWeek(DateTime now) {
    final start = Dates.dateOnly(now)
        .subtract(Duration(days: (now.weekday - DateTime.saturday + 7) % 7));
    return DateRange(start, start.add(const Duration(days: 7)));
  }

  String get fromId => Dates.dayId(from);
  String get toIdInclusive =>
      Dates.dayId(to.subtract(const Duration(days: 1)));

  String get label =>
      '${Dates.display(from)} - ${Dates.display(to.subtract(const Duration(days: 1)))}';

  @override
  bool operator ==(Object other) => other is DateRange && other.from == from && other.to == to;
  @override
  int get hashCode => Object.hash(from, to);
}

class FollowUpCounts {
  const FollowUpCounts({
    this.calls = 0,
    this.visits = 0,
    this.phoneSuggestions = 0,
    this.homeSuggestions = 0,
    this.phoneCompleted = 0,
    this.homeCompleted = 0,
    this.pending = 0,
    this.overdue = 0,
  });
  final int calls;
  final int visits;
  final int phoneSuggestions;
  final int homeSuggestions;
  final int phoneCompleted;
  final int homeCompleted;
  final int pending;
  final int overdue;

  int get completed => phoneCompleted + homeCompleted;
}

class ServantStats {
  const ServantStats({
    required this.servantId,
    required this.servantName,
    required this.assignedWomen,
    required this.followUps,
    required this.meetingPresent,
    required this.meetingAbsent,
    required this.withConsecutiveAbsences,
  });

  final String servantId;
  final String servantName;
  final int assignedWomen;
  final FollowUpCounts followUps;
  final int meetingPresent;
  final int meetingAbsent;
  final int withConsecutiveAbsences;

  double get attendanceRate {
    final t = meetingPresent + meetingAbsent;
    return t == 0 ? 0 : meetingPresent / t;
  }
}

class OverviewStats {
  const OverviewStats({
    required this.totalWomen,
    required this.activeWomen,
    required this.totalServants,
    required this.meetingId,
    required this.meetingPresent,
    required this.meetingAbsent,
    required this.followUps,
    required this.birthdaysToday,
  });

  final int totalWomen;
  final int activeWomen;
  final int totalServants;
  final String meetingId;
  final int meetingPresent;
  final int meetingAbsent;
  final FollowUpCounts followUps;
  final int birthdaysToday;

  double get attendanceRate {
    final t = meetingPresent + meetingAbsent;
    return t == 0 ? 0 : meetingPresent / t;
  }
}

class StreetStats {
  const StreetStats({
    required this.streetId,
    required this.name,
    required this.women,
    required this.present,
    required this.absent,
    required this.activeSuggestions,
  });
  final String streetId;
  final String name;
  final int women;
  final int present;
  final int absent;
  final int activeSuggestions;

  int get missing => absent;
  double get rate => present + absent == 0 ? 0 : present / (present + absent);
}

class StatsFilter {
  const StatsFilter({
    required this.range,
    this.servantId,
    this.streetId,
    this.followUpType,
  });
  final DateRange range;
  final String? servantId;
  final String? streetId;
  final FollowUpType? followUpType;

  @override
  bool operator ==(Object other) =>
      o is StatsFilter &&
      o.range == range &&
      o.servantId == servantId &&
      o.streetId == streetId &&
      o.followUpType == followUpType;
  @override
  int get hashCode => Object.hash(range, servantId, streetId, followUpType);
}
