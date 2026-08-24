import 'stroke_path.dart';

class CharacterEntry {
  const CharacterEntry({
    required this.char,
    required this.pinyin,
    required this.radical,
    required this.strokeCount,
    required this.strokes,
    this.examples = const <String>[],
    this.synthetic = false,
    this.flipYAxis = false,
    this.strokeNames = const <String>[],
  });

  final String char;
  final String pinyin;
  final String radical;
  final int strokeCount;
  final List<StrokePath> strokes;
  final List<String> examples;
  final bool synthetic;
  final bool flipYAxis;

  /// Authoritative per-stroke names (from the cnchar-order derived
  /// dataset). Ambiguous pairs are slash-joined candidates, e.g.
  /// "横撇/横钩"; empty means no data and the geometric classifier
  /// should be used instead.
  final List<String> strokeNames;

  factory CharacterEntry.fromJson(Map<String, dynamic> json) {
    final parsedStrokes = ((json['strokes'] as List<dynamic>?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(StrokePath.fromJson)
        .toList(growable: false);
    final hasMedianPoints = parsedStrokes.any((stroke) => stroke.medianPoints.isNotEmpty);

    return CharacterEntry(
      char: (json['char'] as String?)?.trim() ?? '',
      pinyin: (json['pinyin'] as String?)?.trim() ?? '',
      radical: (json['radical'] as String?)?.trim() ?? '',
      strokeCount: (json['strokeCount'] as num?)?.toInt() ?? 0,
      strokes: parsedStrokes,
      examples: ((json['examples'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<String>()
          .map((it) => it.trim())
          .where((it) => it.isNotEmpty)
          .toList(growable: false),
      synthetic: json['synthetic'] == true,
      flipYAxis: json.containsKey('flipYAxis')
          ? json['flipYAxis'] == true
          : hasMedianPoints,
      strokeNames: ((json['strokeNames'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'char': char,
      'pinyin': pinyin,
      'radical': radical,
      'strokeCount': strokeCount,
      'strokes': strokes.map((item) => item.toJson()).toList(growable: false),
      'examples': examples,
      'synthetic': synthetic,
      'flipYAxis': flipYAxis,
      if (strokeNames.isNotEmpty) 'strokeNames': strokeNames,
    };
  }

  CharacterEntry copyWith({
    String? char,
    String? pinyin,
    String? radical,
    int? strokeCount,
    List<StrokePath>? strokes,
    List<String>? examples,
    bool? synthetic,
    bool? flipYAxis,
    List<String>? strokeNames,
  }) {
    return CharacterEntry(
      char: char ?? this.char,
      pinyin: pinyin ?? this.pinyin,
      radical: radical ?? this.radical,
      strokeCount: strokeCount ?? this.strokeCount,
      strokes: strokes ?? this.strokes,
      examples: examples ?? this.examples,
      synthetic: synthetic ?? this.synthetic,
      flipYAxis: flipYAxis ?? this.flipYAxis,
      strokeNames: strokeNames ?? this.strokeNames,
    );
  }
}
