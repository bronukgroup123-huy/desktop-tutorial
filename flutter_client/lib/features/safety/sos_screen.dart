import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_client/features/safety/safety_device.dart';

const _sosRed = Color(0xffc62828);

/// Екран SOS (ADR-022 §22.3 п.1): сирена вмикається одразу, «Подзвонити 112», мої координати
/// великими цифрами, світловий сигнал. Тривога Наглядачам — коли буде Наглядач (§22.4).
/// Працює без інтернету й без акаунта.
class SosScreen extends ConsumerStatefulWidget {
  const SosScreen({super.key, this.sirenOnStart = true});

  final bool sirenOnStart;

  @override
  ConsumerState<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends ConsumerState<SosScreen> {
  late final SafetyDevice _device = ref.read(safetyDeviceProvider);
  bool _siren = false;

  @override
  void initState() {
    super.initState();
    _device.keepAwake(true);
    if (widget.sirenOnStart) _setSiren(true);
  }

  Future<void> _setSiren(bool on) async {
    setState(() => _siren = on);
    try {
      await _device.siren(on);
    } catch (_) {
      if (mounted) setState(() => _siren = false);
    }
  }

  @override
  void dispose() {
    _device.siren(false);
    _device.keepAwake(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('sos-screen'),
        backgroundColor: _sosRed,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              const Text('SOS',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.w900, letterSpacing: 6)),
              const Text('Залишайтеся на місці. Бережіть батарею.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 15)),
              const SizedBox(height: 20),
              SizedBox(
                height: 72,
                child: FilledButton.icon(
                  key: const ValueKey('sos-call-112'),
                  onPressed: () => _device.dial('112'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _sosRed,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  icon: const Icon(Icons.call_rounded, size: 30),
                  label: const Text('Подзвонити 112', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                ),
              ),
              const SizedBox(height: 14),
              const MyCoordinatesCard(dark: true),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _SosToggle(
                      key: const ValueKey('sos-siren'),
                      icon: _siren ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                      label: _siren ? 'Сирена увімкнена' : 'Сирена',
                      active: _siren,
                      onTap: () => _setSiren(!_siren),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SosToggle(
                      key: const ValueKey('sos-light'),
                      icon: Icons.flashlight_on_rounded,
                      label: 'Світловий сигнал',
                      active: false,
                      onTap: () async {
                        if (_siren) await _setSiren(false);
                        if (!context.mounted) return;
                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LightSignalScreen()));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                key: const ValueKey('sos-close'),
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white70),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Я в безпеці — закрити', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      );
}

class _SosToggle extends StatelessWidget {
  const _SosToggle({super.key, required this.icon, required this.label, required this.active, required this.onTap});

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: active ? Colors.white : Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              children: [
                Icon(icon, color: active ? _sosRed : Colors.white, size: 30),
                const SizedBox(height: 6),
                Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: active ? _sosRed : Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );
}

/// «Мої координати» (ADR-022 §22.3 п.8): великими цифрами, щоб продиктувати 112; «Скопіювати»;
/// погана точність — попередження про можливі збої GPS (§22.5 п.5).
class MyCoordinatesCard extends ConsumerStatefulWidget {
  const MyCoordinatesCard({super.key, this.dark = false, this.autoLocate = true});

  /// На червоному екрані SOS.
  final bool dark;
  final bool autoLocate;

  @override
  ConsumerState<MyCoordinatesCard> createState() => _MyCoordinatesCardState();
}

class _MyCoordinatesCardState extends ConsumerState<MyCoordinatesCard> {
  SafetyFix? _fix;
  LocateError? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoLocate) WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  Future<void> _locate() async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = await ref.read(safetyDeviceProvider).locate();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _fix = r.fix ?? _fix;
      _error = r.fix == null ? r.error : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.dark ? Colors.white : const Color(0xff14532d);
    final dim = fg.withValues(alpha: 0.75);
    final fix = _fix;
    return Container(
      key: const ValueKey('my-coordinates'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: widget.dark ? Colors.white.withValues(alpha: 0.15) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.my_location_rounded, color: fg, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Мої координати', style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 16))),
              if (_busy)
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
              else
                IconButton(
                  key: const ValueKey('coords-refresh'),
                  onPressed: _locate,
                  icon: Icon(Icons.refresh_rounded, color: fg),
                  tooltip: 'Оновити',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          if (fix != null) ...[
            const SizedBox(height: 4),
            SelectableText(fix.decimal,
                key: const ValueKey('coords-decimal'),
                style: TextStyle(color: fg, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            Text(fix.dms, style: TextStyle(color: dim, fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              fix.lowAccuracy
                  ? 'Точність низька (±${fix.accuracyM.round()} м) — можливі збої GPS. Вийдіть на відкрите місце й оновіть.'
                  : 'Точність ±${fix.accuracyM.round()} м',
              key: const ValueKey('coords-accuracy'),
              style: TextStyle(
                color: fix.lowAccuracy ? (widget.dark ? const Color(0xffffe082) : const Color(0xffb45309)) : dim,
                fontSize: 12.5,
                fontWeight: fix.lowAccuracy ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('coords-copy'),
                onPressed: () async {
                  await ref.read(safetyDeviceProvider).copy(fix.decimal);
                  if (!context.mounted) return;
                  ScaffoldMessenger.maybeOf(context)
                    ?..hideCurrentSnackBar()
                    ..showSnackBar(const SnackBar(content: Text('Координати скопійовано')));
                },
                style: TextButton.styleFrom(foregroundColor: fg),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Скопіювати'),
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                switch (_error) {
                  LocateError.denied => 'Дозвольте доступ до геолокації, щоб бачити свої координати.',
                  LocateError.unavailable => 'Не вдалося визначити місце. Вийдіть на відкрите місце й оновіть.',
                  null => _busy ? 'Визначаємо місце…' : 'Натисніть ⟳, щоб визначити місце.',
                },
                key: const ValueKey('coords-status'),
                style: TextStyle(color: dim),
              ),
            ),
        ],
      ),
    );
  }
}

/// Світловий сигнал SOS (ADR-022 §22.3 п.17): екран і спалах блимають азбукою Морзе
/// (··· — — — ···), екран не гасне. Дотик — вийти.
class LightSignalScreen extends ConsumerStatefulWidget {
  const LightSignalScreen({super.key});

  @override
  ConsumerState<LightSignalScreen> createState() => _LightSignalScreenState();
}

class _LightSignalScreenState extends ConsumerState<LightSignalScreen> {
  late final SafetyDevice _device = ref.read(safetyDeviceProvider);
  final _steps = morseSos();
  Timer? _timer;
  int _i = 0;
  bool _on = false;
  bool _torch = true;

  @override
  void initState() {
    super.initState();
    _device.keepAwake(true);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _step();
  }

  void _step() {
    final s = _steps[_i];
    setState(() => _on = s.on);
    if (_torch) {
      _device.torch(s.on).then((ok) {
        if (!ok && mounted) setState(() => _torch = false); // немає спалаху — лише екран
      });
    }
    _timer = Timer(s.d, () {
      if (!mounted) return;
      _i = (_i + 1) % _steps.length;
      _step();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _device.torch(false);
    _device.keepAwake(false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        key: const ValueKey('light-signal'),
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: ColoredBox(
          color: _on ? Colors.white : Colors.black,
          child: SizedBox.expand(
            child: SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Text(
                    '··· — — — ···  Торкніться, щоб вийти',
                    style: TextStyle(color: _on ? Colors.black54 : Colors.white54, fontSize: 14, decoration: TextDecoration.none),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
