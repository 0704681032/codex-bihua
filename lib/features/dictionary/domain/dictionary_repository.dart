import 'character_entry.dart';
import 'filter_criteria.dart';

abstract class DictionaryRepository {
  Future<void> warmUp();

  Future<CharacterEntry?> getByChar(String char);

  Future<List<CharacterEntry>> searchByChars(List<String> chars);

  Future<List<CharacterEntry>> filter(FilterCriteria criteria);

  Future<List<String>> getAvailablePinyins();

  Future<List<String>> getAvailableRadicals();

  Future<List<int>> getAvailableStrokeCounts();

  Future<List<CharacterEntry>> getExamples({int limit = 8});

  Future<List<CharacterEntry>> getCommonConfusables({int limit = 12});
}
