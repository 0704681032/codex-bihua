import 'package:bihua/features/detail/application/reference_data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 单测环境没有真实 assets，词库/释义 provider 会永远停留在加载态；
/// 详情页的加载 spinner 是无限动画，会让 pumpAndSettle 超时——这里
/// 直接视为「已加载但没有数据」，走既有占位链。
List<Override> detailReferenceOverrides(List<String> chars) => <Override>[
      for (final char in chars) ...<Override>[
        wordsForCharProvider(char).overrideWith((ref) async => null),
        definitionZhProvider(char).overrideWith((ref) async => null),
      ],
    ];
