import 'package:kfusion/enum/enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('every rule action carries its own description', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      TestApp(
        child: Builder(
          builder: (captured) {
            context = captured;
            return const SizedBox();
          },
        ),
      ),
    );

    final descriptions = [
      for (final action in RuleAction.values) action.getDesc(context),
    ];

    expect(descriptions, everyElement(isNotEmpty));
    expect(descriptions.toSet(), hasLength(RuleAction.values.length));
  });

  testWidgets('every rule payload error names its problem', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      TestApp(
        child: Builder(
          builder: (captured) {
            context = captured;
            return const SizedBox();
          },
        ),
      ),
    );

    final messages = [
      for (final error in RulePayloadError.values) error.getMessage(context),
    ];

    expect(messages, everyElement(isNotEmpty));
    expect(messages.toSet(), hasLength(RulePayloadError.values.length));
  });

  test('only the actions taking a payload say they have params', () {
    expect(RuleAction.GEOIP.hasParams, isTrue);
    expect(RuleAction.RULE_SET.hasParams, isTrue);
    expect(RuleAction.DOMAIN.hasParams, isFalse);
    expect(RuleAction.MATCH.hasParams, isFalse);

    expect(RuleAction.AND.nestsRules, isTrue);
    expect(RuleAction.SUB_RULE.nestsRules, isTrue);
    expect(RuleAction.DOMAIN.nestsRules, isFalse);

    expect(RuleAction.DOMAIN_REGEX.hasCommaPayload, isTrue);
    expect(RuleAction.NOT.hasCommaPayload, isTrue);
    expect(RuleAction.DOMAIN.hasCommaPayload, isFalse);
  });

  test('a relay group stays parseable but is never selectable', () {
    expect(GroupType.selectableValues, isNot(contains(GroupType.Relay)));
    expect(GroupType.selectableValues, hasLength(GroupType.values.length - 1));
  });

  test('geo resources parse from their file names', () {
    expect(GeoResource.fromJson('mmdb'), GeoResource.MMDB);
    expect(GeoResource.fromJson('asn'), GeoResource.ASN);
    expect(GeoResource.fromJson('geo-ip'), GeoResource.GEOIP);
    expect(GeoResource.fromJson('geoip'), GeoResource.GEOIP);
    expect(GeoResource.fromJson('geo-site'), GeoResource.GEOSITE);
    expect(GeoResource.fromJson('geosite'), GeoResource.GEOSITE);
    expect(() => GeoResource.fromJson('other'), throwsArgumentError);
  });
}
