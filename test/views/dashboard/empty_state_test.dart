import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/models/models.dart';
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
  // Pumps the phone home at a fixed size over a fresh preference store,
  // the state a new install is in.
  Future<void> pumpHome(
    WidgetTester tester, {
    List<Profile> profiles = const [],
  }) async {
    await mockPreferences();
    final container = ProviderContainer(
      overrides: [profilesProvider.overrideWith(() => TestProfiles(profiles))],
    );
    addTearDown(container.dispose);
    globalState.container = container;
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
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('the home shows the full saved list, plus the import card '
      'while there is no profile', (tester) async {
    await pumpHome(tester);

    expect(find.byType(CabinCoreCard), findsOneWidget);
    expect(find.byType(NetworkSpeedCard), findsOneWidget);
    expect(find.byType(ProfilesCard), findsOneWidget);
    expect(find.byType(OutboundModeCard), findsOneWidget);
    expect(find.byType(VpnCard), findsOneWidget);
    expect(find.byType(ServiceStatusCard), findsOneWidget);
    expect(find.text('万能导入'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await drain(tester);
  });

  testWidgets('the import card goes away once a profile exists', (
    tester,
  ) async {
    await pumpHome(
      tester,
      profiles: const [Profile(id: 1, autoUpdateDuration: Duration.zero)],
    );

    expect(find.byType(CabinCoreCard), findsOneWidget);
    expect(find.text('万能导入'), findsNothing);
    expect(tester.takeException(), isNull);

    await drain(tester);
  });

  testWidgets('the edit button opens the editor over the full saved list', (
    tester,
  ) async {
    await pumpHome(tester);

    expect(find.byTooltip('Edit dashboard'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit dashboard'));
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(DashboardEditor), findsOneWidget);
    expect(find.byType(OutboundModeCard), findsOneWidget);
    expect(tester.takeException(), isNull);

    await drain(tester);
  });
}
