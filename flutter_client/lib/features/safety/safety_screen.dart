import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/features/safety/safety_device.dart';
import 'package:flutter_client/features/safety/sos_screen.dart';

/// Вкладка «Безпека» (ADR-022 §22.3), частина 1: SOS (утримати 3 с), мої координати, екстрені
/// номери, світловий сигнал SOS. Усе працює без інтернету й без акаунта (гостю теж — ADR-001,
/// уточнення 2026-11-17). Компас, маршрут, довідкові екрани й Наглядач — наступні частини.
class SafetyScreen extends StatelessWidget {
  const SafetyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Безпека', style: GoogleFonts.merriweather(color: AppTheme.darkGreen)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        key: const ValueKey('safety-list'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const Center(child: SosHoldButton()),
          const SizedBox(height: 8),
          Text(
            'Утримайте 3 секунди: увімкнеться сирена, з\'являться ваші координати й дзвінок 112.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.darkGreen.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 18),
          const MyCoordinatesCard(autoLocate: false),
          const SizedBox(height: 12),
          _ActionTile(
            key: const ValueKey('open-light-signal'),
            icon: Icons.flashlight_on_rounded,
            title: 'Світловий сигнал SOS',
            subtitle: 'Екран і спалах блимають азбукою Морзе ··· — — — ··· — щоб вас побачили вночі',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LightSignalScreen())),
          ),
          const SizedBox(height: 18),
          Text('Екстрені номери',
              style: GoogleFonts.merriweather(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.darkGreen)),
          const SizedBox(height: 8),
          const EmergencyNumbers(),
        ],
      ),
    );
  }
}

/// Велика кнопка SOS: утримати 3 с (кільце заповнюється) — щоб не натиснути випадково.
class SosHoldButton extends ConsumerStatefulWidget {
  const SosHoldButton({super.key, this.hold = const Duration(seconds: 3)});

  final Duration hold;

  @override
  ConsumerState<SosHoldButton> createState() => _SosHoldButtonState();
}

class _SosHoldButtonState extends ConsumerState<SosHoldButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.hold)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _fire();
    });

  Future<void> _fire() async {
    HapticFeedback.heavyImpact();
    _c.reset();
    await Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const SosScreen()));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        key: const ValueKey('sos-hold'),
        onPointerDown: (_) {
          HapticFeedback.selectionClick();
          _c.forward(from: 0);
        },
        onPointerUp: (_) {
          if (_c.status != AnimationStatus.completed) _c.reverse();
        },
        onPointerCancel: (_) => _c.reverse(),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => SizedBox(
            width: 168,
            height: 168,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: _c.value,
                    strokeWidth: 8,
                    color: const Color(0xffc62828),
                    backgroundColor: const Color(0xffc62828).withValues(alpha: 0.15),
                  ),
                ),
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.lerp(const Color(0xffe53935), const Color(0xffb71c1c), _c.value),
                    boxShadow: [BoxShadow(color: const Color(0xffc62828).withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6))],
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('SOS', style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 3)),
                      Text(_c.value > 0 ? 'Тримайте…' : 'Утримати 3 с',
                          style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// 112, 101, 102, 103 — дотик відкриває набір номера (ADR-022 §22.3 п.15).
class EmergencyNumbers extends ConsumerWidget {
  const EmergencyNumbers({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
        children: [
          for (final n in kEmergencyNumbers)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ActionTile(
                key: ValueKey('call-${n.number}'),
                leading: Container(
                  width: 52,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: n.number == '112' ? const Color(0xffc62828) : AppTheme.darkGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(n.number,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: n.number == '112' ? Colors.white : AppTheme.darkGreen)),
                ),
                title: n.title,
                subtitle: n.note.isEmpty ? null : n.note,
                trailing: Icons.call_rounded,
                onTap: () => ref.read(safetyDeviceProvider).dial(n.number),
              ),
            ),
        ],
      );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing = Icons.chevron_right_rounded,
    required this.onTap,
  });

  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final IconData trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Row(
              children: [
                leading ?? Icon(icon, color: AppTheme.darkGreen, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.darkGreen, fontSize: 15)),
                      if (subtitle != null)
                        Text(subtitle!, style: TextStyle(fontSize: 12.5, color: AppTheme.darkGreen.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
                Icon(trailing, color: AppTheme.darkGreen.withValues(alpha: 0.6)),
              ],
            ),
          ),
        ),
      );
}
