import 'package:egtma3/core/utils/birth_date.dart';
import 'package:egtma3/core/utils/phone.dart';
import 'package:egtma3/features/excel/domain/import_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every format found in the church's real sheet (اجتماع السيدات.xlsx),
/// with made-up names and numbers.
void main() {
  final now = DateTime(2026, 10, 15);

  group('birth date formats', () {
    BirthDate? p(Object? v) => BirthDate.parse(v, now: now);

    test('"30/4" = day 30, April, no year', () {
      final b = p('30/4')!;
      expect((b.day, b.month, b.year), (30, 4, null));
      expect(b.display, '30 أبريل');
    });

    test('"    /8" and "/12" = month only (spaces ignored)', () {
      expect(p('    /8')!.month, 8);
      expect(p('    /8')!.day, isNull);
      expect(p('   /10 ')!.month, 10);
      expect(p('/12')!.month, 12);
      expect(p('/6')!.display, 'شهر يونيو');
    });

    test('a single number is the month', () {
      expect(p('6')!.month, 6);
      expect(p(6)!.month, 6);
      expect(p('6')!.day, isNull);
    });

    test('Excel-converted date (year 2026, swapped) → typed day/month', () {
      // Typed "11/2" (11 February); Excel stored it as 2 November 2026.
      final b = p(DateTime(2026, 11, 2))!;
      expect((b.day, b.month, b.year), (11, 2, null));
    });

    test('real old dates and full text dates keep the year', () {
      expect(p(DateTime(1965, 4, 30))!.full, DateTime(1965, 4, 30));
      expect(p('15/3/1970')!.full, DateTime(1970, 3, 15));
      expect(p('1970-03-15')!.full, DateTime(1970, 3, 15));
      expect(p('١٥/٣')!.month, 3);
    });

    test('stray "1" turned into 1900-01-01 → empty, blanks → empty', () {
      expect(p(DateTime(1900, 1, 1))!.isEmpty, isTrue);
      expect(p(DateTime(1899, 12, 31))!.isEmpty, isTrue);
      expect(p(' ')!.isEmpty, isTrue);
      expect(p(null)!.isEmpty, isTrue);
    });

    test('impossible values are rejected', () {
      expect(p('31/2'), isNull);
      expect(p('5/13'), isNull);
      expect(p('/13'), isNull);
      expect(p('hello'), isNull);
    });

    test('29 February without a year is a valid birthday', () {
      expect(p('29/2')!.anchor, DateTime(2000, 2, 29));
    });
  });

  group('phone cell splitting', () {
    test('mobile/landline → two fields, landline gets 03', () {
      final s = PhoneUtils.split('01222000111/5916000');
      expect(s.mobile, '01222000111');
      expect(s.landline, '035916000');
      expect(s.noteText, isEmpty);
    });

    test('landline first, mobile second', () {
      final s = PhoneUtils.split('4270000/01223000111');
      expect(s.mobile, '01223000111');
      expect(s.landline, '034270000');
    });

    test('landline only (text or numeric cell)', () {
      expect(PhoneUtils.split('5926000').landline, '035926000');
      expect(PhoneUtils.split(5916000).landline, '035916000');
      expect(PhoneUtils.split(5916000).mobile, isNull);
    });

    test('numeric mobile without the leading zero', () {
      expect(PhoneUtils.split(1226000756).mobile, '01226000756');
    });

    test('two mobiles: first is the phone, second kept in notes', () {
      final s = PhoneUtils.split('01271000322/01206000620');
      expect(s.mobile, '01271000322');
      expect(s.noteText, contains('01206000620'));
    });

    test('three numbers: mobile, landline, extra landline in notes', () {
      final s = PhoneUtils.split('01276000409/5928000/5909000');
      expect(s.mobile, '01276000409');
      expect(s.landline, '035928000');
      expect(s.noteText, contains('035909000'));
    });

    test('words next to numbers are kept in the notes', () {
      final s = PhoneUtils.split('01001000081/5930000-(01001000081) إيناس بنتها');
      expect(s.mobile, '01001000081');
      expect(s.landline, '035930000');
      expect(s.noteText, contains('إيناس بنتها'));
    });

    test('a 12-digit typo is not lost', () {
      final s = PhoneUtils.split('010612000709/5916000');
      expect(s.mobile, isNull);
      expect(s.landline, '035916000');
      expect(s.noteText, contains('010612000709'));
    });

    test('empty cell', () {
      expect(PhoneUtils.split(null).isEmpty, isTrue);
    });
  });

  group('whole rows like the church sheet', () {
    final header = ['الاسم كامل', 'رقم التليفون', 'الشارع', 'العنوان بالكامل', 'تاريخ الميلاد'];

    test('typical rows import with split phones and day/month birthdays', () {
      final rows = ImportParser.parse([
        header,
        ['ت/ سيدة تجربة', '01222000908/5916000', 'ش منيوزيس', '12ش منيوزيس شقة 5', '    /12'],
        ['سيدة تانية', 5916000, 'ش أبيقور', '21ش أبيقور', '2/11'],
        ['سيدة تالتة', '01270000500', 'ش أبيقور', '21ش أبيقور', DateTime(2026, 11, 2)],
        [null, null, null, null, null], // empty spacer row
        ['سيدة بدون شارع', '01205000921', null, null, null],
      ], ColumnDetection.detect(header), now: now);

      expect(rows.length, 4); // empty row skipped
      expect(rows.every((r) => r.isValid), isTrue);

      final a = rows[0].draft!;
      expect((a.phone, a.landline), ('01222000908', '035916000'));
      expect((a.birth.day, a.birth.month), (null, 12));

      final b = rows[1].draft!;
      expect((b.phone, b.landline), ('', '035916000'));
      expect((b.birth.day, b.birth.month), (2, 11));

      final c = rows[2].draft!;
      expect((c.birth.day, c.birth.month, c.birth.year), (11, 2, null));

      expect(rows[3].draft!.streetName, kNoStreetName);
    });

    test('optional "التليفون الأرضي" column is read when present', () {
      final h = [...header, 'التليفون الأرضي'];
      final row = ImportParser.parse([
        h,
        ['سيدة', '01222000908', 'ش', 'ع', '1/1', '5916000'],
      ], ColumnDetection.detect(h), now: now).single;
      expect(row.draft!.landline, '035916000');
      expect(row.draft!.phone, '01222000908');
    });
  });
}
