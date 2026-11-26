import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/features/map/region_camera.dart';
import 'package:flutter_client/features/picks/mushroom_marker.dart';

/// Гриб для мінікарти: вид і його рівень на обраний день (усе — підписи із сервера).
class StickerSpecies {
  const StickerSpecies({
    required this.type,
    required this.name,
    required this.level,
    required this.levelLabel,
    required this.color,
    required this.whenLabel,
  });

  final String type;
  final String name;

  /// `peak | high | medium | low | no_data`; `null` — цього дня виду немає серед найкращих.
  final String? level;
  final String levelLabel;
  final Color color;
  final String whenLabel;
}

/// Нерухома камера мінікарти: центр і масштаб, у які вміщується ділянка.
class StickerCamera {
  const StickerCamera({required this.center, required this.zoom, required this.size});

  final LatLng center;
  final double zoom;
  final Size size;

  Offset toScreen(LatLng p) => projectToScreen(p, center, zoom, size);
  LatLng toLatLng(Offset o) => screenToLatLng(o, center, zoom, size);
}

/// Гриби поверх мінікарти ділянки (ADR-015 §15.9). Спочатку карта порожня: усі гриби зі шансом
/// на обраний день лежать у плетеному кошику в кутку карти (з-за краю видно капелюшки, вони
/// підстрибують). Торкнутися кошика — «заглянути»: кошик нахиляється й збільшується, далі
/// вигляд згори з грибами всередині. Торкнутися гриба — його назва; затиснути — кошик стискається
/// в куток, гриб їде за пальцем на карту. Поставлений гриб можна пересунути або перенести назад
/// у кошик. Усе — в межах мінікарти.
class StickerBoard extends StatefulWidget {
  const StickerBoard({
    super.key,
    required this.camera,
    required this.species,
    required this.positions,
    required this.onMove,
    required this.onRemove,
    required this.map,
    this.history = const [],
  });

  final StickerCamera camera;

  /// Гриби зі шансом обраного дня (кошик).
  final List<StickerSpecies> species;

  /// Поставлені гриби: вид → точка.
  final Map<String, LatLng> positions;
  final void Function(String type, LatLng point) onMove;
  final void Function(String type) onRemove;

  /// Карта під грибами (у тестах — будь-який віджет).
  final Widget map;

  /// Ваші знахідки торік у ці тижні — бліді мітки під грибами (тап — дата й вид).
  final List<({LatLng point, String type, String name, String dateLabel})> history;

  @override
  State<StickerBoard> createState() => _StickerBoardState();
}

class _StickerBoardState extends State<StickerBoard> with TickerProviderStateMixin {
  /// Гриб на карті — дрібніший, щоб не закривати ліс (мінікарта тепер рівно на ділянку).
  static const double _stickerSize = 30;

  /// Гриб у відкритому кошику — великий, як справжній гриб у кошику (менше грибів — більші).
  static double _inBasketSize(int n) => n <= 3 ? 84 : (n <= 6 ? 72 : 60);
  static const Size _basketSize = Size(60, 52);

  late final AnimationController _open =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final AnimationController _bob = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  /// Гриб, який зараз тягнуть: вид і позиція «ніжки» на мінікарті.
  String? _dragging;
  Offset? _dragAt;
  bool _dragFromBasket = false;
  String? _tooltipFor;

  /// Відкритий підпис торішньої знахідки.
  int? _historyTip;
  String? _nameFor;
  final GlobalKey _boardKey = GlobalKey();

  // Назви видів, що вже стоять на карті, але цього дня не серед грибів зі шансом.
  final Map<String, String> _names = {};

