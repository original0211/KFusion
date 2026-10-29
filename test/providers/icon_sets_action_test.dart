import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:kfusion/database/database.dart' as db;
import 'package:kfusion/l10n/l10n.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/action.dart';
import 'package:kfusion/providers/database.dart';
import 'package:kfusion/state.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod/riverpod.dart';

String _iconSetJson(String name, List<String> icons) => json.encode({
  'name': name,
  'icons': [
    for (final icon in icons)
      {'name': '$icon.png', 'url': 'https://example.com/$icon.png'},
  ],
});

/// Real downloads over loopback: the test binding answers every request with a
/// 400, so its override is lifted while a test runs.
void main() {
  late HttpServer server;
  late String body;
  Completer<void>? held;
  late db.Database testDatabase;
  late ProviderContainer container;

  setUpAll(() async {
    await AppLocalizations.load(const Locale('en'));
    globalState.packageInfo = PackageInfo(
      appName: 'FlClash',
      packageName: 'com.follow.clash',
      version: '1.0.0',
      buildNumber: '1',
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await held?.future;
      final response = request.response;
      if (request.uri.path == '/missing') {
        response.statusCode = HttpStatus.notFound;
      } else {
        response.write(body);
      }
      await response.close();
    });
  });

  tearDownAll(() => server.close(force: true));

  setUp(() {
    final bindingOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = bindingOverrides);
    held = null;
    testDatabase = db.Database(NativeDatabase.memory());
    db.database = testDatabase;
    container = ProviderContainer();
    globalState.container = container;
    container.listen(iconSetsProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await testDatabase.close();
  });

  String urlOf(String path) => 'http://127.0.0.1:${server.port}/$path';

  IconSetsAction action() => container.read(iconSetsActionProvider.notifier);

  Future<List<IconSet>> stored() async {
    await pumpEventQueue();
    return testDatabase.iconSetsDao.query().get();
  }

  group('a set changed while it downloads', () {
    late IconSet saved;
    late Future<IconSet> syncing;

    setUp(() async {
      body = _iconSetJson('Qure', ['Proxy']);
      container
          .read(iconSetsProvider.notifier)
          .put(
            IconSet(
              id: 1,
              name: 'Qure',
              url: urlOf('qure.json'),
              icons: const [
                IconSetIcon(
                  name: 'Proxy.png',
                  url: 'https://example.com/Proxy.png',
                ),
              ],
            ),
          );
      saved = (await stored()).single;
      body = _iconSetJson('Qure', ['Proxy', 'Direct']);
      held = Completer();
      syncing = action().sync(saved);
      await pumpEventQueue();
    });

    Future<void> download() async {
      held!.complete();
      await syncing;
    }

    test('stays deleted', () async {
      container.read(iconSetsProvider.notifier).del(saved.id);
      await pumpEventQueue();

      await download();

      expect(await stored(), isEmpty);
    });

    test('keeps its new name and takes the new icons', () async {
      container
          .read(iconSetsProvider.notifier)
          .put(saved.copyWith(name: 'Renamed'));
      await pumpEventQueue();

      await download();

      final iconSet = (await stored()).single;
      expect(iconSet.name, 'Renamed');
      expect(iconSet.icons, hasLength(2));
    });
  });
}
