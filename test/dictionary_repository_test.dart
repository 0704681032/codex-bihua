import 'dart:async';

import 'package:bihua/features/dictionary/data/asset_dictionary_repository.dart';
import 'package:bihua/features/dictionary/domain/dictionary_repository.dart';
import 'package:bihua/features/dictionary/domain/filter_criteria.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AssetDictionaryRepository', () {
    final bundle = _FakeAssetBundle(<String, String>{
      'assets/data/chars_index.json': '''
{
  "shardSize": 2,
  "chars": [
    {"c": "笔", "p": "bi3", "r": "竹", "n": 2, "s": 0},
    {"c": "顺", "p": "shun4", "r": "页", "n": 1, "s": 0}
  ]
}
''',
      'assets/data/shards/shard_000.json': '''
[
  {
    "char": "笔",
    "pinyin": "bi3",
    "radical": "竹",
    "strokeCount": 2,
    "examples": ["笔顺"],
    "strokes": [
      {"order": 2, "svgPath": "M160 280 L860 280"},
      {"order": 1, "svgPath": "M120 200 L900 200"}
    ]
  },
  {
    "char": "顺",
    "pinyin": "shun4",
    "radical": "页",
    "strokeCount": 1,
    "examples": ["顺序"],
    "strokes": [
      {"order": 1, "svgPath": "M200 100 L200 860"}
    ]
  }
]
''',
      'assets/data/radicals.json': '["竹", "页", "口"]',
    });

    final repo = AssetDictionaryRepository(
      bundle: bundle,
      minDictionarySize: 12,
    );

    test('index loads fast; getByChar hydrates the shard on demand', () async {
      await repo.warmUp();
      // The index alone must already know the char.
      final results = await repo.searchByChars(['笔']);
      expect(results, hasLength(1));

      final item = await repo.getByChar('笔');
      expect(item, isNotNull);
      expect(item!.pinyin, 'bi3');
      // The rendered stroke list is authoritative: entries are normalized
      // to sequential orders and the count follows the actual strokes.
      expect(item.strokeCount, 2);
      expect(
        item.strokes.map((s) => s.order),
        [1, 2],
        reason: 'strokes must be re-ordered into a strict 1..n sequence',
      );
      expect(item.strokes.first.svgPath, 'M120 200 L900 200');
    });

    test('hydrating one shard also serves its neighbours', () async {
      await repo.getByChar('笔');
      // Same shard → served from cache without another asset fetch.
      final cached = await repo.getByChar('顺');
      expect(cached, isNotNull);
      expect(cached!.strokeCount, 1);
    });

    test('inflates dictionary to minimum size', () async {
      await repo.warmUp();
      final synthetic = await repo.getByChar('一');
      expect(synthetic, isNotNull);
      expect(synthetic!.synthetic, isTrue);
    });

    test('radical options derive from the index, not radicals.json', () async {
      final noInflateRepo = AssetDictionaryRepository(
        bundle: _FakeAssetBundle(<String, String>{
          'assets/data/chars_index.json': '''
{
  "shardSize": 2,
  "chars": [
    {"c": "笔", "p": "bi3", "r": "竹", "n": 2, "s": 0},
    {"c": "顺", "p": "shun4", "r": "页", "n": 1, "s": 0}
  ]
}
''',
          'assets/data/shards/shard_000.json': '[]',
          // 「戶」不在索引里（简体数据用「户」），不允许成为死选项。
          'assets/data/radicals.json': '["竹", "页", "戶"]',
        }),
      );
      await noInflateRepo.warmUp();

      final radicals = await noInflateRepo.getAvailableRadicals();
      expect(radicals, <String>['竹', '页'],
          reason: '部首选项必须来自索引实际数据，避免选中后查不到字');
    });

    test('filters by pinyin/radical/stroke count', () async {
      await repo.warmUp();
      final pinyin = await repo.filter(const FilterCriteria(pinyin: 'bi3'));
      expect(pinyin.map((e) => e.char), contains('笔'));

      final radical = await repo.filter(const FilterCriteria(radical: '页'));
      expect(radical.map((e) => e.char), contains('顺'));

      final strokeCount = await repo.filter(const FilterCriteria(strokeCount: 1));
      expect(strokeCount.map((e) => e.char), contains('顺'));
    });
  });

  group('AssetDictionaryRepository concurrency', () {
    _GatedAssetBundle gatedBundle() => _GatedAssetBundle(<String, String>{
          'assets/data/chars_index.json': '''
{
  "shardSize": 2,
  "chars": [
    {"c": "笔", "p": "bi3", "r": "竹", "n": 2, "s": 0},
    {"c": "顺", "p": "shun4", "r": "页", "n": 1, "s": 0}
  ]
}
''',
          'assets/data/shards/shard_000.json': '''
[
  {
    "char": "笔",
    "pinyin": "bi3",
    "radical": "竹",
    "strokeCount": 2,
    "examples": ["笔顺"],
    "strokes": [
      {"order": 1, "svgPath": "M120 200 L900 200"},
      {"order": 2, "svgPath": "M160 280 L860 280"}
    ]
  },
  {
    "char": "顺",
    "pinyin": "shun4",
    "radical": "页",
    "strokeCount": 1,
    "examples": ["顺序"],
    "strokes": [
      {"order": 1, "svgPath": "M200 100 L200 860"}
    ]
  }
]
''',
          'assets/data/radicals.json': '["竹", "页"]',
        });

    test('concurrent getByChar on one shard: shared load, full strokes, one read',
        () async {
      final bundle = gatedBundle()..gate('assets/data/shards/shard_000.json');
      final repo = AssetDictionaryRepository(bundle: bundle);

      final first = repo.getByChar('笔');
      final second = repo.getByChar('顺');
      await Future<void>.delayed(Duration.zero);
      bundle.release('assets/data/shards/shard_000.json');

      final a = await first;
      final b = await second;
      expect(a!.strokes, hasLength(2),
          reason: '并发调用不得拿到只有元数据的轻量条目');
      expect(b!.strokes, hasLength(1));
      expect(
        bundle.reads
            .where((key) => key.contains('shard_000'))
            .length,
        1,
        reason: '同片并发请求必须共享一次资产读取',
      );
    });

    test('concurrent cold start parses the index exactly once', () async {
      final bundle = gatedBundle()..gate('assets/data/chars_index.json');
      final repo = AssetDictionaryRepository(bundle: bundle);

      final warming = repo.warmUp();
      final lookup = repo.getByChar('笔');
      await Future<void>.delayed(Duration.zero);
      bundle.release('assets/data/chars_index.json');

      await warming;
      expect(await lookup, isNotNull);
      expect(
        bundle.reads.where((key) => key.contains('chars_index')).length,
        1,
        reason: '两个冷启动请求必须共享一次索引解析',
      );
    });

    test('failed shard load throws a distinguishable error and a retry re-reads',
        () async {
      final bundle = gatedBundle();
      bundle.corrupt('assets/data/shards/shard_000.json');
      final repo = AssetDictionaryRepository(bundle: bundle);

      await expectLater(
        repo.getByChar('笔'),
        throwsA(isA<StrokeShardLoadException>()),
        reason: '分片缺失/损坏必须可区分, 而不是静默返回无笔画条目',
      );

      // 修复资产后, 同一仓储实例的"重试"必须真正重新读取。
      bundle.repair('assets/data/shards/shard_000.json');
      final entry = await repo.getByChar('笔');
      expect(entry!.strokes, hasLength(2));
      expect(
        bundle.reads.where((key) => key.contains('shard_000')).length,
        2,
        reason: '失败后的第二次调用应重新加载分片',
      );
    });

    test('shardForChar reports the index shard (or -1 for unknown chars)',
        () async {
      final repo = AssetDictionaryRepository(bundle: gatedBundle());
      expect(await repo.shardForChar('笔'), 0);
      expect(await repo.shardForChar('龘'), -1);
    });
  });
}

