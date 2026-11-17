import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/features/profile/licenses_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Профіль', style: GoogleFonts.merriweather(color: AppTheme.darkGreen)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        children: [
          ListTile(
            key: const ValueKey('profile-licenses'),
            leading: const Icon(Icons.copyright_rounded, color: AppTheme.darkGreen),
            title: const Text('Джерела та ліцензії'),
            subtitle: const Text('Фото, карти, погода, ШІ — автори й ліцензії'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LicensesScreen())),
          ),
        ],
      ),
    );
  }
}
