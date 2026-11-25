import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/features/catalog/catalog_motion.dart' show reduceMotion;
import 'package:flutter_client/features/recognize/ai_model.dart';
import 'package:flutter_client/features/recognize/capture_screen.dart';
import 'package:flutter_client/features/recognize/recognition_flow.dart';

/// Банер-камера вгорі «Розпізнати» (рішення PO 2026-11-17): темно-зелений видошукач із куточками.
/// Моделі немає — «Завантажити ШІ» з прогресом прямо на банері; є — «Зробити 3 фото». Сканувальна
/// лінія пробігає кілька разів; оновлення й видалення моделі — у меню «⋮».
class RecognizeBanner extends ConsumerStatefulWidget {
  const RecognizeBanner({super.key, this.camera});

  /// Камера для знімка (у тестах — підміна).
  final CaptureCamera Function()? camera;

  @override
  ConsumerState<RecognizeBanner> createState() => _RecognizeBannerState();
}

class _RecognizeBannerState extends ConsumerState<RecognizeBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _scan = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!reduceMotion(context)) _scan.repeat(count: 3);
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  Future<void> _recognize() async {
    final nav = Navigator.of(context);
    while (mounted) {
      final photos = await nav.push<List<Uint8List>>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CaptureScreen(camera: (widget.camera ?? DeviceCamera.new)()),
      ));
      if (photos == null || photos.isEmpty || !mounted) return;
      final retake = await nav.push<bool>(MaterialPageRoute(builder: (_) => RecognitionFlowScreen(photos: List<Uint8List>.of(photos))));
      if (retake != true) return; // «Перезняти» — знову до камери
    }
  }

  Future<void> _confirmDelete(int bytes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Видалити ШІ-розпізнавач?'),
        content: Text('Звільнить ${_mb(bytes)}. Довідник лишиться, а розпізнавати за фото можна буде після нового завантаження.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Скасувати')),
          TextButton(key: const ValueKey('ai-delete-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Видалити')),
        ],
      ),
    );
    if (ok == true) await ref.read(aiModelProvider.notifier).deleteModel();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(aiModelProvider);
    final ctrl = ref.read(aiModelProvider.notifier);
    final ready = s.ready && !s.downloading;
    Widget center;
    if (!s.checked) {
      center = const SizedBox.shrink();
    } else if (ready) {
      center = Column(
        key: const ValueKey('ai-ready'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), shape: BoxShape.circle),
            child: const Icon(Icons.photo_camera_rounded, color: Colors.white),
          ),
          const SizedBox(height: 8),
          const Text('Зробити 3 фото', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          Text('Шапка · Ніжка · Зріз', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
        ],
      );
    } else if (s.downloading) {
      center = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Завантаження ШІ…', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: s.bytesTotal == 0 ? null : s.bytesDone / s.bytesTotal,
              color: const Color(0xffa5d6a7),
              backgroundColor: Colors.white24,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 6),
            Text('${_mb(s.bytesDone)} з ${_mb(s.bytesTotal)}', key: const ValueKey('ai-subtitle'), style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
            TextButton(
              key: const ValueKey('ai-stop'),
              onPressed: ctrl.stop,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Зупинити'),
            ),
          ],
        ),
      );
    } else {
      final remote = s.remote;
      center = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 30),
            const SizedBox(height: 6),
            const Text('ШІ-розпізнавання', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              remote == null ? 'Модель завантажиться, коли буде інтернет.' : 'Завантажте один раз — далі розпізнає гриб за фото без інтернету.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
            ),
            if (s.error != null) ...[
              const SizedBox(height: 4),
              Text(s.error!, key: const ValueKey('ai-error'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Color(0xffffcdd2))),
            ],
            if (remote != null) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const ValueKey('ai-download'),
                onPressed: ctrl.start,
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppTheme.darkGreen),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text('${s.bytesDone > 0 || s.error != null ? 'Продовжити' : 'Завантажити ШІ'} · ${_mb(remote.totalBytes)}'),
              ),
              const SizedBox(height: 4),
              Text('Краще через Wi‑Fi', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11)),
            ],
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        key: const ValueKey('ai-banner'),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('ai-shoot'),
          onTap: ready ? _recognize : null,
          child: Ink(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xff2f4a3a), Color(0xff4a6b54), Color(0xff6b8570)]),
            ),
            // Звичайно 210 px; з великим шрифтом банер росте, а не обрізає кнопку (UI-001).
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 210),
              child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _scan,
                      builder: (context, _) => CustomPaint(painter: _ViewfinderPainter(_scan.isAnimating ? _scan.value : -1)),
                    ),
                  ),
                ),
                Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: center),
                if (s.updateAvailable && !s.downloading)
                  Positioned(
                    left: 14,
                    top: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xffffc928), borderRadius: BorderRadius.circular(20)),
                      child: const Text('Нова версія ШІ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xff4a3b00))),
                    ),
                  ),
                if (s.ready && !s.downloading)
                  Positioned(
                    right: 2,
                    top: 2,
                    child: PopupMenuButton<String>(
                      key: const ValueKey('ai-menu'),
                      icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                      onSelected: (v) => v == 'update' ? ctrl.start() : _confirmDelete(s.installed!.totalBytes),
                      itemBuilder: (_) => [
                        if (s.updateAvailable)
                          PopupMenuItem(value: 'update', child: Text('Оновити ШІ · ${_mb(s.remote!.totalBytes)}')),
                        PopupMenuItem(key: const ValueKey('ai-delete'), value: 'delete', child: Text('Видалити ШІ · ${_mb(s.installed!.totalBytes)}')),
                      ],
                    ),
                  ),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }
}

String _mb(int bytes) => '${(bytes / (1024 * 1024)).round()} МБ';

/// Куточки видошукача і сканувальна лінія ([scan] 0…1; < 0 — немає).
class _ViewfinderPainter extends CustomPainter {
  _ViewfinderPainter(this.scan);

  final double scan;

  @override
  void paint(Canvas canvas, Size size) {
    const m = 16.0, k = 30.0;
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final r = Rect.fromLTRB(m, m, size.width - m, size.height - m);
    for (final (o, dx, dy) in [(r.topLeft, 1.0, 1.0), (r.topRight, -1.0, 1.0), (r.bottomLeft, 1.0, -1.0), (r.bottomRight, -1.0, -1.0)]) {
      canvas.drawPath(Path()..moveTo(o.dx, o.dy + dy * k)..lineTo(o.dx, o.dy)..lineTo(o.dx + dx * k, o.dy), p);
    }
    if (scan < 0) return;
    // Лінія ходить униз-угору, з м'яким світінням.
    final t = scan < 0.5 ? scan * 2 : 2 - scan * 2;
    final y = r.top + 8 + (r.height - 16) * Curves.easeInOut.transform(t);
    final glow = Rect.fromLTRB(r.left + 10, y - 14, r.right - 10, y + 14);
    canvas.drawRect(
      glow,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0), const Color(0xffa5d6a7).withValues(alpha: 0.35), Colors.white.withValues(alpha: 0)],
        ).createShader(glow),
    );
    canvas.drawLine(Offset(r.left + 10, y), Offset(r.right - 10, y), Paint()
      ..color = const Color(0xffc8e6c9)
      ..strokeWidth = 1.6);
  }

  @override
  bool shouldRepaint(covariant _ViewfinderPainter old) => old.scan != scan;
}
