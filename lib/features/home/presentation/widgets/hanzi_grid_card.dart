import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/dashed_line.dart' as dashed;
import '../../../dictionary/domain/character_entry.dart';

class HanziGridCard extends StatelessWidget {
  const HanziGridCard({
    super.key,
    required this.entry,
    required this.onTap,
    this.size = 82,
  });

  final CharacterEntry entry;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F3F3),
              border: Border.all(color: AppPalette.guideRed, width: 2),
            ),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: CustomPaint(
                    painter: _GuideGridPainter(),
                  ),
                ),
                Center(
                  child: Text(
                    entry.char,
                    style: TextStyle(
                      fontSize: size * 0.62,
                      color: AppPalette.strokeBlack,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${entry.pinyin} · ${entry.strokeCount}画',
            style: const TextStyle(
              color: AppPalette.primaryBrownDark,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppPalette.guideRed.withValues(alpha: 0.55)
      ..strokeWidth = 1.2;

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    dashed.drawDashedLine(canvas, Offset(centerX, 0), Offset(centerX, size.height), paint, dash: 4, gap: 3);
    dashed.drawDashedLine(canvas, Offset(0, centerY), Offset(size.width, centerY), paint, dash: 4, gap: 3);
  }

  @override
  bool shouldRepaint(covariant _GuideGridPainter oldDelegate) => false;
}
