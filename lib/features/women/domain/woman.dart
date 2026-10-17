import '../../../core/constants/enums.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/utils/arabic_text.dart';
import '../../../core/utils/birth_date.dart';
import '../../../core/utils/phone.dart';

/// A member of the women's meeting.
///
/// Attendance history lives in the `attendance` collection; only small,
/// function-maintained summary fields are denormalised here.
class Woman {
  const Woman({
    required this.id,
    required this.fullName,
    required this.streetId,
    required this.streetName,
    required this.address,
    required this.phone,
    required this.dateOfBirth,
    required this.active,
    this.landline = '',
    this.isServant = false,
    this.birthDay,
    this.birthMonth,
    this.notes = '',
    this.consecutiveAbsences = 0,
    this.totalPresent = 0,
    this.totalAbsent = 0,
    this.phoneCalls = 0,
    this.homeVisits = 0,
    this.lastCallAt,
    this.lastVisitAt,
    this.lastAttendanceDate,
    this.activeSuggestionType,
    this.isDemo = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String fullName;
  final String streetId;
  final String streetName;
  final String address;
  final String phone; // normalised
  /// Full date — only when the year is known.
  final DateTime? dateOfBirth;

  /// Day / month of the birthday (year often unknown). Month may be alone.
  final int? birthDay;
  final int? birthMonth;
  final bool active;

  /// Home landline, e.g. 035916219.
  final String landline;

  /// She serves in the meeting (خادمة). Servants' attendance is taken by
  /// أبونا on a separate page and they are not in the women's list.
  final bool isServant;
  final String notes;

  // Server-maintained summary (Cloud Functions only).
  final int consecutiveAbsences;
  final int totalPresent;
  final int totalAbsent;
  final int phoneCalls;
  final int homeVisits;
  final DateTime? lastCallAt;
  final DateTime? lastVisitAt;
  final String? lastAttendanceDate;
  final SuggestionType? activeSuggestionType;

  final bool isDemo;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasPhone => phone.isNotEmpty;
  bool get hasLandline => landline.isNotEmpty;

  BirthDate get birth => BirthDate(
        day: dateOfBirth?.day ?? birthDay,
        month: dateOfBirth?.month ?? birthMonth,
        year: dateOfBirth?.year,
      );
  bool get hasWhatsApp => PhoneUtils.isValidMobile(phone);

  double? get attendanceRate {
    final total = totalPresent + totalAbsent;
    return total == 0 ? null : totalPresent / total;
  }

  factory Woman.fromMap(String id, Map<String, dynamic> m) => Woman(
        id: id,
        fullName: (m['fullName'] as String?) ?? '',
        streetId: (m['streetId'] as String?) ?? '',
        streetName: (m['streetName'] as String?) ?? '',
        address: (m['address'] as String?) ?? '',
        phone: (m['phone'] as String?) ?? '',
        dateOfBirth: tsToDate(m['dateOfBirth']),
        birthDay: (m['birthDay'] as num?)?.toInt(),
        birthMonth: (m['birthMonth'] as num?)?.toInt(),
        landline: (m['landline'] as String?) ?? '',
        isServant: (m['isServant'] as bool?) ?? false,
        active: (m['active'] as bool?) ?? true,
        notes: (m['notes'] as String?) ?? '',
        consecutiveAbsences: (m['consecutiveAbsences'] as num?)?.toInt() ?? 0,
        totalPresent: (m['totalPresent'] as num?)?.toInt() ?? 0,
        totalAbsent: (m['totalAbsent'] as num?)?.toInt() ?? 0,
        phoneCalls: (m['phoneCalls'] as num?)?.toInt() ?? 0,
        homeVisits: (m['homeVisits'] as num?)?.toInt() ?? 0,
        lastCallAt: tsToDate(m['lastCallAt']),
        lastVisitAt: tsToDate(m['lastVisitAt']),
        lastAttendanceDate: m['lastAttendanceDate'] as String?,
        activeSuggestionType:
            SuggestionType.fromWire(m['activeSuggestionType'] as String?),
        isDemo: (m['isDemo'] as bool?) ?? false,
        createdAt: tsToDate(m['createdAt']),
        updatedAt: tsToDate(m['updatedAt']),
      );
}

/// The editable part of a woman (form / import input).
class WomanDraft {
  const WomanDraft({
    required this.fullName,
    required this.streetName,
    required this.address,
    required this.phone,
    this.birth = BirthDate.empty,
    this.landline = '',
    this.isServant = false,
    this.active = true,
    this.notes = '',
  });

  final String fullName;
  final String streetName;
  final String address;
  final String phone; // normalised mobile
  final String landline;
  final bool isServant;
  final BirthDate birth;
  final bool active;
  final String notes;

  /// Firestore fields derived from the draft. `streetId` is supplied by the
  /// street repository so street names stay consistent.
  Map<String, dynamic> toFields(String streetId) {
    return {
      'fullName': fullName.trim(),
      'nameNormalized': ArabicText.normalizeName(fullName),
      'searchKeywords': ArabicText.searchKeywords(
          [fullName, streetName, address, phone, landline]),
      'streetId': streetId,
      'streetName': streetName.trim(),
      'address': address.trim(),
      'phone': phone,
      'landline': landline,
      'isServant': isServant,
      'dateOfBirth': birth.full,
      'birthMonth': birth.month,
      'birthDay': birth.day,
      'active': active,
      'notes': notes.trim(),
    };
  }
}
