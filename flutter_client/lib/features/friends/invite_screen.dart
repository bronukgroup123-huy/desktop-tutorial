import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/ui.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/friends.dart';
import 'package:flutter_client/data/providers.dart';

/// «Запросити друга» (B9.5, ADR-021 §21.4): мій код, QR і посилання в Google Play.
/// Друг встановлює за посиланням — і ви одразу друзі; +10 балів обом після його першого походу.
class InviteScreen extends ConsumerWidget {
  const InviteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invite = ref.watch(myInviteProvider);
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(title: Text('Запросити друга', style: AppTheme.appBarTitle)),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(myInviteProvider.future),
        child: invite.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                e is ApiException ? e.userMessage : 'Не вдалося отримати код. Перевірте інтернет.',
                key: const ValueKey('invite-error'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(onPressed: () => ref.invalidate(myInviteProvider), child: const Text('Повторити')),
              ),
            ],
          ),
          data: (i) => _InviteBody(invite: i),
        ),
      ),
    );
  }
}

class _InviteBody extends StatelessWidget {
  const _InviteBody({required this.invite});

  final MyInvite invite;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('invite-list'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AppCard(
          child: Column(
            children: [
              Text(
                'Покажіть QR другові або надішліть посилання. Воно відкриває Google Play — встановіть за ним, '
                'і ви одразу станете друзями.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Semantics(
                label: 'QR-код запрошення в Google Play',
                image: true,
                child: QrImageView(
                  key: const ValueKey('invite-qr'),
                  data: invite.shareUrl,
                  size: 200,
                  backgroundColor: AppTheme.surface,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppTheme.darkGreen),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: AppTheme.darkGreen),
                ),
              ),
              const SizedBox(height: 8),
              Text('Ваш код', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppTheme.textMuted)),
              SelectableText(
                invite.code,
                key: const ValueKey('invite-code'),
                style: AppTheme.heading(28).copyWith(letterSpacing: 4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('invite-share'),
          icon: const Icon(Icons.share_rounded),
          label: const Text('Поділитися посиланням'),
          onPressed: () => SharePlus.instance.share(ShareParams(text: invite.shareText)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('invite-copy'),
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Скопіювати посилання'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: invite.shareUrl));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Посилання скопійовано')));
            }
          },
        ),
        if (invite.label != null) ...[
          const SizedBox(height: 16),
          AppTile(
            key: const ValueKey('invite-bonus'),
            icon: Icons.emoji_events_outlined,
            title: invite.label!,
            subtitle: 'Запрошено: ${invite.invited} · бонусів отримано: ${invite.rewarded}',
          ),
        ],
      ],
    );
  }
}
