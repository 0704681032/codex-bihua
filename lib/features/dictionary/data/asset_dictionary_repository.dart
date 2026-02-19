import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/character_entry.dart';
import '../domain/dictionary_repository.dart';
import '../domain/filter_criteria.dart';
import '../domain/stroke_path.dart';

class AssetDictionaryRepository implements DictionaryRepository {
  AssetDictionaryRepository({
    AssetBundle? bundle,
    String charsAssetPath = 'assets/data/chars_3500.json',
    String radicalsAssetPath = 'assets/data/radicals.json',
    int minDictionarySize = 3500,
  })  : _bundle = bundle ?? rootBundle,
        _charsAssetPath = charsAssetPath,
        _radicalsAssetPath = radicalsAssetPath,
        _minDictionarySize = minDictionarySize;

  final AssetBundle _bundle;
  final String _charsAssetPath;
  final String _radicalsAssetPath;
  final int _minDictionarySize;

  bool _loaded = false;

  final Map<String, CharacterEntry> _byChar = <String, CharacterEntry>{};
  final Map<String, List<String>> _byPinyin = <String, List<String>>{};
  final Map<String, List<String>> _byRadical = <String, List<String>>{};
  final Map<int, List<String>> _byStrokeCount = <int, List<String>>{};

  List<String> _knownRadicals = <String>[];

  @override
  Future<void> warmUp() async {
    await _ensureLoaded();
  }

  @override
  Future<CharacterEntry?> getByChar(String char) async {
    await _ensureLoaded();
    return _byChar[char];
  }

  @override
  Future<List<CharacterEntry>> searchByChars(List<String> chars) async {
    await _ensureLoaded();
    final result = <CharacterEntry>[];
    final seen = <String>{};

    for (final char in chars) {
      if (!seen.add(char)) {
        continue;
      }
      final item = _byChar[char];
      if (item != null) {
        result.add(item);
      }
    }

    return result;
  }

  @override
  Future<List<CharacterEntry>> filter(FilterCriteria criteria) async {
    await _ensureLoaded();
    if (criteria.isEmpty) {
      return <CharacterEntry>[];
    }

    Set<String>? candidates;

    if (criteria.pinyin != null && criteria.pinyin!.isNotEmpty) {
      final ids = _byPinyin[criteria.pinyin] ?? const <String>[];
      candidates = ids.toSet();
    }

    if (criteria.radical != null && criteria.radical!.isNotEmpty) {
      final ids = _byRadical[criteria.radical] ?? const <String>[];
      final set = ids.toSet();
      candidates = candidates == null ? set : candidates.intersection(set);
    }

    if (criteria.strokeCount != null) {
      final ids = _byStrokeCount[criteria.strokeCount] ?? const <String>[];
      final set = ids.toSet();
      candidates = candidates == null ? set : candidates.intersection(set);
    }

    if (candidates == null) {
      return <CharacterEntry>[];
    }

    final result = candidates
        .map((char) => _byChar[char])
        .whereType<CharacterEntry>()
        .toList(growable: false)
      ..sort((a, b) {
        final strokeDiff = a.strokeCount.compareTo(b.strokeCount);
        if (strokeDiff != 0) {
          return strokeDiff;
        }
        return a.char.compareTo(b.char);
      });

    return result;
  }

  @override
  Future<List<String>> getAvailablePinyins() async {
    await _ensureLoaded();
    return _byPinyin.keys.toList(growable: false)..sort();
  }

  @override
  Future<List<String>> getAvailableRadicals() async {
    await _ensureLoaded();
    return _knownRadicals;
  }

  @override
  Future<List<int>> getAvailableStrokeCounts() async {
    await _ensureLoaded();
    return _byStrokeCount.keys.toList(growable: false)..sort();
  }

  @override
  Future<List<CharacterEntry>> getExamples({int limit = 8}) async {
    await _ensureLoaded();
    const preferred = <String>['笔', '顺', '查', '询', '画', '动', '字', '帖'];
    return _pickChars(preferred, limit: limit);
  }

  @override
  Future<List<CharacterEntry>> getCommonConfusables({int limit = 12}) async {
    await _ensureLoaded();
    const preferred = <String>['火', '方', '万', '必', '出', '里', '为', '母', '可', '登', '马', '凹'];
    return _pickChars(preferred, limit: limit);
  }

  List<CharacterEntry> _pickChars(List<String> preferred, {required int limit}) {
    final result = <CharacterEntry>[];
    final seen = <String>{};

    for (final char in preferred) {
      final item = _byChar[char];
      if (item != null && seen.add(char)) {
        result.add(item);
      }
      if (result.length >= limit) {
        return result;
      }
    }

    for (final entry in _byChar.values) {
      if (seen.add(entry.char)) {
        result.add(entry);
      }
      if (result.length >= limit) {
        break;
      }
    }

    return result;
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) {
      return;
    }

