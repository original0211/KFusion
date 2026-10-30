import 'dart:io';

import 'package:kfusion/providers/app.dart';
import 'package:kfusion/providers/database.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/config/general.dart';
import 'package:kfusion/views/theme.dart';
import 'package:kfusion/views/tools.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_paths.dart';
import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

void main() {
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('kfusion-line-std');
    await useAppPaths(dir);
  });

  group('theme standards', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [profilesProvider.overrideWith(TestProfiles.new)],
      );
      globalState.container = container;
      container.read(viewSizeProvider.notifier).value = const Size(1400, 2400);
    });

    tearDown(() => container.dispose());

    testWidgets('theme cards take the card corner档; the settings switch '
        'card reads square', (tester) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(child: ThemeView()),
        ),
      );
      await tester.pumpAndSettle();

      final view = find.byType(ThemeView);
      final strayShapes = find.descendant(
        of: view,
        matching: find.byWidgetPredicate((widget) {
          if (widget is Material) return widget.shape == AppShape.lg;
          if (widget is Container) {
            final decoration = widget.decoration;
            return decoration is ShapeDecoration &&
                decoration.shape == AppShape.lg;
          }
          return false;
        }),
      );
      expect(strayShapes, findsNothing);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(child: ToolsView()),
        ),
      );
      await tester.pumpAndSettle();

      final switchCard = find.byType(CoreSwitchCard);
      expect(
        find.descendant(of: switchCard, matching: find.byType(CommonCard)),
        findsNothing,
      );
      final roundedShapes = find.descendant(
        of: switchCard,
        matching: find.byWidgetPredicate((widget) {
          if (widget is Material) {
            final shape = widget.shape;
            return shape is RoundedSuperellipseBorder &&
                shape.borderRadius != BorderRadius.zero;
          }
          if (widget is DecoratedBox) {
            final decoration = widget.decoration;
            if (decoration is ShapeDecoration) {
              final shape = decoration.shape;
              return shape is RoundedSuperellipseBorder &&
                  shape.borderRadius != BorderRadius.zero;
            }
          }
          return false;
        }),
      );
      expect(roundedShapes, findsNothing);
    });
  });
}
