import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One suggestion in the 组词举例 grid: a word plus its pinyin (from the
/// CC-CEDICT derived dataset).
class WordCard {
  const WordCard({required this.word, this.pinyin});

  final String word;
  final String? pinyin;
}

// Private whole-file providers keep the multi-MB JSON parsed exactly
// once; the public family providers slice per character. Both assets are
// lazy-loaded on first visit to a detail page — the home page never
// pays for them.

final _wordsDataProvider =
    FutureProvider<Map<String, List<WordCard>>>((ref) async {
  final raw = await rootBundle.loadString('assets/data/words.json');
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return decoded.map((char, list) {
    final cards = <WordCard>[
      for (final item in list as List<dynamic>)
        WordCard(
          word: (item as List<dynamic>)[0] as String,
          pinyin: item[1] as String?,
        ),
    ];
    return MapEntry(char, cards);
  });
});

final wordsForCharProvider =
    FutureProvider.family<List<WordCard>?, String>((ref, char) async {
  final all = await ref.watch(_wordsDataProvider.future);
  return all[char];
});

final _definitionsProvider = FutureProvider<Map<String, String>>((ref) async {
  final raw = await rootBundle.loadString('assets/data/definitions_zh.json');
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return decoded.map((char, text) => MapEntry(char, text as String));
});

final definitionZhProvider =
    FutureProvider.family<String?, String>((ref, char) async {
  final all = await ref.watch(_definitionsProvider.future);
  return all[char];
});
