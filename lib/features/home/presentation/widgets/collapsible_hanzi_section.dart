import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class CollapsibleHanziSection extends StatelessWidget {
  const CollapsibleHanziSection({
    super.key,
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEEDADA),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: <Widget>[
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.circle, color: AppPalette.primaryBrown, size: 12),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 42 / 2,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.textMain,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: AppPalette.textMain,
                    size: 34,
                  ),
                ],
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            height: 1,
            color: const Color(0xFFD8C0C0),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: child,
            ),
        ],
      ),
    );
  }
}
