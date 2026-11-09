import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/providers.dart';

/// Поки відновлюється сесія і вантажиться профіль (`GET /v1-me`).
/// Якщо профіль не завантажився — текст помилки з сервера і «Повторити».
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final error = me.hasError && !me.isLoading ? me.error : null;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: error == null
              ? const CircularProgressIndicator(color: AppTheme.darkGreen)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 48, color: AppTheme.darkGreen),
                    const SizedBox(height: 16),
                    Text(
                      error is ApiException ? error.userMessage : 'Не вдалося завантажити профіль.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => ref.read(meProvider.notifier).refresh(),
                      child: const Text('Повторити'),
                    ),
                    TextButton(
                      onPressed: () => ref.read(authRepositoryProvider).signOut(),
                      child: const Text('Вийти'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
