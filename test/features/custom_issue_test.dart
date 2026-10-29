import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/form/custom_issue.dart';
import 'package:kfusion/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

const _issues = <CustomIssue>[
  CustomIssue.emptyName(),
  CustomIssue.reservedName('DIRECT'),
  CustomIssue.duplicateName('Home'),
  CustomIssue.coreRejected('bad line'),
  CustomIssue.missingProxies(['Gone', 'Lost']),
  CustomIssue.missingProviders(['Gone']),
  CustomIssue.noProxySource(),
  CustomIssue.groupLoop(['A', 'B']),
  CustomIssue.invalidEmptyFallback('Group'),
  CustomIssue.invalidFilter('F', 'unclosed'),
  CustomIssue.invalidPayload(RulePayloadError.numberRange),
  CustomIssue.missingRuleSet('Set'),
  CustomIssue.missingSubRule('Sub'),
  CustomIssue.missingTarget('Nowhere'),
  CustomIssue.missingDialer('Node'),
  CustomIssue.dialerLoop('Home', 'Relay'),
];

Future<BuildContext> _context(WidgetTester tester) async {
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
  return context;
}

void main() {
  testWidgets('every issue kind reads as a message naming its subject', (
    tester,
  ) async {
    final context = await _context(tester);

    final messages = [for (final issue in _issues) issue.getMessage(context)];

    expect(messages, everyElement(isNotEmpty));
    expect(messages[1], contains('DIRECT'));
    expect(messages[3], contains('bad line'));
    expect(messages[4], contains('Gone, Lost'));
    expect(messages[7], contains('A › B'));
    expect(messages[9], contains('F'));
    expect(messages[9], contains('unclosed'));
    expect(messages[15], contains('Home'));
    expect(messages[15], contains('Relay'));
  });

  testWidgets('only the not-yet-filled-in issues count as incomplete', (
    tester,
  ) async {
    await _context(tester);

    expect(const CustomIssue.emptyName().isIncomplete, isTrue);
    expect(const CustomIssue.noProxySource().isIncomplete, isTrue);
    expect(const CustomIssue.coreRejected('x').isIncomplete, isTrue);
    expect(const CustomIssue.duplicateName('Home').isIncomplete, isFalse);
    expect(const CustomIssue.missingTarget('X').isIncomplete, isFalse);
  });

  testWidgets('a list of issues reads as one message per issue', (
    tester,
  ) async {
    final context = await _context(tester);
    const single = CustomIssue.missingTarget('Nowhere');
    const other = CustomIssue.missingDialer('Node');

    expect([single].getMessage(context), single.getMessage(context));
    expect(
      [single, other].getMessage(context),
      '• ${single.getMessage(context)}\n• ${other.getMessage(context)}',
    );
  });

  testWidgets('the banner shows the issues and hides when there are none', (
    tester,
  ) async {
    await tester.pumpWidget(
      const TestApp(
        child: CustomIssuesBanner(
          issues: [CustomIssue.missingTarget('Nowhere')],
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Nowhere'), findsOneWidget);

    await tester.pumpWidget(
      const TestApp(child: CustomIssuesBanner(issues: [])),
    );
    await tester.pump();
    expect(find.textContaining('Nowhere'), findsNothing);
  });
}
