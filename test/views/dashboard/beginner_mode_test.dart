import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/views/dashboard/dashboard.dart';
import 'package:kfusion/views/dashboard/edit.dart';
import 'package:kfusion/views/dashboard/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/preferences.dart';
import '../../helpers/test_app.dart';
import '../../helpers/test_profiles.dart';

void main() {
  late ProviderContainer container;

  setUp(() async {
    // The state a new install is in: beginner mode defaults to on.
    await mockPreferences({'beginnerMode': true});
    container = ProviderContainer(
      overrides: [profilesProvider.overrideWith(TestProfiles.new)],
    );
    globalState.container = container;
  });

  tearDown(() => container.dispose());

  testWidgets('beginner mode still shows the dashboard edit button', (
    tester,
  ) async {
    const size = Size(412, 1400);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container.read(viewSizeProvider.notifier).value = size;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(
          child: DashboardView(platform: SupportPlatform.Android),
        ),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Edit dashboard'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit dashboard'));
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(DashboardEditor), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the beginner home shows only the first-run cards, plus the '
      'import card while there is no profile', (tester) async {
    const size = Size(412, 1400);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container.read(viewSizeProvider.notifier).value = size;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(
          child: DashboardView(platform: SupportPlatform.Android),
        ),
      ),
    );
    // The beginner preference is read async; let it land.
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(CurrentOutboundCard), findsOneWidget);
    expect(find.byType(NetworkSpeedCard), findsOneWidget);
    expect(find.byType(ProfilesCard), findsOneWidget);
    expect(find.text('万能导入'), findsOneWidget);
    expect(find.byType(OutboundModeCard), findsNothing);
    expect(find.byType(VpnCard), findsNothing);
    expect(find.byType(ServiceStatusCard), findsNothing);
    expect(tester.takeException(), isNull);

    // The editor still works on the whole saved list.
    await tester.tap(find.byTooltip('Edit dashboard'));
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(DashboardEditor), findsOneWidget);
    expect(find.byType(OutboundModeCard), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
