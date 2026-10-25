import 'package:kfusion/features/form/form.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('a form row shows its subtitle under the title', (tester) async {
    await tester.pumpWidget(
      const TestApp(
        child: Scaffold(
          body: FormRow(
            title: 'Name',
            subtitle: 'Shown under the title',
            trailing: FormRowTextField(initialValue: 'value'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Shown under the title'), findsOneWidget);
  });
}
