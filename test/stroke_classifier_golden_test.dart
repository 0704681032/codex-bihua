import 'dart:convert';
import 'dart:io';

import 'package:bihua/features/detail/application/stroke_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression baseline ("样例字集") for the stroke-name pipeline:
///
///   cnchar-order letters (stroke_names.json)
///     -> StrokeClassifier.refineName (slash-pair disambiguation)
///     -> displayed name
///
/// Each entry lists the official sequence from
///《现代汉语通用字笔顺规范》; a stroke may accept several equivalent
/// names (e.g. 弯钩/竖钩, 横斜钩/横折弯钩 differ only by teaching
/// convention or subtle curvature).
void main() {
  final rawNames = File('assets/data/stroke_names.json').readAsStringSync();
  final namesByChar = (jsonDecode(rawNames) as Map<dynamic, dynamic>)
      .cast<String, List<dynamic>>();

  final rawData = File('assets/data/chars_3500.json').readAsStringSync();
  final data = jsonDecode(rawData) as List<dynamic>;
  final strokesByChar = <String, List<List<List<double>>>>{
    for (final entry in data)
      if (entry is Map && entry['char'] is String)
        entry['char'] as String: <List<List<double>>>[
          for (final stroke in (entry['strokes'] as List<dynamic>))
            <List<double>>[
              for (final point in ((stroke as Map)['medianPoints'] as List<dynamic>))
                List<double>.from(point as List<dynamic>),
            ],
        ],
  };

  /// char -> per-stroke accepted names.
  const golden = <String, List<List<String>>>{
    '一': [['横']],
    '二': [['横'], ['横']],
    '十': [['横'], ['竖']],
    '王': [['横'], ['横'], ['竖'], ['横']],
    '木': [['横'], ['竖'], ['撇'], ['捺']],
    '人': [['撇'], ['捺']],
    '口': [['竖'], ['横折'], ['横']],
    '田': [['竖'], ['横折'], ['横'], ['竖'], ['横']],
    '白': [['撇'], ['竖'], ['横折'], ['横'], ['横']],
    '目': [['竖'], ['横折'], ['横'], ['横'], ['横']],
    '火': [['点'], ['撇'], ['撇'], ['捺']],
    '大': [['横'], ['撇'], ['捺']],
    '万': [['横'], ['横折钩'], ['撇']],
    '方': [['点'], ['横'], ['横折钩'], ['撇']],
    '门': [['点'], ['竖'], ['横折钩']],
    '马': [['横折'], ['竖折折钩'], ['横']],
    '水': [['竖钩'], ['横撇'], ['撇'], ['捺']],
    '丁': [['横'], ['竖钩']],
    '小': [['竖钩'], ['撇'], ['点']],
    '我': [
      ['撇'],
      ['横'],
      ['竖钩'],
      ['提'],
      ['斜钩'],
      ['撇'],
      ['点'],
    ],
    '心': [['点'], ['卧钩'], ['点'], ['点']],
    '字': [
      ['点'],
      ['点'],
      ['横钩'],
      ['横撇'],
      ['弯钩', '竖钩'],
      ['横'],
    ],
    '四': [['竖'], ['横折'], ['撇'], ['竖弯'], ['横']],
    '回': [
      ['竖'],
      ['横折'],
      ['竖'],
      ['横折'],
      ['横'],
      ['横'],
    ],
    '与': [['横'], ['竖折折钩'], ['横']],
    '女': [['撇点'], ['撇'], ['横']],
    '又': [['横撇'], ['捺']],
    '九': [['撇'], ['横折弯钩', '横斜钩']],
    '几': [['撇'], ['横折弯钩', '横斜钩']],
    '飞': [
      ['横折弯钩', '横斜钩'],
      ['撇'],
      ['点'],
    ],
    '长': [['撇'], ['横'], ['竖提'], ['捺']],
    '月': [['撇'], ['横折钩'], ['横'], ['横']],
    '及': [['撇'], ['横折折撇'], ['捺']],
    '乃': [['横折折折钩', '横撇弯钩'], ['撇']],
    '母': [['竖折', '竖弯'], ['横折钩'], ['点'], ['横'], ['点']],
  };

  test('dataset + refinement reproduces official stroke names', () {
    final failures = <String>[];
    var checkedStrokes = 0;
    var missingChars = 0;

    golden.forEach((char, expected) {
      final names = namesByChar[char];
      final medians = strokesByChar[char];
      if (names == null || medians == null) {
        missingChars += 1;
        failures.add('$char: 缺少数据 (names=${names != null}, medians=${medians != null})');
        return;
      }

      if (names.length != expected.length) {
        failures.add('$char: 笔数不符 got=${names.join("、")} 官方=${expected.map((e) => e.first).join("、")}');
        return;
      }

      checkedStrokes += names.length;
      for (var i = 0; i < names.length; i += 1) {
        final resolved = StrokeClassifier.refineName(
          names[i] as String,
          medianPoints: medians[i],
          flipYAxis: true,
        );
        if (!expected[i].contains(resolved)) {
          failures.add(
              '$char 第${i + 1}笔: 数据「${names[i]}」消解为「$resolved」,应为「${expected[i].join("/")}」');
        }
      }
    });

    expect(missingChars, 0, reason: '样例字必须全部在数据集中');
    expect(checkedStrokes, greaterThan(100));
    if (failures.isNotEmpty) {
      fail('共检查 $checkedStrokes 笔:\n${failures.join('\n')}');
    }
  });
}
