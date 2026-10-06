import '../../../core/utils/arabic_text.dart';

class Street {
  const Street({required this.id, required this.name, this.womenCount = 0});

  final String id;
  final String name;

  /// Maintained by Cloud Functions.
  final int womenCount;

  /// Deterministic id from the normalised name, so "شارع مار جرجس" and
  /// "شارع مارجرجس " map to the same street document when re-imported.
  static String idFor(String name) {
    final n = ArabicText.normalize(name).replaceAll(' ', '_');
    return n.isEmpty ? 'unknown' : 's_$n';
  }

  factory Street.fromMap(String id, Map<String, dynamic> m) => Street(
        id: id,
        name: (m['name'] as String?) ?? '',
        womenCount: (m['womenCount'] as num?)?.toInt() ?? 0,
      );
}
