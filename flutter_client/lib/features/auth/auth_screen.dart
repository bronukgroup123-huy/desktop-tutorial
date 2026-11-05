import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_client/core/app_theme.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  Future<void> _signInWithGoogle(BuildContext context) async {
    try {
      final redirectUrl = Uri.base.origin.isNotEmpty ? Uri.base.origin : 'http://localhost:53480';
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectUrl,
        queryParams: {'prompt': 'select_account'},
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Помилка входу через Google: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  void _showPhoneLoginDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'В розробці',
          style: GoogleFonts.merriweather(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.darkGreen,
          ),
        ),
        content: Text(
          'Екран входу за номером телефону в розробці',
          style: GoogleFonts.inter(
            fontSize: 16,
            color: AppTheme.darkGreen.withValues(alpha: 0.8),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Зрозуміло',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.darkGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _continueAsGuest(BuildContext context) {
    context.go('/region-selection');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
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
              _buildSocialButtons(context),
              const SizedBox(height: 16),
              _buildPhoneButton(context),
              const SizedBox(height: 24),
              _buildGuestButton(context),
              const Spacer(flex: 2),
              _buildEulaText(),
            ],
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
        style: GoogleFonts.merriweather(
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
        style: GoogleFonts.inter(
          fontSize: 16,
          color: AppTheme.darkGreen.withValues(alpha: 0.7),
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
          onPressed: () {},
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
        textStyle: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPhoneButton(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () => _showPhoneLoginDialog(context),
      icon: const Icon(Icons.phone_rounded, size: 24, color: Colors.white),
      label: const Text('Увійти за номером телефону'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.darkGreen,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        elevation: 0,
      ),
    );
  }

  Widget _buildGuestButton(BuildContext context) {
    return TextButton(
      onPressed: () => _continueAsGuest(context),
      child: Text(
        'Продовжити без реєстрації',
        style: GoogleFonts.inter(
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
          style: GoogleFonts.inter(
            fontSize: 12,
            color: AppTheme.darkGreen.withValues(alpha: 0.5),
            height: 1.5,
          ),
          children: [
            const TextSpan(text: 'Продовжуючи, ви погоджуєтеся з '),
            TextSpan(
              text: 'Умовами використання',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppTheme.darkGreen,
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w500,
              ),
            ),
            const TextSpan(text: ' та '),
            TextSpan(
              text: 'Політикою конфіденційності',
              style: GoogleFonts.inter(
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