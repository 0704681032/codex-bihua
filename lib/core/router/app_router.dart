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

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case home:
        return MaterialPageRoute<void>(
          builder: (_) => const HomePage(),
          settings: settings,
        );
      case detail:
        final args = settings.arguments;
        if (args is! DetailRouteArgs) {
          return _errorRoute('详情页参数缺失');
        }
        return MaterialPageRoute<void>(
          builder: (_) => DetailPage(char: args.char),
          settings: settings,
        );
      default:
        return _errorRoute('页面不存在: ${settings.name}');
    }
  }

  static Route<dynamic> _errorRoute(String message) {
    return MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        body: Center(child: Text(message)),
      ),
    );
  }
}
