import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_client/core/app_theme.dart';

class MainNavigationScreen extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const MainNavigationScreen({super.key, required this.navigationShell});

  static const List<_TabItem> _tabs = [
    _TabItem(id: 'forecast', label: 'Прогноз', iconAsset: 'assets/icons/ic_forecast.svg'),
    _TabItem(id: 'map', label: 'Карта', iconAsset: 'assets/icons/ic_map.svg'),
    _TabItem(id: 'recognize', label: 'Розпізнати', iconAsset: 'assets/icons/ic_recognize.svg'),
    _TabItem(id: 'safety', label: 'Безпека', iconAsset: 'assets/icons/ic_safety.svg'),
    _TabItem(id: 'community', label: 'Спільнота', iconAsset: 'assets/icons/ic_community.svg'),
    _TabItem(id: 'profile', label: 'Профіль', iconAsset: 'assets/icons/ic_profile.svg'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Container(
        height: 72 + MediaQuery.of(context).padding.bottom,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.backgroundColor, width: 1)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.darkGreen.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: _tabs.asMap().entries.map((entry) {
              final index = entry.key;
              final tab = entry.value;
              final isActive = navigationShell.currentIndex == index;
              return Expanded(
                child: _TabButton(
                  tab: tab,
                  isActive: isActive,
                  onTap: () => navigationShell.goBranch(
                    index,
                    initialLocation: index == navigationShell.currentIndex,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  final String id;
  final String label;
  final String iconAsset;

  const _TabItem({required this.id, required this.label, required this.iconAsset});
}

/// Матриця відтінків сірого (luminance) для неактивних іконок.
const List<double> _grayscale = [
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
];

class _TabButton extends StatelessWidget {
  final _TabItem tab;
  final bool isActive;
  final VoidCallback onTap;

  const _TabButton({required this.tab, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Flat-іконки кольорові: активна — у повному кольорі, неактивні — приглушені.
              Opacity(
                opacity: isActive ? 1 : 0.55,
                child: SvgPicture.asset(
                  tab.iconAsset,
                  width: 36,
                  height: 36,
                  colorFilter: isActive ? null : const ColorFilter.matrix(_grayscale),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                tab.label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isActive ? AppTheme.orange : AppTheme.darkGreen.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}