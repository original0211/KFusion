import 'dart:math' as math;
import 'dart:typed_data';

import 'package:kfusion/ui/icons/icons.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

const _addLabel = 'Add';

// A press only paints, so its swell shows in the paint transform.
Rect _painted(WidgetTester tester, RenderObject box, Rect resting) {
  Matrix4? transform;
  expect(
    box,
    paints..everything((method, arguments) {
      if (method == #transform) {
        transform ??= Matrix4.fromFloat64List(arguments.single as Float64List);
      }
      return true;
    }),
  );
  final local = Offset.zero & resting.size;
  return (transform == null
          ? local
          : MatrixUtils.transformRect(transform!, local))
      .shift(resting.topLeft);
}

void main() {
  testWidgets('a quick tap swells an elastic press all the way', (
    tester,
  ) async {
    await tester.pumpWidget(
      const TestApp(
        child: Center(
          child: ElasticPress(
            child: ColoredBox(
              color: Colors.blue,
              child: SizedBox.square(dimension: 40),
            ),
          ),
        ),
      ),
    );
    final press = find.byType(ElasticPress);
    final resting = tester.getRect(press);
    Rect painted() => _painted(tester, tester.renderObject(press), resting);

    final gesture = await tester.startGesture(resting.center);
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.up();
    var swollen = resting.width;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      swollen = math.max(swollen, painted().width);
    }
    expect(swollen, greaterThan(resting.width * 1.24));

    await tester.pumpAndSettle();
    expect(painted(), resting);
  });

  testWidgets(
    'an elastic button leaves a press to the swell and keeps the icon theme',
    (tester) async {
      await tester.pumpWidget(
        TestApp(
          child: Scaffold(
            body: IconTheme.merge(
              data: const IconThemeData(fill: 1),
              child: Row(
                children: [
                  ElasticButton(
                    child: IconButton.filled(
                      tooltip: _addLabel,
                      onPressed: () {},
                      icon: const GlyphIcon(AppGlyphs.add),
                    ),
                  ),
                  ElasticButton(
                    child: FilledButton(
                      onPressed: () {},
                      child: const Text(_addLabel),
                    ),
                  ),
                  ElasticButton(
                    child: FloatingActionButton(
                      heroTag: null,
                      onPressed: () {},
                      child: const GlyphIcon(AppGlyphs.copy),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      InkWell inkOf(Type button) => tester.widget<InkWell>(
        find.descendant(
          of: find.byType(button),
          matching: find.byType(InkWell),
        ),
      );
      for (final button in [IconButton, FilledButton]) {
        final ink = inkOf(button);
        expect(ink.splashFactory, NoSplash.splashFactory);
        expect(
          ink.overlayColor!.resolve({WidgetState.pressed}),
          Colors.transparent,
        );
      }
      final fabInk = find.descendant(
        of: find.byType(FloatingActionButton),
        matching: find.byType(InkWell),
      );
      final fabTheme = Theme.of(tester.element(fabInk));
      expect(fabTheme.splashFactory, NoSplash.splashFactory);
      expect(fabTheme.highlightColor, Colors.transparent);
      expect(
        IconTheme.of(tester.element(find.byType(GlyphIcon).first)).fill,
        1,
      );
    },
  );
}