/// Asset bundle with per-key gates and a fault injection switch, so tests
/// can hold a load in flight (concurrency) or force it to fail (retry).
class _GatedAssetBundle extends CachingAssetBundle {
  _GatedAssetBundle(this._assets);

  final Map<String, String> _assets;
  final Map<String, Completer<String>> _gates = <String, Completer<String>>{};
  final Set<String> _broken = <String>{};
  final List<String> reads = <String>[];

  void gate(String key) => _gates[key] = Completer<String>();

  void release(String key) => _gates[key]?.complete(_assets[key]!);

  /// Make [key] fail every read until [repair] is called.
  void corrupt(String key) => _broken.add(key);

  void repair(String key) => _broken.remove(key);

  @override
  Future<String> loadString(String key, {bool cache = true}) {
    reads.add(key);
    if (_broken.contains(key)) {
      return Future<String>.error(Exception('injected failure: $key'));
    }
    final gate = _gates[key];
    if (gate != null) {
      return gate.future;
    }
    final value = _assets[key];
    if (value == null) {
      return Future<String>.error(Exception('Missing key: $key'));
    }
    return Future<String>.value(value);
  }

  @override
  Future<ByteData> load(String key) async {
    final string = await loadString(key);
    final bytes = Uint8List.fromList(string.codeUnits);
    return ByteData.view(bytes.buffer);
  }
}

class _FakeAssetBundle extends CachingAssetBundle {
  _FakeAssetBundle(this._assets);

  final Map<String, String> _assets;

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final value = _assets[key];
    if (value == null) {
      throw Exception('Missing key: $key');
    }
    return value;
  }

  @override
  Future<ByteData> load(String key) async {
    final string = await loadString(key);
    final bytes = Uint8List.fromList(string.codeUnits);
    return ByteData.view(bytes.buffer);
  }
}
