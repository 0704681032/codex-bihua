import 'dart:js_interop';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

/// Callback invoked when the user navigates browser history
/// (back/forward). [char] is the detail char encoded in the resulting
/// URL, or null when the URL points at the home page.
typedef HistoryListener = void Function(String? char);

HistoryListener? _listener;
bool _registered = false;

/// 让框架默认安装的 URL 策略（SingleEntryStrategy，history.state 标记
/// {"flutter":true}）退场：它会把外部片段导航（改 hash/点外链）回滚到
/// 自己的条目，与本应用的手动 URL 管理（pushState + popstate/hashchange
/// 监听）冲突。置 null 后 URL 完全归本文件管理。
/// 必须在 runApp 之前调用。
void configureEngineUrlStrategy() {
  setUrlStrategy(null);
}

void setHistoryListener(HistoryListener? listener) {
  _listener = listener;
  if (_registered || listener == null) {
    return;
  }
  _registered = true;
  void handleHistoryEvent(web.Event _) {
    // The browser has already changed the URL; just report it. The
    // Flutter side must not push another history entry while handling
    // this navigation.
    _listener?.call(readCharFromUrl());
  }

  final handler = handleHistoryEvent.toJS;
  web.window.addEventListener('popstate', handler);
  // popstate 只在历史遍历（后退/前进）时触发；在地址栏里改 hash、点外链
  // 或脚本赋值 location.hash 属于片段导航，只触发 hashchange——不监听它
  // 的话，应用运行中改 URL 就不会路由（冷启动和站内导航不受影响）。
  // 历史遍历若伴随片段变化会 popstate、hashchange 连发两次，由应用侧
  // 的目标字去重（第二次调用时路由已就位，直接跳过）。
  web.window.addEventListener('hashchange', handler);
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
