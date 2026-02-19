import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppBottomNavigationBar extends StatelessWidget {
  const AppBottomNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: onTap,
      type: BottomNavigationBarType.fixed,
      backgroundColor: const Color(0xFFF6E7E4),
      selectedItemColor: AppPalette.primaryBrown,
      unselectedItemColor: const Color(0xFF5A4646),
      showUnselectedLabels: true,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
      items: const <BottomNavigationBarItem>[
        BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: '首页'),
        BottomNavigationBarItem(icon: Icon(Icons.list_alt_rounded), label: '分类'),
        BottomNavigationBarItem(icon: Icon(Icons.menu_book_rounded), label: '字帖'),
        BottomNavigationBarItem(icon: Icon(Icons.person_outline_rounded), label: '我的'),
      ],
    );
  }
}
