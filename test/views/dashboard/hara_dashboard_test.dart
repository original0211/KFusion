import 'package:kfusion/common/service_probe.dart' show routedOutbound;
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/outbound_ip.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/providers/route_state.dart';
import 'package:kfusion/providers/routed_probe.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/dashboard/hara_dashboard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/preferences.dart';
import '../../helpers/test_app.dart';

const _ip = '203.0.113.9';
const _node = 'Tokyo 01';

const _profile = Profile(
  id: 1,
  label: 'Home',
  autoUpdateDuration: Duration.zero,
);

class _RecordingSetupAction extends SetupAction {
  final requests = <bool>[];

  @override
  Future<bool> setRunning(bool running, {bool initialize = false}) {
    requests.add(running);
    ref.read(runTimeProvider.notifier).value = running ? 1 : null;
    return Future.value(true);
  }
}

Override _probe(ProbeEntry<IpInfo> entry) {
  return outboundIpProbeProvider.overrideWithBuild(
    (_, _) => RoutedProbeState({routedOutbound: entry}),
  );
}

const _freshEntry = ProbeEntry<IpInfo>(
  phase: ProbePhase.fresh,
  value: IpInfo(ip: _ip, countryCode: 'GB'),
  stamp: RouteStamp(
    coreEpoch: 1,
    picksVersion: 1,
    hostEpoch: 1,
    proxied: true,
    chains: [_node],
  ),
);

Widget _app({
  ProbeEntry<IpInfo> entry = const ProbeEntry(phase: ProbePhase.empty),
  List<Profile> profiles = const [_profile],
}) {
  return TestApp(
    locale: const Locale('en'),
    overrides: [
      profilesProvider.overrideWithValue(profiles),
      currentProfileIdProvider.overrideWithBuild((_, _) => 1),
      suspendProvider.overrideWithValue(false),
      setupActionProvider.overrideWith(_RecordingSetupAction.new),
      _probe(entry),
    ],
    child: const HaraDashboard(),
  );
}

Finder _statusText(String text) => find.byWidgetPredicate(
  (widget) =>
      widget is Text && widget.data == text && widget.style?.fontSize == 15,
);

_RecordingSetupAction _actionOf(WidgetTester tester) =>
    ProviderScope.containerOf(
          tester.element(find.byType(HaraDashboard)),
        ).read(setupActionProvider.notifier)
        as _RecordingSetupAction;

Finder _ring() => find.byType(DiscRingMotif);

void main() {
  setUp(() async {
    await mockPreferences();
  });

  testWidgets('disconnected shows the fixed composition without a dot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.text('KFUSION'), findsOneWidget);
    final ring = tester.widget<DiscRingMotif>(_ring());
    expect(ring.size, HaraSpace.ringSize);
    expect(ring.strokeWidth, HaraSpace.ringStroke);
    expect(ring.color, HaraPalette.light.dim);
    expect(_statusText('Disconnected'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.byType(HaraDot), findsNothing);
    for (final key in [
      'Delay',
      'Exit',
      'Connected',
      'Download',
      'Upload',
      'Total traffic',
    ]) {
      expect(find.text(key), findsOneWidget, reason: key);
    }
    expect(find.text('—'), findsNWidgets(6));
    for (final mode in ['Rule', 'Global', 'Direct']) {
      expect(find.text(mode), findsOneWidget, reason: mode);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the ring toggles the core through the shared action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app());
    await tester.pump();

    await tester.tap(_ring());
    await tester.pump();
    expect(_actionOf(tester).requests, [true]);

    await tester.tap(_ring());
    await tester.pump();
    expect(_actionOf(tester).requests, [true, false]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('connected shows one vermilion dot and live figures', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(entry: _freshEntry));
    await tester.pump();

    await tester.tap(_ring());
    await tester.pump();
    await tester.pump();

    expect(_statusText('Connected'), findsOneWidget);
    expect(find.text(_node), findsOneWidget);
    expect(find.byType(HaraDot), findsOneWidget);
    final ring = tester.widget<DiscRingMotif>(_ring());
    expect(ring.color, HaraPalette.light.ink.withValues(alpha: 0.78));
    expect(find.text(_ip), findsOneWidget);
    expect(find.text('00:00:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed probe reads as an error in red text only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(entry: const ProbeEntry(phase: ProbePhase.failed)),
    );
    await tester.pump();

    await tester.tap(_ring());
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));

    final status = tester.widget<Text>(find.text('Connection failed'));
    final context = tester.element(find.text('Connection failed'));
    expect(status.style!.color, Theme.of(context).colorScheme.error);
    expect(find.text('Check failed'), findsOneWidget);
    expect(find.byType(HaraDot), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no profile swaps the list for the import entry', (tester) async {
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(profiles: const []));
    await tester.pump();

    expect(find.text('Add profile'), findsWidgets);
    expect(find.text('Delay'), findsNothing);
    expect(find.text('Rule'), findsNothing);
    expect(find.byType(HaraDot), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling pins the compact status row once connected', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(entry: _freshEntry));
    await tester.pump();
    await tester.tap(_ring());
    await tester.pump();
    await tester.pump();

    Finder smallRing() => find.byWidgetPredicate(
      (widget) =>
          widget is DiscRingMotif && widget.size == HaraSpace.ringCompact,
    );
    expect(smallRing(), findsNothing);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(smallRing(), findsOneWidget);
    expect(find.byType(HaraDot), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the mode row switches the outbound mode', (tester) async {
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWithValue(const [_profile]),
        suspendProvider.overrideWithValue(false),
        _probe(const ProbeEntry(phase: ProbePhase.empty)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(locale: Locale('en'), child: HaraDashboard()),
      ),
    );
    await tester.pump();
    expect(container.read(patchClashConfigProvider).mode, Mode.rule);

    await tester.tap(find.text('Global'));
    await tester.pump();
    expect(container.read(patchClashConfigProvider).mode, Mode.global);
    expect(tester.takeException(), isNull);
  });
}
