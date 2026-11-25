import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/image_decode.dart';
import 'package:flutter_client/core/toast.dart';
import 'package:flutter_client/core/uuid.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/me.dart' show PickPermissions;
import 'package:flutter_client/data/models/pick.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/picks/photo_validation.dart';
import 'package:flutter_client/features/picks/species_picker.dart';
import 'package:flutter_client/features/recognize/recognizer.dart' show Likelihood, recognizerProvider;

/// Знімок із камери застосунку. Галереї немає, кадр — один (ADR-018 §18.3).
/// Фото стискається на телефоні, щоб уміститися в 5 МБ.
Future<XFile?> takePickPhoto() => ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );

/// Новий тук-тук: фото → вид зі списку → опис → видимість → збереження.
///
/// Місце й час зафіксовано в момент зйомки ([point], [capturedAt]). Усі правила
/// (область, ліміти, хто може публікувати) перевіряє сервер — тут лише показуємо
/// його відповідь. Повертає `true`, якщо точку створено.
class NewPickScreen extends ConsumerStatefulWidget {
  const NewPickScreen({
    super.key,
    required this.photo,
    required this.point,
    required this.capturedAt,
    this.initialVisibility = PickVisibility.private,
  });

  final XFile photo;
  final LatLng point;
  final DateTime capturedAt;
  final PickVisibility initialVisibility;

  @override
  ConsumerState<NewPickScreen> createState() => _NewPickScreenState();
}

class _NewPickScreenState extends ConsumerState<NewPickScreen> {
  /// Один id на весь тук-тук: повторне «Зберегти» після збою не створить дубль.
  final String _clientId = uuidV4();
  final TextEditingController _description = TextEditingController();

  late XFile _photo = widget.photo;
  late DateTime _capturedAt = widget.capturedAt;
  late PickVisibility _visibility = widget.initialVisibility;
  SpeciesChoice? _species;
  bool _saving = false;

  /// Помилка фото (розмір, формат, пошкоджений файл) — зберегти не можна, доки не перезняти.
  String? _photoError;

  @override
  void initState() {
    super.initState();
    _checkPhoto(widget.photo);
  }

  /// Публічні сервер зараз не дозволяє — точка лише приватна, хоч би що було вибрано раніше.
  PickVisibility _effectiveVisibility(PickPermissions? picks) =>
      picks != null && !picks.publicAllowed && _visibility == PickVisibility.public ? PickVisibility.private : _visibility;

