import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../core/application/brightness_controller.dart';
import '../../../core/router/app_router.dart';
import '../../../core/router/web_url.dart' as web_url;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hanzi_search_bar.dart';
import '../../../core/widgets/main_bottom_nav.dart';
import '../../dictionary/application/dictionary_providers.dart';
import '../../dictionary/application/hanzi_input_sanitizer.dart';
import '../../dictionary/domain/character_entry.dart';
import '../application/stroke_player_controller.dart';
import '../application/stroke_player_state.dart';
import 'widgets/stroke_canvas.dart';

class DetailPage extends ConsumerStatefulWidget {
  const DetailPage({super.key, required this.char});

  final String char;

  @override
  ConsumerState<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends ConsumerState<DetailPage> {
  static const double _autoPlaySpeed = 2.4;
  static const Map<String, List<String>> _presetWords = <String, List<String>>{
    '母': <String>['母亲', '字母', '母子', '母体', '母猪', '酵母'],
    '笔': <String>['毛笔', '画笔', '笔顺', '笔记', '笔画', '执笔'],
    '火': <String>['火山', '火苗', '火候', '火种', '灭火', '火车'],
    '马': <String>['马匹', '马术', '马车', '马上', '马步', '马力'],
    '万': <String>['万千', '万物', '万里', '万象', '万岁', '百万'],
  };

  /// Real per-word pinyin for the preset words, so the grid never shows
  /// fabricated readings.
  static const Map<String, String> _presetWordPinyins = <String, String>{
    '万千': 'wàn qiān',
    '万物': 'wàn wù',
    '万里': 'wàn lǐ',
    '万象': 'wàn xiàng',
    '万岁': 'wàn suì',
    '百万': 'bǎi wàn',
    '母亲': 'mǔ qīn',
    '字母': 'zì mǔ',
    '母子': 'mǔ zǐ',
    '母体': 'mǔ tǐ',
    '母猪': 'mǔ zhū',
    '酵母': 'jiào mǔ',
    '毛笔': 'máo bǐ',
    '画笔': 'huà bǐ',
    '笔顺': 'bǐ shùn',
    '笔记': 'bǐ jì',
    '笔画': 'bǐ huà',
    '执笔': 'zhí bǐ',
    '火山': 'huǒ shān',
    '火苗': 'huǒ miáo',
    '火候': 'huǒ hou',
    '火种': 'huǒ zhǒng',
    '灭火': 'miè huǒ',
    '火车': 'huǒ chē',
    '马匹': 'mǎ pī',
    '马术': 'mǎ shù',
    '马车': 'mǎ chē',
    '马上': 'mǎ shàng',
    '马步': 'mǎ bù',
    '马力': 'mǎ lì',
  };

  late final TextEditingController _searchController;
  FlutterTts? _tts;
  final String _playerSessionId = UniqueKey().toString();
  String? _autoPlayStartedKey;
  bool _ttsInitializing = true;
  bool _ttsAvailable = false;

  bool _basicInfoExpanded = true;
  bool _strokeTableExpanded = true;
  bool _explanationExpanded = true;
  bool _wordsExpanded = true;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.char);
    // Keep the address bar in sync so a refresh reopens this exact page.
    web_url.syncDetailUrl(widget.char);
    _initTts();
  }

  @override
  void didUpdateWidget(covariant DetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.char != widget.char) {
      _searchController.text = widget.char;
      web_url.syncDetailUrl(widget.char);
      unawaited(_stopSpeaking());
    }
  }

  @override
  void dispose() {
    unawaited(_stopSpeaking());
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initTts() async {
    try {
      final tts = FlutterTts();

      // Configure each setting on its own: one unsupported call must not
      // disable voice playback entirely (platforms differ here).
      try {
        await tts.setLanguage('zh-CN');
      } catch (_) {
        try {
          await tts.setLanguage('zh');
        } catch (_) {}
      }
      try {
        await tts.setSpeechRate(0.45);
      } catch (_) {}
      try {
        await tts.setPitch(1.0);
      } catch (_) {}

      tts.setErrorHandler((message) {
        if (mounted && message.isNotEmpty) {
          _showSnack('语音播放失败，请稍后重试');
        }
      });

      if (!mounted) {
        return;
      }
      setState(() {
        _tts = tts;
        _ttsAvailable = true;
        _ttsInitializing = false;
      });
    } on MissingPluginException {
      if (mounted) {
        setState(() => _ttsInitializing = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _ttsInitializing = false);
      }
    }
  }

  Future<void> _stopSpeaking() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _onBottomNavTap(int index) {
    if (index == 0) {
      Navigator.of(context)
          .pushNamedAndRemoveUntil(AppRouter.home, (route) => false);
      return;
    }
    _showSnack('当前首版仅开放首页与详情页');
  }

  Future<void> _searchAndOpen(String text) async {
    final chars = HanziInputSanitizer.sanitize(text, maxLength: 20);
    if (chars.isEmpty) {
      _showSnack('请输入汉字');
      return;
    }

    final target = chars.first;
    final entry =
        await ref.read(dictionaryRepositoryProvider).getByChar(target);
    if (!mounted) {
      return;
    }
    if (entry == null) {
      _showSnack('字库中暂未收录该汉字');
      return;
    }

    Navigator.of(context).pushReplacementNamed(
      AppRouter.detailRouteFor(target),
      arguments: DetailRouteArgs(char: target),
    );
  }

  Future<void> _speakText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    if (!_ttsAvailable || _tts == null) {
      _showSnack(
          _ttsInitializing ? '语音初始化中，请稍候再试' : '当前设备暂不支持语音播放');
      return;
    }

    // The web plugin silently ignores speak() while its internal state is
    // still "playing" right after stop(); give cancel a beat to settle.
    try {
      await _tts!.stop();
      await Future<void>.delayed(const Duration(milliseconds: 60));
    } catch (_) {}

    try {
      // Web resolves with null on success, desktop/other return 1; only a
      // definitive non-1 value (never null) counts as failure.
      final result = await _tts!.speak(trimmed);
      if (result != null && result != 1) {
        _showSnack('语音播放失败，请稍后重试');
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() => _ttsAvailable = false);
      }
      _showSnack('当前设备暂不支持语音播放');
    } catch (_) {
      _showSnack('语音播放失败，请稍后重试');
    }
  }

  Future<void> _speakCharacter(CharacterEntry entry) async {
    final pinyin = entry.pinyin.trim();
    final text = pinyin.isEmpty ? entry.char : '${entry.char}，$pinyin';
    await _speakText(text);
  }

  @override
  Widget build(BuildContext context) {
    final characterAsync = ref.watch(characterByCharProvider(widget.char));

    return Scaffold(
      appBar: AppBar(
        title: Text('「${widget.char}」的笔顺详情'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: () => _showSnack('分享功能将在后续版本开放'),
          ),
        ],
      ),
      body: characterAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('加载失败: $error')),
        data: (entry) {
          if (entry == null) {
            return const Center(child: Text('未找到该汉字'));
          }

          final key = StrokePlayerKey(
            sessionId: _playerSessionId,
            char: entry.char,
            totalStrokes: entry.strokes.length,
          );
          final provider = strokePlayerProvider(key);
          final playerState = ref.watch(provider);
          final player = ref.read(provider.notifier);
          final autoPlayKey =
              '${key.sessionId}:${entry.char}:${entry.strokes.length}';
          if (_autoPlayStartedKey != autoPlayKey) {
            _autoPlayStartedKey = autoPlayKey;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }
              player.setSpeed(_autoPlaySpeed);
              if (!ref.read(provider).isPlaying) {
                player.togglePlay();
              }
            });
          }

          final strokeNames = _resolveStrokeNames(entry);
          final words = _resolvePresetWords(entry);
          final definitions = _resolveDefinitions(entry);

          return SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      HanziSearchBar(
                        controller: _searchController,
                        hintText: '输入汉字查看笔顺',
                        onSearchTap: () =>
                            _searchAndOpen(_searchController.text),
                        onSubmitted: _searchAndOpen,
                        onCameraTap: () => _showSnack('拍照识字将在后续版本开放'),
                      ),
                      const SizedBox(height: 10),
                      _buildTopActionBar(entry),
                      const SizedBox(height: 10),
                      _SectionCard(
                        title: '笔顺动画',
                        expanded: true,
                        showToggle: false,
                        child: Column(
                          children: <Widget>[
                            StrokeCanvas(
                                entry: entry, playerState: playerState),
                            const SizedBox(height: 10),
                            _buildPlayerControls(playerState, player),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _SectionCard(
                        title: '基本信息',
                        expanded: _basicInfoExpanded,
                        onToggle: () {
                          setState(() {
                            _basicInfoExpanded = !_basicInfoExpanded;
                          });
                        },
                        child: _buildBasicInfo(entry, strokeNames),
                      ),
                      const SizedBox(height: 10),
                      _SectionCard(
                        title: '笔顺表：共${entry.strokeCount}笔',
                        expanded: _strokeTableExpanded,
                        onToggle: () {
                          setState(() {
                            _strokeTableExpanded = !_strokeTableExpanded;
                          });
                        },
                        child: _buildStrokeTable(entry, strokeNames),
                      ),
                      const SizedBox(height: 10),
                      _SectionCard(
                        title: '汉字解释',
                        expanded: _explanationExpanded,
                        onToggle: () {
                          setState(() {
                            _explanationExpanded = !_explanationExpanded;
                          });
                        },
                        child: _buildExplanationBlock(entry, definitions),
                      ),
                      const SizedBox(height: 10),
                      _SectionCard(
                        title: '组词举例',
                        expanded: _wordsExpanded,
                        onToggle: () {
                          setState(() {
                            _wordsExpanded = !_wordsExpanded;
                          });
                        },
                        child:
                            _buildWordsGrid(entry, words),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: AppBottomNavigationBar(
        currentIndex: 0,
        onTap: _onBottomNavTap,
      ),
    );
  }

  Widget _buildTopActionBar(CharacterEntry entry) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFDCDC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          IconButton(
            onPressed: () => _speakCharacter(entry),
            icon: const Icon(
              Icons.volume_up_rounded,
              color: AppPalette.primaryBrown,
              size: 32,
            ),
          ),
          IconButton(
            onPressed: () => _showSnack('会员能力展示占位'),
            icon: const Icon(
              Icons.diamond_rounded,
              color: Colors.redAccent,
              size: 30,
            ),
          ),
          IconButton(
            onPressed: _showBrightnessSheet,
            icon: const Icon(
              Icons.wb_sunny_outlined,
              color: AppPalette.textMain,
              size: 31,
            ),
          ),
          IconButton(
            onPressed: () => _showSnack('田字格模式切换将在后续版本开放'),
            icon: const Icon(
              Icons.copy_all_outlined,
              color: AppPalette.textMain,
              size: 30,
            ),
          ),
          IconButton(
            onPressed: () => _showSnack('设置面板将在后续版本开放'),
            icon: const Icon(
              Icons.settings_rounded,
              color: AppPalette.textMain,
              size: 31,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicInfo(CharacterEntry entry, List<String> strokeNames) {
    final infoItems = <_InfoItem>[
      _InfoItem(label: '笔画数', value: '${entry.strokeCount}'),
      _InfoItem(label: '结构', value: _guessStructure(entry.strokeCount)),
      _InfoItem(label: '部首', value: entry.radical),
      _InfoItem(label: '造字法', value: _guessFormation(entry)),
      _InfoItem(label: '繁体', value: entry.char),
      _InfoItem(label: '五行', value: _guessElement(entry.radical)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            const SizedBox(
              width: 68,
              child: Text(
                '拼音：',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            _PinyinChip(
              pinyin: entry.pinyin,
              onTap: () => _speakCharacter(entry),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Divider(color: Color(0xFFD6BEBE), height: 1),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(
              width: 68,
              child: Text(
                '笔画：',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: Text(
                strokeNames.join('、'),
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Divider(color: Color(0xFFD6BEBE), height: 1),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: infoItems.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.7,
          ),
          itemBuilder: (context, index) {
            final item = infoItems[index];
            return _InfoCell(item: item);
          },
        ),
      ],
    );
  }

  Widget _buildStrokeTable(CharacterEntry entry, List<String> strokeNames) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fewer columns on narrow screens keeps each preview readable.
        final columns = constraints.maxWidth >= 430 ? 4 : 3;
        const spacing = 10.0;
        final width =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: 12,
          children: List<Widget>.generate(entry.strokes.length, (index) {
            final name = index < strokeNames.length
                ? strokeNames[index]
                : '第${index + 1}笔';
            return SizedBox(
              width: width,
              child: _StrokeTile(
                index: index,
                name: name,
                entry: entry,
                tileSize: width,
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildExplanationBlock(
    CharacterEntry entry,
    List<String> definitions,
  ) {
    final explanation = _buildExplanation(entry, _resolvePresetWords(entry));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Align(
          alignment: Alignment.centerLeft,
          child: _PinyinChip(
            pinyin: entry.pinyin,
            onTap: () => _speakCharacter(entry),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '• $explanation',
          style: const TextStyle(fontSize: 17, height: 1.65),
        ),
        if (definitions.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          for (final definition in definitions)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '• $definition',
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.55,
                  color: Color(0xFF5A4A4A),
                ),
              ),
            ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: () => _showEncyclopediaSheet(entry),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.primaryBrown,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.menu_book_rounded),
            label: Text(
              '「${entry.char}」字的百科解释',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWordsGrid(CharacterEntry entry, List<String>? words) {
    if (words == null || words.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(
            '词库建设中，敬请期待',
            style: TextStyle(fontSize: 15, color: Color(0xFF9A8A8A)),
          ),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: words.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 10,
        childAspectRatio: 1.35,
      ),
      itemBuilder: (context, index) {
        final word = words[index];
        final pinyin = _wordPinyin(word);
        return InkWell(
          onTap: () => _speakText(word),
          borderRadius: BorderRadius.circular(10),
          child: Ink(
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7F7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFD6BEBE)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (pinyin != null)
                    Text(
                      pinyin,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF7B6565),
                        fontSize: 13,
                      ),
                    ),
                  if (pinyin != null) const SizedBox(height: 6),
                  Text(
                    word,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showBrightnessSheet() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final brightness = ref.watch(brightnessProvider);
          final controller = ref.read(brightnessProvider.notifier);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(Icons.nightlight_round,
                          size: 20, color: AppPalette.textMain),
                      const SizedBox(width: 8),
                      const Text(
                        '屏幕亮度',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Text(
                        '${(brightness * 100).round()}%',
                        style: const TextStyle(
                            fontSize: 15, color: AppPalette.primaryBrown),
                      ),
                    ],
                  ),
                  Slider(
                    value: brightness,
                    min: BrightnessController.min,
                    max: BrightnessController.max,
                    divisions: 14,
                    label: '${(brightness * 100).round()}%',
                    onChanged: controller.set,
                  ),
                  const Text(
                    '网页版通过页面遮罩调节明暗，保护夜间视力',
                    style: TextStyle(fontSize: 12, color: Color(0xFF9A8A8A)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlayerControls(
    StrokePlayerState state,
    StrokePlayerController controller,
  ) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _ActionButton(
                icon: Icons.chevron_left_rounded,
                label: '上一笔',
                onTap: controller.previousStroke,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionButton(
                icon: state.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                label: state.isPlaying ? '暂停' : '播放',
                onTap: controller.togglePlay,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionButton(
                icon: Icons.chevron_right_rounded,
                label: '下一笔',
                onTap: controller.nextStroke,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            for (final entry in <double, String>{
              1.4: '慢速',
              2.4: '常速',
              3.2: '快速',
            }.entries)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(entry.value),
                  selected:
                      (state.speed - entry.key).abs() < 0.01,
                  onSelected: (_) => controller.setSpeed(entry.key),
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
      ],
    );
  }

  List<String> _resolveStrokeNames(CharacterEntry entry) {
    if (entry.char == '母' && entry.strokeCount == 5) {
      return const <String>['竖折/竖弯', '横折钩', '点', '横', '点'];
    }

    return <String>[
      for (var i = 0; i < entry.strokes.length; i += 1)
        _classifyStroke(entry, entry.strokes[i].medianPoints, i + 1),
    ];
  }

  /// Classifies a stroke by walking its median polyline in *screen*
  /// coordinates (the asset data is y-up, so flip when needed) and
  /// splitting it into direction runs.
  String _classifyStroke(
    CharacterEntry entry,
    List<List<double>> medianPoints,
    int order,
  ) {
    if (medianPoints.length < 2) {
      return '第$order笔';
    }

    final points = medianPoints
        .where((p) => p.length >= 2)
        .map((p) => Offset(p[0], p[1]))
        .toList(growable: false);
    if (points.length < 2 || _polylineLength(points) <= 0) {
      return '第$order笔';
    }

    // Asset medians use a y-up viewBox; convert to screen space (y-down)
    // so all direction math matches what the user sees.
    final screenPoints = entry.flipYAxis
        ? <Offset>[
            for (final p in points) Offset(p.dx, _viewBoxSize - p.dy),
          ]
        : points;

    final segments =
        _splitIntoRuns(screenPoints).where(_isSignificantSegment).toList();
    if (segments.isEmpty) {
      return '第$order笔';
    }

    final names = <String>[for (final s in segments) _segmentName(s)];
    if (_totalLength(segments) < 100) {
      return '点';
    }
    if (names.length == 1) {
      return names.first;
    }
    return _combineSegments(names, segments, screenPoints);
  }

  static const double _viewBoxSize = 1024;

  Offset _delta(Offset a, Offset b) => b - a;

  double _polylineLength(List<Offset> points) {
    var sum = 0.0;
    for (var i = 0; i + 1 < points.length; i += 1) {
      sum += _delta(points[i], points[i + 1]).distance;
    }
    return sum;
  }

  double _totalLength(List<List<Offset>> segments) {
    var sum = 0.0;
    for (final s in segments) {
      sum += _polylineLength(s);
    }
    return sum;
  }

  /// Splits the polyline at direction changes larger than ~40 degrees,
  /// merging tiny wobble into the surrounding run.
  List<List<Offset>> _splitIntoRuns(List<Offset> points) {
    final runs = <List<Offset>>[<Offset>[points.first]];

    for (var i = 1; i < points.length - 1; i += 1) {
      final prev = points[i - 1];
      final cur = points[i];
      final next = points[i + 1];
      final turn = _angleBetween(prev, cur, next);
      if (turn > 0.7 && _delta(prev, cur).distance > 24) {
        runs.add(<Offset>[cur]);
      } else {
        runs.last.add(cur);
      }
    }
    runs.last.add(points.last);
    return runs;
  }

  double _angleBetween(Offset a, Offset b, Offset c) {
    final u = _delta(a, b);
    final v = _delta(b, c);
    final lu = u.distance;
    final lv = v.distance;
    if (lu == 0 || lv == 0) {
      return 0;
    }
    final cos = (u.dx * v.dx + u.dy * v.dy) / (lu * lv);
    return math.acos(cos.clamp(-1.0, 1.0).toDouble());
  }

  bool _isSignificantSegment(List<Offset> segment) =>
      _polylineLength(segment) > 30;

  String _segmentName(List<Offset> segment) {
    final start = segment.first;
    final end = segment.last;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final absDx = dx.abs();
    final absDy = dy.abs();

    if (absDx > absDy * 2.2) {
      return dx > 0 ? '横' : '提';
    }
    if (absDy > absDx * 2.2) {
      return dy > 0 ? '竖' : '竖钩';
    }
    if (dy > 0) {
      return dx > 0 ? '捺' : '撇';
    }
    return dx > 0 ? '提' : '平撇';
  }

  /// Maps the leading runs to standard compound stroke names. A trailing
  /// flick that rises against the main downward flow marks a "钩".
  String _combineSegments(
    List<String> names,
    List<List<Offset>> segments,
    List<Offset> allPoints,
  ) {
    final first = names.first;
    final second = names.length > 1 ? names[1] : '';
    final hasHook = _endsWithUpwardFlick(allPoints);

    if (first == '横') {
      if (second == '竖') {
        return hasHook ? '横折钩' : '横折';
      }
      if (second == '撇' || second == '平撇') {
        return hasHook ? '横折钩' : '横撇';
      }
      if (second == '捺') {
        return '横折';
      }
    }
    if ((first == '竖') && (second == '横' || second == '提')) {
      if (hasHook) {
        return '竖弯钩';
      }
      return second == '提' ? '竖提' : '竖折';
    }
    if (first == '竖' && second == '竖钩') {
      return '竖钩';
    }
    if (first == '撇' && (second == '横' || second == '提')) {
      return '撇折';
    }
    if (first == '撇' && second == '点') {
      return '撇点';
    }
    return first + second;
  }

  /// True when the stroke's final samples move noticeably upward against
  /// the overall downward flow — the little hook at the end of 横折钩 /
  /// 竖弯钩 style strokes.
  bool _endsWithUpwardFlick(List<Offset> points) {
    if (points.length < 3) {
      return false;
    }
    var rise = 0.0;
    for (var i = points.length - 3; i < points.length - 1; i += 1) {
      rise += points[i].dy - points[i + 1].dy; // screen y decreasing = up
    }
    return rise < -18;
  }

  /// Curated real words win; otherwise there is nothing honest to show —
  /// the data asset only carries English definitions, so fabricating
  /// words/pinyin would repeat the old bug.
  List<String>? _resolvePresetWords(CharacterEntry entry) {
    final preset = _presetWords[entry.char];
    if (preset == null || preset.isEmpty) {
      return null;
    }
    return preset;
  }

  String? _wordPinyin(String word) => _presetWordPinyins[word];

  List<String> _resolveDefinitions(CharacterEntry entry) {
    return entry.examples
        .expand((item) => item.split(';'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  String _buildExplanation(CharacterEntry entry, List<String>? words) {
    final wordText = words == null || words.isEmpty
        ? ''
        : words.take(4).join('、');
    final pinyin = entry.pinyin.trim();
    return '「${entry.char}」读作${pinyin.isEmpty ? '（待补充）' : pinyin}。'
        '部首为${entry.radical}，共${entry.strokeCount}画。'
        '${wordText.isEmpty ? '' : '常见组词：$wordText。'}';
  }

  String _guessStructure(int strokeCount) {
    if (strokeCount <= 4) {
      return '独体字';
    }
    if (strokeCount <= 8) {
      return '上下结构';
    }
    return '左右结构';
  }

  String _guessFormation(CharacterEntry entry) {
    if (entry.synthetic) {
      return '待补充';
    }
    if (entry.strokeCount <= 5) {
      return '象形';
    }
    return '形声';
  }

  String _guessElement(String radical) {
    const map = <String, String>{
      '氵': '水',
      '水': '水',
      '火': '火',
      '灬': '火',
      '木': '木',
      '金': '金',
      '钅': '金',
      '土': '土',
      '石': '土',
      '日': '火',
      '月': '木',
      '口': '木',
    };
    return map[radical] ?? '待补充';
  }

  void _showEncyclopediaSheet(CharacterEntry entry) {
    final strokeNames = _resolveStrokeNames(entry);
    final definitions = _resolveDefinitions(entry);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          maxChildSize: 0.85,
          builder: (context, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: <Widget>[
              Center(
                child: Text(
                  entry.char,
                  style: const TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
              Center(
                child: Text(
                  entry.pinyin,
                  style: const TextStyle(
                    fontSize: 18,
                    color: AppPalette.primaryBrown,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _infoRow('部首', entry.radical),
              _infoRow('笔画数', '${entry.strokeCount}'),
              _infoRow(
                '笔顺',
                strokeNames.isEmpty ? '待补充' : strokeNames.join(' → '),
              ),
              const Divider(height: 22),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '释义',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 6),
              if (definitions.isEmpty)
                const Text('暂无释义数据', style: TextStyle(fontSize: 15))
              else
                for (final definition in definitions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• $definition',
                        style: const TextStyle(fontSize: 15, height: 1.5)),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Text(
              '$label：',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 15)),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.expanded,
    required this.child,
    this.onToggle,
    this.showToggle = true,
  });

  final String title;
  final bool expanded;
  final Widget child;
  final VoidCallback? onToggle;
  final bool showToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.surfacePink,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: <Widget>[
          InkWell(
            onTap: onToggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.circle, size: 11, color: Color(0xFF8E6464)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textMain,
                      ),
                    ),
                  ),
                  if (showToggle)
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 32,
                      color: AppPalette.textMain,
                    ),
                ],
              ),
            ),
          ),
          if (expanded) ...<Widget>[
            const Divider(height: 1, color: Color(0xFFD8C2C2)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: child,
            ),
          ],
        ],
      ),
    );
  }
}

class _PinyinChip extends StatelessWidget {
  const _PinyinChip({required this.pinyin, required this.onTap});

  final String pinyin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: AppPalette.primaryBrown,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.volume_up_rounded, color: Colors.white, size: 28),
            const SizedBox(width: 8),
            Text(
              pinyin.trim().isEmpty ? '拼音待补充' : pinyin.trim(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoItem {
  const _InfoItem({required this.label, required this.value});

  final String label;
  final String value;
}

class _InfoCell extends StatelessWidget {
  const _InfoCell({required this.item});

  final _InfoItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD6BEBE)),
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFFFFF7F7),
      ),
      child: Row(
        children: <Widget>[
          Text(
            '${item.label}：',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          Expanded(
            child: Text(
              item.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 17,
                color: AppPalette.primaryBrown,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StrokeTile extends StatelessWidget {
  const _StrokeTile({
    required this.index,
    required this.name,
    required this.entry,
    required this.tileSize,
  });

  final int index;
  final String name;
  final CharacterEntry entry;
  final double tileSize;

  @override
  Widget build(BuildContext context) {
    final previewState = StrokePlayerState(
      currentStrokeIndex: index,
      isPlaying: false,
      speed: 1,
      progress: 1,
      totalStrokes: entry.strokes.length,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          '第${index + 1}笔',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Center(
          child: SizedBox.square(
            dimension: tileSize.clamp(0.0, 150.0).toDouble(),
            child: StrokeCanvas(entry: entry, playerState: previewState),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        height: 58,
        decoration: BoxDecoration(
          color: AppPalette.primaryBrown,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: Colors.white, size: 27),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
