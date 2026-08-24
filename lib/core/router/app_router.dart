import 'package:flutter/material.dart';

import '../../features/detail/presentation/detail_page.dart';
import '../../features/home/presentation/home_page.dart';

class DetailRouteArgs {
  const DetailRouteArgs({required this.char});

  final String char;
}

class AppRouter {
  static const String home = '/home';
  static const String detail = '/detail';

  /// Builds a route name that carries the char inside the route string
  /// itself (e.g. `/detail/%E4%B8%87`), so a web refresh can restore the
  /// detail page even though in-memory route arguments are gone.
  static String detailRouteFor(String char) =>
      '$detail/${Uri.encodeComponent(char)}';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final name = settings.name ?? home;

    if (_isDetailRoute(name)) {
      final args = settings.arguments;
      final fromArgs = args is DetailRouteArgs && args.char.trim().isNotEmpty;
      final char = fromArgs ? args.char.trim() : _charFromRouteName(name);
      if (char != null) {
        return MaterialPageRoute<void>(
          builder: (_) => DetailPage(char: char),
          settings: settings,
        );
      }
      return _errorRoute('详情页参数缺失');
    }

    switch (name) {
      case home:
        return MaterialPageRoute<void>(
          builder: (_) => const HomePage(),
          settings: settings,
        );
      default:
        return _errorRoute('页面不存在: $name');
    }
  }

  static bool _isDetailRoute(String name) =>
      name == detail || name.startsWith('$detail/');

  /// Public counterpart of [_charFromRouteName]: derives the detail char
  /// from a route name (null for non-detail routes).
  static String? charFromRoute(String? name) {
    if (name == null || !_isDetailRoute(name)) {
      return null;
    }
    return _charFromRouteName(name);
  }

  /// Accepts `/detail/%E4%B8%87` and `/detail?char=万`.
  static String? _charFromRouteName(String name) {
    if (name.startsWith('$detail/')) {
      final raw = name.substring(detail.length + 1);
      try {
        return Uri.decodeComponent(raw).trim();
      } on FormatException {
        return raw.trim();
      }
    }
    final queryChar = Uri.tryParse(name)?.queryParameters['char'];
    return (queryChar == null || queryChar.trim().isEmpty)
        ? null
        : queryChar.trim();
  }

  static Route<dynamic> _errorRoute(String message) {
    return MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        body: Center(child: Text(message)),
      ),
    );
  }
}
