import 'package:bihua/features/detail/application/reference_data.dart';
import 'package:bihua/features/dictionary/application/dictionary_providers.dart';
import 'package:bihua/features/dictionary/data/asset_dictionary_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the per-char reference shard pipeline: one shard file serves
/// every char it contains, shard loads are shared and cached, failures
/// are distinguishable and retryable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAssetBundle bundle;
  late AssetDictionaryRepository repo;
  late ReferenceShardStore store;
  late ProviderContainer container;

  setUp(() {
    bundle = _FakeAssetBundle(<String, String>{
      'assets/data/chars_index.json': '''
{
  "shardSize": 2,
  "chars": [
    {"c": "火", "p": "huo3", "r": "火", "n": 4, "s": 0},
    {"c": "水", "p": "shui3", "r": "水", "n": 4, "s": 0},
    {"c": "木", "p": "mu4", "r": "木", "n": 4, "s": 0},
    {"c": "山", "p": "shan1", "r": "山", "n": 3, "s": 1}
  ]
}
''',
      'assets/data/radicals.json': '["火", "水", "山"]',
      'assets/data/references/reference_000.json': '''
{
  "火": {"w": [["火山","huǒ shān"], ["火苗","huǒ miáo"]], "d": "象形。甲骨文字形象火焰。"},
  "水": {"d": "象形。中间像水脉。"}
}
''',
      'assets/data/references/reference_001.json': '''
{"山": {"w": [["山顶","shān dǐng"]]}}
''',
    });
    repo = AssetDictionaryRepository(bundle: bundle);
    store = ReferenceShardStore(bundle: bundle);
    container = ProviderContainer(overrides: <Override>[
      dictionaryRepositoryProvider.overrideWithValue(repo),
      referenceShardStoreProvider.overrideWithValue(store),
    ]);
  });

  tearDown(() => container.dispose());

  test('referenceForCharProvider slices one shard into per-char data',
      () async {
    final fire = await container.read(referenceForCharProvider('火').future);
    expect(fire.words.map((w) => w.word), ['火山', '火苗']);
    expect(fire.words.first.pinyin, 'huǒ shān');
    expect(fire.definition, startsWith('象形'));

    // 同片第二字不得重复读取分片文件。
    final water = await container.read(referenceForCharProvider('水').future);
    expect(water.words, isEmpty, reason: '「水」只有释义数据');
    expect(water.definition, isNotNull);
    expect(
      bundle.reads.where((key) => key.contains('reference_000')).length,
      1,
      reason: '同片两个字必须共享一次分片读取',
    );

    final mountain = await container.read(referenceForCharProvider('山').future);
    expect(mountain.words.single.word, '山顶');
  });

  test('unknown char yields empty reference without any asset read', () async {
    final result = await container.read(referenceForCharProvider('龘').future);
    expect(result.words, isEmpty);
    expect(result.definition, isNull);
    expect(bundle.reads.where((key) => key.contains('references')), isEmpty);
  });

  test('char missing from its shard payload degrades to empty, not error',
      () async {
    // 「木」在索引分片 0 中, 但参考分片 0 没有它的数据 → 空数据而非报错。
    final result = await container.read(referenceForCharProvider('木').future);
    expect(result.words, isEmpty);
    expect(result.definition, isNull);
  });

  test('missing shard file surfaces an error state for retry', () async {
    bundle.remove('assets/data/references/reference_001.json');
    await expectLater(
      container.read(referenceForCharProvider('山').future),
      throwsA(isA<Exception>()),
      reason: '分片读取失败必须可区分, 页面据此显示降级提示',
    );
    // 修复资产后 refresh 重试应重新读取并成功(对应详情页的重试入口)。
    bundle.put(
      'assets/data/references/reference_001.json',
      '{"山": {"w": [["山顶","shān dǐng"]]}}',
    );
    container.refresh(referenceForCharProvider('山'));
    final mountain = await container.read(referenceForCharProvider('山').future);
    expect(mountain.words.single.word, '山顶');
  });

  test('store drops failed loads so the next call re-reads', () async {
    bundle.remove('assets/data/references/reference_000.json');
    await expectLater(store.shard(0), throwsA(isA<Exception>()));
    expect(
      bundle.reads.where((key) => key.contains('reference_000')).length,
      1,
    );

    bundle.put(
      'assets/data/references/reference_000.json',
      '{"火": {"w": [["火山","huǒ shān"]]}}',
    );
    final shards = await store.shard(0);
    expect(shards!['火']!.words.single.word, '火山');
    expect(
      bundle.reads.where((key) => key.contains('reference_000')).length,
      2,
      reason: '失败后的下一次调用应重新读取分片',
    );
  });
}

class _FakeAssetBundle extends CachingAssetBundle {
  _FakeAssetBundle(this._assets);

  final Map<String, String> _assets;
  final List<String> reads = <String>[];

  void remove(String key) => _assets.remove(key);

  void put(String key, String value) => _assets[key] = value;

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    reads.add(key);
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
