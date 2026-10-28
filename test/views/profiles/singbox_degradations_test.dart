import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/config_hub/config_hub.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/views/profiles/hara_profiles.dart';
import 'package:kfusion/views/profiles/singbox_degradations.dart';

import '../../helpers/test_app.dart';
import '../../helpers/test_profiles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const alpha = Profile(
    id: 1,
    label: 'Alpha',
    type: ProfileType.file,
    autoUpdateDuration: Duration.zero,
  );
  const beta = Profile(
    id: 2,
    label: 'Beta',
    type: ProfileType.file,
    autoUpdateDuration: Duration.zero,
  );

  const ledger = [
    SingBoxDegradation(
      kind: SingBoxDegradationKind.nodeProtocol,
      name: 'OVPN-1',
      reason: '协议 openvpn 不在 sing-box 渲染契约内',
      message: 'OVPN-1：协议 openvpn 不在 sing-box 渲染契约内',
    ),
    SingBoxDegradation(
      kind: SingBoxDegradationKind.groupType,
      name: 'FallbackG',
      reason: '组类型 fallback 未承接（契约只保留 select / url-test）',
      message: 'FallbackG：组类型 fallback 未承接',
    ),
    SingBoxDegradation(
      kind: SingBoxDegradationKind.routing,
      name: '订阅分流规则',
      reason: '共 3 条订阅规则未移植，由内置模板替代',
      message: '订阅分流规则：共 3 条订阅规则未移植，由内置模板替代',
    ),
    SingBoxDegradation(
      kind: SingBoxDegradationKind.nodeUnusable,
      name: 'WG-1',
      reason: 'wireguard 节点缺少本地地址（ip/ipv6）',
      message: 'WG-1：wireguard 节点缺少本地地址（ip/ipv6）',
    ),
  ];

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles(const [alpha, beta])),
        currentProfileIdProvider.overrideWithBuild((_, _) => 1),
        profileDegradationsProvider.overrideWith(
          (ref, id) async => id == 1 ? ledger : const <SingBoxDegradation>[],
        ),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(412, 800));
    return container;
  }

  Future<void> pumpPage(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = makeContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(child: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the row entry shows the count only where degradations exist', (
    tester,
  ) async {
    await pumpPage(tester, const HaraProfilesView());
    expect(find.text('4 sing-box degradations'), findsOneWidget);
    expect(find.text('0 sing-box degradations'), findsNothing);
  });

  testWidgets('tapping the entry opens the named, grouped list', (
    tester,
  ) async {
    await pumpPage(tester, const HaraProfilesView());
    await tester.tap(find.text('4 sing-box degradations'));
    await tester.pumpAndSettle();
    expect(find.byType(SingBoxDegradationsView), findsOneWidget);
    expect(find.text('Node protocols'), findsOneWidget);
    expect(find.text('OVPN-1'), findsOneWidget);
    expect(
      find.text('Protocol openvpn is not supported by sing-box'),
      findsOneWidget,
    );
    expect(find.text('Group types'), findsOneWidget);
    expect(find.text('FallbackG'), findsOneWidget);
    expect(find.text('Routing'), findsOneWidget);
    expect(
      find.text(
        '3 subscription rules were not carried over; '
        'the built-in template applies',
      ),
      findsOneWidget,
    );
    expect(find.text('Other'), findsOneWidget);
    expect(find.text('WG-1'), findsOneWidget);
    expect(
      find.text(
        'Missing a field sing-box requires (the WireGuard local address)',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a profile without degradations reads as fully carried', (
    tester,
  ) async {
    await pumpPage(tester, const SingBoxDegradationsView(profile: beta));
    expect(find.text('Everything is carried over to sing-box'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('the import summary names the count and can open the list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<bool?>? summary;
    await tester.pumpWidget(
      TestApp(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              summary = showSingBoxImportSummary(context, 4);
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Imported, with sing-box degradations'), findsOneWidget);
    expect(
      find.textContaining('4 items in this profile are degraded'),
      findsOneWidget,
    );
    await tester.tap(find.text('View list'));
    await tester.pumpAndSettle();
    expect(await summary, isTrue);
  });
}
