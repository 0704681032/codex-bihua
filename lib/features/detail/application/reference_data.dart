import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/application/perf_log.dart';
import '../../dictionary/application/dictionary_providers.dart';

/// One suggestion in the 组词举例 grid: a word plus its pinyin (from the
/// CC-CEDICT derived dataset).
class WordCard {
  const WordCard({required this.word, this.pinyin});

  final String word;
  final String? pinyin;
}

/// The reference data one character actually needs on its detail page:
/// its example words and its Chinese definition. Both live in the same
/// per-shard file, so opening a char decodes one ~33 KB payload instead
/// of the two whole-file datasets (~4.9 MB) the app used to parse.
class CharReference {
  const CharReference({this.words = const <WordCard>[], this.definition});

  final List<WordCard> words;
  final String? definition;

  static CharReference fromJson(String char, Map<dynamic, dynamic> json) {
    final rawWords = json['w'];
    final words = <WordCard>[
      if (rawWords is List<dynamic>)
        for (final item in rawWords)
          if (item is List<dynamic> && item.isNotEmpty)
            WordCard(
              word: item[0] as String,
              pinyin: item.length > 1 ? item[1] as String? : null,
            ),
    ];
    final rawDefinition = json['d'];
    return CharReference(
      words: words,
      definition: rawDefinition is String && rawDefinition.isNotEmpty
          ? rawDefinition
          : null,
    );
  }
}

/// Loads and caches `references/reference_NNN.json` shards. Shard ids
/// come from `chars_index.json` via the dictionary repository — the same
/// numbering the stroke shards use, so no asset scanning is needed.
///
/// Concurrent requests for one shard share a single load; failed loads
/// are dropped so a retry re-reads the file.
class ReferenceShardStore {
  ReferenceShardStore({AssetBundle? bundle, String assetBase = 'assets/data/references'})
      : _bundle = bundle ?? rootBundle,
        _assetBase = assetBase;

  final AssetBundle _bundle;
  final String _assetBase;
  final Map<int, Future<Map<String, CharReference>>> _shards =
      <int, Future<Map<String, CharReference>>>{};

  /// A char unknown to the index (shard -1) has no reference data.
  static const int unknownShard = -1;

  Future<Map<String, CharReference>?> shard(int id) {
    if (id == unknownShard) {
      return Future<Map<String, CharReference>?>.value();
    }
    return _shards.putIfAbsent(id, () => _readShard(id));
  }

  Future<Map<String, CharReference>> _readShard(int id) {
    final completer = Completer<Map<String, CharReference>>();
    () async {
      final path = '$_assetBase/reference_${id.toString().padLeft(3, '0')}.json';
      try {
        final raw = await PerfLog.time(
          'reference shard #$id read+decode',
          () => _bundle.loadString(path),
          bytesOf: (raw) => raw.length,
        );
        final decoded = jsonDecode(raw);
        if (decoded is! Map<dynamic, dynamic>) {
          throw FormatException('reference 分片必须是对象: $path');
        }
        completer.complete(
          decoded.map(
            (char, value) => MapEntry(
              char as String,
              CharReference.fromJson(char, value as Map<dynamic, dynamic>),
            ),
          ),
        );
      } on Exception catch (error) {
        // Drop the failed future so a retry re-reads the shard. Log only:
        // reference data is auxiliary — the detail page degrades to its
        // built-in fallbacks instead of failing the whole page.
        debugPrint('reference shard #$id 加载失败: $error');
        _shards.remove(id);
        completer.completeError(error);
      }
    }();
    return completer.future;
  }

  @visibleForTesting
  void debugClearCache() => _shards.clear();
}

/// Shard store override point for tests (fake bundles).
final referenceShardStoreProvider = Provider<ReferenceShardStore>((ref) {
  return ReferenceShardStore();
});

/// Per-character reference data: locates the char's shard through the
/// repository index, loads that one file, and slices out the char's own
/// words + definition. A char missing from its shard (or entirely from
/// the datasets) yields an empty [CharReference]. A shard that fails to
/// LOAD errors here on purpose: the page can distinguish "no data" from
/// "load failed" and show fallback content plus a retry hint.
final referenceForCharProvider =
    FutureProvider.family<CharReference, String>((ref, char) async {
  final shard = await ref
      .watch(dictionaryRepositoryProvider)
      .shardForChar(char);
  if (shard == ReferenceShardStore.unknownShard) {
    return const CharReference();
  }
  final shards = await ref.watch(referenceShardStoreProvider).shard(shard);
  return shards?[char] ?? const CharReference();
});
