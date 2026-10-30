import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _androidAttribute(String source, String element, String attribute) {
  final elementTag = RegExp('<$element\\b[^>]*>').firstMatch(source)!.group(0)!;
  return RegExp(
    'android:$attribute="([^"]+)"',
  ).firstMatch(elementTag)!.group(1)!;
}

void main() {
  for (final name in ['ic_launcher', 'ic_launcher_round']) {
    test('$name adaptive icon uses the direct raster foreground', () {
      final adaptiveIcon = File(
        'android/app/src/main/res/mipmap-anydpi-v26/$name.xml',
      ).readAsStringSync();
      expect(
        _androidAttribute(adaptiveIcon, 'foreground', 'drawable'),
        '@mipmap/ic_launcher_foreground',
      );
      expect(
        _androidAttribute(adaptiveIcon, 'background', 'drawable'),
        '@color/ic_launcher_background',
      );
      expect(
        _androidAttribute(adaptiveIcon, 'monochrome', 'drawable'),
        '@drawable/ic_launcher_glyph_mono',
      );
    });
  }
}
