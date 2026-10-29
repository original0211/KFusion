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

    test('the retired and gated pages are no longer navigation items', () {
      // Requests / connections / DNS retired with the screen plan; logs
      // and resources moved behind the settings page's advanced gate.
      expect(items, hasLength(3));
      for (final label in [
        PageLabel.requests,
        PageLabel.connections,
        PageLabel.dns,
        PageLabel.resources,
        PageLabel.logs,
      ]) {
        expect(
          items.where((item) => item.label == label),
          isEmpty,
          reason: '$label must not be a navigation item',
        );
      }
    });
  });
}
