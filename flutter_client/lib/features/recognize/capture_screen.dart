import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_client/core/image_decode.dart';

/// Знімок гриба у 3 кроки на весь екран (рішення PO 2026-11-17): шапка → ніжка → зріз. Живий видошукач
/// з контуром-підказкою для кожного кроку, мініатюри знятого внизу, спалах і галочка після кадру.
/// Ніжку й зріз можна пропустити. Лише камера, без галереї (ADR-015 §18.6). Повертає кадри (JPEG).

/// Крок знімка.
class CaptureStep {
  const CaptureStep(this.title, this.hint, this.guide);

  final String title;
  final String hint;

  /// Що малює контур-підказка: `cap | stem | cut`.
  final String guide;
}

const kCaptureSteps = [
  CaptureStep('Шапка', 'Наведіть камеру на шапку гриба зверху або трохи збоку', 'cap'),
  CaptureStep('Ніжка', 'Тепер ніжка збоку — цілком у кадрі, разом із низом шапки', 'stem'),
  CaptureStep('Зріз', 'Останній кадр: зріз ніжки або низ шапки зблизька', 'cut'),
];

/// Камера (у тестах — підміна без пристрою).
abstract class CaptureCamera {
  Future<void> init();
  Widget preview();
  Future<Uint8List> take();
  Future<void> dispose();
}

class DeviceCamera implements CaptureCamera {
  CameraController? _c;

  @override
  Future<void> init() async {
    final cams = await availableCameras();
    if (cams.isEmpty) throw CameraException('no_camera', 'Камеру не знайдено');
    final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
    final c = CameraController(back, ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
    await c.initialize();
    _c = c;
  }

  @override
  Widget preview() {
    final c = _c;
    if (c == null) return const SizedBox.shrink();
    // Видошукач на весь екран без спотворень: обрізаємо зайве по краях.
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(width: c.value.previewSize?.height ?? 1080, height: c.value.previewSize?.width ?? 1920, child: CameraPreview(c)),
    );
  }

  @override
  Future<Uint8List> take() async => (await _c!.takePicture()).readAsBytes();

  @override
  Future<void> dispose() async => _c?.dispose();
}

