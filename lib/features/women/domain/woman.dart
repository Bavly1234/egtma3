import '../../../core/constants/enums.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/utils/arabic_text.dart';
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
  final DateTime? dateOfBirth;
  final bool active;
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
    required     this.dateOfBirth,
    this.active = true,
    this.notes = '',
  });

  final String fullName;
  final String streetName;
  final String address;
  final String phone; // normalised
  final DateTime? dateOfBirth;
  final bool active;
  final String notes;

  /// Firestore fields derived from the draft. `streetId` is supplied by the
  /// street repository so street names stay consistent.
  Map<String, dynamic> toFields(String streetId) {
    final dob = dateOfBirth;
    return {
      'fullName': fullName.trim(),
      'nameNormalized': ArabicText.normalizeName(fullName),
      'searchKeywords': ArabicText.searchKeywords(
          [fullName, streetName, address, phone]),
      'streetId': streetId,
      'streetName': streetName.trim(),
      'address': address.trim(),
      'phone': phone,
      'dateOfBirth': dob,
      'birthMonth': dob?.month,
      'birthDay': dob?.day,
      'active': active,
      'notes': notes.trim(),
    };
  }
}
