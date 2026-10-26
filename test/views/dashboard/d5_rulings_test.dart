import 'package:kfusion/common/common.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/dashboard/style.dart';
import 'package:kfusion/views/dashboard/widgets/card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// Pins the settled half of the P-D D5 ledger: the glass default, the
// dashboard colour mapping onto the shared surface levels, and the
// dashboard text and chip readings kept as the dashboard's own track.
void main() {
  test('liquid glass defaults to none and keeps its three modes', () {
    expect(const ThemeProps().liquidGlass, LiquidGlassMode.none);
    expect(LiquidGlassMode.values, hasLength(3));
  });

  ColorScheme schemeOf(Brightness brightness) => seededColorScheme(
    seedColor: const Color(defaultPrimaryColor),
    brightness: brightness,
    style: ColorStyle.vivid,
  );

  for (final brightness in Brightness.values) {
    testWidgets('dashboard colours map onto the surface levels ($brightness)', (
      tester,
    ) async {
      final scheme = schemeOf(brightness);
      late DashboardColors colors;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: scheme),
          home: Builder(
            builder: (context) {
              colors = DashboardColors.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(colors.page, SurfaceLevel.page.colorOf(scheme));
      expect(colors.card, SurfaceLevel.card.colorOf(scheme));
      expect(colors.tone, SurfaceLevel.block.colorOf(scheme));
      expect(colors.tone2, SurfaceLevel.inset.colorOf(scheme));
      expect(colors.track, scheme.surfaceContainerHighest);
      expect(colors.ok, scheme.success);
      expect(colors.okContainer, scheme.successContainer);
      expect(colors.onOkContainer, scheme.onSuccessContainer);
      expect(colors.warn, scheme.warning);
      expect(colors.warnContainer, scheme.warningContainer);
      expect(colors.onWarnContainer, scheme.onWarningContainer);
      expect(
        colors.series2,
        Color.alphaBlend(scheme.primary.withValues(alpha: 0.45), colors.card),
      );
    });
  }

  testWidgets('dashboard text roles keep their ruled readings', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (captured) {
            context = captured;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final title = DashboardText.cardTitle(context);
    expect(title.fontSize, AppTextStyle.footnote.size);
    expect(title.fontWeight, FontWeight.w600);
    expect(title.color, Theme.of(context).colorScheme.onSurfaceVariant);
    final mobileTitle = DashboardText.mobileCardTitle(context);
    expect(mobileTitle.fontSize, AppTextStyle.subheadline.size);
    expect(mobileTitle.fontWeight, FontWeight.w600);
    final figure = DashboardText.figure(context, AppTextStyle.display);
    expect(figure.fontFeatures, contains(const FontFeature.tabularFigures()));
    expect(figure.letterSpacing, -0.02 * AppTextStyle.display.size);
  });

  testWidgets('the dashboard chip keeps the shared caption reading', (
    tester,
  ) async {
    final scheme = schemeOf(Brightness.light);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: const Scaffold(
          body: Center(child: DashboardChip(label: 'Ready')),
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('Ready'));
    expect(text.style?.fontSize, AppTextStyle.caption1.size);
    expect(text.style?.fontWeight, FontWeight.w600);
    expect(
      text.style?.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
    expect(text.style?.color, scheme.onSurfaceVariant);
    final chip = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(DashboardChip),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = chip.decoration as ShapeDecoration;
    expect(decoration.color, SurfaceLevel.block.colorOf(scheme));
  });
}
