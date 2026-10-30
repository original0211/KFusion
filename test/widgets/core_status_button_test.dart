import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/ui/icons/icons.dart';
import 'package:kfusion/views/dashboard/widgets/core_status_button.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/glyph_finders.dart';
import '../helpers/test_app.dart';

class _RecordingCoreAction extends CoreAction {
  int restarts = 0;
  bool fail = false;

  @override
  Future<bool> restartCore() async {
    restarts++;
    if (fail) {
      throw StateError('restart failed');
    }
    return true;
  }
}

void main() {
  testWidgets(
    'holds connecting for the minimum duration after a fast restart',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      globalState.container = container;
      container.read(coreStatusProvider.notifier).value = CoreStatus.connected;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: TestApp(
            includeNavigatorKey: false,
            homeBuilder: (child) => Scaffold(body: Center(child: child)),
            child: const CoreStatusButton(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byGlyph(AppGlyphs.check), findsOneWidget);
      expect(find.byType(CommonCircleLoading), findsNothing);

      container.read(coreStatusProvider.notifier).value = CoreStatus.connecting;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CommonCircleLoading), findsOneWidget);
      expect(find.byGlyph(AppGlyphs.check), findsNothing);

      container.read(coreStatusProvider.notifier).value = CoreStatus.connected;
      await tester.pump();
      expect(find.byType(CommonCircleLoading), findsOneWidget);
      expect(find.byGlyph(AppGlyphs.check), findsNothing);

      await tester.pump(const Duration(milliseconds: 199));
      expect(find.byType(CommonCircleLoading), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byGlyph(AppGlyphs.check), findsOneWidget);
      expect(find.byType(CommonCircleLoading), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      expect(find.byGlyph(AppGlyphs.check), findsOneWidget);
    },
  );

  testWidgets(
    'shows disconnected immediately when restart fails during the hold',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      globalState.container = container;
      container.read(coreStatusProvider.notifier).value = CoreStatus.connected;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: TestApp(
            includeNavigatorKey: false,
            homeBuilder: (child) => Scaffold(body: Center(child: child)),
            child: const CoreStatusButton(),
          ),
        ),
      );
      await tester.pump();

      container.read(coreStatusProvider.notifier).value = CoreStatus.connecting;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CommonCircleLoading), findsOneWidget);

      container.read(coreStatusProvider.notifier).value =
          CoreStatus.disconnected;
      await tester.pump();
      expect(find.byGlyph(AppGlyphs.refresh), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byGlyph(AppGlyphs.refresh), findsOneWidget);
      expect(find.byType(CommonCircleLoading), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      expect(find.byGlyph(AppGlyphs.refresh), findsOneWidget);
      expect(find.byType(CommonCircleLoading), findsNothing);
    },
  );

  testWidgets('does not clip a connecting state longer than the hold', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    globalState.container = container;
    container.read(coreStatusProvider.notifier).value = CoreStatus.connected;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          includeNavigatorKey: false,
          homeBuilder: (child) => Scaffold(body: Center(child: child)),
          child: const CoreStatusButton(),
        ),
      ),
    );
    await tester.pump();

    container.read(coreStatusProvider.notifier).value = CoreStatus.connecting;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(CommonCircleLoading), findsOneWidget);

    container.read(coreStatusProvider.notifier).value = CoreStatus.connected;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byGlyph(AppGlyphs.check), findsOneWidget);
    expect(find.byType(CommonCircleLoading), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    expect(find.byGlyph(AppGlyphs.check), findsOneWidget);
  });

  testWidgets('holds connecting when restarting from disconnected', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    globalState.container = container;
    container.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          includeNavigatorKey: false,
          homeBuilder: (child) => Scaffold(body: Center(child: child)),
          child: const CoreStatusButton(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byGlyph(AppGlyphs.refresh), findsOneWidget);

    container.read(coreStatusProvider.notifier).value = CoreStatus.connecting;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CommonCircleLoading), findsOneWidget);
    expect(find.byGlyph(AppGlyphs.refresh), findsNothing);

    container.read(coreStatusProvider.notifier).value = CoreStatus.connected;
    await tester.pump();
    expect(find.byType(CommonCircleLoading), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 199));
    expect(find.byType(CommonCircleLoading), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byGlyph(AppGlyphs.check), findsOneWidget);
    expect(find.byType(CommonCircleLoading), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    expect(find.byGlyph(AppGlyphs.check), findsOneWidget);
  });

  Future<ProviderContainer> pumpButton(
    WidgetTester tester,
    CoreStatus status,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    globalState.container = container;
    container.read(coreStatusProvider.notifier).value = status;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          includeNavigatorKey: false,
          homeBuilder: (child) => Scaffold(body: Center(child: child)),
          child: const CoreStatusButton(),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('connected state wears a hairline ring, not a status fill', (
    tester,
  ) async {
    await pumpButton(tester, CoreStatus.connected);

    final style = tester.widget<IconButton>(find.byType(IconButton)).style!;
    const states = <WidgetState>{};
    expect(style.backgroundColor!.resolve(states), HaraPalette.transparent);
    expect(style.foregroundColor!.resolve(states), HaraPalette.light.ink);
    final side = style.side!.resolve(states)!;
    expect(side.color, HaraPalette.light.line);
    expect(side.width, HaraSpace.hairline);
  });

  testWidgets('disconnected state is a hairline pill in sub ink', (
    tester,
  ) async {
    await pumpButton(tester, CoreStatus.disconnected);

    final style = tester.widget<FilledButton>(find.byType(FilledButton)).style!;
    const states = <WidgetState>{};
    expect(style.backgroundColor!.resolve(states), HaraPalette.transparent);
    expect(style.foregroundColor!.resolve(states), HaraPalette.light.sub);
    final side = style.side!.resolve(states)!;
    expect(side.color, HaraPalette.light.line);
    expect(side.width, HaraSpace.hairline);
  });

  testWidgets('connecting state spins in ink inside the hairline pill', (
    tester,
  ) async {
    final container = await pumpButton(tester, CoreStatus.connected);

    container.read(coreStatusProvider.notifier).value = CoreStatus.connecting;
    await tester.pump();

    final loading = tester.widget<CommonCircleLoading>(
      find.byType(CommonCircleLoading),
    );
    expect(loading.color, HaraPalette.light.ink);
    final style = tester.widget<FilledButton>(find.byType(FilledButton)).style!;
    expect(
      style.foregroundColor!.resolve(const <WidgetState>{}),
      HaraPalette.light.ink,
    );
  });

  Future<_RecordingCoreAction> pumpButtonWithAction(
    WidgetTester tester,
    CoreStatus status,
  ) async {
    final action = _RecordingCoreAction();
    final container = ProviderContainer(
      overrides: [coreActionProvider.overrideWith(() => action)],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container.read(coreStatusProvider.notifier).value = status;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          homeBuilder: (child) => Scaffold(body: Center(child: child)),
          child: const CoreStatusButton(),
        ),
      ),
    );
    await tester.pump();
    return action;
  }

  testWidgets('a tap on the connected ring asks, then restarts the core', (
    tester,
  ) async {
    final action = await pumpButtonWithAction(tester, CoreStatus.connected);

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(find.text('Confirm'), findsOneWidget);
    expect(action.restarts, 0);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(action.restarts, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling the prompt leaves the core alone', (tester) async {
    final action = await pumpButtonWithAction(tester, CoreStatus.disconnected);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(action.restarts, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed restart is reported, not thrown', (tester) async {
    final action = await pumpButtonWithAction(tester, CoreStatus.connected);
    action.fail = true;

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(action.restarts, 1);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 5));
  });
}
