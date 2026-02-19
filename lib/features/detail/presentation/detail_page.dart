import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  late final TextEditingController _searchController;
  final String _playerSessionId = UniqueKey().toString();

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.char);
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
    _searchController.dispose();
    super.dispose();
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

          return SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
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
                      const SizedBox(height: 18),
                      _buildPreview(entry),
                      const SizedBox(height: 14),
                      _buildFunctionRow(),
                      const SizedBox(height: 14),
                      StrokeCanvas(entry: entry, playerState: playerState),
                      const SizedBox(height: 14),
                      _buildPlayerControls(playerState, player),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _ActionButton(
                              icon: Icons.note_add_outlined,
                              label: '添加到生字本',
                              onTap: () => _showSnack('已添加到生字本（本地）'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _ActionButton(
                              icon: Icons.download_rounded,
                              label: '下载字帖',
                              onTap: () => _showSnack('已生成本地字帖任务'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Opacity(
                        opacity: 0.55,
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: _ActionButton(
                                icon: Icons.send_outlined,
                                label: '转发「${entry.char}」字笔顺',
                                onTap: () => _showSnack('分享功能将在后续版本开放'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _ActionButton(
                                icon: Icons.edit_outlined,
                                label: '写一写',
                                onTap: () => _showSnack('临摹练习将在后续版本开放'),
                              ),
                            ),
                          ],
                        ),
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

  Widget _buildPreview(CharacterEntry entry) {
    return Center(
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          border: Border.all(color: AppPalette.guideRed, width: 3),
          color: const Color(0xFFF7F7F7),
        ),
        child: Center(
          child: Text(
            entry.char,
            style: const TextStyle(fontSize: 62, color: AppPalette.strokeBlack),
          ),
        ),
      ),
    );
  }

  Widget _buildFunctionRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: <Widget>[
        IconButton(
          onPressed: () => _showSnack('语音朗读将在后续版本开放'),
          icon: const Icon(Icons.volume_up_rounded,
              color: AppPalette.primaryBrown, size: 34),
        ),
        IconButton(
          onPressed: () => _showSnack('会员能力展示占位'),
          icon: const Icon(Icons.diamond_rounded,
              color: Colors.redAccent, size: 32),
        ),
        IconButton(
          onPressed: () => _showSnack('主题亮度调节将在后续版本开放'),
          icon: const Icon(Icons.wb_sunny_outlined,
              color: AppPalette.textMain, size: 32),
        ),
        IconButton(
          onPressed: () => _showSnack('田字格模式切换将在后续版本开放'),
          icon: const Icon(Icons.copy_all_outlined,
              color: AppPalette.textMain, size: 31),
        ),
        IconButton(
          onPressed: () => _showSnack('设置面板将在后续版本开放'),
          icon: const Icon(Icons.settings_rounded,
              color: AppPalette.textMain, size: 32),
        ),
      ],
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
        height: 62,
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
