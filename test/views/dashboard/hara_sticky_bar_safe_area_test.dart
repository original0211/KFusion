import 'dart:async';

import 'package:kfusion/common/service_probe.dart' show routedOutbound;
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/ip_quality.dart';
import 'package:kfusion/providers/outbound_ip.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/providers/routed_probe.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/dashboard/hara_dashboard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/preferences.dart';
import '../../helpers/test_app.dart';

// The pinned compact bar is an overlay at the top of the screen: its
// content must start below the status-bar inset, and must sit exactly
// where it always sat when there is no inset at all.

const _node = 'Node-01';

const _profile = Profile(
  id: 1,
  label: 'Home',
  autoUpdateDuration: Duration.zero,
);

class _RecordingSetupAction extends SetupAction {
  @override
  Future<bool> setRunning(bool running, {bool initialize = false}) {
    ref.read(runTimeProvider.notifier).value = running ? 1 : null;
    return Future.value(true);
  }
}

final _qualityHeld = Completer<IpQuality>().future;

const _freshEntry = ProbeEntry<IpInfo>(
  phase: ProbePhase.fresh,
  value: IpInfo(ip: '203.0.113.9', countryCode: 'AU'),
  stamp: RouteStamp(
    coreEpoch: 1,
    picksVersion: 1,
    hostEpoch: 1,
    proxied: true,
    chains: [_node],
  ),
);

final _groups = [
  Group(
    name: 'GLOBAL',
    type: GroupType.Selector,
    all: [
      for (var i = 1; i <= 21; i++)
        Proxy(
          name: 'Node-${i.toString().padLeft(2, '0')}',
          type: 'Shadowsocks',
        ),
    ],
  ),
];

Finder _smallRing() => find.byWidgetPredicate(
  (widget) => widget is DiscRingMotif && widget.size == HaraSpace.ringCompact,
);

Future<void> _pinBar(WidgetTester tester, {required double inset}) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(top: inset);
  tester.view.viewPadding = FakeViewPadding(top: inset);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  await tester.pumpWidget(
    TestApp(
      locale: const Locale('en'),
      overrides: [
        profilesProvider.overrideWithValue(const [_profile]),
        currentProfileIdProvider.overrideWithBuild((_, _) => 1),
        suspendProvider.overrideWithValue(false),
        setupActionProvider.overrideWith(_RecordingSetupAction.new),
        outboundIpProbeProvider.overrideWithBuild(
          (_, _) => const RoutedProbeState({routedOutbound: _freshEntry}),
        ),
        ipQualityProvider.overrideWith((_, _) => _qualityHeld),
        groupsProvider.overrideWithValue(_groups),
        currentGroupsStateProvider.overrideWithValue(
          GroupsState(value: _groups),
        ),
      ],
      child: const HaraDashboard(),
    ),
  );
  await tester.pump();
  await tester.tap(
    find.byWidgetPredicate(
      (widget) => widget is DiscRingMotif && widget.size == HaraSpace.ringSize,
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(_smallRing(), findsOneWidget);
}

void main() {
  setUp(() async {
    await mockPreferences();
  });

  testWidgets('pinned bar content clears the status-bar inset', (tester) async {
    await _pinBar(tester, inset: 24);
    final top = tester.getRect(_smallRing()).top;
    expect(top, greaterThanOrEqualTo(24));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinned bar geometry is unchanged without an inset', (
    tester,
  ) async {
    await _pinBar(tester, inset: 0);
    final top = tester.getRect(_smallRing()).top;
    // The compact ring centers in the bar's fixed content row:
    // (48 - 0.7 hairline - 28 ring) / 2 from the top of the screen.
    expect(top, moreOrLessEquals(9.65, epsilon: 0.2));
    expect(tester.takeException(), isNull);
  });
}
