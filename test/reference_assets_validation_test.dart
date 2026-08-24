import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the lazily-loaded detail-page datasets (组词 + 中文释义).
/// These are build artifacts; the assertions pin their contract so a
/// broken regeneration cannot ship silently.
void main() {
  late final Map<String, dynamic> words;
  late final Map<String, dynamic> definitions;

  setUpAll(() {
    words = (jsonDecode(
                File('assets/data/words.json').readAsStringSync())
            as Map<dynamic, dynamic>)
        .cast<String, dynamic>();
    definitions = (jsonDecode(
                File('assets/data/definitions_zh.json').readAsStringSync())
            as Map<dynamic, dynamic>)
        .cast<String, dynamic>();
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
}
