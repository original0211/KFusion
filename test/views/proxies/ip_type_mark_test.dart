import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/node_ip.dart';
import 'package:kfusion/providers/routed_probe.dart';
import 'package:kfusion/views/proxies/ip_type_mark.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';

class _FakeSweeper extends NodeIpSweeper {
  _FakeSweeper(this.readings, this.watched);

  final Map<String, NodeIpReading> readings;
  final List<String> watched;

  @override
  Map<String, NodeIpReading> build() => readings;

  @override
  void watch(String name) => watched.add(name);

  @override
  void unwatch(String name) => watched.remove(name);
}

Widget _slot(_FakeSweeper sweeper, {String type = 'Shadowsocks'}) {
  return TestApp(
    locale: const Locale('en'),
    overrides: [nodeIpSweeperProvider.overrideWith(() => sweeper)],
    child: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: NodeIpTypeSlot(
          proxy: Proxy(name: 'HK-01', type: type),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a probed hosting type shows the data-center mark', (
    tester,
  ) async {
    final watched = <String>[];
    await tester.pumpWidget(
      _slot(
        _FakeSweeper({
          'HK-01': const NodeIpReading(
            phase: ProbePhase.fresh,
            ip: '2.2.2.2',
            type: IpType.hosting,
          ),
        }, watched),
      ),
    );
    await tester.pump();
    expect(find.text('Data center'), findsOneWidget);
    expect(watched, ['HK-01']);
  });

  testWidgets('business folds into the data-center mark on rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      _slot(
        _FakeSweeper({
          'HK-01': const NodeIpReading(
            phase: ProbePhase.fresh,
            ip: '2.2.2.2',
            type: IpType.business,
          ),
        }, []),
      ),
    );
    await tester.pump();
    expect(find.text('Data center'), findsOneWidget);
    expect(find.text('Business'), findsNothing);
  });

  testWidgets('an unknown type renders nothing at all', (tester) async {
    await tester.pumpWidget(_slot(_FakeSweeper({}, [])));
    await tester.pump();
    expect(find.text('Data center'), findsNothing);
    expect(find.text('Residential'), findsNothing);
    expect(find.text('Probing'), findsNothing);
  });

  testWidgets('a probing node shows the weak placeholder', (tester) async {
    await tester.pumpWidget(
      _slot(
        _FakeSweeper({
          'HK-01': const NodeIpReading(phase: ProbePhase.probing),
        }, []),
      ),
    );
    await tester.pump();
    expect(find.text('Probing'), findsOneWidget);
  });
}
