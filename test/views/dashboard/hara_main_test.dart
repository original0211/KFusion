import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/config_hub/singbox_action.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/outbound_ip.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/providers/routed_probe.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/dashboard/hara_dashboard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/preferences.dart';
import '../../helpers/test_app.dart';
import '../../helpers/test_profiles.dart';

const _profile = Profile(
  id: 1,
  label: 'Test',
  type: ProfileType.url,
  url: 'https://example.com/sub',
  selectedMap: {'GLOBAL': 'Home', 'Home': 'JP-03'},
  autoUpdateDuration: Duration.zero,
);

const _groups = [
  Group(
    name: 'GLOBAL',
    type: GroupType.Selector,
    all: [
      Proxy(name: 'Home', type: 'Selector'),
      Proxy(name: 'JP-03', type: 'Shadowsocks'),
    ],
  ),
  Group(
    name: 'Home',
    type: GroupType.Selector,
    all: [
      Proxy(name: 'JP-03', type: 'Shadowsocks'),
      Proxy(name: 'HK-01', type: 'Shadowsocks'),
    ],
  ),
];

class _RecordingProxiesAction extends ProxiesAction {
  static final List<String> tested = [];

  @override
  Future<void> delayTestPageGroup(
    String groupName, {
    bool matchSearch = true,
  }) async {
    tested.add(groupName);
  }
}

class _RecordingSetupAction extends SetupAction {
  final requests = <bool>[];

  @override
  Future<bool> setRunning(bool running, {bool initialize = false}) {
    requests.add(running);
    ref.read(runTimeProvider.notifier).value = running ? 1 : null;
    return Future.value(true);
  }
}

class _RunningSingBoxAction extends SingBoxAction {
  @override
  Future<SingBoxStatus> build() async =>
      const SingBoxStatus(state: SingBoxState.running);
}

Widget _app({bool singBoxRunning = false}) {
  return TestApp(
    locale: const Locale('en'),
    overrides: [
      profilesProvider.overrideWith(() => TestProfiles(const [_profile])),
      currentProfileIdProvider.overrideWithBuild((_, _) => _profile.id),
      groupsProvider.overrideWithValue(_groups),
      currentGroupsStateProvider.overrideWithValue(
        const GroupsState(value: _groups),
      ),
      suspendProvider.overrideWithValue(false),
      proxiesActionProvider.overrideWith(_RecordingProxiesAction.new),
      setupActionProvider.overrideWith(_RecordingSetupAction.new),
      outboundIpProbeProvider.overrideWithBuild(
        (_, _) => const RoutedProbeState({}),
      ),
      if (singBoxRunning)
        singBoxActionProvider.overrideWith(_RunningSingBoxAction.new),
    ],
    child: const HaraDashboard(),
  );
}

Future<ProviderContainer> _pump(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(412, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(app);
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byType(HaraDashboard)));
}

void main() {
  setUp(() async {
    await mockPreferences();
  });

  testWidgets('connected marks the exit leaf with a label, not a dot', (
    tester,
  ) async {
    final container = await _pump(tester, _app());
    await tester.tap(find.byType(DiscRingMotif).first);
    await tester.pump();
    await tester.pump();

    // The status row owns the screen's single vermilion dot.
    expect(find.byType(HaraDot), findsOneWidget);
    expect(find.text('Current exit'), findsOneWidget);
    final exitRow = find.ancestor(
      of: find.text('Current exit'),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: exitRow, matching: find.text('JP-03')),
      findsOneWidget,
    );
    // The group row on the path still names its real selected leaf.
    expect(find.text('→ JP-03'), findsOneWidget);
    expect(container.read(selectedMapProvider)['Home'], 'JP-03');
    expect(tester.takeException(), isNull);
  });

  testWidgets('disconnected falls back to the dot on the exit leaf row', (
    tester,
  ) async {
    await _pump(tester, _app());

    expect(find.byType(HaraDot), findsOneWidget);
    final dotRow = find.ancestor(
      of: find.byType(HaraDot),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: dotRow, matching: find.text('JP-03')),
      findsOneWidget,
    );
    expect(find.text('Current exit'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the node list head test-all entry delay-tests every group', (
    tester,
  ) async {
    _RecordingProxiesAction.tested.clear();
    await _pump(tester, _app());
    expect(find.text('Test all delays'), findsOneWidget);
    await tester.tap(find.text('Test all delays'));
    await tester.pump();
    expect(_RecordingProxiesAction.tested, ['GLOBAL', 'Home']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a node row writes the selection through the group', (
    tester,
  ) async {
    final container = await _pump(tester, _app());
    await tester.tap(find.text('HK-01'));
    await tester.pump();
    expect(container.read(selectedMapProvider)['Home'], 'HK-01');
    // Flush the debounced core sync chain the selection action schedules.
    await tester.pump(const Duration(seconds: 15));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a running sing-box is presented and the ring stays inert', (
    tester,
  ) async {
    final container = await _pump(tester, _app(singBoxRunning: true));

    expect(find.text('Connected'), findsWidgets);
    expect(find.text('sing-box'), findsOneWidget);
    expect(find.text('mihomo not running'), findsOneWidget);
    expect(find.byType(HaraDot), findsOneWidget);

    await tester.tap(find.byType(DiscRingMotif).first);
    await tester.pump();
    final action =
        container.read(setupActionProvider.notifier) as _RecordingSetupAction;
    expect(action.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
