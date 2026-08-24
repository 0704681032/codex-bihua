/// 播放速度的唯一事实来源：初始状态、自动播放与三档预设共用同一组
/// 数值，避免出现「自动播放时没有任何档位高亮」的错位。
class PlaybackSpeeds {
  const PlaybackSpeeds._();

  static const double slow = 0.7;
  static const double normal = 1.0;
  static const double fast = 2.0;

  /// 详情页打开时的自动播放速度（常速）。
  static const double defaultSpeed = normal;

  static const List<(double, String)> presets = <(double, String)>[
    (slow, '慢速'),
    (normal, '常速'),
    (fast, '快速'),
  ];
}
