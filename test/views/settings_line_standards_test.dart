import 'package:kfusion/common/common.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/app.dart';
import 'package:kfusion/providers/config.dart';
import 'package:kfusion/providers/database.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/ui/icons/icons.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/hotkey.dart';
import 'package:kfusion/views/theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

final _keyA = PhysicalKeyboardKey.keyA.usbHidUsage;

ProviderContainer _hotKeyContainer(
  WidgetTester tester, {
  List<HotKeyAction> hotKeyActions = const [],
}) {
  const size = Size(1400, 1400);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer();
  addTearDown(container.dispose);
  globalState.container = container;
  container.read(viewSizeProvider.notifier).update((_) => size);
  final subscription = container.listen(
    hotKeyActionsProvider,
    (_, _) {},
    fireImmediately: true,
  );
  addTearDown(subscription.close);
  container.read(hotKeyActionsProvider.notifier).value = hotKeyActions;
  return container;
}

ColorScheme _schemeOf(WidgetTester tester, Finder finder) {
  return Theme.of(tester.element(finder)).colorScheme;
}

void main() {
  group('hotkey standards', () {
    testWidgets('an unbound row reads its state in the variant tone', (
      tester,
    ) async {
      final container = _hotKeyContainer(tester);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(child: HotKeyView()),
        ),
      );
      await tester.pumpAndSettle();

      final finder = find.text(currentAppLocalizations.hotkeyNotSet).first;
      final scheme = _schemeOf(tester, finder);
      expect(tester.widget<Text>(finder).style?.color, scheme.onSurfaceVariant);
      expect(tester.widget<Text>(finder).style?.color, isNot(scheme.outline));
    });

    testWidgets('the intro glyph stays a neutral mark', (tester) async {
      final container = _hotKeyContainer(tester);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(child: HotKeyView()),
        ),
      );
      await tester.pumpAndSettle();

      final finder = find.byWidgetPredicate(
        (widget) => widget is GlyphIcon && widget.glyph == AppGlyphs.keyboard,
      );
      expect(finder, findsOne);
      final scheme = _schemeOf(tester, finder);
      expect(tester.widget<GlyphIcon>(finder).color, scheme.onSurfaceVariant);
    });

    testWidgets('key caps set their labels in tabular figures', (tester) async {
      final container = _hotKeyContainer(
        tester,
        hotKeyActions: [
          HotKeyAction(
            action: HotAction.view,
            key: _keyA,
            modifiers: const {KeyboardModifier.shift},
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(child: HotKeyView()),
        ),
      );
      await tester.pumpAndSettle();

      final labels = ShortcutLabels.host();
      final finder = find.text(labels.key(_keyA));
      expect(finder, findsOne);
      final features = tester.widget<Text>(finder).style?.fontFeatures;
      expect(features, contains(const FontFeature.tabularFigures()));
    });

    testWidgets('a conflict reads in the warning tone, never tertiary', (
      tester,
    ) async {
      final taken = HotKeyAction(
        action: HotAction.start,
        key: _keyA,
        modifiers: const {KeyboardModifier.control},
      );
      final container = _hotKeyContainer(tester, hotKeyActions: [taken]);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: TestApp(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const Scaffold(
                      body: HotKeyRecorder(
                        hotKeyAction: HotKeyAction(action: HotAction.mode),
                        labels: ShortcutLabels(isMacOS: false, isWindows: true),
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await simulateKeyDownEvent(
        LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft,
      );
      await simulateKeyDownEvent(
        LogicalKeyboardKey.keyA,
        physicalKey: PhysicalKeyboardKey.keyA,
      );
      await simulateKeyUpEvent(
        LogicalKeyboardKey.keyA,
        physicalKey: PhysicalKeyboardKey.keyA,
      );
      await simulateKeyUpEvent(
        LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft,
      );
      await tester.pumpAndSettle();

      final finder = find.text(
        currentAppLocalizations.hotkeyConflictWith(HotAction.start.label),
      );
      expect(finder, findsOne);
      final scheme = _schemeOf(tester, finder);
      expect(tester.widget<Text>(finder).style?.color, scheme.warning);
    });
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

    testWidgets('cards on the theme page take the card corner档', (
      tester,
    ) async {
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

      final fontCard = find.ancestor(
        of: find.text('Aa').first,
        matching: find.byType(Material),
      );
      final fontShape =
          tester.widget<Material>(fontCard.first).shape
              as RoundedSuperellipseBorder;
      expect(fontShape.borderRadius, AppRadius.xl);
    });
  });
}
