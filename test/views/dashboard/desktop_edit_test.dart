import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/views/dashboard/dashboard.dart';
import 'package:kfusion/views/dashboard/edit.dart';
import 'package:kfusion/views/dashboard/widgets/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/preferences.dart';
import '../../helpers/test_app.dart';
import '../../helpers/test_profiles.dart';

void main() {
  late ProviderContainer container;

  setUp(() async {
    await mockPreferences({'beginnerMode': false});
    container = ProviderContainer(
      overrides: [profilesProvider.overrideWith(TestProfiles.new)],
    );
    globalState.container = container;
    container.listen(groupsProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  List<DashboardWidget> saved() =>
      container.read(appSettingProvider).dashboardWidgets;

  void seed(List<DashboardWidget> widgets) {
    container
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(dashboardWidgets: widgets));
  }

  // The cards sway for as long as they are edited, so nothing settles.
  Future<void> settle(WidgetTester tester) async {
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpDashboard(
    WidgetTester tester, {
    Size size = const Size(1280, 960),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container.read(viewSizeProvider.notifier).value = size;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(
          child: DashboardView(platform: SupportPlatform.Windows),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> pumpEditor(
    WidgetTester tester, {
    Size size = const Size(1280, 960),
  }) async {
    await pumpDashboard(tester, size: size);
    await tester.tap(find.byTooltip('Edit dashboard'));
    await settle(tester);
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  }

  double top(WidgetTester tester, Finder finder) =>
      tester.getTopLeft(finder).dy;

  testWidgets('the desktop shows the edit entry and opens the editor', (
    tester,
  ) async {
    await pumpDashboard(tester);

    expect(find.byTooltip('Edit dashboard'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit dashboard'));
    await settle(tester);

    expect(find.byType(DashboardEditor), findsOneWidget);
    expect(tester.takeException(), isNull);

    await teardown(tester);
  });

  testWidgets('the status card cannot be removed on the desktop either', (
    tester,
  ) async {
    seed(const [
      DashboardWidget.currentOutbound,
      DashboardWidget.networkSpeed,
      DashboardWidget.memoryInfo,
    ]);
    await pumpEditor(tester, size: const Size(1280, 1400));

    expect(find.byTooltip('Remove Status'), findsNothing);
    expect(find.byTooltip('Remove Network speed'), findsOneWidget);
    expect(find.byTooltip('Remove Memory info'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await teardown(tester);
  });

  testWidgets('removing a card on the desktop saves to the shared list '
      'at once', (tester) async {
    seed(const [
      DashboardWidget.currentOutbound,
      DashboardWidget.networkSpeed,
      DashboardWidget.memoryInfo,
    ]);
    await pumpEditor(tester, size: const Size(1280, 1400));

    await tester.tap(find.byTooltip('Remove Memory info'));
    await tester.pump();

    expect(saved(), const [
      DashboardWidget.currentOutbound,
      DashboardWidget.networkSpeed,
    ]);

    await settle(tester);
    expect(find.byType(MemoryInfo), findsNothing);
    expect(tester.takeException(), isNull);

    await teardown(tester);
  });

  testWidgets('adding a card on the desktop saves to the shared list', (
    tester,
  ) async {
    seed(const [DashboardWidget.currentOutbound, DashboardWidget.networkSpeed]);
    await pumpEditor(tester);

    await tester.tap(find.byTooltip('Add Memory info'));
    await settle(tester);

    expect(saved(), const [
      DashboardWidget.currentOutbound,
      DashboardWidget.networkSpeed,
      DashboardWidget.memoryInfo,
    ]);
    expect(find.byType(MemoryInfo), findsOneWidget);
    expect(tester.takeException(), isNull);

    await teardown(tester);
  });

  testWidgets('the addable rows stand on the first screen, above the '
      'cards', (tester) async {
    seed(defaultDashboardWidgets);
    await pumpEditor(tester);

    expect(find.text('Available to add'), findsOneWidget);
    final add = find.byTooltip('Add Memory info');
    expect(add, findsOneWidget);
    final rect = tester.getRect(add);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(960));
    expect(
      rect.bottom,
      lessThan(top(tester, find.byType(CurrentOutboundCard))),
    );
    expect(tester.takeException(), isNull);

    await teardown(tester);
  });

  testWidgets('a card removed on the desktop joins the addable rows', (
    tester,
  ) async {
    seed(defaultDashboardWidgets);
    await pumpEditor(tester);

    await tester.tap(find.byTooltip('Remove Network speed'));
    await settle(tester);

    expect(saved(), isNot(contains(DashboardWidget.networkSpeed)));
    final add = find.byTooltip('Add Network speed');
    expect(add, findsOneWidget);
    expect(tester.getRect(add).bottom, lessThanOrEqualTo(960));
    expect(tester.takeException(), isNull);

    await teardown(tester);
  });

  testWidgets('with every card shown the addable section says so', (
    tester,
  ) async {
    seed(const [
      DashboardWidget.currentOutbound,
      DashboardWidget.networkSpeed,
      DashboardWidget.outboundMode,
      DashboardWidget.networkTakeover,
      DashboardWidget.serviceStatus,
      DashboardWidget.profiles,
      DashboardWidget.proxyGroups,
      DashboardWidget.connectionStats,
      DashboardWidget.intranetIp,
      DashboardWidget.memoryInfo,
    ]);
    await pumpEditor(tester);

    expect(find.text('Available to add'), findsOneWidget);
    expect(find.text('All cards have been added'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await teardown(tester);
  });

  testWidgets('a card dragged on the desktop saves the new order', (
    tester,
  ) async {
    seed(const [
      DashboardWidget.currentOutbound,
      DashboardWidget.networkTakeover,
      DashboardWidget.profiles,
    ]);
    await pumpEditor(tester, size: const Size(1280, 1400));

    final card = find.byType(ProfilesCard);
    final rise =
        top(tester, card) - top(tester, find.byType(NetworkTakeoverCard)) - 10;
    final gesture = await tester.startGesture(
      tester.getCenter(card),
      kind: PointerDeviceKind.mouse,
    );
    for (var step = 0; step < 4; step++) {
      await gesture.moveBy(Offset(0, -rise / 4));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await gesture.up();
    await settle(tester);

    expect(saved(), const [
      DashboardWidget.currentOutbound,
      DashboardWidget.profiles,
      DashboardWidget.networkTakeover,
    ]);
    expect(tester.takeException(), isNull);

    await teardown(tester);
  });

  testWidgets('the grid follows the saved list', (tester) async {
    const full = [
      DashboardWidget.currentOutbound,
      DashboardWidget.networkSpeed,
      DashboardWidget.profiles,
      DashboardWidget.outboundMode,
      DashboardWidget.networkTakeover,
      DashboardWidget.intranetIp,
      DashboardWidget.serviceStatus,
      DashboardWidget.connectionStats,
      DashboardWidget.proxyGroups,
    ];
    seed(full);
    await pumpDashboard(tester, size: const Size(1440, 900));

    expect(find.byType(MemoryInfo), findsNothing);
    expect(find.byType(ConnectionsTableCard), findsOneWidget);
    expect(tester.takeException(), isNull);

    seed(const [...full, DashboardWidget.memoryInfo]);
    await tester.pump();

    expect(find.byType(MemoryInfo), findsOneWidget);
    expect(tester.takeException(), isNull);

    await teardown(tester);
  });

  testWidgets('without the groups card the grid has no tables row', (
    tester,
  ) async {
    seed(const [
      DashboardWidget.currentOutbound,
      DashboardWidget.networkSpeed,
      DashboardWidget.profiles,
      DashboardWidget.outboundMode,
      DashboardWidget.networkTakeover,
      DashboardWidget.intranetIp,
      DashboardWidget.serviceStatus,
      DashboardWidget.connectionStats,
    ]);
    await pumpDashboard(tester, size: const Size(1440, 900));

    expect(find.byType(ConnectionsTableCard), findsNothing);
    expect(find.byType(ProxyGroupsCard), findsNothing);
    expect(find.byType(ProxyGroupsSummaryCard), findsNothing);
    expect(find.byType(ConnectionStatsCard), findsOneWidget);
    expect(tester.takeException(), isNull);

    await teardown(tester);
  });
}
