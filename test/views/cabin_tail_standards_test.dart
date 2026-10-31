import 'package:flutter/foundation.dart' show listEquals;
import 'package:kfusion/common/common.dart';
import 'package:kfusion/features/form/custom_issue.dart';
import 'package:kfusion/ui/hara.dart';
import 'package:kfusion/ui/icons/icons.dart';
import 'package:kfusion/ui/null_status.dart';
import 'package:kfusion/ui/segmented_control.dart';
import 'package:kfusion/ui/shape.dart';
import 'package:kfusion/ui/surface.dart';
import 'package:kfusion/views/disclaimer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

const _seed = Color(0xFF00696D);

ColorScheme _scheme(Brightness brightness) =>
    ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);

ThemeData _theme(Brightness brightness) {
  final scheme = _scheme(brightness);
  return ThemeData(colorScheme: scheme, useMaterial3: true).withAppShapes;
}

void main() {
  group('floating shapes at the theme base', () {
    for (final brightness in Brightness.values) {
      test('dialog and menu shapes carry the cabin rim ($brightness)', () {
        final scheme = _scheme(brightness);
        final theme = _theme(brightness);
        final floating = AppShape.floating.copyWith(side: scheme.cabinRimSide);

        expect(theme.dialogTheme.shape, floating);
        expect(theme.popupMenuTheme.shape, floating);
        expect(theme.menuTheme.style?.shape?.resolve({}), floating);
        expect(theme.bottomSheetTheme.shape, AppShape.top(AppCorner.floating));
      });
    }
  });

  group('error faces, plan B', () {
    testWidgets('the error banner is a neutral panel with red marks', (
      tester,
    ) async {
      final scheme = _scheme(Brightness.light);
      await tester.pumpWidget(
        TestApp(
          theme: _theme(Brightness.light),
          child: const ErrorBanner(message: 'It broke'),
        ),
      );
      await tester.pumpAndSettle();

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ErrorBanner),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as ShapeDecoration;
      expect(decoration.color, SurfaceLevel.card.colorOf(scheme));
      expect((decoration.shape as OutlinedBorder).side, scheme.cabinRimSide);
      final glyph = tester.widget<GlyphIcon>(find.byType(GlyphIcon));
      expect(glyph.color, scheme.error);
      final text = tester.widget<Text>(find.text('It broke'));
      expect(text.style?.color, scheme.error);
    });

    testWidgets('the error illustration keeps red on its lines and glyph '
        'only', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: NullStatus(
              label: 'Nothing here',
              illustration: NullStatusIllustration.error,
            ),
          ),
        ),
      );
      await tester.pump();

      final scheme = Theme.of(
        tester.element(find.byType(NullStatus)),
      ).colorScheme;
      final paint = tester.widget<CustomPaint>(
        find
            .descendant(
              of: find.byType(EmptyIllustration),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      final painter = paint.painter as dynamic;
      expect(painter.glyphColor as Color, scheme.error);
      expect(painter.frameColor as Color, scheme.error);
      expect(painter.ruleColor as Color, HaraPalette.light.dim);
    });
  });

  testWidgets('the segmented control chooses with the ink face', (
    tester,
  ) async {
    final scheme = _scheme(Brightness.light);
    await tester.pumpWidget(
      TestApp(
        theme: _theme(Brightness.light),
        child: SegmentedControl<String>(
          segments: const [('a', 'Alpha'), ('b', 'Beta')],
          value: 'a',
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final decorations = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(SegmentedControl<String>),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((box) => box.decoration)
        .whereType<ShapeDecoration>()
        .toList();
    expect(
      decorations.where((decoration) => decoration.color == scheme.onSurface),
      hasLength(1),
    );
    final chosen = tester.widget<DefaultTextStyle>(
      find
          .ancestor(
            of: find.text('Alpha'),
            matching: find.byType(DefaultTextStyle),
          )
          .first,
    );
    expect(chosen.style.color, SurfaceLevel.page.colorOf(scheme));
  });

  testWidgets('the disclaimer body sits flat on the page field', (
    tester,
  ) async {
    final scheme = _scheme(Brightness.light);
    await tester.pumpWidget(
      TestApp(
        theme: _theme(Brightness.light),
        wrapInProviderScope: true,
        child: const DisclaimerView(),
      ),
    );
    await tester.pumpAndSettle();

    final panels = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<ShapeDecoration>()
        .where(
          (decoration) =>
              decoration.shadows != null &&
              decoration.shadows!.isNotEmpty &&
              listEquals(decoration.shadows, scheme.cabinPanelShadows),
        )
        .toList();
    expect(panels, isEmpty);
    expect(
      find.text(currentAppLocalizations.disclaimerSoftwareTitle),
      findsOneWidget,
    );
  });
}
