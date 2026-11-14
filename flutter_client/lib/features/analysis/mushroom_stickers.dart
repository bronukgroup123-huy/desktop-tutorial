import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

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

/// Гриби поверх мінікарти ділянки: ставить їх сам грибник — на свої місця («тут соснячок»),
/// бо карта лісів груба. Звідки беруться: лоток під картою (перетягнути на карту). Поставлений
/// гриб можна затиснути й пересунути, торкнутися — підказка з рівнем дня й «Прибрати».
/// Анімація — за рівнем обраного дня: розпал хвилі — підстрибує й світиться, без хвилі — сірий.
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

  /// Види обраного дня (найкращий і альтернатива).
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

class _StickerBoardState extends State<StickerBoard> {
  static const double _stickerSize = 38;

  /// Гриб, який зараз тягнуть по карті: вид → поточна позиція на екрані.
  String? _dragging;
  Offset? _dragAt;
  String? _tooltipFor;
  final GlobalKey _mapKey = GlobalKey();

  StickerSpecies _speciesFor(String type) => widget.species.firstWhere(
        (s) => s.type == type,
        orElse: () => StickerSpecies(
          type: type,
          name: _names[type] ?? type,
          level: null,
          levelLabel: 'Цього дня не серед найкращих',
          color: const Color(0xff94a3b8),
          whenLabel: '',
        ),
      );

  // Назви видів, що вже стоять на карті, але цього дня не серед найкращих.
  final Map<String, String> _names = {};

  Offset _clamp(Offset o) => Offset(
        o.dx.clamp(0, widget.camera.size.width),
        o.dy.clamp(0, widget.camera.size.height),
      );

  /// [globalPointer] — де палець відпустив гриб: туди стає «ніжка» гриба.
  void _dropFromTray(String type, Offset globalPointer) {
    final box = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = _clamp(box.globalToLocal(globalPointer));
    widget.onMove(type, widget.camera.toLatLng(local));
  }

  @override
  Widget build(BuildContext context) {
    for (final s in widget.species) {
      _names[s.type] = s.name;
    }
    final placed = widget.positions.keys.toList();
    final tray = widget.species.where((s) => !widget.positions.containsKey(s.type)).toList();
    final size = widget.camera.size;

    return Column(
      // Карта — рівно розміру камери: гриби й карта в одному масштабі.
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            key: _mapKey,
            width: size.width,
            height: size.height,
            child: DragTarget<String>(
              onAcceptWithDetails: (d) => _dropFromTray(d.data, d.offset),
              builder: (context, candidates, _) => Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(child: widget.map),
                  if (candidates.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(color: AppTheme.darkGreen.withValues(alpha: 0.08)),
                      ),
                    ),
                  for (final type in placed) _placed(type),
                  if (_tooltipFor != null && widget.positions[_tooltipFor] != null) _tooltip(_tooltipFor!),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (tray.isNotEmpty)
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final s in tray)
                Draggable<String>(
                  key: ValueKey('tray-${s.type}'),
                  data: s.type,
                  // «Ніжка» гриба — під пальцем (а не край плашки з лотка).
                  dragAnchorStrategy: pointerDragAnchorStrategy,
                  feedback: Transform.translate(
                    offset: const Offset(-_stickerSize / 2, -_stickerSize),
                    child: Material(color: Colors.transparent, child: MushroomSticker(species: s, size: _stickerSize)),
                  ),
                  childWhenDragging: Opacity(opacity: 0.3, child: _TrayChip(species: s)),
                  child: _TrayChip(species: s),
                ),
              Text(
                'Перетягніть гриб на своє місце в лісі',
                style: TextStyle(fontSize: 12, color: AppTheme.darkGreen.withValues(alpha: 0.6)),
              ),
            ],
          )
        else if (placed.isNotEmpty)
          Text(
            'Затисніть гриб, щоб пересунути. Торкніться — підказка.',
            style: TextStyle(fontSize: 12, color: AppTheme.darkGreen.withValues(alpha: 0.6)),
          ),
      ],
    );
  }

  Widget _placed(String type) {
    final s = _speciesFor(type);
    final at = _dragging == type && _dragAt != null ? _dragAt! : widget.camera.toScreen(widget.positions[type]!);
    return Positioned(
      key: ValueKey('placed-$type'),
      left: at.dx - _stickerSize / 2,
      top: at.dy - _stickerSize,
      child: GestureDetector(
        onTap: () => setState(() => _tooltipFor = _tooltipFor == type ? null : type),
        onLongPressStart: (_) => setState(() {
          _dragging = type;
          _dragAt = at;
          _tooltipFor = null;
        }),
        onLongPressMoveUpdate: (d) => setState(() => _dragAt = _clamp(at + d.offsetFromOrigin)),
        onLongPressEnd: (_) {
          final end = _dragAt;
          setState(() {
            _dragging = null;
            _dragAt = null;
          });
          if (end != null) widget.onMove(type, widget.camera.toLatLng(end));
        },
        child: AnimatedScale(
          scale: _dragging == type ? 1.25 : 1,
          duration: const Duration(milliseconds: 150),
          child: MushroomSticker(species: s, size: _stickerSize),
        ),
      ),
    );
  }

  Widget _tooltip(String type) {
    final s = _speciesFor(type);
    final at = widget.camera.toScreen(widget.positions[type]!);
    const width = 200.0;
    final left = (at.dx - width / 2).clamp(4.0, widget.camera.size.width - width - 4);
    final above = at.dy > 110;
    return Positioned(
      left: left,
      top: above ? at.dy - _stickerSize - 92 : at.dy + 8,
      width: width,
      child: Material(
        elevation: 3,
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${s.name} · ${s.levelLabel}', style: TextStyle(fontWeight: FontWeight.w600, color: s.color)),
              if (s.whenLabel.isNotEmpty) Text(s.whenLabel, style: const TextStyle(fontSize: 12)),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: ValueKey('remove-$type'),
                  onPressed: () {
                    setState(() => _tooltipFor = null);
                    widget.onRemove(type);
                  },
                  child: const Text('Прибрати'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrayChip extends StatelessWidget {
  const _TrayChip({required this.species});

  final StickerSpecies species;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(4, 2, 10, 2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: species.color.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MushroomMarker(color: species.color, isPrivate: false, size: 26),
            const SizedBox(width: 4),
            Text(species.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      );
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
