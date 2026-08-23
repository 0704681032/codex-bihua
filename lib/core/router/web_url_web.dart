import 'package:web/web.dart' as web;

String? readCharFromUrl() {
  final uri = Uri.tryParse(web.window.location.href);
  if (uri == null) {
    return null;
  }

  // Hash-first: #/char/万 keeps deep links working without server rewrites.
  final rawFragment = uri.fragment.replaceFirst(RegExp(r'^/+'), '');
  final fragment = Uri.tryParse(rawFragment);
  if (fragment != null) {
    final fromFragmentPath = _charFromSegment(fragment.pathSegments);
    if (fromFragmentPath != null) {
      return fromFragmentPath;
    }
    final fromQuery = fragment.queryParameters['char']?.trim();
    if (fromQuery != null && fromQuery.isNotEmpty) {
      return fromQuery;
    }
  }

  return _charFromSegment(uri.pathSegments) ??
      _nonEmpty(uri.queryParameters['char']);
}

String? _charFromSegment(List<String> segments) {
  for (var i = 0; i < segments.length - 1; i += 1) {
    if (segments[i] == 'char' || segments[i] == 'detail') {
      return _nonEmpty(segments[i + 1]);
    }
  }
  return null;
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

void syncDetailUrl(String char) {
  _replaceUrl('#/char/${Uri.encodeComponent(char)}');
}

void syncHomeUrl() {
  _replaceUrl('#/');
}

/// Rewrites only the URL. The Flutter web engine stores its own bookkeeping
/// in history.state (a "serial count"); passing null would trip its
/// "unexpected null history state" assertion, so the existing state object
/// is carried over untouched.
void _replaceUrl(String url) {
  web.window.history.replaceState(web.window.history.state, '', url);
}
