class DailyVerse {
  const DailyVerse({
    required this.date,
    required this.text,
    required this.reference,
  });

  final String date; // yyyy-MM-dd
  final String text; // Arabic
  final String reference; // e.g. "مزمور 23: 1"

  factory DailyVerse.fromMap(String date, Map<String, dynamic> m) => DailyVerse(
        date: date,
        text: (m['text'] as String?) ?? '',
        reference: (m['reference'] as String?) ?? '',
      );
}

/// Abstraction over where verses come from (Firestore today; an external API
/// could implement this later without touching the UI).
abstract interface class VerseSource {
  Future<DailyVerse?> verseFor(DateTime day);
}
