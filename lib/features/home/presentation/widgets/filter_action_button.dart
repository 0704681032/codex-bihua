import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class FilterActionButton extends StatelessWidget {
  const FilterActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.activeValue,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final String? activeValue;

  @override
  Widget build(BuildContext context) {
    final active = activeValue != null;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 92,
          decoration: BoxDecoration(
            color: active ? AppPalette.primaryBrownDark : AppPalette.primaryBrown,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              if (active)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    activeValue!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
