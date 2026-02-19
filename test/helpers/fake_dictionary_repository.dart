import 'package:bihua/features/dictionary/domain/character_entry.dart';
import 'package:bihua/features/dictionary/domain/dictionary_repository.dart';
import 'package:bihua/features/dictionary/domain/filter_criteria.dart';
import 'package:bihua/features/dictionary/domain/stroke_path.dart';

class FakeDictionaryRepository implements DictionaryRepository {
  FakeDictionaryRepository({List<CharacterEntry>? seed})
      : _entries = seed ?? _defaultEntries;

  final List<CharacterEntry> _entries;

  Map<String, CharacterEntry> get _byChar =>
      {for (final item in _entries) item.char: item};

  @override
  Future<void> warmUp() async {}

  @override
  Future<CharacterEntry?> getByChar(String char) async => _byChar[char];

  @override
  Future<List<CharacterEntry>> searchByChars(List<String> chars) async {
    final result = <CharacterEntry>[];
    final seen = <String>{};
    for (final char in chars) {
      if (seen.add(char) && _byChar[char] != null) {
        result.add(_byChar[char]!);
      }
    }
    return result;
  }

  @override
  Future<List<CharacterEntry>> filter(FilterCriteria criteria) async {
    return _entries.where((item) {
      if (criteria.pinyin != null && item.pinyin != criteria.pinyin) {
        return false;
      }
      if (criteria.radical != null && item.radical != criteria.radical) {
        return false;
      }
      if (criteria.strokeCount != null && item.strokeCount != criteria.strokeCount) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  @override
  Future<List<String>> getAvailablePinyins() async {
    final data = _entries.map((item) => item.pinyin).toSet().toList(growable: false)
      ..sort();
    return data;
  }

  @override
  Future<List<String>> getAvailableRadicals() async {
    final data = _entries.map((item) => item.radical).toSet().toList(growable: false)
      ..sort();
    return data;
  }

  @override
  Future<List<int>> getAvailableStrokeCounts() async {
    final data = _entries.map((item) => item.strokeCount).toSet().toList(growable: false)
      ..sort();
    return data;
  }

  @override
  Future<List<CharacterEntry>> getExamples({int limit = 8}) async {
    return _entries.take(limit).toList(growable: false);
  }

  @override
  Future<List<CharacterEntry>> getCommonConfusables({int limit = 12}) async {
    return _entries.reversed.take(limit).toList(growable: false);
  }
}

final List<CharacterEntry> _defaultEntries = <CharacterEntry>[
  CharacterEntry(
    char: '笔',
    pinyin: 'bi3',
    radical: '竹',
    strokeCount: 10,
    examples: const <String>['毛笔', '笔顺'],
    strokes: List<StrokePath>.generate(
      10,
      (index) => StrokePath(order: index + 1, svgPath: 'M100 ${120 + index * 40} L860 ${120 + index * 40}'),
      growable: false,
    ),
  ),
  CharacterEntry(
    char: '顺',
    pinyin: 'shun4',
    radical: '页',
    strokeCount: 9,
    examples: const <String>['笔顺'],
    strokes: List<StrokePath>.generate(
      9,
      (index) => StrokePath(order: index + 1, svgPath: 'M${200 + index * 60} 140 L${220 + index * 50} 860'),
      growable: false,
    ),
  ),
  CharacterEntry(
    char: '火',
    pinyin: 'huo3',
    radical: '火',
    strokeCount: 4,
    examples: const <String>['火山'],
    strokes: const <StrokePath>[
      StrokePath(order: 1, svgPath: 'M500 150 L460 530'),
      StrokePath(order: 2, svgPath: 'M340 370 L160 670'),
      StrokePath(order: 3, svgPath: 'M680 360 L860 680'),
      StrokePath(order: 4, svgPath: 'M500 530 L500 860')
    ],
  ),
];
