import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/asset_dictionary_repository.dart';
import '../domain/character_entry.dart';
import '../domain/dictionary_repository.dart';

final dictionaryRepositoryProvider = Provider<DictionaryRepository>((ref) {
  return AssetDictionaryRepository();
});

final dictionaryWarmUpProvider = FutureProvider<void>((ref) async {
  await ref.watch(dictionaryRepositoryProvider).warmUp();
});

final characterByCharProvider = FutureProvider.family<CharacterEntry?, String>((ref, char) {
  return ref.watch(dictionaryRepositoryProvider).getByChar(char);
});

final exampleCharactersProvider = FutureProvider<List<CharacterEntry>>((ref) {
  return ref.watch(dictionaryRepositoryProvider).getExamples();
});

final confusableCharactersProvider = FutureProvider<List<CharacterEntry>>((ref) {
  return ref.watch(dictionaryRepositoryProvider).getCommonConfusables();
});

final pinyinFilterOptionsProvider = FutureProvider<List<String>>((ref) {
  return ref.watch(dictionaryRepositoryProvider).getAvailablePinyins();
});

final radicalFilterOptionsProvider = FutureProvider<List<String>>((ref) {
  return ref.watch(dictionaryRepositoryProvider).getAvailableRadicals();
});

final strokeCountFilterOptionsProvider = FutureProvider<List<int>>((ref) {
  return ref.watch(dictionaryRepositoryProvider).getAvailableStrokeCounts();
});
