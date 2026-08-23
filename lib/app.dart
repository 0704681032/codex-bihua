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
  late final String _initialRoute;

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
