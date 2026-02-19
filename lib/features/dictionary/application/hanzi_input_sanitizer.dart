class HanziInputSanitizer {
  static const int defaultMaxLength = 20;

  static List<String> sanitize(String raw, {int maxLength = defaultMaxLength}) {
    final result = <String>[];

    for (final rune in raw.runes) {
      if (result.length >= maxLength) {
        break;
      }
      if (_isCjk(rune)) {
        result.add(String.fromCharCode(rune));
      }
    }

    return result;
  }

  static bool _isCjk(int rune) {
    return (rune >= 0x3400 && rune <= 0x4DBF) ||
        (rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0x20000 && rune <= 0x2A6DF) ||
        (rune >= 0x2A700 && rune <= 0x2B73F) ||
        (rune >= 0x2B740 && rune <= 0x2B81F) ||
        (rune >= 0x2B820 && rune <= 0x2CEAF) ||
        (rune >= 0x2CEB0 && rune <= 0x2EBEF);
  }
}
