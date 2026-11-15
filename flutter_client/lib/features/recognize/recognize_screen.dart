import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/features/catalog/catalog_browser.dart';

/// Вкладка «Розпізнати»: довідник грибів (розпізнавання за фото — локальний ONNX, ADR — додамо над ним).
class RecognizeScreen extends StatelessWidget {
  const RecognizeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Розпізнати', style: GoogleFonts.merriweather(color: AppTheme.darkGreen)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: const CatalogBrowser(),
    );
  }
}
