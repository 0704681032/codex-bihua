import 'package:flutter_riverpod/flutter_riverpod.dart';

/// In-app screen brightness (1.0 = full, 0.3 = dimmest).
///
/// Web/desktop builds cannot change the system backlight, so the value
/// drives a global dimming overlay instead — same trick e-readers use.
class BrightnessController extends StateNotifier<double> {
  BrightnessController() : super(1.0);

  static const double min = 0.3;
  static const double max = 1.0;

  void set(double value) {
    state = value.clamp(min, max).toDouble();
  }
}

final brightnessProvider =
    StateNotifierProvider<BrightnessController, double>(
        (ref) => BrightnessController());
