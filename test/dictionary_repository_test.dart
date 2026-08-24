import 'package:bihua/features/dictionary/data/asset_dictionary_repository.dart';
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