  bool get _reduceMotion => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _open.duration = _reduceMotion ? Duration.zero : const Duration(milliseconds: 520);
    if (_reduceMotion) {
      _bob.stop();
    } else if (!_bob.isAnimating) {
      _bob.repeat();
    }
  }

  @override
  void dispose() {
    _open.dispose();
    _bob.dispose();
    super.dispose();
  }

  Size get _size => widget.camera.size;

  /// Кошик — у правому нижньому куті мінікарти.
  Rect get _basketRect => Rect.fromLTWH(
        _size.width - _basketSize.width - 8,
        _size.height - _basketSize.height - 8,
        _basketSize.width,
        _basketSize.height,
      );

  bool _overBasket(Offset p) => _basketRect.inflate(14).contains(p);

  StickerSpecies _speciesFor(String type) => widget.species.firstWhere(
        (s) => s.type == type,
        orElse: () => StickerSpecies(
          type: type,
          name: _names[type] ?? type,
          level: null,
          levelLabel: 'Цього дня шансу немає',
          color: const Color(0xff94a3b8),
          whenLabel: '',
        ),
      );

  List<StickerSpecies> get _inBasket => widget.species.where((s) => !widget.positions.containsKey(s.type)).toList();

  Offset _local(Offset global) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    final p = box == null ? global : box.globalToLocal(global);
    return Offset(p.dx.clamp(0, _size.width), p.dy.clamp(0, _size.height));
  }

  void _toggleBasket() {
    setState(() {
      _nameFor = null;
      _tooltipFor = null;
    });
    if (_open.value > 0.5) {
      _open.reverse();
    } else {
      _open.forward();
    }
  }

  // ─── Перетягування ──────────────────────────────────────────────────────

  void _startDrag(String type, Offset global, {required bool fromBasket}) {
    setState(() {
      _dragging = type;
      _dragAt = _local(global);
      _dragFromBasket = fromBasket;
      _tooltipFor = null;
      _nameFor = null;
    });
    // З кошика — кошик стискається в куток, щоб було видно карту.
    if (fromBasket) _open.reverse();
  }

  void _moveDrag(Offset global) => setState(() => _dragAt = _local(global));

  void _endDrag() {
    final type = _dragging, at = _dragAt, fromBasket = _dragFromBasket;
    setState(() {
      _dragging = null;
      _dragAt = null;
      _dragFromBasket = false;
    });
    if (type == null || at == null) return;
    if (_overBasket(at)) {
      if (!fromBasket) widget.onRemove(type); // назад у кошик
      return;
    }
    widget.onMove(type, widget.camera.toLatLng(at));
  }

  @override
  Widget build(BuildContext context) {
    for (final s in widget.species) {
      _names[s.type] = s.name;
    }
    final placed = widget.positions.keys.where((t) => t != _dragging || !_dragFromBasket).toList();
    return Column(
      // Карта — рівно розміру камери: гриби й карта в одному масштабі.
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            key: _boardKey,
            width: _size.width,
            height: _size.height,
            child: AnimatedBuilder(
              animation: _open,
              builder: (context, _) => Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(child: widget.map),
                  for (var i = 0; i < widget.history.length; i++) _historyMark(i),
                  if (_historyTip != null && _historyTip! < widget.history.length) _historyTooltip(_historyTip!),
                  // Підпис гриба відкритий — торкнутися будь-де повз нього, щоб закрити.
                  if (_tooltipFor != null || _historyTip != null)
                    Positioned.fill(
                      child: GestureDetector(
                        key: const ValueKey('tooltip-dismiss'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() {
                          _tooltipFor = null;
                          _historyTip = null;
                        }),
                      ),
                    ),
                  for (final type in placed) _placed(type),
                  if (_tooltipFor != null && widget.positions[_tooltipFor] != null) _tooltip(_tooltipFor!),
                  _closedBasket(),
                  if (_open.value > 0 || (_dragging != null && _dragFromBasket)) _openBasket(),
                  if (_dragging != null && _dragAt != null)
                    Positioned(
                      left: _dragAt!.dx - _stickerSize / 2,
                      top: _dragAt!.dy - _stickerSize,
                      child: IgnorePointer(
                        child: Transform.scale(
                          scale: 1.25,
                          child: MushroomSticker(species: _speciesFor(_dragging!), size: _stickerSize),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Гриби на карті ─────────────────────────────────────────────────────

  Widget _placed(String type) {
    final s = _speciesFor(type);
    final dragging = _dragging == type && _dragAt != null;
    final at = widget.camera.toScreen(widget.positions[type]!);
    return Positioned(
      key: ValueKey('placed-$type'),
      left: at.dx - _stickerSize / 2,
      top: at.dy - _stickerSize,
      child: GestureDetector(
        onTap: () => setState(() => _tooltipFor = _tooltipFor == type ? null : type),
        onLongPressStart: (d) => _startDrag(type, d.globalPosition, fromBasket: false),
        onLongPressMoveUpdate: (d) => _moveDrag(d.globalPosition),
        onLongPressEnd: (_) => _endDrag(),
        child: Opacity(opacity: dragging ? 0 : 1, child: MushroomSticker(species: s, size: _stickerSize)),
      ),
    );
  }

  // ─── Торішні знахідки ───────────────────────────────────────────────────

  Widget _historyMark(int i) {
    final h = widget.history[i];
    final at = widget.camera.toScreen(h.point);
    const size = 22.0;
    return Positioned(
      key: ValueKey('history-$i'),
      left: at.dx - size / 2,
      top: at.dy - size / 2,
      child: GestureDetector(
        onTap: () => setState(() {
          _tooltipFor = null;
          _historyTip = _historyTip == i ? null : i;
        }),
        child: Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xff8d6e63), width: 1.5),
          ),
          child: Opacity(opacity: 0.75, child: SpeciesIcon(type: h.type, fallbackColor: const Color(0xff8d6e63), size: 16)),
        ),
      ),
    );
  }

  Widget _historyTooltip(int i) {
    final h = widget.history[i];
    final at = widget.camera.toScreen(h.point);
    const width = 190.0;
    final left = (at.dx - width / 2).clamp(4.0, _size.width - width - 4);
    return Positioned(
      left: left,
      top: at.dy > 60 ? at.dy - 48 : at.dy + 14,
      width: width,
      child: IgnorePointer(
        child: Center(
          child: Container(
            key: ValueKey('history-tip-$i'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(10)),
            child: Text(
              'Торік ${h.dateLabel} · ${h.name}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xff5d4037)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tooltip(String type) {
    final s = _speciesFor(type);
    final at = widget.camera.toScreen(widget.positions[type]!);
    const width = 200.0;
    final left = (at.dx - width / 2).clamp(4.0, _size.width - width - 4);
    final above = at.dy > 90;
    return Positioned(
      left: left,
      top: above ? at.dy - _stickerSize - 52 : at.dy + 8,
      width: width,
      child: IgnorePointer(child: Center(child: _NameLabel(species: s, key: ValueKey('tooltip-$type')))),
    );
  }

  // ─── Кошик: закритий (збоку) ────────────────────────────────────────────

  Widget _closedBasket() {
    final t = _open.value;
    // «Заглядання»: кошик нахиляється до грибника й збільшується, потім зникає у вигляд згори.
    final tilt = (t / 0.45).clamp(0.0, 1.0);
    final hover = _dragging != null && !_dragFromBasket && _dragAt != null && _overBasket(_dragAt!);
    final r = _basketRect;
    final peek = _inBasket.take(3).toList();
    return Positioned(
      left: r.left,
      top: r.top,
      width: r.width,
      height: r.height,
      child: Opacity(
        opacity: t < 0.5 ? 1 : (1 - (t - 0.5) * 2).clamp(0.0, 1.0),
        child: GestureDetector(
          key: const ValueKey('basket'),
          onTap: _toggleBasket,
          child: Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.003)
              ..scaleByDouble(1 + 0.45 * tilt + (hover ? 0.2 : 0), 1 + 0.45 * tilt + (hover ? 0.2 : 0), 1, 1)
              ..rotateX(-0.85 * tilt),
            child: AnimatedBuilder(
              animation: _bob,
              builder: (context, _) => Stack(
                clipBehavior: Clip.none,
                children: [
                  // Капелюшки з-за краю кошика — по черзі легенько підстрибують.
                  for (var i = 0; i < peek.length; i++)
                    Positioned(
                      left: 8 + i * 15.0,
                      top: 2 - _peekJump(i, peek.length),
                      child: SpeciesIcon(type: peek[i].type, fallbackColor: peek[i].color, size: 24),
                    ),
                  Positioned.fill(child: CustomPaint(painter: _BasketPainter(glow: hover))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _peekJump(int i, int n) {
    if (_reduceMotion) return 0;
    final phase = (_bob.value + i / math.max(1, n)) % 1;
    final w = math.sin(phase * 2 * math.pi);
    return w > 0.4 ? (w - 0.4) / 0.6 * 4 : 0;
  }

  // ─── Кошик: відкритий (вигляд згори) ────────────────────────────────────

  Widget _openBasket() {
    final t = _open.value;
    final appear = ((t - 0.35) / 0.65).clamp(0.0, 1.0);
    final g = BasketGeometry.fit(_size);
    final items = _inBasket;
    // Звідки «виростає» відкритий кошик — з кошика в куті.
    final origin = Alignment(
      (_basketRect.center.dx / _size.width) * 2 - 1,
      (_basketRect.center.dy / _size.height) * 2 - 1,
    );
    return Positioned.fill(
      child: Stack(
        children: [
          // Тло: торкнутися повз гриби — закрити кошик.
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('basket-backdrop'),
              onTap: _toggleBasket,
              child: Container(color: Colors.black.withValues(alpha: 0.28 * appear)),
            ),
          ),
          Positioned.fill(
            child: Transform.scale(
              scale: 0.3 + 0.7 * appear,
              alignment: origin,
              child: Opacity(
                opacity: appear,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        key: const ValueKey('basket-open'),
                        behavior: HitTestBehavior.translucent,
                        // Відкрита назва гриба — перше торкання повз неї лише закриває її.
                        onTap: () => _nameFor != null ? setState(() => _nameFor = null) : _toggleBasket(),
                        child: CustomPaint(painter: OpenBasketPainter(g)),
                      ),
                    ),
                    for (var i = 0; i < items.length; i++)
                      _inBasketItem(items[i], g.slot(i, items.length), _inBasketSize(items.length)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Гриб лежить на дні кошика: трохи нахилений, з м'якою тінню під собою.
  Widget _inBasketItem(StickerSpecies s, Offset at, double size) {
    final seed = s.type.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0x7fffffff);
    final tilt = ((seed % 9) - 4) * 0.07;
    final bobY = _reduceMotion ? 0.0 : math.sin((_bob.value + seed % 7 / 7) * 2 * math.pi) * 1.2;
    return Positioned(
      key: ValueKey('basket-${s.type}'),
      left: at.dx - size / 2,
      top: at.dy - size * 0.8,
      child: GestureDetector(
        onTap: () => setState(() => _nameFor = _nameFor == s.type ? null : s.type),
        onLongPressStart: (d) => _startDrag(s.type, d.globalPosition, fromBasket: true),
        onLongPressMoveUpdate: (d) => _moveDrag(d.globalPosition),
        onLongPressEnd: (_) => _endDrag(),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            // Тінь на дні кошика.
            Positioned(
              top: size * 0.7,
              child: IgnorePointer(
                child: Container(
                  width: size * 0.82,
                  height: size * 0.26,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.elliptical(size * 0.41, size * 0.13)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 5, spreadRadius: -1),
                    ],
                  ),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(0, bobY),
              child: Transform.rotate(
                angle: tilt,
                child: Opacity(
                  opacity: _dragging == s.type ? 0.2 : 1,
                  child: MushroomSticker(species: s, size: size),
                ),
              ),
            ),
            if (_nameFor == s.type)
              Positioned(
                bottom: size + 2,
                child: IgnorePointer(child: _NameLabel(species: s)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Підпис гриба: лише вид і рівень, напівпрозорий білий фон.
class _NameLabel extends StatelessWidget {
  const _NameLabel({super.key, required this.species});

  final StickerSpecies species;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '${species.name} · ${species.levelLabel}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: species.level == null ? AppTheme.darkGreen : Color.lerp(species.color, Colors.black, 0.25),
          ),
        ),
      );
}

/// Плетений кошик збоку (закритий, у кутку мінікарти) — у тому ж стилі, що й відкритий:
/// лоза «в шахівницю», плетений обідок, обмотана ручка, тінь на карті.
class _BasketPainter extends CustomPainter {
  _BasketPainter({this.glow = false});

  final bool glow;

  static const _light = OpenBasketPainter._light;
  static const _mid = OpenBasketPainter._mid;
  static const _dark = OpenBasketPainter._dark;
  static const _deep = OpenBasketPainter._deep;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rimY = h * 0.4;
    final rimH = h * 0.11;
    // Тінь на карті.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.52, h * 0.98), width: w * 0.9, height: h * 0.14),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // Ручка — обмотана лозою.
    final handle = Path()
      ..moveTo(w * 0.2, rimY)
      ..cubicTo(w * 0.2, -h * 0.12, w * 0.8, -h * 0.12, w * 0.8, rimY);
    canvas.drawPath(handle, Paint()
      ..color = _deep
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.07
      ..strokeCap = StrokeCap.round);
    final wrap = Paint()
      ..color = _mid
      ..strokeWidth = w * 0.025
      ..strokeCap = StrokeCap.round;
    for (final m in handle.computeMetrics()) {
      for (var d = 2.0; d < m.length - 2; d += w * 0.055) {
        final tg = m.getTangentForOffset(d)!;
        final n = Offset(-tg.vector.dy, tg.vector.dx) * (w * 0.03);
        canvas.drawLine(tg.position - n - tg.vector * 1.5, tg.position + n + tg.vector * 1.5, wrap);
      }
    }
    // Корпус — трапеція з лозою «в шахівницю», темніше до боків.
    final body = Path()
      ..moveTo(w * 0.04, rimY)
      ..lineTo(w * 0.96, rimY)
      ..quadraticBezierTo(w * 0.9, h * 0.97, w * 0.8, h * 0.97)
      ..lineTo(w * 0.2, h * 0.97)
      ..quadraticBezierTo(w * 0.1, h * 0.97, w * 0.04, rimY)
      ..close();
    if (glow) {
      canvas.drawPath(body, Paint()
        ..color = const Color(0xffffd54f).withValues(alpha: 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    }
    canvas.save();
    canvas.clipPath(body);
    canvas.drawPath(body, Paint()..color = _mid);
    const rows = 4, cols = 7;
    final rowH = (h * 0.97 - rimY) / rows;
    for (var r = 0; r < rows; r++) {
      final y = rimY + r * rowH;
      for (var c = 0; c < cols; c++) {
        final cell = Rect.fromLTWH(w * c / cols, y, w / cols, rowH);
        final side = ((c + 0.5) / cols - 0.5).abs() * 2; // 0 — посередині, 1 — край
        canvas.drawRect(cell, Paint()..color = Color.lerp((r + c).isEven ? _light : _mid, _deep, side * 0.45)!);
        canvas.drawRect(cell, Paint()
          ..color = _deep.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7);
      }
    }
    canvas.restore();
    // Обідок — дві скручені лозини.
    final rim = RRect.fromRectAndRadius(Rect.fromLTWH(0, rimY - rimH / 2, w, rimH), Radius.circular(rimH / 2));
    canvas.drawRRect(rim, Paint()..color = _deep);
    final n = (w / (rimH * 0.7)).round();
    for (var i = 0; i < n; i++) {
      final cx = (i + 0.5) / n * w;
      canvas.save();
      canvas.translate(cx, rimY);
      canvas.rotate(0.6);
      final r = Rect.fromCenter(center: Offset.zero, width: rimH * 1.2, height: rimH * 0.55);
      canvas.drawOval(r, Paint()..color = _dark);
      canvas.drawOval(r.deflate(rimH * 0.1), Paint()..color = _light.withValues(alpha: 0.8));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BasketPainter old) => old.glow != glow;
}

/// Розміри відкритого кошика «згори під кутом» на мінікарті [area]: овал отвору, стінка
/// спереду, дно всередині, ручка за кошиком. Спільні для малювання й розкладки грибів.
class BasketGeometry {
  BasketGeometry._(this.center, this.rx, this.ry, this.wallH, this.handleRise);

  factory BasketGeometry.fit(Size area) {
    // Повна висота ≈ 0.82 ширини: ручка 0.18, отвір 0.48, стінка 0.16.
    final w = math.min(area.width * 0.94, area.height * 0.94 / 0.82);
    final top = (area.height - w * 0.82) / 2;
    final rx = w / 2 * 0.96;
    final ry = rx * 0.5;
    final handleRise = w * 0.18;
    return BasketGeometry._(Offset(area.width / 2, top + handleRise + ry), rx, ry, w * 0.16, handleRise);
  }

  /// Центр і півосі овалу отвору (обідка).
  final Offset center;
  final double rx;
  final double ry;

  /// Висота зовнішньої стінки під обідком.
  final double wallH;
  final double handleRise;

  /// Дно всередині: нижче центру отвору (дивимось згори спереду).
  Offset get floorCenter => center + Offset(0, ry * 0.3);
  double get floorRx => rx * 0.78;
  double get floorRy => ry * 0.7;

  /// Низ кошика зовні.
  Offset get bottomCenter => center + Offset(0, wallH);
  double get bottomRx => rx * 0.86;
  double get bottomRy => ry * 0.86;

  double get rimWidth => rx * 0.095;

  /// Точка на еліпсі ([a] — кут, 0 — праворуч, π/2 — спереду).
  static Offset onEllipse(Offset c, double rx, double ry, double a) => c + Offset(math.cos(a) * rx, math.sin(a) * ry);

  /// Де лежить i-й гриб із n: купкою на дні — зовнішнє коло (до 6), далі всередину.
  Offset slot(int i, int n) {
    final c = floorCenter + Offset(0, floorRy * 0.1);
    if (n == 1) return c;
    final outer = math.min(n, 6);
    if (i < outer) {
      final a = -math.pi / 2 + (i + 0.5) * 2 * math.pi / outer;
      return onEllipse(c, floorRx * 0.66, floorRy * 0.6, a);
    }
    final inner = n - outer;
    if (inner == 1) return c;
    final a = (i - outer) * 2 * math.pi / inner;
    return onEllipse(c, floorRx * 0.26, floorRy * 0.22, a);
  }
}

/// Відкритий плетений кошик під кутом згори: тінь, зовнішня стінка з лозою «в шахівницю»,
/// усередині — дальня стінка й дно з плетінням, тінь від обідка, товстий плетений обідок
/// і ручка позаду.
class OpenBasketPainter extends CustomPainter {
  OpenBasketPainter(this.g);

  final BasketGeometry g;

  static const _light = Color(0xffd7b98e);
  static const _mid = Color(0xffb48a5a);
  static const _dark = Color(0xff7a5532);
  static const _deep = Color(0xff4e3420);

  @override
  void paint(Canvas canvas, Size size) {
    _shadow(canvas);
    _handle(canvas);
    _outerWall(canvas);
    _interior(canvas);
    _rim(canvas);
  }

  Path _ellipse(Offset c, double rx, double ry) =>
      Path()..addOval(Rect.fromCenter(center: c, width: rx * 2, height: ry * 2));

  void _shadow(Canvas canvas) {
    canvas.drawOval(
      Rect.fromCenter(center: g.bottomCenter + Offset(g.rx * 0.06, g.bottomRy * 0.55), width: g.bottomRx * 2.3, height: g.bottomRy * 1.3),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
  }

  void _handle(Canvas canvas) {
    final l = BasketGeometry.onEllipse(g.center, g.rx, g.ry, math.pi * 1.04);
    final r = BasketGeometry.onEllipse(g.center, g.rx, g.ry, -math.pi * 0.04);
    // Вершина кубічної дуги — на 3/4 висоти контрольних точок: ручка над дальнім краєм обідка.
    final controlY = l.dy - (g.ry + g.handleRise) / 0.75;
    final path = Path()
      ..moveTo(l.dx, l.dy)
      ..cubicTo(l.dx + g.rx * 0.05, controlY, r.dx - g.rx * 0.05, controlY, r.dx, r.dy);
    canvas.drawPath(path, Paint()
      ..color = _deep
      ..style = PaintingStyle.stroke
      ..strokeWidth = g.rimWidth * 0.95
      ..strokeCap = StrokeCap.round);
    // Обмотка ручки лозою — косі штрихи.
    final wrap = Paint()
      ..color = _mid
      ..strokeWidth = g.rimWidth * 0.32
      ..strokeCap = StrokeCap.round;
    for (final m in path.computeMetrics()) {
      for (var d = 4.0; d < m.length - 4; d += g.rimWidth * 0.7) {
        final tg = m.getTangentForOffset(d)!;
        final n = Offset(-tg.vector.dy, tg.vector.dx) * (g.rimWidth * 0.4);
        final along = tg.vector * (g.rimWidth * 0.25);
        canvas.drawLine(tg.position - n - along, tg.position + n + along, wrap);
      }
    }
  }

  /// Смуга плетіння між двома еліпсами (кути [a0]..[a1]): ряди лози «в шахівницю»,
  /// темніше до боків — так видно округлість.
  void _wovenBand({
    required Canvas canvas,
    required Offset c0, required double rx0, required double ry0,
    required Offset c1, required double rx1, required double ry1,
    required double a0, required double a1,
    required int rows, required int cols,
    required double shade,
  }) {
    for (var row = 0; row < rows; row++) {
      final s0 = row / rows, s1 = (row + 1) / rows;
      Offset lerpC(double s) => Offset.lerp(c0, c1, s)!;
      double lx(double s) => rx0 + (rx1 - rx0) * s;
      double ly(double s) => ry0 + (ry1 - ry0) * s;
      for (var col = 0; col < cols; col++) {
        final t0 = a0 + (a1 - a0) * col / cols, t1 = a0 + (a1 - a0) * (col + 1) / cols;
        final p = Path()
          ..moveTo(BasketGeometry.onEllipse(lerpC(s0), lx(s0), ly(s0), t0).dx, BasketGeometry.onEllipse(lerpC(s0), lx(s0), ly(s0), t0).dy);
        const steps = 3;
        for (var k = 1; k <= steps; k++) {
          final o = BasketGeometry.onEllipse(lerpC(s0), lx(s0), ly(s0), t0 + (t1 - t0) * k / steps);
          p.lineTo(o.dx, o.dy);
        }
        for (var k = steps; k >= 0; k--) {
          final o = BasketGeometry.onEllipse(lerpC(s1), lx(s1), ly(s1), t0 + (t1 - t0) * k / steps);
          p.lineTo(o.dx, o.dy);
        }
        p.close();
        final over = (row + col).isEven;
        final mid = (t0 + t1) / 2;
        // Світло спереду-зліва: боки й дальня частина — темніші.
        final light = (0.55 + 0.45 * math.sin(mid).abs() * (math.cos(mid + 0.6) * 0.25 + 0.75)) * shade;
        final base = Color.lerp(over ? _light : _mid, _deep, (1 - light).clamp(0.0, 1.0))!;
        canvas.drawPath(p, Paint()..color = base);
        // Межа між прутами — тонка темна лінія.
        canvas.drawPath(p, Paint()
          ..color = _deep.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8);
        // Відблиск на «верхньому» пруті.
        if (over) {
          final hi = BasketGeometry.onEllipse(lerpC((s0 + s1) / 2), lx((s0 + s1) / 2), ly((s0 + s1) / 2), mid);
          canvas.drawCircle(hi, (lx(s0) * (t1 - t0)).abs() * 0.12, Paint()..color = Colors.white.withValues(alpha: 0.12 * shade));
        }
      }
    }
  }

  void _outerWall(Canvas canvas) {
    _wovenBand(
      canvas: canvas,
      c0: g.center, rx0: g.rx, ry0: g.ry,
      c1: g.bottomCenter, rx1: g.bottomRx, ry1: g.bottomRy,
      a0: 0, a1: math.pi,
      rows: 4, cols: 18,
      shade: 1,
    );
  }

  void _interior(Canvas canvas) {
    final opening = _ellipse(g.center, g.rx, g.ry);
    canvas.save();
    canvas.clipPath(opening);
    canvas.drawPath(opening, Paint()..color = _deep);
    // Дальня внутрішня стінка — від обідка до дна.
    _wovenBand(
      canvas: canvas,
      c0: g.center, rx0: g.rx, ry0: g.ry,
      c1: g.floorCenter, rx1: g.floorRx, ry1: g.floorRy,
      a0: math.pi, a1: 2 * math.pi,
      rows: 3, cols: 16,
      shade: 0.62,
    );
    // Дно — плетіння «в шахівницю» в перспективі.
    final floor = _ellipse(g.floorCenter, g.floorRx, g.floorRy);
    canvas.save();
    canvas.clipPath(floor);
    canvas.drawPath(floor, Paint()..color = _mid);
    final cell = g.floorRx / 5;
    final cellY = cell * g.floorRy / g.floorRx;
    final left = g.floorCenter.dx - g.floorRx, top = g.floorCenter.dy - g.floorRy;
    for (var j = 0; j * cellY < g.floorRy * 2; j++) {
      for (var i = 0; i * cell < g.floorRx * 2; i++) {
        final r = Rect.fromLTWH(left + i * cell, top + j * cellY, cell, cellY);
        canvas.drawRect(r, Paint()..color = (i + j).isEven ? _light : _mid);
        canvas.drawRect(r, Paint()
          ..color = _dark.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8);
      }
    }
    // Дно в тіні стінок — світліше посередині.
    canvas.drawPath(floor, Paint()
      ..shader = RadialGradient(
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.45)],
        stops: const [0.45, 1],
      ).createShader(Rect.fromCenter(center: g.floorCenter, width: g.floorRx * 2, height: g.floorRy * 2)));
    canvas.restore();
    // Тінь від обідка всередину (глибина).
    canvas.drawPath(opening, Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = g.rimWidth * 2.2
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, g.rimWidth * 0.9));
    canvas.restore();
  }

  void _rim(Canvas canvas) {
    final w = g.rimWidth;
    // Основа обідка.
    canvas.drawPath(_ellipse(g.center, g.rx, g.ry), Paint()
      ..color = _deep
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 1.15);
    // Дві скручені лозини: косі «зерна», спереду трохи товстіші (перспектива).
    const n = 46;
    for (var strand = 0; strand < 2; strand++) {
      for (var i = 0; i < n; i++) {
        final a = (i + strand * 0.5) / n * 2 * math.pi;
        final p = BasketGeometry.onEllipse(g.center, g.rx, g.ry, a);
        final tangent = math.atan2(math.cos(a) * g.ry, -math.sin(a) * g.rx);
        final front = 0.85 + 0.25 * math.sin(a);
        final len = 2 * math.pi * g.rx / n * 1.5;
        canvas.save();
        canvas.translate(p.dx, p.dy);
        canvas.rotate(tangent + (strand == 0 ? 0.55 : -0.55));
        final r = Rect.fromCenter(center: Offset.zero, width: len, height: w * 0.62 * front);
        canvas.drawOval(r, Paint()..color = strand == 0 ? _mid : _dark);
        canvas.drawOval(
          r.deflate(w * 0.12).shift(Offset(0, -w * 0.06)),
          Paint()..color = (strand == 0 ? _light : _mid).withValues(alpha: 0.75),
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(OpenBasketPainter old) =>
      old.g.center != g.center || old.g.rx != g.rx || old.g.ry != g.ry;
}

/// Анімований гриб-стікер. Розпал хвилі (пік, висока) — підстрибує й світиться; середня —
/// легко «дихає»; низька — маленький і спокійний; немає — сірий. Без анімацій у системі —
/// нерухомий.
class MushroomSticker extends StatefulWidget {
  const MushroomSticker({super.key, required this.species, this.size = 38});

  final StickerSpecies species;
  final double size;

  @override
  State<MushroomSticker> createState() => _MushroomStickerState();
}

class _MushroomStickerState extends State<MushroomSticker> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  String? get _level => widget.species.level;
  bool get _animated => _level == 'peak' || _level == 'high' || _level == 'medium';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(MushroomSticker old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_animated && !reduce) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.species;
    final base = switch (_level) {
      'peak' => 1.15,
      'high' => 1.05,
      'medium' => 0.95,
      'low' => 0.8,
      _ => 0.7,
    };
    final color = (_level == null || _level == 'no_data') ? const Color(0xff94a3b8) : s.color;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        final wave = math.sin(t * 2 * math.pi);
        final jump = switch (_level) {
          'peak' => (wave > 0 ? wave : 0) * 7.0,
          'high' => (wave > 0 ? wave : 0) * 4.0,
          _ => 0.0,
        };
        final breathe = _level == 'medium' ? 1 + 0.05 * wave : 1.0;
        final glow = (_level == 'peak' || _level == 'high') ? 0.18 + 0.17 * wave.abs() : 0.0;
        return Transform.translate(
          offset: Offset(0, -jump),
          child: Transform.scale(
            scale: base * breathe,
            alignment: Alignment.bottomCenter,
            child: Container(
              decoration: glow > 0
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: color.withValues(alpha: glow), blurRadius: 18)],
                    )
                  : null,
              child: child,
            ),
          ),
        );
      },
      child: Opacity(
        opacity: _level == null ? 0.6 : 1,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              SpeciesIcon(
                type: s.type,
                fallbackColor: color,
                size: widget.size,
                grey: _level == null || _level == 'no_data',
              ),
              // Рівень дня — маленька кольорова мітка (колір — з сервера).
              if (_level != null && _level != 'no_data')
                Positioned(
                  right: -1,
                  bottom: 1,
                  child: Container(
                    key: ValueKey('level-dot-${s.type}'),
                    width: widget.size * 0.28,
                    height: widget.size * 0.28,
                    decoration: BoxDecoration(
                      color: s.color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Види, для яких є власна іконка (assets/stickers, з книжкових описів — scripts/stickers).
const speciesWithIcon = {
  'agaricus_campestris', 'armillaria_mellea', 'boletus_edulis', 'boletus_luridus', 'cantharellus_cibarius',
  'flammulina_velutipes', 'hydnum_repandum', 'imleria_badia', 'lactarius_deliciosus', 'lactarius_resimus',
  'lactarius_torminosus', 'leccinum_aurantiacum', 'leccinum_scabrum', 'lycoperdon_perlatum', 'morchella_esculenta',
  'pleurotus_ostreatus', 'russula_vesca', 'suillus_bovinus', 'suillus_luteus', 'xerocomus_subtomentosus',
};

/// Іконка саме цього гриба (білий — як білий, лисичка — як лисичка); без іконки — загальний гриб
/// кольору рівня. [grey] — виду цього дня немає серед грибів зі шансом.
class SpeciesIcon extends StatelessWidget {
  const SpeciesIcon({super.key, required this.type, required this.fallbackColor, this.size = 38, this.grey = false});

  final String type;
  final Color fallbackColor;
  final double size;
  final bool grey;

  static const _greyscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final Widget icon = speciesWithIcon.contains(type)
        ? SvgPicture.asset('assets/stickers/$type.svg', width: size, height: size)
        : MushroomMarker(color: fallbackColor, isPrivate: false, size: size);
    return grey ? ColorFiltered(colorFilter: _greyscale, child: icon) : icon;
  }
}
