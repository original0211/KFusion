import 'package:kfusion/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('the settled scale: titles one weight lighter, body a point looser', () {
    for (final style in [
      AppTextStyle.display,
      AppTextStyle.largeTitle,
      AppTextStyle.title1,
      AppTextStyle.pageTitle,
      AppTextStyle.title2,
    ]) {
      expect(style.emphasizedWeight, FontWeight.w600, reason: '$style');
    }
    expect(AppTextStyle.title3.emphasizedWeight, FontWeight.w500);
    expect(AppTextStyle.body.leading, 23);
    expect(AppTextStyle.callout.leading, 22);
    expect(AppTextStyle.subheadline.leading, 21);
    expect(
      AppTextStyle.display.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
  });

  testWidgets('display applies its weight and tabular figures', (tester) async {
    late TextStyle display;
    late TextStyle body;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true).withAppTypography,
        home: Builder(
          builder: (context) {
            display = AppTextStyle.display.of(context, emphasized: true);
            body = AppTextStyle.body.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(display.fontWeight, FontWeight.w600);
    expect(display.fontFeatures, contains(const FontFeature.tabularFigures()));
    expect(body.height, 23 / 17);
  });
}
