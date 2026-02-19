import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hanzi_search_bar.dart';
import '../../../core/widgets/main_bottom_nav.dart';
import '../../dictionary/application/dictionary_providers.dart';
import '../../dictionary/application/hanzi_input_sanitizer.dart';
import '../../dictionary/domain/character_entry.dart';
import '../../dictionary/domain/filter_criteria.dart';
import '../../dictionary/domain/dictionary_repository.dart';
import 'widgets/collapsible_hanzi_section.dart';
import 'widgets/filter_action_button.dart';
import 'widgets/hanzi_grid_card.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final TextEditingController _searchController = TextEditingController();

  FilterCriteria _criteria = const FilterCriteria();
  List<CharacterEntry> _searchResults = <CharacterEntry>[];
  List<CharacterEntry> _filterResults = <CharacterEntry>[];
  bool _examplesExpanded = true;
  bool _confusablesExpanded = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DictionaryRepository get _repo => ref.read(dictionaryRepositoryProvider);

  Future<void> _performSearch() async {
    final rawChars = HanziInputSanitizer.sanitize(_searchController.text, maxLength: 240);
    if (rawChars.isEmpty) {
      _showSnack('请输入 1~20 个汉字');
      return;
    }

    final limited = rawChars.take(20).toList(growable: false);
    if (rawChars.length > 20) {
      _showSnack('最多支持前 20 个汉字');
    }

    final result = await _repo.searchByChars(limited);
    if (!mounted) {
      return;
    }

    setState(() {
      _searchResults = result;
    });

    if (result.isEmpty) {
      _showSnack('未找到匹配汉字');
      return;
    }

    if (result.length == 1) {
      _openDetail(result.first.char);
    }
  }

  Future<void> _applyFilter() async {
    if (_criteria.isEmpty) {
      setState(() {
        _filterResults = <CharacterEntry>[];
      });
      return;
    }

    final result = await _repo.filter(_criteria);
    if (!mounted) {
      return;
    }

    setState(() {
      _filterResults = result.take(80).toList(growable: false);
    });
  }

  Future<void> _pickPinyin() async {
    final options = await _repo.getAvailablePinyins();
    if (!mounted) {
      return;
    }
    final selected = await _showStringOptionSheet(
      title: '按拼音筛选',
      options: options,
      selectedValue: _criteria.pinyin,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _criteria = selected == null
          ? _criteria.copyWith(clearPinyin: true)
          : _criteria.copyWith(pinyin: selected);
    });
    await _applyFilter();
  }

  Future<void> _pickRadical() async {
    final options = await _repo.getAvailableRadicals();
    if (!mounted) {
      return;
    }
    final selected = await _showStringOptionSheet(
      title: '按部首筛选',
      options: options,
      selectedValue: _criteria.radical,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _criteria = selected == null
          ? _criteria.copyWith(clearRadical: true)
          : _criteria.copyWith(radical: selected);
    });
    await _applyFilter();
  }

  Future<void> _pickStrokeCount() async {
    final options = await _repo.getAvailableStrokeCounts();
    if (!mounted) {
      return;
    }

    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF7EEEE),
      builder: (ctx) {
        return SizedBox(
          height: 460,
          child: Column(
            children: <Widget>[
              const SizedBox(height: 4),
              const Text(
                '按笔画筛选',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(-1),
                child: const Text('清除筛选'),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    childAspectRatio: 1.8,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final item = options[index];
                    final active = item == _criteria.strokeCount;
                    return OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(item),
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            active ? Colors.white : AppPalette.primaryBrown,
                        backgroundColor:
                            active ? AppPalette.primaryBrown : Colors.transparent,
                        side: const BorderSide(color: AppPalette.primaryBrown),
                      ),
                      child: Text('$item画'),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selected == null || !mounted) {
      return;
    }

    setState(() {
      _criteria = selected == -1
          ? _criteria.copyWith(clearStrokeCount: true)
          : _criteria.copyWith(strokeCount: selected);
    });
    await _applyFilter();
  }

  Future<String?> _showStringOptionSheet({
    required String title,
    required List<String> options,
    required String? selectedValue,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF7EEEE),
      builder: (ctx) {
        return SizedBox(
          height: 520,
          child: Column(
            children: <Widget>[
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(''),
                child: const Text('清除筛选'),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final item = options[index];
                    final active = item == selectedValue;
                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      tileColor:
                          active ? const Color(0xFFEBCFCF) : Colors.transparent,
                      title: Text(item),
                      trailing: active
                          ? const Icon(Icons.check_rounded,
                              color: AppPalette.primaryBrown)
                          : null,
                      onTap: () => Navigator.of(ctx).pop(item),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    ).then((value) {
      if (value == '') {
        return null;
      }
      return value;
    });
  }

  void _openDetail(String char) {
    Navigator.of(context).pushNamed(
      AppRouter.detail,
      arguments: DetailRouteArgs(char: char),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _onBottomNavTap(int index) {
    if (index == 0) {
      return;
    }
    _showSnack('当前首版仅开放首页与详情页');
  }

  @override
  Widget build(BuildContext context) {
    final warmup = ref.watch(dictionaryWarmUpProvider);

    return Scaffold(
      body: warmup.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('字库加载失败: $error'),
          ),
        ),
        data: (_) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildLogo(),
                const SizedBox(height: 18),
                HanziSearchBar(
                  controller: _searchController,
                  onSearchTap: _performSearch,
                  onSubmitted: (_) => _performSearch(),
                  onCameraTap: () => _showSnack('拍照识字将在后续版本开放'),
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    FilterActionButton(
                      label: '拼音',
                      icon: Icons.abc_rounded,
                      onTap: _pickPinyin,
                      activeValue: _criteria.pinyin,
                    ),
                    const SizedBox(width: 12),
                    FilterActionButton(
                      label: '笔画',
                      icon: Icons.brush_rounded,
                      onTap: _pickStrokeCount,
                      activeValue: _criteria.strokeCount?.toString(),
                    ),
                    const SizedBox(width: 12),
                    FilterActionButton(
                      label: '部首',
                      icon: Icons.auto_awesome_mosaic_rounded,
                      onTap: _pickRadical,
                      activeValue: _criteria.radical,
                    ),
                  ],
                ),
                if (_searchResults.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 18),
                  _buildResultPanel('查询结果', _searchResults),
                ],
                if (_filterResults.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 18),
                  _buildResultPanel('筛选结果', _filterResults),
                ],
                const SizedBox(height: 18),
                _buildExamplesSection(),
                const SizedBox(height: 14),
                _buildConfusableSection(),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: AppBottomNavigationBar(
        currentIndex: 0,
        onTap: _onBottomNavTap,
      ),
    );
  }

  Widget _buildLogo() {
    return Center(
      child: SizedBox(
        width: 170,
        child: Column(
          children: <Widget>[
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFEA838A), width: 4),
                color: const Color(0xFFF7F7F7),
              ),
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: CustomPaint(painter: _CircleGuidePainter()),
                  ),
                  const Center(
                    child: Text(
                      '笔',
                      style: TextStyle(
                        fontSize: 84,
                        color: AppPalette.strokeBlack,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultPanel(String title, List<CharacterEntry> data) {
    return CollapsibleHanziSection(
      title: title,
      expanded: true,
      onToggle: () {},
      child: _buildHanziGrid(data),
    );
  }

  Widget _buildExamplesSection() {
    final examples = ref.watch(exampleCharactersProvider);
    return CollapsibleHanziSection(
      title: '汉字举例',
      expanded: _examplesExpanded,
      onToggle: () => setState(() => _examplesExpanded = !_examplesExpanded),
      child: examples.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(18),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, __) => const Text('加载失败'),
        data: _buildHanziGrid,
      ),
    );
  }

  Widget _buildConfusableSection() {
    final confusables = ref.watch(confusableCharactersProvider);
    return CollapsibleHanziSection(
      title: '易错汉字',
      expanded: _confusablesExpanded,
      onToggle: () => setState(() => _confusablesExpanded = !_confusablesExpanded),
      child: confusables.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(18),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, __) => const Text('加载失败'),
        data: _buildHanziGrid,
      ),
    );
  }

  Widget _buildHanziGrid(List<CharacterEntry> entries) {
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: Text('暂无数据')),
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: entries
          .map(
            (entry) => HanziGridCard(
              entry: entry,
              onTap: () => _openDetail(entry.char),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _CircleGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppPalette.guideRed.withOpacity(0.55)
      ..strokeWidth = 2;

    _drawDashedLine(canvas, Offset(size.width / 2, 0), Offset(size.width / 2, size.height), paint);
    _drawDashedLine(canvas, Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint);
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dash = 7.0;
    const gap = 6.0;
    final delta = end - start;
    final total = delta.distance;
    final direction = delta / total;

    var current = 0.0;
    while (current < total) {
      final from = start + direction * current;
      final to = start + direction * (current + dash).clamp(0, total);
      canvas.drawLine(from, to, paint);
      current += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _CircleGuidePainter oldDelegate) => false;
}
