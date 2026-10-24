import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/common/preferences.dart';
import 'package:kfusion/features/config_hub/core_kind.dart';

import '../../helpers/preferences.dart';

void main() {
  test('core kind store defaults to mihomo and roundtrips', () async {
    await mockPreferences();
    final preferences = Preferences();
    expect(await preferences.getCoreKindMap(), isEmpty);
    expect(await preferences.getActiveCoreKind(), 'mihomo');
    await preferences.setCoreKindMap({7: 'singbox', 9: 'mihomo'});
    final kinds = await preferences.getCoreKindMap();
    expect(kinds[7], 'singbox');
    expect(kinds[9], 'mihomo');
    await preferences.setActiveCoreKind('singbox');
    expect(await preferences.getActiveCoreKind(), 'singbox');
    expect(CoreKind.fromValue('singbox'), CoreKind.singbox);
    expect(CoreKind.singbox.value, 'singbox');
    expect(CoreKind.mihomo.value, 'mihomo');
  });

  test('sing-box tun defaults to off', () async {
    await mockPreferences();
    expect(await Preferences().getSingBoxTunEnabled(), isFalse);
    await Preferences().setSingBoxTunEnabled(true);
    expect(await Preferences().getSingBoxTunEnabled(), isTrue);
  });
}