/// Відкрити знімок; `null` — скасовано.
Future<List<Uint8List>?> showCapture(BuildContext context, {CaptureCamera Function()? camera}) =>
    Navigator.of(context).push<List<Uint8List>>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CaptureScreen(camera: (camera ?? DeviceCamera.new)()),
    ));

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, required this.camera});

  final CaptureCamera camera;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> with TickerProviderStateMixin {
  final _shots = <Uint8List>[];
  late final AnimationController _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  bool _ready = false, _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.camera.init().then((_) {
      if (mounted) setState(() => _ready = true);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = 'Не вдалося відкрити камеру. Дозвольте доступ до камери в налаштуваннях телефону.');
    });
  }

  @override
  void dispose() {
    _flash.dispose();
    widget.camera.dispose();
    super.dispose();
  }

  int get _step => _shots.length;

  Future<void> _shoot() async {
    if (_busy || !_ready) return;
    setState(() => _busy = true);
    try {
      final bytes = await widget.camera.take();
      HapticFeedback.lightImpact();
      _flash.forward(from: 0);
      setState(() => _shots.add(bytes));
      if (_shots.length == kCaptureSteps.length) {
        await Future<void>.delayed(const Duration(milliseconds: 450)); // встигнути побачити третю галочку
        if (mounted) Navigator.of(context).pop(List<Uint8List>.of(_shots));
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Не вдалося зробити фото — спробуйте ще раз.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _skip() => Navigator.of(context).pop(List<Uint8List>.of(_shots));

  @override
  Widget build(BuildContext context) {
    final step = kCaptureSteps[math.min(_step, kCaptureSteps.length - 1)];
    return Scaffold(
      key: const ValueKey('capture-screen'),
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_ready) widget.camera.preview(),
          // Затемнення довкола рамки, куточки й контур-підказка кроку.
          IgnorePointer(child: CustomPaint(painter: _GuidePainter(step.guide))),
          // Спалах після кадру.
          IgnorePointer(
            child: FadeTransition(
              opacity: Tween(begin: 0.85, end: 0.0).animate(_flash),
              child: AnimatedBuilder(
                animation: _flash,
                builder: (context, _) => _flash.isAnimating ? Container(color: Colors.white) : const SizedBox.shrink(),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 12),
                Text('Крок ${math.min(_step + 1, 3)} з 3 · ${step.title}',
                    key: const ValueKey('capture-step'),
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
                  child: Text(step.hint, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, key: const ValueKey('capture-error'), textAlign: TextAlign.center, style: const TextStyle(color: Color(0xffffcdd2))),
                  ),
                const Spacer(),
                // Мініатюри: зняте — з галочкою, наступне — номер.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < kCaptureSteps.length; i++)
                      Container(
                        key: ValueKey('capture-slot-$i'),
                        width: 58,
                        height: 58,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: i == _step ? Colors.white : Colors.white38, width: i == _step ? 2.5 : 1.5),
                          color: Colors.white10,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: i < _shots.length
                            ? Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image(
                                    // Мініатюра 58×58 — не розкодовувати весь кадр (PERF-001).
                                    image: coverDecoded(MemoryImage(_shots[i]), const Size(58, 58), context),
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                    errorBuilder: (_, __, ___) => const SizedBox(),
                                  ),
                                  const Align(
                                    alignment: Alignment.bottomRight,
                                    child: Padding(
                                      padding: EdgeInsets.all(3),
                                      child: Icon(Icons.check_circle_rounded, color: Color(0xff66bb6a), size: 20),
                                    ),
                                  ),
                                ],
                              )
                            : Center(
                                child: Text(kCaptureSteps[i].title,
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w700)),
                              ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: TextButton(
                          key: const ValueKey('capture-cancel'),
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(foregroundColor: Colors.white),
                          child: const Text('Скасувати'),
                        ),
                      ),
                    ),
                    // Кнопка знімка.
                    GestureDetector(
                      key: const ValueKey('capture-shutter'),
                      onTap: _shoot,
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                        padding: const EdgeInsets.all(5),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(shape: BoxShape.circle, color: _busy || !_ready ? Colors.white38 : Colors.white),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: _step > 0 && _step < kCaptureSteps.length
                            ? TextButton(
                                key: const ValueKey('capture-skip'),
                                onPressed: _skip,
                                style: TextButton.styleFrom(foregroundColor: Colors.white),
                                child: const Text('Пропустити'),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Рамка видошукача з куточками й контур гриба-підказки: шапка / ніжка / зріз.
class _GuidePainter extends CustomPainter {
  _GuidePainter(this.guide);

  final String guide;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width * 0.78, size.height * 0.5);
    final frame = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.45), width: side, height: side);
    // Затемнення довкола рамки.
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(RRect.fromRectAndRadius(frame, const Radius.circular(22))),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    // Куточки.
    final corner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    const k = 28.0;
    for (final (o, dx, dy) in [
      (frame.topLeft, 1.0, 1.0),
      (frame.topRight, -1.0, 1.0),
      (frame.bottomLeft, 1.0, -1.0),
      (frame.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawPath(Path()..moveTo(o.dx, o.dy + dy * k)..lineTo(o.dx, o.dy)..lineTo(o.dx + dx * k, o.dy), corner);
    }
    // Контур-підказка (пунктиром).
    final s = side / 100;
    final c = frame.center;
    final guidePath = Path();
    switch (guide) {
      case 'cap':
        guidePath
          ..moveTo(c.dx - 38 * s, c.dy + 8 * s)
          ..cubicTo(c.dx - 38 * s, c.dy - 34 * s, c.dx + 38 * s, c.dy - 34 * s, c.dx + 38 * s, c.dy + 8 * s)
          ..quadraticBezierTo(c.dx, c.dy + 18 * s, c.dx - 38 * s, c.dy + 8 * s);
      case 'stem':
        guidePath
          ..moveTo(c.dx - 30 * s, c.dy - 22 * s)
          ..cubicTo(c.dx - 30 * s, c.dy - 44 * s, c.dx + 30 * s, c.dy - 44 * s, c.dx + 30 * s, c.dy - 22 * s)
          ..quadraticBezierTo(c.dx, c.dy - 14 * s, c.dx - 30 * s, c.dy - 22 * s)
          ..moveTo(c.dx - 9 * s, c.dy - 18 * s)
          ..quadraticBezierTo(c.dx - 13 * s, c.dy + 20 * s, c.dx - 11 * s, c.dy + 40 * s)
          ..lineTo(c.dx + 11 * s, c.dy + 40 * s)
          ..quadraticBezierTo(c.dx + 13 * s, c.dy + 20 * s, c.dx + 9 * s, c.dy - 18 * s);
      default: // зріз: розрізаний навпіл гриб
        guidePath
          ..moveTo(c.dx - 34 * s, c.dy - 6 * s)
          ..cubicTo(c.dx - 34 * s, c.dy - 40 * s, c.dx + 34 * s, c.dy - 40 * s, c.dx + 34 * s, c.dy - 6 * s)
          ..lineTo(c.dx - 34 * s, c.dy - 6 * s)
          ..moveTo(c.dx - 12 * s, c.dy - 6 * s)
          ..lineTo(c.dx - 12 * s, c.dy + 38 * s)
          ..lineTo(c.dx + 12 * s, c.dy + 38 * s)
          ..lineTo(c.dx + 12 * s, c.dy - 6 * s)
          ..moveTo(c.dx, c.dy - 30 * s)
          ..lineTo(c.dx, c.dy + 38 * s);
    }
    final dash = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final m in guidePath.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 12) {
        canvas.drawPath(m.extractPath(d, math.min(d + 7, m.length)), dash);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GuidePainter old) => old.guide != guide;
}
