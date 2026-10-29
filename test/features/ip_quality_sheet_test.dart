import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/common/common.dart';
import 'package:kfusion/common/ip_quality.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/ip_quality/ip_quality_sheet.dart';
import 'package:kfusion/features/ip_quality/ip_quality_text.dart';
import 'package:kfusion/features/ip_quality/labels.dart';
import 'package:kfusion/l10n/l10n.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/config.dart';
import 'package:kfusion/providers/ip_quality.dart';
import 'package:kfusion/ui/icons/icons.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/glyph_finders.dart';
import '../helpers/test_app.dart';

const _ip = '203.0.113.9';

const _quality = IpQuality(
  ip: _ip,
  source: IpQualitySource.ipApiCom,
  type: IpType.residential,
  organization: 'Example ISP',
  asn: 64500,
  isVpn: true,
  isProxy: true,
);

class _QualityStub {
  _QualityStub(this.answer);

  final Future<IpQuality> Function(String ip) answer;
  final calls = <String>[];

  Future<IpQuality> call(Ref ref, String ip) {
    calls.add(ip);
    return answer(ip);
  }
}

Widget _host(_QualityStub stub) {
  return TestApp(
    locale: const Locale('en'),
    overrides: [ipQualityProvider.overrideWith(stub.call)],
    child: Builder(
      builder: (context) => TextButton(
        onPressed: () => showIpQualitySheet(context, ip: _ip),
        child: const Text('open'),
      ),
    ),
  );
}

Future<AppLocalizations> _openSheet(
  WidgetTester tester,
  _QualityStub stub,
) async {
  await tester.pumpWidget(_host(stub));
  await tester.pump();
  final context = tester.element(find.text('open'));
  final localizations = context.appLocalizations;
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return localizations;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('labels read every enum value from the localizations', (
    tester,
  ) async {
    late BuildContext captured;
    await tester.pumpWidget(
      TestApp(
        locale: const Locale('en'),
        child: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    final localizations = captured.appLocalizations;
    expect(IpType.values.map((type) => type.label(captured)).toList(), [
      localizations.ipTypeResidential,
      localizations.ipTypeMobile,
      localizations.ipTypeBusiness,
      localizations.ipTypeHosting,
    ]);
    expect(
      IpQualityLevel.values.map((level) => level.label(captured)).toList(),
      [
        localizations.ipQualityGood,
        localizations.ipQualityNormal,
        localizations.ipQualityRisky,
      ],
    );
    final scheme = captured.colorScheme;
    expect(IpQualityLevel.good.color(captured), scheme.success);
    expect(IpQualityLevel.normal.color(captured), null);
    expect(IpQualityLevel.risky.color(captured), scheme.error);
    expect(
      IpQualitySourceStatus.values
          .map((status) => status.label(captured))
          .toList(),
      [
        localizations.ipSourceNoType,
        localizations.timeout,
        localizations.ipSourceRateLimited,
        localizations.serviceFailed,
        localizations.ipSourceIpMismatch,
      ],
    );
  });

  testWidgets('the sheet lists the loaded quality, flags and network rows', (
    tester,
  ) async {
    final stub = _QualityStub((_) async => _quality);
    final localizations = await _openSheet(tester, stub);

    expect(find.text(localizations.outboundIp), findsOneWidget);
    expect(find.text(localizations.ipAddress), findsOneWidget);
    expect(find.text(_ip), findsWidgets);
    expect(find.text(localizations.ipQualityLevel), findsOneWidget);
    expect(find.text(localizations.ipQualityGood), findsOneWidget);
    expect(find.text(localizations.ipType), findsOneWidget);
    expect(find.text(localizations.ipTypeResidential), findsOneWidget);
    expect(find.text(localizations.ipFlagVpn), findsOneWidget);
    expect(find.text(localizations.ipFlagProxy), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Example ISP'), 120);
    expect(find.text('Example ISP'), findsOneWidget);
    expect(find.text('AS64500'), findsOneWidget);
    expect(find.text('ip-api.com'), findsOneWidget);
    await tester.scrollUntilVisible(find.text(localizations.hideIp), 120);
    expect(find.text(localizations.hideIp), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);

    await tester.tap(find.byGlyph(AppGlyphs.refresh));
    await tester.pumpAndSettle();
    expect(stub.calls, [_ip, _ip]);
  });

  testWidgets('the sheet lays out skeletons while the lookup runs', (
    tester,
  ) async {
    final stub = _QualityStub((_) => Completer<IpQuality>().future);
    await tester.pumpWidget(_host(stub));
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(SkeletonText), findsWidgets);
    expect(find.text(_ip), findsWidgets);
  });

  testWidgets('the sheet names the failed sources when the lookup fails', (
    tester,
  ) async {
    final stub = _QualityStub(
      (_) async => throw const IpQualityLookupException([
        (
          source: IpQualitySource.identMe,
          status: IpQualitySourceStatus.timeout,
        ),
        (
          source: IpQualitySource.ipQuery,
          status: IpQualitySourceStatus.rateLimited,
        ),
      ]),
    );
    final localizations = await _openSheet(tester, stub);

    expect(find.text(localizations.ipQualityFailed), findsOneWidget);
    expect(find.text(localizations.network), findsNothing);
    expect(find.text(localizations.ipQualitySources), findsOneWidget);
    expect(find.text('ident.me'), findsOneWidget);
    expect(find.text(localizations.timeout), findsOneWidget);
    expect(find.text('ipquery.io'), findsOneWidget);
    expect(find.text(localizations.ipSourceRateLimited), findsOneWidget);
  });

  testWidgets('the ip text masks the address while hide ip is on', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [ipQualityProvider.overrideWith((_, _) async => _quality)],
    );
    addTearDown(container.dispose);
    container
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(hideIp: true));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(
          locale: Locale('en'),
          child: IpQualityText(ip: _ip),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('*****'), findsOneWidget);
    expect(find.text(_ip), findsNothing);
    // Flush the debounced sync the settings write schedules.
    await tester.pump(const Duration(seconds: 15));
  });

  testWidgets('the ip text takes the level colour of a risky address', (
    tester,
  ) async {
    const risky = IpQuality(
      ip: _ip,
      source: IpQualitySource.proxyCheck,
      type: IpType.hosting,
      isTor: true,
    );
    await tester.pumpWidget(
      TestApp(
        locale: const Locale('en'),
        overrides: [ipQualityProvider.overrideWith((_, _) async => risky)],
        child: const IpQualityText(ip: _ip),
      ),
    );
    await tester.pump();
    final text = tester.widget<Text>(find.text(_ip));
    final context = tester.element(find.text(_ip));
    expect(text.style?.color, context.colorScheme.error);
  });
}
