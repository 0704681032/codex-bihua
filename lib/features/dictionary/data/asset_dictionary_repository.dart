import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/character_entry.dart';
import '../domain/dictionary_repository.dart';
import '../domain/filter_criteria.dart';
import '../domain/stroke_path.dart';

/// Metadata kept in memory for every char after loading the light index.
class _CharMeta {
  const _CharMeta({
    required this.char,
    required this.pinyin,
    required this.radical,
    required this.strokeCount,
    required this.shard,
  });

  final String char;
  final String pinyin;
  final String radical;
  final int strokeCount;
  final int shard;

  CharacterEntry toLightEntry() {
    return CharacterEntry(
      char: char,
      pinyin: pinyin,
      radical: radical,
      strokeCount: strokeCount,
      // Grid cards and filter lists only render text; full strokes are
      // hydrated on demand when the detail page asks for the char.
      strokes: const <StrokePath>[],
    );
  }
}

/// Dictionary repository backed by split assets:
///
///  * `chars_index.json` (~435 KB) — metadata for all chars, loaded once
///    at startup so the home page paints immediately.
///  * `shards/shard_NNN.json` — full stroke payloads, fetched only when a
///    detail page actually needs them (one shard ≈ 256 chars) and cached
///    in memory afterwards.
class AssetDictionaryRepository implements DictionaryRepository {
  AssetDictionaryRepository({
    AssetBundle? bundle,
    String indexAssetPath = 'assets/data/chars_index.json',
    String shardAssetBase = 'assets/data/shards',
    String radicalsAssetPath = 'assets/data/radicals.json',
    int minDictionarySize = 0,
  })  : _bundle = bundle ?? rootBundle,
        _indexAssetPath = indexAssetPath,
        _shardAssetBase = shardAssetBase,
        _radicalsAssetPath = radicalsAssetPath,
        _minDictionarySize = minDictionarySize;

  final AssetBundle _bundle;
  final String _indexAssetPath;
  final String _shardAssetBase;
  final String _radicalsAssetPath;
  final int _minDictionarySize;

  bool _loaded = false;

  final Map<String, _CharMeta> _metaByChar = <String, _CharMeta>{};
  final Map<String, CharacterEntry> _hydrated = <String, CharacterEntry>{};
  final Set<int> _loadedShards = <int>{};
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

    final existing = _hydrated[char];
    if (existing != null && existing.strokes.isNotEmpty) {
      return existing;
    }

    final meta = _metaByChar[char];
    if (meta == null) {
      return null;
    }

    await _loadShard(meta.shard);
    return _hydrated[char] ?? meta.toLightEntry();
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
      final hydratedItem = _hydrated[char];
      if (hydratedItem != null && hydratedItem.strokes.isNotEmpty) {
        result.add(hydratedItem);
        continue;
      }
      final meta = _metaByChar[char];
      if (meta != null) {
        result.add(meta.toLightEntry());
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

    return _resolveEntries(candidates);
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

  // ---- loading ----

  Future<void> _ensureLoaded() async {
    if (_loaded) {
      return;
    }

    final rawIndex = await _bundle.loadString(_indexAssetPath);
    _parseIndex(rawIndex);

    final radicals = await _loadRadicals();
    _inflateToMinDictionary(radicals);
    _buildIndexes(radicals);
    _loaded = true;
  }

  void _parseIndex(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<dynamic, dynamic>) {
      throw const FormatException('chars_index.json 必须是对象');
    }
    final chars = decoded['chars'];
    if (chars is! List<dynamic>) {
      throw const FormatException('chars_index.json 缺少 chars 数组');
    }

    for (final item in chars) {
      if (item is! Map<dynamic, dynamic>) {
        continue;
      }
      final char = (item['c'] as String?)?.trim() ?? '';
      if (char.runes.length != 1) {
        continue;
      }
      final meta = _CharMeta(
        char: char,
        pinyin: (item['p'] as String?)?.trim() ?? '',
        radical: (item['r'] as String?)?.trim() ?? '',
        strokeCount: (item['n'] as num?)?.toInt() ?? 0,
        shard: (item['s'] as num?)?.toInt() ?? 0,
      );
      _metaByChar[char] = meta;
    }
  }

