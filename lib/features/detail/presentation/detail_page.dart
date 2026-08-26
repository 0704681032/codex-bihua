import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../core/application/brightness_controller.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hanzi_search_bar.dart';
import '../../../core/widgets/main_bottom_nav.dart';
import '../../dictionary/application/dictionary_providers.dart';
import '../../dictionary/application/hanzi_input_sanitizer.dart';
import '../../dictionary/domain/character_entry.dart';
import '../../dictionary/domain/dictionary_repository.dart';
import '../../dictionary/domain/stroke_path.dart';
import '../application/playback_speeds.dart';
import '../application/reference_data.dart';
import '../application/stroke_classifier.dart';
import '../application/stroke_player_controller.dart';
import '../application/stroke_player_state.dart';
import 'widgets/stroke_canvas.dart';

class DetailPage extends ConsumerStatefulWidget {
  const DetailPage({super.key, required this.char});

  final String char;

  /// 测试观测点:最近一次构建的播放器 provider,供集成测试读取
  /// 真实状态机(避免复现随机 sessionId)。
  @visibleForTesting
  static AutoDisposeStateNotifierProvider<StrokePlayerController,
          StrokePlayerState>? lastPlayerProvider;

  @override
  ConsumerState<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends ConsumerState<DetailPage> {
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
  int _searchToken = 0;
  FlutterTts? _tts;
  final String _playerSessionId = UniqueKey().toString();
  String? _autoPlayStartedKey;
  bool _ttsInitializing = true;
  bool _ttsAvailable = false;

  /// 笔顺动画区的锚点：点击笔顺表某笔后把动画区滚回视野。
  final GlobalKey _animationSectionKey = GlobalKey();
  bool _basicInfoExpanded = true;
  bool _strokeTableExpanded = true;
  bool _explanationExpanded = true;
  bool _wordsExpanded = true;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.char);
    _initTts();
  }

  @override
  void didUpdateWidget(covariant DetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.char != widget.char) {
      _searchController.text = widget.char;
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

      // Web 端连续点击时会因打断上一段合成而触发浏览器级 error
      // (interrupted/canceled),此时新语音往往已在正常播放——把失败
      // 提示收敛为仅记录日志,避免误导用户。
      tts.setErrorHandler((message) {
        debugPrint('TTS error: $message');
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
    final token = ++_searchToken;
    final CharacterEntry? entry;
    try {
      entry = await ref.read(dictionaryRepositoryProvider).getByChar(target);
    } on StrokeShardLoadException {
      if (mounted && token == _searchToken) {
        _showSnack('笔画资源加载失败，请重试');
      }
      return;
    }
    if (!mounted || token != _searchToken) {
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
      await Future<void>.delayed(const Duration(milliseconds: 120));
    } catch (_) {}

    try {
      // Web resolves with null on success, desktop/other return 1; only a
      // definitive non-1 value (never null) counts as failure.
      final result = await _tts!.speak(trimmed);
      if (result != null && result != 1) {
        debugPrint('TTS speak returned $result');
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() => _ttsAvailable = false);
      }
      _showSnack('当前设备暂不支持语音播放');
    } catch (error) {
      debugPrint('TTS speak failed: $error');
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
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '分享',
            icon: const Icon(Icons.share_rounded),
            onPressed: () => _showSnack('分享功能将在后续版本开放'),
          ),
        ],
      ),
      body: characterAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  error is StrokeShardLoadException
                      ? '笔画资源加载失败，请重试'
                      : '加载失败，请重试',
                ),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    ref.refresh(characterByCharProvider(widget.char)),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (entry) {
          if (entry == null) {
            return const Center(child: Text('未找到该汉字'));
          }

          final key = StrokePlayerKey(
            sessionId: _playerSessionId,
            char: entry.char,
            totalStrokes: entry.strokes.length,
            strokeWeights: _strokeWeights(entry),
          );
          final provider = strokePlayerProvider(key);
          DetailPage.lastPlayerProvider = provider;
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
              player.setSpeed(PlaybackSpeeds.defaultSpeed);
              if (!ref.read(provider).isPlaying) {
                player.togglePlay();
              }
            });
          }

          final strokeNames = _resolveStrokeNames(entry);
          // 组词/中文释义共用一次按字分片加载(~33KB, 一次解码同时供应
          // 两区); 两个区块都折叠时不发起任何参考数据请求。
          final referenceAsync = (_explanationExpanded || _wordsExpanded)
              ? ref.watch(referenceForCharProvider(entry.char))
              : null;
          final datasetWords = referenceAsync?.valueOrNull?.words;
          final wordCards = _resolveWordCards(entry, datasetWords);
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
                        key: _animationSectionKey,
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
                        child: _buildStrokeTable(entry, strokeNames, player),
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
                        child: _buildExplanationBlock(
                            entry, definitions, referenceAsync),
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
                        child: _buildWordsGrid(referenceAsync, wordCards),
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
            tooltip: '朗读',
            onPressed: () => _speakCharacter(entry),
            icon: const Icon(
              Icons.volume_up_rounded,
              color: AppPalette.primaryBrown,
              size: 32,
            ),
          ),
          // 会员入口在业务定义明确前先隐藏, 避免不可完成的占位点击。
          IconButton(
            tooltip: '屏幕亮度',
            onPressed: _showBrightnessSheet,
            icon: const Icon(
              Icons.wb_sunny_outlined,
              color: AppPalette.textMain,
              size: 31,
            ),
          ),
          IconButton(
            tooltip: '田字格模式',
            onPressed: () => _showSnack('田字格模式切换将在后续版本开放'),
            icon: const Icon(
              Icons.copy_all_outlined,
              color: AppPalette.textMain,
              size: 30,
            ),
          ),
          IconButton(
            tooltip: '设置',
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

  /// 点击笔顺表某笔：暂停并完整显示该笔，同时把动画区滚回视野。
  void _jumpToStroke(StrokePlayerController player, int index) {
    player.jumpToStroke(index);
    final ctx = _animationSectionKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        alignment: 0.1,
      );
    }
  }

  Widget _buildBasicInfo(CharacterEntry entry, List<String> strokeNames) {
    // 只展示字库里真实存在的字段。结构/造字法/五行没有可靠数据源，
    // 旧版按笔画数猜测的结果是错的，宁可少展示也不展示错误事实。
    final infoItems = <_InfoItem>[
      _InfoItem(label: '笔画数', value: '${entry.strokeCount}'),
      _InfoItem(label: '部首', value: entry.radical),
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

  Widget _buildStrokeTable(
    CharacterEntry entry,
    List<String> strokeNames,
    StrokePlayerController player,
  ) {
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
                onTap: () => _jumpToStroke(player, index),
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
    AsyncValue<CharReference>? referenceAsync,
  ) {
    final zhDefinition = referenceAsync?.valueOrNull?.definition;
    final referenceFailed = referenceAsync?.hasError ?? false;
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
        if (referenceFailed) _referenceFailureHint(entry.char),
        if (referenceAsync?.isLoading ?? false) ...<Widget>[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          ),
        ] else if (zhDefinition != null && zhDefinition.isNotEmpty) ...<Widget>[
          Text(
            '• $zhDefinition',
            style: const TextStyle(fontSize: 17, height: 1.65),
          ),
          const SizedBox(height: 10),
        ] else ...<Widget>[
          Text(
            '• ${_buildExplanation(entry, _resolveWordCards(entry, null))}',
            style: const TextStyle(fontSize: 17, height: 1.65),
          ),
          const SizedBox(height: 10),
        ],
        if (definitions.isNotEmpty) ...<Widget>[
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
            onPressed: () => _showEncyclopediaSheet(entry, zhDefinition),
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

  /// 参考分片读取失败时的可见降级提示:内容走内置兜底,并提供重试。
  Widget _referenceFailureHint(String char) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          const Icon(Icons.cloud_off_outlined,
              size: 16, color: Color(0xFF9A8A8A)),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              '组词/释义数据加载失败，已显示内置内容',
              style: TextStyle(fontSize: 13, color: Color(0xFF9A8A8A)),
            ),
          ),
          GestureDetector(
            onTap: () => ref.refresh(referenceForCharProvider(char)),
            child: const Text(
              '重试',
              style: TextStyle(
                fontSize: 13,
                color: AppPalette.primaryBrown,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWordsGrid(
      AsyncValue<CharReference>? wordsAsync, List<WordCard> words) {
    if (wordsAsync?.isLoading ?? false) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            height: 26,
            width: 26,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        ),
      );
    }
    if (words.isEmpty) {
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
        final card = words[index];
        final pinyin = card.pinyin;
        return InkWell(
          onTap: () => _speakText(card.word),
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
                    card.word,
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
            for (final (speed, label) in PlaybackSpeeds.presets)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(label),
                  selected: (state.speed - speed).abs() < 0.01,
                  onSelected: (_) => controller.setSpeed(speed),
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Resolution order: authoritative dataset names (disambiguated by
  /// geometry) -> geometric classifier fallback -> 第N笔 placeholder.
  List<String> _resolveStrokeNames(CharacterEntry entry) {
    if (entry.strokeNames.length == entry.strokes.length &&
        entry.strokeNames.isNotEmpty) {
      return <String>[
        for (var i = 0; i < entry.strokeNames.length; i += 1)
          StrokeClassifier.refineName(
            entry.strokeNames[i],
            medianPoints: entry.strokes[i].medianPoints,
            flipYAxis: entry.flipYAxis,
          ),
      ];
    }

    return <String>[
      for (var i = 0; i < entry.strokes.length; i += 1)
        StrokeClassifier.classify(
          medianPoints: entry.strokes[i].medianPoints,
          flipYAxis: entry.flipYAxis,
          fallback: '第${i + 1}笔',
        ),
    ];
  }

  /// Relative stroke durations from median lengths, normalized so the
  /// *average* stroke plays at 1.0. Anchoring to the mean (not the max)
  /// keeps the overall pace identical to uniform timing. The raw
  /// length/mean ratio is then softened halfway toward 1.0 and clamped,
  /// so short strokes still finish visibly earlier but adjacent strokes
  /// never differ by several times in pace (阳's two short closing 横
  /// used to sweep by at ~2.5x right after a 0.65x 横折). Lengths are
  /// measured in glyph coordinates — flipping the y axis does not
  /// change distances. Strokes without usable medians fall back to the
  /// mean length instead of snapping to full speed.
  List<double> _strokeWeights(CharacterEntry entry) {
    final lengths = <double>[
      for (final stroke in entry.strokes) _medianPolylineLength(stroke),
    ];
    final measured = lengths.where((length) => length > 0).toList();
    if (measured.isEmpty) {
      return const <double>[];
    }

    final meanLength =
        measured.fold<double>(0, (sum, length) => sum + length) /
            measured.length;

    return <double>[
      for (final length in lengths)
        _strokeWeightFor(length, meanLength),
    ];
  }

  static const double _weightSoftening = 0.5;
  static const double _minStrokeWeight = 0.6;
  static const double _maxStrokeWeight = 1.35;

  double _strokeWeightFor(double length, double meanLength) {
    final raw = (length > 0 ? length : meanLength) / meanLength;
    final softened = 1.0 + (raw - 1.0) * _weightSoftening;
    return softened.clamp(_minStrokeWeight, _maxStrokeWeight).toDouble();
  }

  double _medianPolylineLength(StrokePath stroke) {
    var sum = 0.0;
    for (var i = 0; i + 1 < stroke.medianPoints.length; i += 1) {
      final a = stroke.medianPoints[i];
      final b = stroke.medianPoints[i + 1];
      if (a.length < 2 || b.length < 2) {
        continue;
      }
      sum += math.sqrt(
        (a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]),
      );
    }
    return sum;
  }

  /// Resolution order: CC-CEDICT dataset (lazy-loaded) -> curated preset
  /// words -> empty (grid shows the 词库建设中 placeholder). Preset
  /// pinyin fills gaps for cards without a reading.
  List<WordCard> _resolveWordCards(
    CharacterEntry entry,
    List<WordCard>? datasetWords,
  ) {
    if (datasetWords != null && datasetWords.isNotEmpty) {
      return <WordCard>[
        for (final card in datasetWords)
          WordCard(
            word: card.word,
            pinyin: card.pinyin ?? _presetWordPinyins[card.word],
          ),
      ];
    }
    final preset = _presetWords[entry.char];
    if (preset == null || preset.isEmpty) {
      return const <WordCard>[];
    }
    return <WordCard>[
      for (final word in preset)
        WordCard(word: word, pinyin: _presetWordPinyins[word]),
    ];
  }

  List<String> _resolveDefinitions(CharacterEntry entry) {
    return entry.examples
        .expand((item) => item.split(';'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  String _buildExplanation(CharacterEntry entry, List<WordCard> words) {
    final wordText = words.isEmpty
        ? ''
        : words.take(4).map((card) => card.word).join('、');
    final pinyin = entry.pinyin.trim();
    return '「${entry.char}」读作${pinyin.isEmpty ? '（待补充）' : pinyin}。'
        '部首为${entry.radical}，共${entry.strokeCount}画。'
        '${wordText.isEmpty ? '' : '常见组词：$wordText。'}';
  }

  void _showEncyclopediaSheet(
    CharacterEntry entry,
    String? zhDefinition,
  ) {
    final strokeNames = _resolveStrokeNames(entry);
    final definitions = <String>[
      if (zhDefinition != null && zhDefinition.isNotEmpty) zhDefinition,
      ..._resolveDefinitions(entry),
    ];

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
    super.key,
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
    this.onTap,
  });

  final int index;
  final String name;
  final CharacterEntry entry;
  final double tileSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final previewState = StrokePlayerState(
      currentStrokeIndex: index,
      isPlaying: false,
      speed: 1,
      progress: 1,
      totalStrokes: entry.strokes.length,
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
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
      ),
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
