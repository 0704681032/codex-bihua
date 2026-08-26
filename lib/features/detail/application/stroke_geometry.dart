import 'dart:ui' show Path;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart' show Offset;

import '../../dictionary/domain/character_entry.dart';
import '../../dictionary/domain/stroke_path.dart';
import 'stroke_reveal.dart';

/// One character's parsed + measured stroke geometry.
///
/// The detail page renders one main canvas plus one thumbnail per stroke,
/// and each of those used to re-parse every SVG path and re-run the
/// width-profile ray casting for the whole glyph — O(N²) heavy work for a
/// 20-stroke character. Sharing one [StrokeGeometry] per glyph via
/// [StrokeGeometryCache.of] makes that happen exactly once.
class StrokeGeometry {
  const StrokeGeometry({required this.paths, required this.brushStamps});

  final List<Path> paths;
  final List<List<BrushStamp>> brushStamps;
}

/// Small static LRU of per-character geometry (main canvas + stroke table
/// + a neighbouring character's page typically fit comfortably).
class StrokeGeometryCache {
  const StrokeGeometryCache._();

  static const int _capacity = 16;
  static final Map<String, StrokeGeometry> _cache = <String, StrokeGeometry>{};

  /// Content-verified key: the same char arriving with different stroke
  /// payloads (hydration timing, test fakes) must not reuse stale
  /// geometry. Folds EVERY stroke's SVG into the digest — keying on just
  /// the first/last stroke let mid-glyph changes collide. String
  /// hashCodes are cached per instance, so repeat lookups stay cheap.
  static String keyOf(CharacterEntry entry) {
    final strokes = entry.strokes;
    var digest = strokes.length;
    for (final stroke in strokes) {
      digest = Object.hash(digest, stroke.svgPath);
    }
    return '${entry.char}|$digest';
  }

  static StrokeGeometry of(CharacterEntry entry) {
    final key = keyOf(entry);
    final cached = _cache.remove(key);
    if (cached != null) {
      // Re-insert so the key lands at the tail: eviction must drop the
      // least recently USED entry, not the least recently written one.
      _cache[key] = cached;
      return cached;
    }

    final geometry = _build(entry);
    if (_cache.length >= _capacity) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = geometry;
    return geometry;
  }

  static StrokeGeometry _build(CharacterEntry entry) {
    final paths = <Path>[
      for (final stroke in entry.strokes) parseStrokeSvg(stroke.svgPath),
    ];
    final profiles = StrokeReveal.computeWidthProfiles(entry.strokes, paths);
    final brushStamps = <List<BrushStamp>>[
      for (var i = 0; i < entry.strokes.length; i += 1)
        StrokeReveal.buildBrushStamps(
          _medianOffsetsOf(entry.strokes[i]) ?? const <Offset>[],
          profiles[i],
        ),
    ];
    return StrokeGeometry(paths: paths, brushStamps: brushStamps);
  }

  static List<Offset>? _medianOffsetsOf(StrokePath stroke) {
    final offsets = stroke.medianPoints
        .where((p) => p.length >= 2)
        .map((p) => Offset(p[0], p[1]))
        .toList(growable: false);
    return offsets.length < 2 ? null : offsets;
  }

  @visibleForTesting
  static void debugClear() => _cache.clear();
}
