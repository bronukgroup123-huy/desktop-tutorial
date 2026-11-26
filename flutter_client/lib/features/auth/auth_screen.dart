import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/auth_errors.dart';
import 'package:flutter_client/core/supabase_config.dart';
import 'package:flutter_client/core/toast.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/data/repositories/auth_repository.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  AuthRepository _auth(BuildContext context) =>
      ProviderScope.containerOf(context, listen: false).read(authRepositoryProvider);

  Future<void> _signInWithGoogle(BuildContext context) async {
    try {
      await _auth(context).signInWithGoogle(
        redirectTo: kIsWeb ? Uri.base.origin : SupabaseConfig.authRedirectUrl,
      );
    } catch (e) {
      debugPrint('Google sign-in failed: $e');
      if (context.mounted) showToast(context, authErrorMessage(e, action: 'увійти через Google'), isError: true);
    }
  }

  /// Гість — Anonymous Sign-In (ADR-001). Далі роутер сам відкриє онбординг
  /// за `onboarding.next_step` з сервера.
  Future<void> _continueAsGuest(BuildContext context) async {
    try {
      await _auth(context).signInAsGuest();
    } catch (e) {
      debugPrint('Anonymous sign-in failed: $e');
      if (context.mounted) {
        showToast(context, authErrorMessage(e, action: 'продовжити без реєстрації'), isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      // На високому екрані — як раніше (розпірки розносять блоки); на малому, у альбомній
      // орієнтації чи з великим системним шрифтом — прокручується, нічого не обрізається (UI-001).
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) => SingleChildScrollView(
            key: const ValueKey('auth-scroll'),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: (viewport.maxHeight - 64).clamp(0, double.infinity)),
              child: IntrinsicHeight(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(flex: 2),
                    _buildLogo(),
                    const SizedBox(height: 32),
                    _buildTitle(),
                    const SizedBox(height: 12),
                    _buildSubtitle(),
                    const Spacer(flex: 3),
                    const SizedBox(height: 24),
                    _buildSocialButtons(context),
                    const SizedBox(height: 24),
                    _buildGuestButton(context),
                    const Spacer(flex: 2),
                    const SizedBox(height: 16),
                    _buildEulaText(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Center(
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: AppTheme.darkGreen,
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Icon(
          Icons.eco_rounded,
          size: 56,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return Center(
      child: Text(
        'Грибний Радар',
        style: TextStyle(fontFamily: AppTheme.serif, 
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: AppTheme.darkGreen,
          height: 1.2,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildSubtitle() {
    return Center(
      child: Text(
        'Ваш особистий цифровий помічник',
        style: TextStyle(
          fontSize: 16,
          color: AppTheme.textMuted,
          height: 1.5,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildSocialButtons(BuildContext context) {
    return Column(
      children: [
        _buildSocialButton(
          icon: Icons.g_mobiledata_rounded,
          label: 'Увійти через Google',
          onPressed: () => _signInWithGoogle(context),
        ),
        const SizedBox(height: 12),
        _buildSocialButton(
          icon: Icons.apple_rounded,
          label: 'Увійти через Apple',
          // Провайдер Apple ще не налаштований у Supabase (BACKEND_PLAN B1.5).
          onPressed: () => showToast(context, 'Вхід через Apple — скоро'),
        ),
      ],
    );
  }

  Widget _buildSocialButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 24, color: AppTheme.darkGreen),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.darkGreen,
        side: BorderSide(color: AppTheme.darkGreen.withValues(alpha: 0.5), width: 1.5),
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildGuestButton(BuildContext context) {
    return TextButton(
      onPressed: () => _continueAsGuest(context),
      child: Text(
        'Продовжити без реєстрації',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppTheme.darkGreen,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  Widget _buildEulaText() {
    return Center(
      child: Text.rich(
        TextSpan(
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.textMuted,
            height: 1.5,
          ),
          children: [
            const TextSpan(text: 'Продовжуючи, ви погоджуєтеся з '),
            TextSpan(
              text: 'Умовами використання',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.darkGreen,
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w500,
              ),
            ),
            const TextSpan(text: ' та '),
            TextSpan(
              text: 'Політикою конфіденційності',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.darkGreen,
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w500,
              ),
            ),
            const TextSpan(text: '.'),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}