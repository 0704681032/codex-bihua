import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/router/web_url.dart' as web_url;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  web_url.configureEngineUrlStrategy();
  runApp(const ProviderScope(child: HanziStrokeApp()));
}
