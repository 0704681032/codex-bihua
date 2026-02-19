class FilterCriteria {
  const FilterCriteria({
    this.pinyin,
    this.radical,
    this.strokeCount,
  });

  final String? pinyin;
  final String? radical;
  final int? strokeCount;

  bool get isEmpty => pinyin == null && radical == null && strokeCount == null;

  FilterCriteria copyWith({
    String? pinyin,
    String? radical,
    int? strokeCount,
    bool clearPinyin = false,
    bool clearRadical = false,
    bool clearStrokeCount = false,
  }) {
    return FilterCriteria(
      pinyin: clearPinyin ? null : (pinyin ?? this.pinyin),
      radical: clearRadical ? null : (radical ?? this.radical),
      strokeCount: clearStrokeCount ? null : (strokeCount ?? this.strokeCount),
    );
  }
}
