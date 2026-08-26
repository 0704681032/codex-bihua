import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the lazily-loaded detail-page datasets (组词 + 中文释义).
/// These are build artifacts; the assertions pin their contract so a
/// broken regeneration cannot ship silently.
///
/// words.json / definitions_zh.json are build INTERMEDIATES (inputs of
/// tools/split_reference_data.py); the runtime artifact is the
/// references/reference_NNN.json shard family, validated below against
/// the same coverage contract.
void main() {
  late final Map<String, dynamic> words;
  late final Map<String, dynamic> definitions;
  late final Map<String, dynamic> index;
  late final Map<int, String> referenceShards;

  setUpAll(() {
    words = (jsonDecode(
                File('assets/data/words.json').readAsStringSync())
            as Map<dynamic, dynamic>)
        .cast<String, dynamic>();
    definitions = (jsonDecode(
                File('assets/data/definitions_zh.json').readAsStringSync())
            as Map<dynamic, dynamic>)
        .cast<String, dynamic>();
    index = (jsonDecode(
            File('assets/data/chars_index.json').readAsStringSync())
            as Map<dynamic, dynamic>)
        .cast<String, dynamic>();
    referenceShards = <int, String>{};
    for (final file
        in Directory('assets/data/references').listSync().whereType<File>()) {
      final match =
          RegExp(r'reference_(\d+)\.json$').firstMatch(file.path) as RegExpMatch;
      referenceShards[int.parse(match.group(1)!)] = file.readAsStringSync();
    }
  });

  test('words dataset covers most common chars with pinyin', () {
    expect(words.keys.length, greaterThan(5000));
    for (final char in const ['火', '马', '母', '笔', '万', '水', '字']) {
      final list = words[char] as List<dynamic>?;
      expect(list, isNotNull, reason: '$char 应有组词');
      expect(list, isNotEmpty);
      for (final item in list!) {
        final pair = item as List<dynamic>;
        expect(pair, hasLength(2));
        expect(pair[0] as String, contains(char));
        // Tone-marked pinyin from the converter.
        expect(pair[1] as String, isNotEmpty);
      }
    }
    // At least one entry must show a tone mark — proves the numbered
    // pinyin conversion actually ran.
    final toneMarked = words['马']!
        .any((e) => RegExp(r'[āáǎàēéěèīíǐìōóǒòūúǔù]').hasMatch((e as List)[1] as String));
    expect(toneMarked, isTrue);
  });

  test('definitions dataset carries Chinese explanations', () {
    expect(definitions.keys.length, greaterThan(6000));
    for (final char in const ['火', '水', '母', '山']) {
      final text = definitions[char] as String?;
      expect(text, isNotNull, reason: '$char 应有中文释义');
      expect(text!.length, greaterThan(10), reason: '$char 释义过短');
      expect(text.startsWith(char), isFalse,
          reason: '$char 释义不应以重复字头开头');
    }
  });

  test('reference shards keep every char in its index-declared shard', () {
    final shardOf = <String, int>{
      for (final item in index['chars'] as List<dynamic>)
        (item as Map<dynamic, dynamic>)['c'] as String:
            item['s'] as int,
    };

    var charsWithWords = 0;
    var charsWithDefs = 0;
    for (final entry in referenceShards.entries) {
      final decoded =
          jsonDecode(entry.value) as Map<dynamic, dynamic>;
      expect(decoded, isNotEmpty,
          reason: 'reference_${entry.key.toString().padLeft(3, '0')} 不应为空文件');
      for (final char in decoded.keys) {
        expect(shardOf[char], entry.key,
            reason: '字「$char」出现在分片 ${entry.key} 但索引声明为 ${shardOf[char]}');
        final payload = decoded[char] as Map<dynamic, dynamic>;
        if (payload.containsKey('w')) {
          charsWithWords += 1;
          for (final item in payload['w'] as List<dynamic>) {
            final pair = item as List<dynamic>;
            expect(pair, hasLength(2));
            expect(pair[0] as String, contains(char as String));
            expect(pair[1] as String, isNotEmpty);
          }
        }
        if (payload.containsKey('d')) {
          charsWithDefs += 1;
          expect((payload['d'] as String).length, greaterThan(5),
              reason: '字「$char」分片释义过短');
        }
      }
    }

    // Coverage must match the whole-file datasets the shards were built
    // from (6122 chars with words / 7451 with definitions today).
    expect(charsWithWords, greaterThan(5000));
    expect(charsWithDefs, greaterThan(6000));
    expect(referenceShards.length,
        lessThanOrEqualTo(shardOf.values.toSet().length),
        reason: '参考分片数不应超过笔画分片数');
  });

  test('sample chars resolve words+definition from one shard load', () {
    final shardOf = <String, int>{
      for (final item in index['chars'] as List<dynamic>)
        (item as Map<dynamic, dynamic>)['c'] as String: item['s'] as int,
    };
    for (final char in const ['火', '母', '水', '阳']) {
      final shard = referenceShards[shardOf[char]]!;
      final decoded = jsonDecode(shard) as Map<dynamic, dynamic>;
      final payload = decoded[char] as Map<dynamic, dynamic>?;
      expect(payload, isNotNull, reason: '$char 应在参考分片中');
      expect((payload!['w'] as List<dynamic>?) ?? const <dynamic>[], isNotEmpty,
          reason: '$char 应有组词');
      expect(payload['d'] as String?, isNotNull, reason: '$char 应有中文释义');
    }
  });
}
