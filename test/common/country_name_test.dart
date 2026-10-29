import 'dart:ui';

import 'package:kfusion/common/country_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('countryName', () {
    test('resolves a listed code in the app language', () {
      expect(countryName('JP', const Locale('en')), 'Japan');
      expect(countryName('JP', const Locale('zh', 'CN')), '日本');
      expect(countryName('GB', const Locale('ja')), 'イギリス');
      expect(countryName('DE', const Locale('ru')), 'Германия');
    });

    test('accepts a lowercase code', () {
      expect(countryName('jp', const Locale('en')), 'Japan');
    });

    test('falls back to English for a language the table does not carry', () {
      expect(countryName('JP', const Locale('de')), 'Japan');
    });

    test('returns null for a code outside the table', () {
      expect(countryName('AQ', const Locale('en')), isNull);
      expect(countryName('', const Locale('en')), isNull);
    });
  });
}