  Future<void> _checkPhoto(XFile photo) async {
    final check = await validatePickPhoto(photo);
    if (mounted && identical(photo, _photo)) setState(() => _photoError = check.error);
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _retake() async {
    final photo = await takePickPhoto();
    if (photo == null || !mounted) return;
    setState(() {
      _photo = photo;
      _capturedAt = DateTime.now();
      _photoError = null;
    });
    await _checkPhoto(photo);
  }

  Future<void> _pickSpecies() async {
    final choice = await showSpeciesPicker(context);
    if (choice == null || !mounted) return;
    setState(() => _species = choice);
  }

  Future<void> _save() async {
    final species = _species;
    if (species == null) {
      showToast(context, 'Оберіть вид зі списку або «Не знаю, що це»', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      // Фото обов'язкове: перевіряємо ще раз безпосередньо перед відправкою
      // (файл міг зникнути з кешу камери), тип — за вмістом, а не розширенням.
      final check = await validatePickPhoto(_photo);
      if (!check.isOk) {
        if (mounted) setState(() => _photoError = check.error);
        if (mounted) showToast(context, check.error!, isError: true);
        return;
      }
      final aiCheck = await _aiCheck(species.species?.id);
      final created = await ref.read(picksRepositoryProvider).createPick(
            NewPick(
              clientId: _clientId,
              point: widget.point,
              capturedAt: _capturedAt,
              visibility: _effectiveVisibility(ref.read(meProvider).valueOrNull?.picks),
              speciesId: species.species?.id,
              description: _description.text,
              aiCheck: aiCheck,
            ),
            PickPhoto(
              openRead: _photo.openRead,
              sizeBytes: check.sizeBytes,
              contentType: check.contentType!,
            ),
          );
      if (!mounted) return;
      // Щойно створену приватну точку одразу видно на карті.
      if (created.visibility == PickVisibility.private) {
        ref.read(showPrivatePicksProvider.notifier).state = true;
      }
      ref.invalidate(picksMapProvider);
      ref.invalidate(meProvider); // бали й дозволи на точки змінилися (PROD-001)
      showToast(context, 'Тук-тук збережено: ${created.statusLabel}');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.userMessage, isError: true);
    } catch (_) {
      if (mounted) showToast(context, 'Не вдалося зберегти тук-тук. Спробуйте ще раз.', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Підказка розпізнавання для цього фото — лише на телефоні (ADR: локальний ONNX, без
  /// серверних запитів); на сервер іде тільки результат: до трьох видів рівнями, без відсотків.
  /// Немає моделі чи «Не знаю, що це» — `null` (тук-тук зберігається як завжди).
  Future<Map<String, dynamic>?> _aiCheck(String? speciesId) async {
    if (speciesId == null) return null;
    try {
      final recognizer = await ref.read(recognizerProvider.future);
      if (recognizer == null) return null;
      final r = await recognizer.recognize([await _photo.readAsBytes()]);
      if (r.notMushroom || r.candidates.isEmpty) return null;
      String level(Likelihood l) => switch (l) {
            Likelihood.likely => 'high',
            Likelihood.possible => 'medium',
            Likelihood.unlikely => 'low',
          };
      final v = recognizer.manifest.version;
      return {
        'model_version': v.length > 64 ? v.substring(0, 64) : v,
        'top': [for (final c in r.candidates.take(3)) {'species_id': c.label.id, 'level': level(c.likelihood)}],
        'match': r.candidates.first.label.id == speciesId,
        'twin_alert': r.dangerous != null && r.dangerous!.id != speciesId,
      };
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = AppTheme.darkGreen.withValues(alpha: 0.6);
    final picks = ref.watch(meProvider.select((m) => m.valueOrNull?.picks));
    final visibility = _effectiveVisibility(picks);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новий тук-тук'),
        backgroundColor: AppTheme.backgroundColor,
        foregroundColor: AppTheme.darkGreen,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: LayoutBuilder(
                builder: (context, box) => Image(
                // Прев'ю 220 px заввишки — без декодування фото в повному розмірі (PERF-001).
                image: coverDecoded(FileImage(File(_photo.path)), Size(box.maxWidth, 220), context),
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => Container(
                  height: 220,
                  color: Colors.white,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined, size: 48),
                ),
              ),
              ),
            ),
            if (_photoError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_photoError!, style: const TextStyle(color: Colors.red))),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _saving ? null : _retake,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Перезняти'),
              ),
            ),
            const SizedBox(height: 4),
            Text('Що це за гриб?', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: const Icon(Icons.eco_outlined, color: AppTheme.darkGreen),
                title: Text(_species?.title ?? 'Оберіть вид зі списку'),
                subtitle: _species?.species?.latinLabel == null
                    ? null
                    : Text(_species!.species!.latinLabel!, style: const TextStyle(fontStyle: FontStyle.italic)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _saving ? null : _pickSpecies,
              ),
            ),
            const SizedBox(height: 20),
            Text('Опис (необов\'язково)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              enabled: !_saving,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Під якими деревами, яка погода…',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            Text('Хто бачить точку', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<PickVisibility>(
              segments: [
                const ButtonSegment(
                  value: PickVisibility.private,
                  icon: Icon(Icons.lock_outline_rounded),
                  label: Text('Лише я'),
                ),
                // «Усі» — лише коли сервер дозволяє публічні (рівень, тижневий ліміт; PROD-001)
                ButtonSegment(
                  value: PickVisibility.public,
                  icon: const Icon(Icons.public_rounded),
                  label: const Text('Усі'),
                  enabled: picks?.publicAllowed ?? true,
                ),
              ],
              selected: {visibility},
              onSelectionChanged: _saving ? null : (s) => setState(() => _visibility = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              visibility == PickVisibility.public
                  ? 'Публічну точку бачать усі в області — приблизно, з похибкою 300–500 м. '
                      'Спершу її перевірить спільнота.'
                  : 'Приватну точку з точним місцем бачите лише ви.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            if (picks != null && !picks.publicAllowed && picks.publicHint != null)
              _PermissionHint(key: const ValueKey('pick-public-hint'), icon: Icons.public_off_rounded, text: picks.publicHint!),
            if (visibility == PickVisibility.private && picks != null && !picks.privateAllowed && picks.privateHint != null)
              _PermissionHint(key: const ValueKey('pick-private-hint'), icon: Icons.info_outline_rounded, text: picks.privateHint!, warning: true),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving || _photoError != null ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.darkGreen,
                minimumSize: const Size.fromHeight(52),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_saving ? 'Зберігаємо…' : 'Зберегти тук-тук'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Підказка сервера, чому видимість недоступна (рівень, ліміт, «видаліть одну»).
class _PermissionHint extends StatelessWidget {
  const _PermissionHint({super.key, required this.icon, required this.text, this.warning = false});

  final IconData icon;
  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? const Color(0xffb45309) : AppTheme.darkGreen.withValues(alpha: 0.75);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: color, fontWeight: warning ? FontWeight.w600 : FontWeight.w400))),
        ],
      ),
    );
  }
}
