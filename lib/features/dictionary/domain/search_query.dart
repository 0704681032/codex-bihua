import 'filter_criteria.dart';

class SearchQuery {
  const SearchQuery({
    required this.rawText,
    required this.normalizedChars,
    this.filters = const FilterCriteria(),
  });

  final String rawText;
  final List<String> normalizedChars;
  final FilterCriteria filters;

  bool get hasChars => normalizedChars.isNotEmpty;
}
