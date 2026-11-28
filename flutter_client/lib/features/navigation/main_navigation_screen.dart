import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/features/friends/referral.dart';

class MainNavigationScreen extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainNavigationScreen({super.key, required this.navigationShell});

  @override
  ConsumerState<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  StatefulNavigationShell get navigationShell => widget.navigationShell;

  @override
  void initState() {
    super.initState();
    // Встановили за посиланням друга — один раз передати код запрошення (B9.5).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final label = await redeemInstallReferral(ref);
      if (label != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(key: const ValueKey('referral-snack'), content: Text(label), duration: const Duration(seconds: 6)),
        );
      }
    });
  }

  static const List<_TabItem> _tabs = [
    _TabItem(id: 'forecast', label: 'Прогноз', iconAsset: 'assets/icons/ic_forecast.svg'),
    _TabItem(id: 'map', label: 'Карта', iconAsset: 'assets/icons/ic_map.svg'),
    _TabItem(id: 'recognize', label: 'Розпізнати', iconAsset: 'assets/icons/ic_recognize.svg'),
    _TabItem(id: 'safety', label: 'Безпека', iconAsset: 'assets/icons/ic_safety.svg'),
    _TabItem(id: 'profile', label: 'Профіль', iconAsset: 'assets/icons/ic_profile.svg'),
  ];

  @override
  Widget build(BuildContext context) {
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
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isActive ? AppTheme.orange : AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}