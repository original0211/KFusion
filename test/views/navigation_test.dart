import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/views/navigation.dart';

void main() {
  group('primary navigation shell', () {
    final items = Navigation().getItems(openLogs: true);

    List<PageLabel> labelsFor(NavigationItemMode mode) {
      return [
        for (final item in items)
          if (item.modes.contains(mode)) item.label,
      ];
    }

    test('mobile and desktop both carry exactly the three entries', () {
      const expected = [
        PageLabel.dashboard,
        PageLabel.profiles,
        PageLabel.tools,
      ];
      expect(labelsFor(NavigationItemMode.mobile), expected);
      expect(labelsFor(NavigationItemMode.desktop), expected);
    });

    test('the proxies page is no longer an entry of its own', () {
      expect(items.where((item) => item.label == PageLabel.proxies), isEmpty);
    });

    test('the more class keeps its tools-page reachability only', () {
      final byLabel = {for (final item in items) item.label: item};
      expect(byLabel[PageLabel.requests]!.modes, [NavigationItemMode.moreFull]);
      expect(byLabel[PageLabel.connections]!.modes, [
        NavigationItemMode.moreFull,
      ]);
      expect(byLabel[PageLabel.dns]!.modes, [NavigationItemMode.moreFull]);
      expect(byLabel[PageLabel.resources]!.modes, [NavigationItemMode.more]);
      expect(byLabel[PageLabel.logs]!.modes, [NavigationItemMode.more]);
    });
  });
}
