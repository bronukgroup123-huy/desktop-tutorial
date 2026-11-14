import 'dart:math' as math;

import 'package:flutter/material.dart';
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

  @override
  State<StickerBoard> createState() => _StickerBoardState();
}

class _StickerBoardState extends State<StickerBoard> with TickerProviderStateMixin {
  static const double _stickerSize = 38;
  static const Size _basketSize = Size(66, 58);

  late final AnimationController _open =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final AnimationController _bob = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  /// Гриб, який зараз тягнуть: вид і позиція «ніжки» на мінікарті.
  String? _dragging;
  Offset? _dragAt;
  bool _dragFromBasket = false;
  String? _tooltipFor;
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
    final hint = widget.positions.isEmpty
        ? 'Торкніться кошика — там гриби дня. Затисніть гриб і перенесіть на своє місце.'
        : 'Затисніть гриб, щоб пересунути, або перенесіть у кошик, щоб прибрати.';

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
        const SizedBox(height: 6),
        Text(hint, style: TextStyle(fontSize: 12, color: AppTheme.darkGreen.withValues(alpha: 0.6))),
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

  Widget _tooltip(String type) {
    final s = _speciesFor(type);
    final at = widget.camera.toScreen(widget.positions[type]!);
    const width = 200.0;
    final left = (at.dx - width / 2).clamp(4.0, _size.width - width - 4);
    final above = at.dy > 90;
    return Positioned(
      left: left,
      top: above ? at.dy - _stickerSize - 64 : at.dy + 8,
      width: width,
      child: IgnorePointer(
        child: Material(
          elevation: 3,
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${s.name} · ${s.levelLabel}', style: TextStyle(fontWeight: FontWeight.w600, color: s.color)),
                if (s.whenLabel.isNotEmpty) Text(s.whenLabel, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
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
                      child: MushroomMarker(color: peek[i].color, isPrivate: false, size: 22),
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
    final d = math.min(_size.width, _size.height) * 0.88;
    final center = Offset(_size.width / 2, _size.height / 2);
    final items = _inBasket;
    // Звідки «виростає» вигляд згори — з кошика в куті.
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
              child: Container(color: Colors.black.withValues(alpha: 0.22 * appear)),
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
                    Positioned(
                      left: center.dx - d / 2,
                      top: center.dy - d / 2,
                      width: d,
                      height: d,
                      child: GestureDetector(
                        key: const ValueKey('basket-open'),
                        onTap: _toggleBasket,
                        child: CustomPaint(painter: _BasketTopPainter()),
                      ),
                    ),
                    if (items.isEmpty)
                      Positioned.fill(
                        child: Center(
                          child: Text(
                            'Цього дня грибів зі шансом немає',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.95), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    for (var i = 0; i < items.length; i++) _inBasketItem(items[i], _basketSlot(i, items.length, center, d)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Гриби в кошику: по колу (до 6), далі — внутрішнє коло і центр.
  Offset _basketSlot(int i, int n, Offset c, double d) {
    if (n == 1) return c;
    final outer = math.min(n, 6);
    if (i < outer) {
      final a = -math.pi / 2 + i * 2 * math.pi / outer;
      return c + Offset(math.cos(a), math.sin(a)) * d * 0.3;
    }
    final inner = n - outer;
    if (inner == 1) return c;
    final a = -math.pi / 2 + (i - outer) * 2 * math.pi / inner + math.pi / inner;
    return c + Offset(math.cos(a), math.sin(a)) * d * 0.13;
  }

  Widget _inBasketItem(StickerSpecies s, Offset at) {
    final bobY = _reduceMotion ? 0.0 : math.sin((_bob.value + s.type.hashCode % 7 / 7) * 2 * math.pi) * 1.5;
    return Positioned(
      key: ValueKey('basket-${s.type}'),
      left: at.dx - _stickerSize / 2,
      top: at.dy - _stickerSize / 2 + bobY,
      child: GestureDetector(
        onTap: () => setState(() => _nameFor = _nameFor == s.type ? null : s.type),
        onLongPressStart: (d) => _startDrag(s.type, d.globalPosition, fromBasket: true),
        onLongPressMoveUpdate: (d) => _moveDrag(d.globalPosition),
        onLongPressEnd: (_) => _endDrag(),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Opacity(
              opacity: _dragging == s.type ? 0.2 : 1,
              child: MushroomSticker(species: s, size: _stickerSize),
            ),
            if (_nameFor == s.type)
              Positioned(
                bottom: _stickerSize + 2,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                    child: Text(s.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.darkGreen)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Плетений кошик збоку: корпус-трапеція з лозою, обідок, ручка.
class _BasketPainter extends CustomPainter {
  _BasketPainter({this.glow = false});

  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rimY = h * 0.38;
    final handle = Paint()
      ..color = const Color(0xff6d4c41)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawArc(Rect.fromLTWH(w * 0.18, -h * 0.05, w * 0.64, rimY * 1.9), math.pi, math.pi, false, handle);
    final body = Path()
      ..moveTo(w * 0.04, rimY)
      ..lineTo(w * 0.96, rimY)
      ..lineTo(w * 0.84, h)
      ..lineTo(w * 0.16, h)
      ..close();
    if (glow) {
      canvas.drawPath(body, Paint()
        ..color = const Color(0xffffd54f).withValues(alpha: 0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    }
    canvas.drawPath(body, Paint()..color = const Color(0xffa1887f));
    final weave = Paint()
      ..color = const Color(0xff795548)
      ..strokeWidth = 1.4;
    for (var y = rimY + 7; y < h - 2; y += 7) {
      final inset = (y - rimY) / (h - rimY) * w * 0.12;
      canvas.drawLine(Offset(w * 0.04 + inset, y), Offset(w * 0.96 - inset, y), weave);
    }
    for (var x = 0.2; x < 0.85; x += 0.15) {
      canvas.drawLine(Offset(w * x, rimY), Offset(w * (0.5 + (x - 0.5) * 0.8), h), weave);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, rimY - 4, w, 8), const Radius.circular(4)),
      Paint()..color = const Color(0xff6d4c41),
    );
  }

  @override
  bool shouldRepaint(_BasketPainter old) => old.glow != glow;
}

/// Кошик згори: дно з плетінням (кола й промені), товстий обідок.
class _BasketTopPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r, Paint()..color = const Color(0xff6d4c41));
    canvas.drawCircle(c, r * 0.9, Paint()..color = const Color(0xffbcaaa4));
    final weave = Paint()
      ..color = const Color(0xff8d6e63)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    for (var k = 1; k <= 5; k++) {
      canvas.drawCircle(c, r * 0.9 * k / 5.5, weave);
    }
    for (var a = 0.0; a < 2 * math.pi; a += math.pi / 8) {
      canvas.drawLine(c, c + Offset(math.cos(a), math.sin(a)) * r * 0.9, weave);
    }
  }

  @override
  bool shouldRepaint(_BasketTopPainter old) => false;
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
        final glow = (_level == 'peak' || _level == 'high') ? 0.35 + 0.25 * wave.abs() : 0.0;
        return Transform.translate(
          offset: Offset(0, -jump),
          child: Transform.scale(
            scale: base * breathe,
            alignment: Alignment.bottomCenter,
            child: Container(
              decoration: glow > 0
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: color.withValues(alpha: glow), blurRadius: 14, spreadRadius: 2)],
                    )
                  : null,
              child: child,
            ),
          ),
        );
      },
      child: Opacity(
        opacity: _level == null ? 0.55 : 1,
        child: MushroomMarker(color: color, isPrivate: false, size: widget.size, tooltip: null),
      ),
    );
  }
}
