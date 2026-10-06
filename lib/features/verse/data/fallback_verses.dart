import '../../../core/utils/dates.dart';
import '../domain/daily_verse.dart';

/// Small offline fallback (Smith–Van Dyke Arabic, public domain).
/// The primary pool lives in Firestore (`verse_pool`, seeded by functions).
const _fallback = <(String, String)>[
  ('الرَّبُّ رَاعِيَّ فَلاَ يُعْوِزُنِي شَيْءٌ.', 'مزمور 23: 1'),
  ('تَعَالَوْا إِلَيَّ يَا جَمِيعَ الْمُتْعَبِينَ وَالثَّقِيلِي الأَحْمَالِ، وَأَنَا أُرِيحُكُمْ.', 'متى 11: 28'),
  ('أَسْتَطِيعُ كُلَّ شَيْءٍ فِي الْمَسِيحِ الَّذِي يُقَوِّينِي.', 'فيلبي 4: 13'),
  ('لأَنَّهُ هكَذَا أَحَبَّ اللهُ الْعَالَمَ حَتَّى بَذَلَ ابْنَهُ الْوَحِيدَ، لِكَيْ لاَ يَهْلِكَ كُلُّ مَنْ يُؤْمِنُ بِهِ، بَلْ تَكُونُ لَهُ الْحَيَاةُ الأَبَدِيَّةُ.', 'يوحنا 3: 16'),
  ('سِرَاجٌ لِرِجْلِي كَلاَمُكَ وَنُورٌ لِسَبِيلِي.', 'مزمور 119: 105'),
  ('اَللهُ لَنَا مَلْجَأٌ وَقُوَّةٌ. عَوْنًا فِي الضِّيقَاتِ وُجِدَ شَدِيدًا.', 'مزمور 46: 1'),
  ('وَنَحْنُ نَعْلَمُ أَنَّ كُلَّ الأَشْيَاءِ تَعْمَلُ مَعًا لِلْخَيْرِ لِلَّذِينَ يُحِبُّونَ اللهَ.', 'رومية 8: 28'),
];

DailyVerse fallbackVerseFor(DateTime day) {
  final idx = Dates.dateOnly(day).difference(DateTime(2024)).inDays.abs() %
      _fallback.length;
  final (text, ref) = _fallback[idx];
  return DailyVerse(date: Dates.dayId(day), text: text, reference: ref);
}
