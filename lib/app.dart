import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/application/brightness_controller.dart';
import 'core/router/app_router.dart';
import 'core/router/web_url.dart' as web_url;
import 'core/theme/app_theme.dart';

class HanziStrokeApp extends ConsumerStatefulWidget {
  const HanziStrokeApp({super.key});

  @override
  ConsumerState<HanziStrokeApp> createState() => _HanziStrokeAppState();
}

class _HanziStrokeAppState extends ConsumerState<HanziStrokeApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final _UrlSyncObserver _routeObserver;
  late final String _initialRoute;

  /// The detail char currently on top of the navigation stack — the
  /// reference point for deciding what a history event means.
  String? _routedChar;

  @override
  void initState() {
    super.initState();
    // A browser refresh must land on the page shown in the URL, so the
    // initial route is derived from the address bar (web only; no-op
    // elsewhere).
    final char = web_url.readCharFromUrl();
    _initialRoute = char == null || char.isEmpty
        ? AppRouter.home
        : AppRouter.detailRouteFor(char);
    _routedChar = char;

    // Browser back/forward buttons drive in-app navigation.
    _routeObserver = _UrlSyncObserver(onCharChanged: (char) {
      _routedChar = char;
    });
    web_url.setHistoryListener(_onHistoryChanged);
  }

  /// Runs when the user pressed browser back/forward: the URL is already
  /// correct, so only the Flutter navigator has to catch up.
  void _onHistoryChanged(String? char) {
    if (!mounted || char == _routedChar) {
      return;
    }
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      return;
    }

    if (char == null) {
      navigator.pushNamedAndRemoveUntil(AppRouter.home, (route) => false);
      return;
    }
    final routeName = AppRouter.detailRouteFor(char);
    final args = DetailRouteArgs(char: char);
    if (_routedChar == null) {
      navigator.pushNamed(routeName, arguments: args);
    } else {
      navigator.pushReplacementNamed(routeName, arguments: args);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = ref.watch(brightnessProvider);
    final dimOpacity = (1.0 - brightness) * 0.85;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '汉字笔画',
      theme: buildAppTheme(),
      initialRoute: _initialRoute,
      navigatorKey: _navigatorKey,
      navigatorObservers: <NavigatorObserver>[_routeObserver],
      onGenerateRoute: AppRouter.onGenerateRoute,
      builder: (context, child) {
        return Stack(
          children: <Widget>[
            if (child != null) child,
            if (dimOpacity > 0)
              IgnorePointer(
                child: ColoredBox(
                  color: Color.fromRGBO(0, 0, 0, dimOpacity),
                  child: const SizedBox.expand(),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Keeps the address bar in sync with whatever route is on top and
/// reports the current detail char back to the app state.
class _UrlSyncObserver extends NavigatorObserver {
  _UrlSyncObserver({required this.onCharChanged});

  final void Function(String? char) onCharChanged;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _sync(route);

  @override
  void didReplace(
          {Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _sync(newRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _sync(previousRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _sync(previousRoute);

  void _sync(Route<dynamic>? route) {
    final char = AppRouter.charFromRoute(route?.settings.name);
    onCharChanged(char);
    if (char == null) {
      web_url.syncHomeUrl();
    } else {
      web_url.syncDetailUrl(char);
    }
  }
}
