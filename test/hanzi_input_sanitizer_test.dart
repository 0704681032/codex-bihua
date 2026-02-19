import 'package:bihua/features/dictionary/application/hanzi_input_sanitizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HanziInputSanitizer', () {
    test('filters non-hanzi and keeps order', () {
      final result = HanziInputSanitizer.sanitize('A笔!顺?3查');
      expect(result, <String>['笔', '顺', '查']);
    });

    test('enforces max length', () {
      final result = HanziInputSanitizer.sanitize('笔顺查询动画字帖', maxLength: 4);
      expect(result.length, 4);
      expect(result, <String>['笔', '顺', '查', '询']);
    });
  });
}