  Future<void> _loadShard(int shard) async {
    if (!_loadedShards.add(shard)) {
      return;
    }
    final path = '$_shardAssetBase/shard_${shard.toString().padLeft(3, '0')}.json';
    try {
      final raw = await _bundle.loadString(path);
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) {
        return;
      }
      for (final item in decoded) {
        if (item is! Map<dynamic, dynamic>) {
          continue;
        }
        final entry = _entryFromJson(Map<String, dynamic>.from(item));
        if (entry != null) {
          _hydrated[entry.char] = entry;
        }
      }
    } on Exception {
      // A missing or corrupt shard must not crash lookups; callers fall
      // back to the light metadata entry.
      _loadedShards.remove(shard);
    }
  }

  CharacterEntry? _entryFromJson(Map<String, dynamic> json) {
    final parsed = CharacterEntry.fromJson(json);
    if (parsed.char.runes.length != 1) {
      return null;
    }

    // Stroke order must follow the stored `order` field; drop entries
    // without a drawable path and normalize the sequence to 1..n.
    final orderedStrokes = parsed.strokes
        .where((stroke) => stroke.svgPath.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final normalizedStrokes = <StrokePath>[
      for (var i = 0; i < orderedStrokes.length; i += 1)
        StrokePath(
          order: i + 1,
          svgPath: orderedStrokes[i].svgPath,
          medianPoints: orderedStrokes[i].medianPoints,
        ),
    ];

    // The rendered stroke list is the source of truth for the count.
    final strokeCount = normalizedStrokes.isNotEmpty
        ? normalizedStrokes.length
        : (parsed.strokeCount > 0 ? parsed.strokeCount : 6);

    var strokes = normalizedStrokes;
    if (strokes.isEmpty) {
      strokes = _generateSyntheticStrokes(strokeCount, parsed.char.runes.first);
    }

    // Names must line up with the normalized stroke list or they would
    // label the wrong stroke.
    final strokeNames = parsed.strokeNames.length == strokes.length
        ? parsed.strokeNames
        : const <String>[];

    return parsed.copyWith(
      strokeCount: strokeCount,
      strokes: strokes,
      pinyin: parsed.pinyin.isEmpty ? 'zi4' : parsed.pinyin,
      radical: parsed.radical.isEmpty ? '一' : parsed.radical,
      strokeNames: strokeNames,
      flipYAxis: strokes.any((stroke) => stroke.medianPoints.isNotEmpty),
    );
  }

  Future<List<String>> _loadRadicals() async {
    try {
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
    } on Exception {
      return _defaultRadicals;
    }
  }

  void _inflateToMinDictionary(List<String> radicals) {
    if (_metaByChar.length >= _minDictionarySize) {
      return;
    }

    final radicalPool = radicals.isNotEmpty ? radicals : _defaultRadicals;

    var code = 0x4E00;
    while (_metaByChar.length < _minDictionarySize && code <= 0x9FFF) {
      final char = String.fromCharCode(code);
      if (!_metaByChar.containsKey(char)) {
        final strokeCount = 3 + (code % 12);
        final radical = radicalPool[code % radicalPool.length];
        _metaByChar[char] = _CharMeta(
          char: char,
          pinyin: 'zi${(code % 4) + 1}',
          radical: radical,
          strokeCount: strokeCount,
          shard: -1,
        );
        _hydrated[char] = CharacterEntry(
          char: char,
          pinyin: 'zi${(code % 4) + 1}',
          radical: radical,
          strokeCount: strokeCount,
          strokes: _generateSyntheticStrokes(strokeCount, code),
          examples: <String>['$char字', '$char形'],
          synthetic: true,
        );
      }
      code += 1;
    }
  }

  void _buildIndexes(List<String> radicals) {
    _byPinyin.clear();
    _byRadical.clear();
    _byStrokeCount.clear();

    void indexMeta(_CharMeta meta) {
      _byPinyin.putIfAbsent(meta.pinyin, () => <String>[]).add(meta.char);
      _byRadical.putIfAbsent(meta.radical, () => <String>[]).add(meta.char);
      _byStrokeCount
          .putIfAbsent(meta.strokeCount, () => <String>[])
          .add(meta.char);
    }

    for (final meta in _metaByChar.values) {
      // Synthetic (inflated) entries also get a meta row with shard -1,
      // so one pass over the table covers every indexed char.
      indexMeta(meta);
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

  List<CharacterEntry> _resolveEntries(Set<String> chars) {
    final result = <CharacterEntry>[];
    for (final char in chars) {
      final hydratedItem = _hydrated[char];
      if (hydratedItem != null && hydratedItem.strokes.isNotEmpty) {
        result.add(hydratedItem);
        continue;
      }
      final meta = _metaByChar[char];
      if (meta != null) {
        result.add(meta.toLightEntry());
      } else {
        final synthetic = _hydrated[char];
        if (synthetic != null) {
          result.add(synthetic);
        }
      }
    }
    result.sort((a, b) {
      final strokeDiff = a.strokeCount.compareTo(b.strokeCount);
      if (strokeDiff != 0) {
        return strokeDiff;
      }
      return a.char.compareTo(b.char);
    });
    return result;
  }

  List<CharacterEntry> _pickChars(List<String> preferred, {required int limit}) {
    final result = <CharacterEntry>[];
    final seen = <String>{};

    for (final char in preferred) {
      final item = _hydrated[char] ?? _metaByChar[char]?.toLightEntry();
      if (item != null && seen.add(char)) {
        result.add(item);
      }
      if (result.length >= limit) {
        return result;
      }
    }

    for (final meta in _metaByChar.values) {
      if (seen.add(meta.char)) {
        result.add(meta.toLightEntry());
      }
      if (result.length >= limit) {
        break;
      }
    }

    return result;
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
