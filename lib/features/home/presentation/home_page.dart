import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dashed_line.dart' as dashed;
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
  List<CharacterEntry> _filterResultsAll = <CharacterEntry>[];
  List<CharacterEntry> _filterResults = <CharacterEntry>[];
  bool _searchPanelExpanded = true;
  bool _filterPanelExpanded = true;
  bool _examplesExpanded = true;
  bool _confusablesExpanded = true;

  /// 筛选结果默认展示的字数；超出部分点「显示全部」展开，避免一次
  /// 渲染几千张字卡，同时不再静默截断。
  static const int _filterResultPageSize = 80;

  int _searchToken = 0;
  int _filterToken = 0;
  bool _detailPushInFlight = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DictionaryRepository get _repo => ref.read(dictionaryRepositoryProvider);

  Future<void> _performSearch() async {
    // 多取 1 个汉字用于检测超限，实际查询仍以 20 个为上限（与详情页一致）。
    final rawChars =
        HanziInputSanitizer.sanitize(_searchController.text, maxLength: 21);
    if (rawChars.isEmpty) {
      _showSnack('请输入 1~20 个汉字');
      return;
    }

    final limited = rawChars.take(20).toList(growable: false);
    if (rawChars.length > 20) {
      _showSnack('最多支持前 20 个汉字');
    }

    final token = ++_searchToken;
    final result = await _repo.searchByChars(limited);
    if (!mounted || token != _searchToken) {
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
    final token = ++_filterToken;
    if (_criteria.isEmpty) {
      setState(() {
        _filterResults = <CharacterEntry>[];
      });
      return;
    }

    final result = await _repo.filter(_criteria);
    if (!mounted || token != _filterToken) {
      return;
    }

    setState(() {
      _filterResultsAll = result;
      _filterResults = result.take(_filterResultPageSize).toList(growable: false);
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
    // 下滑/点遮罩关闭（null）保留原筛选，仅「清除筛选」('') 才清空，与笔画弹层一致。
    if (!mounted || selected == null) {
      return;
    }
    setState(() {
      _criteria = selected.isEmpty
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
    if (!mounted || selected == null) {
      return;
    }
    setState(() {
      _criteria = selected.isEmpty
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
    );
  }

  void _openDetail(String char) {
    if (_detailPushInFlight) {
      return;
    }
    _detailPushInFlight = true;
    Navigator.of(context)
        .pushNamed(
          AppRouter.detailRouteFor(char),
          arguments: DetailRouteArgs(char: char),
        )
        .whenComplete(() => _detailPushInFlight = false);
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('字库加载失败，请重试'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => ref.refresh(dictionaryWarmUpProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
              ),
            ],
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
                  _buildResultPanel(
                    title: '查询结果（共 ${_searchResults.length} 字）',
                    data: _searchResults,
                    expanded: _searchPanelExpanded,
                    onToggle: () => setState(
                        () => _searchPanelExpanded = !_searchPanelExpanded),
                  ),
                ],
                if (_filterResults.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 18),
                  _buildResultPanel(
                    title: '筛选结果（共 ${_filterResultsAll.length} 字）',
                    data: _filterResults,
                    expanded: _filterPanelExpanded,
                    onToggle: () => setState(
                        () => _filterPanelExpanded = !_filterPanelExpanded),
                    onShowAll:
                        _filterResultsAll.length > _filterResults.length
                            ? () => setState(() {
                                  _filterResults = _filterResultsAll;
                                })
                            : null,
                  ),
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

  Widget _buildResultPanel({
    required String title,
    required List<CharacterEntry> data,
    required bool expanded,
    required VoidCallback onToggle,
    VoidCallback? onShowAll,
  }) {
    return CollapsibleHanziSection(
      title: title,
      expanded: expanded,
      onToggle: onToggle,
      child: Column(
        children: <Widget>[
          _buildHanziGrid(data),
          if (onShowAll != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: TextButton(
                  onPressed: onShowAll,
                  child: const Text(
                    '已显示前 80 字，点击显示全部',
                    style: TextStyle(color: AppPalette.primaryBrown),
                  ),
                ),
              ),
            ),
        ],
      ),
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
      ..color = AppPalette.guideRed.withValues(alpha: 0.55)
      ..strokeWidth = 2;

    dashed.drawDashedLine(
        canvas, Offset(size.width / 2, 0), Offset(size.width / 2, size.height), paint,
        dash: 7, gap: 6);
    dashed.drawDashedLine(
        canvas, Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint,
        dash: 7, gap: 6);
  }

  @override
  bool shouldRepaint(covariant _CircleGuidePainter oldDelegate) => false;
}
