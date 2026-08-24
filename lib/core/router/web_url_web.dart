import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Callback invoked when the user navigates browser history
/// (back/forward). [char] is the detail char encoded in the resulting
/// URL, or null when the URL points at the home page.
typedef HistoryListener = void Function(String? char);

HistoryListener? _listener;
bool _registered = false;

void setHistoryListener(HistoryListener? listener) {
  _listener = listener;
  if (_registered || listener == null) {
    return;
  }
  _registered = true;
  web.window.addEventListener(
    'popstate',
    ((web.PopStateEvent _) {
      // The browser has already changed the URL; just report it. The
      // Flutter side must not push another history entry while handling
      // this navigation.
      _listener?.call(readCharFromUrl());
    }).toJS,
  );
}

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
  // 与 Web 引擎的写法保持一致(路由名即 hash 路径)。两种格式并存会让
  // 引擎簿记错乱并触发 popstate 风暴, 把刚推入的页面盖掉。
  _pushUrl('#/detail/${Uri.encodeComponent(char)}');
}

void syncHomeUrl() {
  _pushUrl('#/');
}

/// Pushes a history entry so the browser back button stays inside the
/// app instead of leaving it (the old replaceState approach kept only a
/// single entry). Skips when the URL already matches — popstate-driven
/// rebuilds land here with the target already in place, and pushing
/// again would duplicate entries and break further back navigation.
void _pushUrl(String url) {
  if (web.window.location.hash == url) {
    return;
  }
  // The Flutter web engine keeps bookkeeping in history.state (a
  // "serial count"); carry the current object over so its internal
  // assertions stay happy.
  web.window.history.pushState(web.window.history.state, '', url);
}
