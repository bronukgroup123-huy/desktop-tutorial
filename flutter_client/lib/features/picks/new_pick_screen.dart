import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/toast.dart';
import 'package:flutter_client/core/uuid.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/pick.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/picks/photo_validation.dart';
import 'package:flutter_client/features/picks/species_picker.dart';

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
      final created = await ref.read(picksRepositoryProvider).createPick(
            NewPick(
              clientId: _clientId,
              point: widget.point,
              capturedAt: _capturedAt,
              visibility: _visibility,
              speciesId: species.species?.id,
              description: _description.text,
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

  @override
  Widget build(BuildContext context) {
    final muted = AppTheme.darkGreen.withValues(alpha: 0.6);
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
              child: Image.file(
                File(_photo.path),
                height: 220,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => Container(
                  height: 220,
                  color: Colors.white,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined, size: 48),
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
              segments: const [
                ButtonSegment(
                  value: PickVisibility.private,
                  icon: Icon(Icons.lock_outline_rounded),
                  label: Text('Лише я'),
                ),
                ButtonSegment(
                  value: PickVisibility.public,
                  icon: Icon(Icons.public_rounded),
                  label: Text('Усі'),
                ),
              ],
              selected: {_visibility},
              onSelectionChanged: _saving ? null : (s) => setState(() => _visibility = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              _visibility == PickVisibility.public
                  ? 'Публічну точку бачать усі в області — приблизно, з похибкою 300–500 м. '
                      'Спершу її перевірить спільнота.'
                  : 'Приватну точку з точним місцем бачите лише ви.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
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
