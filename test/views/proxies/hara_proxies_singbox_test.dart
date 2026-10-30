import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/core/controller.dart';
import 'package:kfusion/core/interface.dart';
import 'package:kfusion/core/singbox/singbox_runner.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/config_hub/singbox_action.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/proxies/hara_proxies.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/test_app.dart';
import '../../helpers/test_profiles.dart';

class _MockCoreHandlerInterface extends Mock implements CoreHandlerInterface {}

class _RecordingSingBoxApi extends SingBoxClashApi {
  _RecordingSingBoxApi() : super(port: 0, secret: '');

  final puts = <({String groupName, String proxyName})>[];

  @override
  Future<void> changeProxy(String groupName, String proxyName) async {
    puts.add((groupName: groupName, proxyName: proxyName));
  }

  @override
  Future<void> closeConnections() async {}
}

class _BearerSingBoxAction extends SingBoxAction {
  _BearerSingBoxAction(this._api);

  final SingBoxClashApi _api;

  @override
  Future<SingBoxStatus> build() async =>
      const SingBoxStatus(state: SingBoxState.running);

  @override
  SingBoxClashApi? get api => _api;
}

class _IdleSingBoxAction extends SingBoxAction {
  @override
  Future<SingBoxStatus> build() async =>
      const SingBoxStatus(state: SingBoxState.idle);

