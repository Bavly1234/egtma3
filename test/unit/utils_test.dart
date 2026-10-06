import 'package:egtma3/core/utils/arabic_text.dart';
import 'package:egtma3/core/utils/dates.dart';
import 'package:egtma3/core/utils/phone.dart';
import 'package:egtma3/features/birthdays/domain/birthday_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('phone normalisation', () {
    test('local and international forms are the same number', () {
      expect(PhoneUtils.normalize('01012345678'), '01012345678');
      expect(PhoneUtils.normalize('+201012345678'), '01012345678');
      expect(PhoneUtils.normalize('00201012345678'), '01012345678');
      expect(PhoneUtils.normalize('1012345678'), '01012345678');
      expect(PhoneUtils.normalize('010 1234-5678'), '01012345678');
      expect(PhoneUtils.normalize('٠١٠١٢٣٤٥٦٧٨'), '01012345678');
    });

    test('validation', () {
      expect(PhoneUtils.isValidMobile('01012345678'), isTrue);
      expect(PhoneUtils.isValidMobile('01312345678'), isFalse);
      expect(PhoneUtils.isValid('0223456789'), isTrue); // Cairo landline
      expect(PhoneUtils.isValid('123'), isFalse);
      expect(PhoneUtils.toInternational('01012345678'), '201012345678');
    });
  });

  group('Arabic text', () {
    test('normalises alef/yaa/taa marbuta and diacritics', () {
      expect(ArabicText.normalize('أَمِيرَة'), ArabicText.normalize('اميره'));
      expect(ArabicText.normalize('مُنَى'), 'مني');
    });

    test('strips honorific from names', () {
      expect(ArabicText.normalizeName('السيدة مريم أحمد'), ArabicText.normalizeName('مريم احمد'));
    });

    test('search keywords are prefixes', () {
      final k = ArabicText.searchKeywords(['مريم']);
      expect(k, containsAll(['مر', 'مري', 'مريم']));
    });
  });

  group('dates', () {
    test('flexible parsing', () {
      expect(Dates.parseFlexible('15/03/1970'), DateTime(1970, 3, 15));
      expect(Dates.parseFlexible('1970-03-15'), DateTime(1970, 3, 15));
      expect(Dates.parseFlexible('١٥/٣/١٩٧٠'), DateTime(1970, 3, 15));
      expect(Dates.parseFlexible(25642), DateTime(1970, 3, 15)); // Excel serial
      expect(Dates.parseFlexible('31/02/1970'), isNull);
      expect(Dates.parseFlexible('hello'), isNull);
    });

    test('meeting day helpers', () {
      final tue = DateTime(2026, 10, 6);
      expect(Dates.currentOrLastMeeting(tue), DateTime(2026, 9, 30));
      expect(Dates.nextMeeting(tue), DateTime(2026, 10, 7));
      expect(Dates.currentOrLastMeeting(DateTime(2026, 10, 7, 20)), DateTime(2026, 10, 7));
    });

    test('age', () {
      expect(Dates.ageOn(DateTime(1970, 10, 7), DateTime(2026, 10, 6)), 55);
      expect(Dates.ageOn(DateTime(1970, 10, 6), DateTime(2026, 10, 6)), 56);
    });
  });

  group('birthday logic (Rule G)', () {
    test('birthday matching including Feb 29', () {
      expect(BirthdayRules.isBirthdayOn(DateTime(1970, 10, 6), DateTime(2026, 10, 6)), isTrue);
      expect(BirthdayRules.isBirthdayOn(DateTime(1972, 2, 29), DateTime(2026, 2, 28)), isTrue);
      expect(BirthdayRules.isBirthdayOn(DateTime(1972, 2, 29), DateTime(2028, 2, 28)), isFalse);
    });

    test('next birthday and days until', () {
      expect(BirthdayRules.nextBirthday(DateTime(1970, 10, 1), DateTime(2026, 10, 6)),
          DateTime(2027, 10, 1));
      expect(BirthdayRules.daysUntil(DateTime(1970, 10, 10), DateTime(2026, 10, 6)), 4);
    });

    test('one notification key per woman/recipient/year', () {
      final k = BirthdayRules.notificationKey('w1', 'u1', 2026);
      expect(k, BirthdayRules.notificationKey('w1', 'u1', 2026));
      expect(k, isNot(BirthdayRules.notificationKey('w1', 'u1', 2027)));
      expect(k, isNot(BirthdayRules.notificationKey('w1', 'u2', 2026)));
    });
  });
}
