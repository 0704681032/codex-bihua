import 'package:flutter/foundation.dart';

/// Lightweight performance observation points for the data layer.
///
/// Records asset load timings (index, stroke shards, reference shards)
/// in debug/profile builds; release builds compile this away to no-ops
/// so the logging itself never shows up in production logs. Use these
/// numbers to compare first-detail-open timings before/after a change —
/// they are the reproducible baseline the optimization plan calls for.
class PerfLog {
  PerfLog._();

  static const String _prefix = '[perf]';

  /// True in debug and profile builds only (kReleaseMode is const, so
  /// callers below are tree-shaken in release).
  static bool get enabled => !kReleaseMode;

  /// Log a timed asset event: [name] with optional [elapsed] and [bytes].
  static void event(String name, {Duration? elapsed, int? bytes}) {
    if (!enabled) {
      return;
    }
    final parts = <String>[
      if (elapsed != null) '${elapsed.inMilliseconds}ms',
      if (bytes != null) '${(bytes / 1024).toStringAsFixed(1)}KB',
    ];
    debugPrint('$_prefix $name${parts.isEmpty ? '' : ' (${parts.join(', ')})'}');
  }

  /// Runs [action], logging [name] with its duration and optional byte
  /// count of the loaded payload.
  static Future<T> time<T>(
    String name,
    Future<T> Function() action, {
    int Function(T result)? bytesOf,
  }) async {
    if (!enabled) {
      return action();
    }
    final watch = Stopwatch()..start();
    final result = await action();
    watch.stop();
    event(name, elapsed: watch.elapsed, bytes: bytesOf?.call(result));
    return result;
  }
}
