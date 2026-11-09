import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Іконки нижньої навігації мають бути в бандлі (pubspec: assets/icons/) і бути SVG.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const icons = ['forecast', 'map', 'recognize', 'safety', 'community', 'profile'];

  for (final name in icons) {
    test('assets/icons/ic_$name.svg у бандлі', () async {
      final svg = await rootBundle.loadString('assets/icons/ic_$name.svg');
      expect(svg, startsWith('<svg'));
      expect(svg, contains('viewBox="0 0 64 64"'));
    });
  }
}
