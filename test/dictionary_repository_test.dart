import 'dart:typed_data';

import 'package:bihua/features/dictionary/data/asset_dictionary_repository.dart';
import 'package:bihua/features/dictionary/domain/filter_criteria.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AssetDictionaryRepository', () {
    final bundle = _FakeAssetBundle(<String, String>{
      'assets/data/chars_3500.json': '''
[
  {
    "char": "笔",
    "pinyin": "bi3",
    "radical": "竹",
    "strokeCount": 10,
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
    "strokeCount": 9,
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

    test('loads entries and can query by char', () async {
      await repo.warmUp();
      final item = await repo.getByChar('笔');
      expect(item, isNotNull);
      expect(item!.pinyin, 'bi3');
      expect(item.strokeCount, 10);
    });

    test('inflates dictionary to minimum size', () async {
      await repo.warmUp();
      final synthetic = await repo.getByChar('一');
      expect(synthetic, isNotNull);
    });

    test('filters by pinyin/radical/stroke count', () async {
      await repo.warmUp();
      final pinyin = await repo.filter(const FilterCriteria(pinyin: 'bi3'));
      expect(pinyin.map((e) => e.char), contains('笔'));

      final radical = await repo.filter(const FilterCriteria(radical: '页'));
      expect(radical.map((e) => e.char), contains('顺'));

      final strokeCount = await repo.filter(const FilterCriteria(strokeCount: 9));
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