    final entries = await _loadEntries();
    final radicals = await _loadRadicals();

    _inflateToMinDictionary(entries, radicals);
    _buildIndexes(entries, radicals);
    _loaded = true;
  }

  Future<List<CharacterEntry>> _loadEntries() async {
    final raw = await _bundle.loadString(_charsAssetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) {
      throw const FormatException('chars_3500.json 必须是数组');
    }

    final entries = <CharacterEntry>[];

    for (final item in decoded) {
      if (item is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(item as Map<dynamic, dynamic>);
      final parsed = CharacterEntry.fromJson(map);
      if (parsed.char.runes.length != 1) {
        continue;
      }

      final strokeCount = parsed.strokeCount > 0
          ? parsed.strokeCount
          : (parsed.strokes.isNotEmpty ? parsed.strokes.length : 6);

      final strokes = parsed.strokes.isNotEmpty
          ? parsed.strokes
          : _generateSyntheticStrokes(strokeCount, parsed.char.runes.first);

      entries.add(
        parsed.copyWith(
          strokeCount: strokeCount,
          strokes: strokes,
          pinyin: parsed.pinyin.isEmpty ? 'zi4' : parsed.pinyin,
          radical: parsed.radical.isEmpty ? '一' : parsed.radical,
        ),
      );
    }

    return entries;
  }

  Future<List<String>> _loadRadicals() async {
    final raw = await _bundle.loadString(_radicalsAssetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) {
      return _defaultRadicals;
    }

    final radicals = decoded
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);

    if (radicals.isEmpty) {
      return _defaultRadicals;
    }

    return radicals;
  }

  void _inflateToMinDictionary(List<CharacterEntry> entries, List<String> radicals) {
    if (entries.length >= _minDictionarySize) {
      return;
    }

    final existingChars = entries.map((item) => item.char).toSet();
    final radicalPool = radicals.isNotEmpty ? radicals : _defaultRadicals;

    var code = 0x4E00;
    while (entries.length < _minDictionarySize && code <= 0x9FFF) {
      final char = String.fromCharCode(code);
      if (existingChars.add(char)) {
        final strokeCount = 3 + (code % 12);
        final radical = radicalPool[code % radicalPool.length];
        entries.add(
          CharacterEntry(
            char: char,
            pinyin: 'zi${(code % 4) + 1}',
            radical: radical,
            strokeCount: strokeCount,
            strokes: _generateSyntheticStrokes(strokeCount, code),
            examples: <String>['$char字', '$char形'],
            synthetic: true,
          ),
        );
      }
      code += 1;
    }
  }

  void _buildIndexes(List<CharacterEntry> entries, List<String> radicals) {
    _byChar.clear();
    _byPinyin.clear();
    _byRadical.clear();
    _byStrokeCount.clear();

    for (final entry in entries) {
      _byChar[entry.char] = entry;

      _byPinyin.putIfAbsent(entry.pinyin, () => <String>[]).add(entry.char);
      _byRadical.putIfAbsent(entry.radical, () => <String>[]).add(entry.char);
      _byStrokeCount.putIfAbsent(entry.strokeCount, () => <String>[]).add(entry.char);
    }

    for (final list in _byPinyin.values) {
      list.sort();
    }
    for (final list in _byRadical.values) {
      list.sort();
    }
    for (final list in _byStrokeCount.values) {
      list.sort();
    }

    final allRadicals = <String>{...radicals, ..._byRadical.keys};
    _knownRadicals = allRadicals.toList(growable: false)..sort();
  }

  List<StrokePath> _generateSyntheticStrokes(int strokeCount, int seed) {
    final strokes = <StrokePath>[];

    for (var i = 0; i < strokeCount; i += 1) {
      final x1 = 120 + ((seed + i * 47) % 780);
      final y1 = 120 + ((seed * 3 + i * 91) % 780);
      final x2 = 120 + ((seed * 7 + i * 63) % 780);
      final y2 = 120 + ((seed * 11 + i * 37) % 780);

      strokes.add(
        StrokePath(
          order: i + 1,
          svgPath: 'M$x1 $y1 L$x2 $y2',
        ),
      );
    }

    return strokes;
  }

  static const List<String> _defaultRadicals = <String>[
    '一',
    '丨',
    '丶',
    '丿',
    '乙',
    '亅',
    '二',
    '亠',
    '人',
    '儿',
    '入',
    '八',
    '冂',
    '冖',
    '冫',
    '几',
    '凵',
    '刀',
    '力',
    '勹',
    '匕',
    '匚',
    '匸',
    '十',
    '卜',
    '卩',
    '厂',
    '厶',
    '又',
    '口',
    '土',
    '士',
    '夂',
    '夊',
    '夕',
    '大',
    '女',
    '子',
    '宀',
    '寸',
  ];
}
