import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class HanziSearchBar extends StatelessWidget {
  const HanziSearchBar({
    super.key,
    required this.controller,
    this.hintText = '请输入 1 ~ 20 个汉字进行查询',
    this.onSubmitted,
    this.onSearchTap,
    this.onCameraTap,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onSearchTap;
  final VoidCallback? onCameraTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4DCDC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDBB9B9), width: 1.5),
      ),
      child: Row(
        children: <Widget>[
          InkWell(
            onTap: onSearchTap,
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.search_rounded, color: AppPalette.primaryBrown, size: 38),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmitted,
              cursorColor: AppPalette.primaryBrown,
              style: const TextStyle(
                fontSize: 22,
                color: AppPalette.primaryBrownDark,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: hintText,
                hintStyle: const TextStyle(
                  fontSize: 22,
                  color: AppPalette.primaryBrown,
                ),
              ),
            ),
          ),
          InkWell(
            onTap: onCameraTap,
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.photo_camera_rounded, color: Color(0xFFEF9A00), size: 40),
            ),
          ),
        ],
      ),
    );
  }
}