  @override
  SingBoxClashApi? get api => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(
      const ChangeProxyParams(groupName: '', proxyName: ''),
    );
  });

  const parent = '⚡ CF前置';
  const child = '⚡ CF前置 · auto';

  const dualProfile = Profile(
    id: 1,
    label: 'Test',
    type: ProfileType.url,
    url: 'https://example.com/sub',
    selectedMap: {parent: 'CF-02'},
    autoUpdateDuration: Duration.zero,
  );
  const dualGroups = [
    Group(
      name: parent,
      type: GroupType.URLTest,
      now: 'CF-01',
      all: [
        Proxy(name: 'CF-01', type: 'Http'),
        Proxy(name: 'CF-02', type: 'Shadowsocks'),
      ],
    ),
  ];
  const dualPanel = <String, SingBoxPanelGroup>{
    parent: (type: 'Selector', now: 'CF-02', all: [child, 'CF-01', 'CF-02']),
    child: (type: 'URLTest', now: 'CF-01', all: ['CF-01', 'CF-02']),
  };

  const outer = '🚀 节点选择';
  const outerProfile = Profile(
    id: 1,
    label: 'Test',
    type: ProfileType.url,
    url: 'https://example.com/sub',
    selectedMap: {},
    autoUpdateDuration: Duration.zero,
  );
  const outerGroups = [
    Group(
      name: outer,
      type: GroupType.Selector,
      now: parent,
      all: [
        Proxy(name: parent, type: 'URLTest'),
        Proxy(name: 'DIRECT', type: 'Direct'),
        Proxy(name: 'CF-01', type: 'Http'),
      ],
    ),
  ];
  const outerPanel = <String, SingBoxPanelGroup>{
    outer: (type: 'Selector', now: parent, all: [parent, 'direct', 'CF-01']),
    parent: (type: 'Selector', now: 'CF-02', all: [child, 'CF-01', 'CF-02']),
    child: (type: 'URLTest', now: 'CF-01', all: ['CF-01', 'CF-02']),
  };

  const nativeProfile = Profile(
    id: 1,
    label: 'Test',
    type: ProfileType.url,
    url: 'https://example.com/sub',
    selectedMap: {},
    autoUpdateDuration: Duration.zero,
  );
  const nativeGroups = [
    Group(
      name: 'Native',
      type: GroupType.URLTest,
      now: 'N2',
      all: [
        Proxy(name: 'N1', type: 'Shadowsocks'),
        Proxy(name: 'N2', type: 'Shadowsocks'),
      ],
    ),
  ];
  const nativePanel = <String, SingBoxPanelGroup>{
    'Native': (type: 'URLTest', now: 'N2', all: ['N1', 'N2']),
  };

  Future<ProviderContainer> pumpSection(
    WidgetTester tester, {
    required Profile profile,
    required List<Group> groups,
    required Map<String, SingBoxPanelGroup> panel,
    required String? exitName,
    AsyncValue<Map<String, SingBoxPanelGroup>>? panelAsync,
    SingBoxClashApi? api,
    bool bearer = true,
  }) async {
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final core = _MockCoreHandlerInterface();
    when(() => core.changeProxy(any()))
        .thenAnswer((_) async => const ChangeProxyResult(changed: true));
    when(() => core.getProxies())
        .thenAnswer((_) async => const ProxiesData(proxies: {}, all: []));
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        groupsProvider.overrideWithValue(groups),
        currentGroupsStateProvider.overrideWithValue(
          GroupsState(value: groups),
        ),
        singBoxPanelGroupsProvider.overrideWithValue(
          panelAsync ?? AsyncData(panel),
        ),
        singBoxActionProvider.overrideWith(
          () => bearer
              ? _BearerSingBoxAction(api ?? _RecordingSingBoxApi())
              : _IdleSingBoxAction(),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
    });
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(412, 800));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          locale: const Locale('en'),
          child: Builder(
            builder: (context) => Material(
              color: context.haraPalette.bg,
              child: CustomScrollView(
                slivers: [
                  HaraProxyGroupSection(
                    group: groups.single,
                    exitName: exitName,
                    first: true,
                    exitMarker: HaraExitMarker.dot,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Finder dotRow() {
    return find.ancestor(of: find.byType(HaraDot), matching: find.byType(Row));
  }

  testWidgets(
    'a dual-layer group leads with a tappable auto row for the child',
    (tester) async {
      final container = await pumpSection(
        tester,
        profile: dualProfile,
        groups: dualGroups,
        panel: dualPanel,
        exitName: 'CF-01',
      );
      expect(find.text('Auto'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Auto')).dy,
        lessThan(tester.getTopLeft(find.text('CF-01')).dy),
      );
      // The pinned leaf holds the selection, so the exit dot starts on
      // the panel child's current leaf row.
      expect(find.byType(HaraDot), findsOneWidget);
      expect(
        find.descendant(of: dotRow(), matching: find.text('CF-01')),
        findsOneWidget,
      );

      await tester.tap(find.text('Auto'));
      await tester.pump();
      expect(container.read(selectedMapProvider)[parent], child);
      // The dot moves to the auto row, and nowhere else.
      expect(find.byType(HaraDot), findsOneWidget);
      expect(
        find.descendant(of: dotRow(), matching: find.text('Auto')),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 15));

      // Member rows keep their legacy behaviour.
      await tester.tap(find.text('CF-02'));
      await tester.pump();
      expect(container.read(selectedMapProvider)[parent], 'CF-02');
      await tester.pump(const Duration(seconds: 15));
    },
  );

  testWidgets('a nested selector group lists member groups as tappable rows', (
    tester,
  ) async {
    final container = await pumpSection(
      tester,
      profile: outerProfile,
      groups: outerGroups,
      panel: outerPanel,
      exitName: 'CF-01',
    );
    // No synthetic auto row: the outer selector has no URLTest member.
    expect(find.text('Auto'), findsNothing);
    expect(find.text(parent), findsOneWidget);
    expect(find.text('DIRECT'), findsOneWidget);

    await tester.tap(find.text(parent));
    await tester.pump();
    expect(container.read(selectedMapProvider)[outer], parent);
    await tester.pump(const Duration(seconds: 15));

    await tester.tap(find.text('DIRECT'));
    await tester.pump();
    expect(container.read(selectedMapProvider)[outer], 'DIRECT');
    await tester.pump(const Duration(seconds: 15));
  });

  testWidgets('a native URLTest group is labelled auto and locked', (
    tester,
  ) async {
    final container = await pumpSection(
      tester,
      profile: nativeProfile,
      groups: nativeGroups,
      panel: nativePanel,
      exitName: 'N2',
    );
    // The header carries the auto label; no synthetic row appears.
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('N1'), findsOneWidget);
    expect(find.text('N2'), findsOneWidget);
    // The panel's current member shows as the exit.
    expect(find.byType(HaraDot), findsOneWidget);
    expect(
      find.descendant(of: dotRow(), matching: find.text('N2')),
      findsOneWidget,
    );

    await tester.tap(find.text('N1'));
    await tester.pump();
    expect(container.read(selectedMapProvider), isEmpty);
    await tester.tap(find.text('N2'));
    await tester.pump();
    expect(container.read(selectedMapProvider), isEmpty);
    await tester.pump(const Duration(seconds: 15));
  });

  const absentProfile = Profile(
    id: 1,
    label: 'Test',
    type: ProfileType.url,
    url: 'https://example.com/sub',
    selectedMap: {},
    autoUpdateDuration: Duration.zero,
  );
  const absentGroups = [
    Group(
      name: '🚀 节点选择',
      type: GroupType.Selector,
      now: 'DIRECT',
      all: [
        Proxy(name: '⚡ CF前置', type: 'URLTest'),
        Proxy(name: 'DIRECT', type: 'Direct'),
      ],
    ),
  ];
  const absentPanel = <String, SingBoxPanelGroup>{
    '⚡ CF前置': (type: 'Selector', now: 'CF-01', all: ['⚡ CF前置 · auto', 'CF-01']),
    '⚡ CF前置 · auto': (type: 'URLTest', now: 'CF-01', all: ['CF-01']),
  };

  testWidgets('a group missing from the panel table is named and inert', (
    tester,
  ) async {
    final api = _RecordingSingBoxApi();
    final container = await pumpSection(
      tester,
      profile: absentProfile,
      groups: absentGroups,
      panel: absentPanel,
      exitName: null,
      api: api,
    );
    expect(find.text('Unavailable under sing-box'), findsOneWidget);
    expect(find.byType(HaraDot), findsNothing);

    await tester.tap(find.text('⚡ CF前置'));
    await tester.pump();
    await tester.tap(find.text('DIRECT'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    expect(api.puts, isEmpty);
    expect(container.read(selectedMapProvider), isEmpty);
  });

  const globalGroups = [
    Group(
      name: 'GLOBAL',
      type: GroupType.Fallback,
      now: 'SG-01',
      all: [
        Proxy(name: 'IT-01', type: 'Http'),
        Proxy(name: 'SG-01', type: 'Http'),
      ],
    ),
  ];
  const globalPanel = <String, SingBoxPanelGroup>{
    'GLOBAL': (type: 'Fallback', now: 'IT-01', all: ['IT-01', 'SG-01']),
  };

  testWidgets('a Fallback panel entry reads as an exit indicator row', (
    tester,
  ) async {
    final api = _RecordingSingBoxApi();
    final container = await pumpSection(
      tester,
      profile: absentProfile,
      groups: globalGroups,
      panel: globalPanel,
      // The mihomo-side exit is stale under the bearer; the panel now wins.
      exitName: 'SG-01',
      api: api,
    );
    expect(find.text('→ IT-01'), findsOneWidget);
    expect(find.byType(HaraDot), findsOneWidget);
    expect(
      find.descendant(of: dotRow(), matching: find.text('IT-01')),
      findsOneWidget,
    );

    await tester.tap(find.text('IT-01'));
    await tester.pump();
    await tester.tap(find.text('SG-01'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    expect(api.puts, isEmpty);
    expect(container.read(selectedMapProvider), isEmpty);
  });

  testWidgets('a failed panel fetch keeps the legacy presentation', (
    tester,
  ) async {
    final api = _RecordingSingBoxApi();
    final container = await pumpSection(
      tester,
      profile: dualProfile,
      groups: dualGroups,
      panel: dualPanel,
      panelAsync: AsyncError<Map<String, SingBoxPanelGroup>>(
        StateError('panel down'),
        StackTrace.empty,
      ),
      exitName: 'CF-01',
      api: api,
    );
    // No table, no reconciliation: no synthetic auto row is derived.
    expect(find.text('Auto'), findsNothing);

    await tester.tap(find.text('CF-01'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    expect(api.puts, hasLength(1));
    expect(api.puts.single.groupName, parent);
    expect(api.puts.single.proxyName, 'CF-01');
    expect(container.read(selectedMapProvider)[parent], 'CF-01');
  });

  testWidgets('without a sing-box bearer the panel table is ignored', (
    tester,
  ) async {
    final container = await pumpSection(
      tester,
      profile: dualProfile,
      groups: dualGroups,
      panel: dualPanel,
      exitName: 'CF-01',
      bearer: false,
    );
    expect(find.text('Auto'), findsNothing);

    await tester.tap(find.text('CF-01'));
    await tester.pump();
    expect(container.read(selectedMapProvider)[parent], 'CF-01');
    await tester.pump(const Duration(seconds: 15));
  });
}
