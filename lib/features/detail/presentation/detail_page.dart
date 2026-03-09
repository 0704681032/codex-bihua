import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../core/router/app_router.dart';
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
  static const double _autoPlaySpeed = 0.6;
  static const Map<String, List<String>> _presetWords = <String, List<String>>{
    '母': <String>['母亲', '字母', '母子', '母体', '母猪', '酵母'],
    '笔': <String>['毛笔', '画笔', '笔顺', '笔记', '笔画', '执笔'],
    '火': <String>['火山', '火苗', '火候', '火种', '灭火', '火车'],
    '马': <String>['马匹', '马术', '马车', '马上', '马步', '马力'],
  };

  late final TextEditingController _searchController;
  late final FlutterTts _tts;
  final String _playerSessionId = UniqueKey().toString();
  String? _autoPlayStartedKey;
  bool _ttsAvailable = true;

  bool _basicInfoExpanded = true;
  bool _strokeTableExpanded = true;
  bool _explanationExpanded = true;
  bool _wordsExpanded = true;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.char);
    _tts = FlutterTts();
    _initTts();
  }

  @override
  void didUpdateWidget(covariant DetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.char != widget.char) {
      _searchController.text = widget.char;
    }
  }

  @override
  void dispose() {
    _tts.stop();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('zh-CN');
      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
    } on MissingPluginException {
      _ttsAvailable = false;
    } catch (_) {
      _ttsAvailable = false;
    }
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
      AppRouter.detail,
      arguments: DetailRouteArgs(char: target),
    );
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

  Future<void> _speakText(String text) async {
    if (!_ttsAvailable) {
      _showSnack('当前设备暂不支持语音播放');
      return;
    }
    try {
      await _tts.stop();
      final result = await _tts.speak(text);
      if (result != 1) {
        _showSnack('语音播放失败，请稍后重试');
      }
    } on MissingPluginException {
      _ttsAvailable = false;
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
          final words = _resolveWordExamples(entry);
          final explanation = _buildExplanation(entry, words);

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
                        child: _buildExplanationBlock(entry, explanation),
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
                        child: _buildWordsGrid(entry, words),
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
            onPressed: () => _showSnack('亮度调节将在后续版本开放'),
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
        final columns = constraints.maxWidth >= 360 ? 4 : 3;
        const spacing = 8.0;
        final width =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: 10,
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
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildExplanationBlock(CharacterEntry entry, String explanation) {
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
      ],
    );
  }

  Widget _buildWordsGrid(CharacterEntry entry, List<String> words) {
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
                  Text(
                    _pseudoPinyin(word, entry.pinyin),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF7B6565),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
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

  Widget _buildPlayerControls(
    StrokePlayerState state,
    StrokePlayerController controller,
  ) {
    return Row(
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
    );
  }

  List<String> _resolveStrokeNames(CharacterEntry entry) {
    if (entry.char == '母' && entry.strokeCount == 5) {
      return const <String>['竖折/竖弯', '横折钩', '点', '横', '点'];
    }

    final names = <String>[];
    for (var i = 0; i < entry.strokes.length; i += 1) {
      final median = entry.strokes[i].medianPoints;
      names.add(_guessStrokeType(median, i + 1));
    }
    return names;
  }

  String _guessStrokeType(List<List<double>> medianPoints, int order) {
    if (medianPoints.length <= 1) {
      return '第$order笔';
    }

    final start = medianPoints.first;
    final end = medianPoints.last;
    final dx = end[0] - start[0];
    final dy = end[1] - start[1];
    final absDx = dx.abs();
    final absDy = dy.abs();

    var turning = false;
    for (var i = 1; i < medianPoints.length - 1; i += 1) {
      final a = medianPoints[i - 1];
      final b = medianPoints[i];
      final c = medianPoints[i + 1];
      final abx = b[0] - a[0];
      final aby = b[1] - a[1];
      final bcx = c[0] - b[0];
      final bcy = c[1] - b[1];
      final dot = abx * bcx + aby * bcy;
      final len =
          math.sqrt(abx * abx + aby * aby) * math.sqrt(bcx * bcx + bcy * bcy);
      if (len > 0) {
        final cos = dot / len;
        if (cos < 0.75) {
          turning = true;
          break;
        }
      }
    }

    if (absDx < 45 && absDy < 45) {
      return '点';
    }
    if (turning) {
      if (absDx >= absDy) {
        return '横折';
      }
      return '竖折';
    }
    if (absDx > absDy * 1.8) {
      return '横';
    }
    if (absDy > absDx * 1.8) {
      return '竖';
    }
    if (dx > 0 && dy > 0) {
      return '捺';
    }
    if (dx < 0 && dy > 0) {
      return '撇';
    }
    return '第$order笔';
  }

  List<String> _resolveWordExamples(CharacterEntry entry) {
    final preset = _presetWords[entry.char];
    if (preset != null) {
      return preset;
    }

    final fromData = entry.examples
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && _containsChinese(item))
        .toSet()
        .toList(growable: false);
    if (fromData.length >= 3) {
      return fromData.take(6).toList(growable: false);
    }

    return <String>[
      '${entry.char}字',
      '${entry.char}形',
      '${entry.char}体',
      '${entry.char}音',
      '${entry.char}义',
      '${entry.char}文',
    ];
  }

  String _buildExplanation(CharacterEntry entry, List<String> words) {
    final wordText = words.take(4).join('、');
    final pinyin = entry.pinyin.trim();
    return '「${entry.char}」读作${pinyin.isEmpty ? '（待补充）' : pinyin}。'
        '部首为${entry.radical}，共${entry.strokeCount}画。'
        '常见组词：$wordText。';
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

  String _pseudoPinyin(String word, String pinyin) {
    final trimmed = pinyin.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final count = word.runes.length.clamp(1, 4);
    return List<String>.filled(count, trimmed).join(' ');
  }

  bool _containsChinese(String text) {
    return RegExp(r'[\u4E00-\u9FFF]').hasMatch(text);
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
  });

  final int index;
  final String name;
  final CharacterEntry entry;

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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '第${index + 1}笔',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 88,
          child: Center(
            child: SizedBox.square(
              dimension: 88,
              child: StrokeCanvas(entry: entry, playerState: previewState),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
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
