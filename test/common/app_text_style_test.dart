import 'package:kfusion/ui/typography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

TextStyle _slot(String family, Color color) =>
    TextStyle(fontFamily: family, color: color, fontSize: 99);

void main() {
  test('the scale keeps its sizes, leadings and weights', () {
    final table = <AppTextStyle, (double, double, FontWeight, FontWeight)>{
      AppTextStyle.display: (40, 44, FontWeight.w400, FontWeight.w600),
      AppTextStyle.largeTitle: (34, 41, FontWeight.w400, FontWeight.w600),
      AppTextStyle.title1: (28, 34, FontWeight.w400, FontWeight.w600),
      AppTextStyle.pageTitle: (27, 34, FontWeight.w600, FontWeight.w600),
      AppTextStyle.title2: (22, 28, FontWeight.w400, FontWeight.w600),
      AppTextStyle.title3: (20, 25, FontWeight.w400, FontWeight.w500),
      AppTextStyle.headline: (17, 22, FontWeight.w600, FontWeight.w600),
      AppTextStyle.body: (17, 23, FontWeight.w400, FontWeight.w600),
      AppTextStyle.callout: (16, 22, FontWeight.w400, FontWeight.w600),
      AppTextStyle.subheadline: (15, 21, FontWeight.w400, FontWeight.w600),
      AppTextStyle.footnote: (13, 18, FontWeight.w400, FontWeight.w600),
      AppTextStyle.caption1: (12, 16, FontWeight.w400, FontWeight.w600),
      AppTextStyle.caption2: (11, 13, FontWeight.w400, FontWeight.w600),
    };
    expect(table.length, AppTextStyle.values.length);
    for (final entry in table.entries) {
      final style = entry.key;
      final (size, leading, weight, emphasized) = entry.value;
      expect(style.size, size, reason: '$style size');
      expect(style.leading, leading, reason: '$style leading');
      expect(style.weight, weight, reason: '$style weight');
      expect(style.emphasizedWeight, emphasized, reason: '$style emphasized');
    }
    expect(AppTextStyle.display.fontFeatures, const [
      FontFeature.tabularFigures(),
    ]);
    for (final style in AppTextStyle.values.skip(1)) {
      expect(style.fontFeatures, isEmpty, reason: '$style features');
    }
  });

  testWidgets('of reads each style from its settled text theme slot', (
    tester,
  ) async {
    const marker = Color(0xFF135713);
    final theme = ThemeData(
      textTheme: TextTheme(
        headlineLarge: _slot('headlineLarge', marker),
        headlineMedium: _slot('headlineMedium', marker),
        headlineSmall: _slot('headlineSmall', marker),
        titleLarge: _slot('titleLarge', marker),
        titleMedium: _slot('titleMedium', marker),
        bodyLarge: _slot('bodyLarge', marker),
        bodyMedium: _slot('bodyMedium', marker),
        bodySmall: _slot('bodySmall', marker),
        labelMedium: _slot('labelMedium', marker),
        labelSmall: _slot('labelSmall', marker),
      ),
    );
    final slots = <AppTextStyle, String>{
      AppTextStyle.display: 'headlineLarge',
      AppTextStyle.largeTitle: 'headlineLarge',
      AppTextStyle.title1: 'headlineMedium',
      AppTextStyle.pageTitle: 'headlineSmall',
      AppTextStyle.title2: 'headlineSmall',
      AppTextStyle.title3: 'titleLarge',
      AppTextStyle.headline: 'titleMedium',
      AppTextStyle.body: 'bodyLarge',
      AppTextStyle.callout: 'bodyLarge',
      AppTextStyle.subheadline: 'bodyMedium',
      AppTextStyle.footnote: 'bodySmall',
      AppTextStyle.caption1: 'labelMedium',
      AppTextStyle.caption2: 'labelSmall',
    };
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    for (final entry in slots.entries) {
      final applied = entry.key.of(context);
      expect(applied.fontFamily, entry.value, reason: '${entry.key} slot');
      expect(applied.color, marker, reason: '${entry.key} keeps slot colour');
      expect(applied.fontSize, entry.key.size, reason: '${entry.key} size');
      expect(
        applied.height,
        entry.key.leading / entry.key.size,
        reason: '${entry.key} height',
      );
      expect(applied.fontWeight, entry.key.weight, reason: '${entry.key}');
      expect(applied.letterSpacing, 0, reason: '${entry.key} tracking');
      final emphasized = entry.key.of(context, emphasized: true);
      expect(
        emphasized.fontWeight,
        entry.key.emphasizedWeight,
        reason: '${entry.key} emphasized',
      );
    }
  });

  testWidgets('custom takes the body slot below title3 and the title slot '
      'from title3 up', (tester) async {
    const marker = Color(0xFF246824);
    final theme = ThemeData(
      textTheme: TextTheme(
        bodyLarge: _slot('bodyLarge', marker),
        titleLarge: _slot('titleLarge', marker),
      ),
    );
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final small = AppTextStyle.custom(context, size: 19.9, leading: 24);
    expect(small.fontFamily, 'bodyLarge');
    expect(small.fontSize, 19.9);
    expect(small.height, 24 / 19.9);
    final large = AppTextStyle.custom(
      context,
      size: 20,
      leading: 25,
      weight: FontWeight.w700,
    );
    expect(large.fontFamily, 'titleLarge');
    expect(large.fontWeight, FontWeight.w700);
    expect(large.letterSpacing, 0);
  });

  test('withAppTypography maps every slot through the scale', () {
    TextStyle base() => const TextStyle(fontSize: 99, color: Color(0xFF111111));
    final theme = ThemeData(
      textTheme: TextTheme(
        displayLarge: base(),
        displayMedium: base(),
        displaySmall: base(),
        headlineLarge: base(),
        headlineMedium: base(),
        headlineSmall: base(),
        titleLarge: base(),
        titleMedium: base(),
        titleSmall: base(),
        bodyLarge: base(),
        bodyMedium: base(),
        bodySmall: base(),
        labelLarge: base(),
        labelMedium: base(),
        labelSmall: base(),
      ),
    ).withAppTypography;
    final text = theme.textTheme;
    final sizes = <TextStyle?, double>{
      text.displayLarge: 34,
      text.displayMedium: 34,
      text.displaySmall: 34,
      text.headlineLarge: 34,
      text.headlineMedium: 28,
      text.headlineSmall: 22,
      text.titleLarge: 20,
      text.titleMedium: 17,
      text.titleSmall: 15,
      text.bodyLarge: 17,
      text.bodyMedium: 15,
      text.bodySmall: 13,
      text.labelLarge: 15,
      text.labelMedium: 12,
      text.labelSmall: 11,
    };
    for (final entry in sizes.entries) {
      expect(entry.key?.fontSize, entry.value);
      expect(entry.key?.color, const Color(0xFF111111));
    }
    expect(text.titleMedium?.fontWeight, FontWeight.w600);
    expect(text.titleSmall?.fontWeight, FontWeight.w600);
    expect(text.labelLarge?.fontWeight, FontWeight.w600);
    expect(text.bodyLarge?.fontWeight, FontWeight.w400);
    expect(text.bodyLarge?.height, 23 / 17);
    expect(
      theme.primaryTextTheme.bodyLarge?.fontSize,
      17,
      reason: 'the primary text theme takes the same scale',
    );
  });

  test('a slot the caller never set still takes the scale', () {
    final theme = ThemeData(
      textTheme: const TextTheme(bodyLarge: TextStyle(fontSize: 99)),
    ).withAppTypography;
    expect(theme.textTheme.displayLarge?.fontSize, 34);
    expect(theme.textTheme.bodyLarge?.fontSize, 17);
  });
}
