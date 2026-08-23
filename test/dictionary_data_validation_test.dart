import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the offline dictionary against stroke-order regressions.
///
/// The app animates strokes by clipping each closed outline along its median
/// polyline (in Make Me a Hanzi's flipped y-up coordinate space), so every
/// entry must satisfy:
///   * `strokeCount` equals the number of strokes,
///   * stroke `order` values form a strict 1..n sequence,
///   * every stroke has a non-empty SVG path and a median with >= 2 points,
///   * all coordinates stay inside the padded viewBox.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late final List<dynamic> entries;

  setUpAll(() async {
    final raw = await rootBundle.loadString('assets/data/chars_3500.json');
    entries = jsonDecode(raw) as List<dynamic>;
  });

  test('dictionary contains a large character set', () {
    expect(entries.length, greaterThanOrEqualTo(9500));
  });

  test('every entry has consistent, ordered, animatable strokes', () {
    var checked = 0;

    for (final item in entries) {
      final entry = item as Map<dynamic, dynamic>;
      final char = entry['char'] as String;
      final strokes = entry['strokes'] as List<dynamic>;
      final declaredCount = entry['strokeCount'] as num;

      expect(char.runes.length, 1, reason: '$char must be a single rune');
      expect(
        strokes,
        isNotEmpty,
        reason: '$char must contain at least one stroke',
      );
      expect(
        declaredCount.toInt(),
        strokes.length,
        reason: '$char strokeCount does not match its stroke list',
      );

      for (var i = 0; i < strokes.length; i += 1) {
        final stroke = strokes[i] as Map<dynamic, dynamic>;
        expect(
          stroke['order'],
          i + 1,
          reason: '$char stroke $i is out of order',
        );

        final svgPath = (stroke['svgPath'] as String?)?.trim() ?? '';
        expect(svgPath, isNotEmpty, reason: '$char stroke ${i + 1} path');

        final medians = stroke['medianPoints'] as List<dynamic>? ?? const [];
        expect(
          medians.length,
          greaterThanOrEqualTo(2),
          reason: '$char stroke ${i + 1} needs a writable median',
        );
        for (final point in medians) {
          final x = (point[0] as num).toDouble();
          final y = (point[1] as num).toDouble();
          expect(x, inInclusiveRange(-300, 1400),
              reason: '$char stroke ${i + 1} median x');
          expect(y, inInclusiveRange(-300, 1400),
              reason: '$char stroke ${i + 1} median y');
        }
      }

      checked += 1;
    }

    expect(checked, entries.length);
  });

  test('medians follow the flipped y-up writing convention', () {
    // 十 writes horizontal first, then the vertical top-to-bottom. In the
    // source's y-up space that means the vertical median starts at a larger
    // y than it ends at; the renderer flips Y before painting.
    final shi = entries.firstWhere((e) => (e as Map)['char'] == '十') as Map;
    final vertical = (shi['strokes'] as List)[1]['medianPoints'] as List;
    final startY = (vertical.first[1] as num).toDouble();
    final endY = (vertical.last[1] as num).toDouble();

    expect(startY, greaterThan(endY),
        reason: 'the vertical stroke starts at the top in y-up space');
    expect(
      (vertical.first[0] as num),
      lessThan(vertical.last[0] as num),
      reason: 'the vertical stroke should drift slightly rightward',
    );
  });
}
