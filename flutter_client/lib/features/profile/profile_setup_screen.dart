import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/toast.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/providers.dart';

/// Крок онбордингу після входу через Google / Apple (ADR-021 §21.2.1): ім'я й нік.
/// Аватар вибирається вже в «Профілі».
class ProfileSetupScreen extends StatelessWidget {
  const ProfileSetupScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
            children: [
              Text('Як вас звати?', style: GoogleFonts.merriweather(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.darkGreen)),
              const SizedBox(height: 8),
              Text(
                'Ім\'я бачать друзі й ваш Наглядач. Нік — щоб вас знайти й додати в друзі.',
                style: TextStyle(color: AppTheme.darkGreen.withValues(alpha: 0.75)),
              ),
              const SizedBox(height: 24),
              const IdentityForm(submitLabel: 'Готово'),
            ],
          ),
        ),
      );
}

/// Редагування імені й ніка з «Профілю».
class EditIdentityScreen extends StatelessWidget {
  const EditIdentityScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Ім\'я й нік', style: GoogleFonts.merriweather(color: AppTheme.darkGreen))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [IdentityForm(submitLabel: 'Зберегти', onSaved: () => Navigator.of(context).pop())],
        ),
      );
}

/// Ім'я (обов'язкове) і нік (унікальний) — лише українською; підказка «вільний / зайнятий»
/// з сервера під час введення. Правила перевіряє сервер (Thin Client).
class IdentityForm extends ConsumerStatefulWidget {
  const IdentityForm({super.key, required this.submitLabel, this.onSaved});

  final String submitLabel;
  final VoidCallback? onSaved;

  @override
  ConsumerState<IdentityForm> createState() => _IdentityFormState();
}

class _IdentityFormState extends ConsumerState<IdentityForm> {
  late final TextEditingController _name;
  late final TextEditingController _handle;
  Timer? _debounce;
  String? _handleHint;
  bool? _available;
  bool _saving = false;
  String? _error;

  /// Латиниця — одразу підказка, ще до сервера.
  static final _latin = RegExp('[A-Za-z]');

  @override
  void initState() {
    super.initState();
    final me = ref.read(meProvider).valueOrNull;
    _name = TextEditingController(text: me?.name ?? '');
    _handle = TextEditingController(text: me?.handle ?? '');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _handle.dispose();
    super.dispose();
  }

  void _onHandleChanged(String v) {
    _debounce?.cancel();
    final h = v.trim().replaceFirst('@', '');
    final current = ref.read(meProvider).valueOrNull?.handle;
    setState(() {
      _available = null;
      _handleHint = _latin.hasMatch(h) ? 'Нік — лише українськими літерами, без латиниці' : null;
    });
    if (h.length < 3 || _handleHint != null || (current != null && current.toLowerCase() == h.toLowerCase())) return;
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      try {
        final r = await ref.read(meRepositoryProvider).checkHandle(h);
        if (!mounted || _handle.text.trim().replaceFirst('@', '') != h) return;
        setState(() {
          _available = r.available;
          _handleHint = r.available ? 'Нік вільний' : r.reason;
        });
      } catch (_) {
        // без мережі — перевірить сервер під час збереження
      }
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(meProvider.notifier).updateIdentity(
            name: _name.text,
            handle: _handle.text.trim().replaceFirst('@', ''),
          );
      if (!mounted) return;
      showToast(context, 'Збережено');
      widget.onSaved?.call();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
    } catch (_) {
      if (mounted) setState(() => _error = 'Не вдалося зберегти. Перевірте інтернет і спробуйте ще раз.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider).valueOrNull;
    final handleLocked = me?.handle != null && me?.handleChange?.allowed == false;
    final ok = _name.text.trim().length >= 2 && _handle.text.trim().replaceFirst('@', '').length >= 3 && _available != false && !_saving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('identity-name'),
          controller: _name,
          textCapitalization: TextCapitalization.words,
          maxLength: 30,
          decoration: const InputDecoration(labelText: 'Ім\'я', hintText: 'Олена Лісова', helperText: 'Українськими літерами'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('identity-handle'),
          controller: _handle,
          enabled: !handleLocked,
          maxLength: 20,
          decoration: InputDecoration(
            labelText: 'Нік',
            prefixText: '@',
            hintText: 'Олена_лісова',
            helperText: handleLocked
                ? me!.handleChange!.reasonLabel
                : _handleHint ?? 'Українські літери, цифри, «_» і «.»; 3–20 символів',
            helperStyle: TextStyle(
              color: _available == true ? const Color(0xff2e7d32) : (_handleHint != null && _available != true ? const Color(0xffb45309) : null),
            ),
          ),
          onChanged: (v) {
            _onHandleChanged(v);
            setState(() {});
          },
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, key: const ValueKey('identity-error'), style: const TextStyle(color: Color(0xffc62828))),
          ),
        const SizedBox(height: 20),
        FilledButton(
          key: const ValueKey('identity-save'),
          onPressed: ok ? _save : null,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.darkGreen, padding: const EdgeInsets.symmetric(vertical: 14)),
          child: _saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(widget.submitLabel),
        ),
      ],
    );
  }
}
