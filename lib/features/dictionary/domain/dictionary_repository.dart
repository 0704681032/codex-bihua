import 'character_entry.dart';
import 'filter_criteria.dart';

/// Thrown when a stroke shard asset is missing or corrupt (or a char is
/// absent from its shard payload). Distinct from a `null` return, which
/// means "char not in the dictionary" — callers can catch this and offer
/// an explicit retry instead of silently showing a stroke-less entry.
class StrokeShardLoadException implements Exception {
  const StrokeShardLoadException(this.shard, this.cause);

  final int shard;
  final Object cause;

  @override
  String toString() => 'StrokeShardLoadException(shard: $shard, cause: $cause)';
}

abstract class DictionaryRepository {
  Future<void> warmUp();

  Future<CharacterEntry?> getByChar(String char);

  /// Shard id owning [char]'s stroke AND reference payloads, or -1 when
  /// the char is unknown. Both shard families share one numbering, so the
  /// reference layer can locate a char's file without rescanning assets.
  Future<int> shardForChar(String char);

  Future<List<CharacterEntry>> searchByChars(List<String> chars);

  Future<List<CharacterEntry>> filter(FilterCriteria criteria);

  Future<List<String>> getAvailablePinyins();

  Future<List<String>> getAvailableRadicals();

  Future<List<int>> getAvailableStrokeCounts();

  Future<List<CharacterEntry>> getExamples({int limit = 8});

  Future<List<CharacterEntry>> getCommonConfusables({int limit = 12});
}
