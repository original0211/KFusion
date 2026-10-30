import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/core/singbox/singbox_runner.dart';
import 'package:kfusion/features/config_hub/singbox_action.dart';
import 'package:kfusion/features/config_hub/singbox_render.dart';

void main() {
  Future<void> noPause(Duration duration) async {}

  test(
    'waitForValue returns true immediately when already at target',
    () async {
      var reads = 0;
      final result = await waitForValue<int>(
        read: () async => ++reads,
        target: 1,
        pause: noPause,
      );
      expect(result, isTrue);
      expect(reads, 1);
    },
  );

  test('waitForValue polls until the value reaches the target', () async {
    var reads = 0;
    final result = await waitForValue<String>(
      read: () async => ++reads >= 3 ? 'disconnected' : 'connected',
      target: 'disconnected',
      pause: noPause,
    );
    expect(result, isTrue);
    expect(reads, 3);
  });

  group('ensureMihomoStopped', () {
    test('does nothing when mihomo is not running', () async {
      var stops = 0;
      await ensureMihomoStopped(
        mihomoRunning: () => false,
        stopMihomo: () async {
          stops++;
          return true;
        },
      );
      expect(stops, 0);
    });

    test('proceeds once the stop chain answers', () async {
      var running = true;
      await ensureMihomoStopped(
        mihomoRunning: () => running,
        stopMihomo: () async {
          running = false;
          return true;
        },
      );
      expect(running, isFalse);
    });

    test('aborts the start when the stop goes unanswered', () async {
      await expectLater(
        ensureMihomoStopped(
          mihomoRunning: () => true,
          stopMihomo: () async => false,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'mihomo 未能停止，sing-box 未启动，避免双核心同时运行。',
          ),
        ),
      );
    });

    test('proceeds when the post-stop verification passes', () async {
      var verified = 0;
      await ensureMihomoStopped(
        mihomoRunning: () => true,
        stopMihomo: () async => true,
        verifyStopped: () async {
          verified++;
          return true;
        },
      );
      expect(verified, 1);
    });

    test('aborts when the core answers but keeps the port', () async {
      await expectLater(
        ensureMihomoStopped(
          mihomoRunning: () => true,
          stopMihomo: () async => true,
          verifyStopped: () async => false,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'mihomo 已应答停止，但运行状态或端口尚未释放，sing-box 未启动。',
          ),
        ),
      );
    });
  });

  group('portOccupiedDetail', () {
    const binary = r'C:\Users\me\AppData\KFusion\sing-box.exe';

    test('names an unidentified holder as unjudged', () async {
      final detail = await portOccupiedDetail(
        port: 7890,
        singBoxBinary: binary,
        findOwner: (_) async => null,
      );
      expect(detail, '端口 7890 仍被其他程序占用（未能判定属主），sing-box 未启动');
    });

    test('names a leftover sing-box of this app', () async {
      final detail = await portOccupiedDetail(
        port: 7890,
        singBoxBinary: binary,
        findOwner: (_) async => const PortOwnerInfo(
          pid: 777,
          imageName: 'sing-box.exe',
          executablePath: binary,
        ),
      );
      expect(detail, '端口 7890 仍被上次运行遗留的 sing-box（PID 777）占用，sing-box 未启动');
    });

    test('names the app mihomo core process', () async {
      final detail = await portOccupiedDetail(
        port: 7890,
        singBoxBinary: binary,
        findOwner: (_) async => const PortOwnerInfo(
          pid: 888,
          imageName: 'KFusionCore.exe',
          executablePath: r'C:\Program Files\Vessel\KFusionCore.exe',
        ),
      );
      expect(detail, '端口 7890 仍被本应用 mihomo 核心进程（PID 888）占用，sing-box 未启动');
    });

    test('names a foreign program by image and pid', () async {
      final detail = await portOccupiedDetail(
        port: 7890,
        singBoxBinary: binary,
        findOwner: (_) async =>
            const PortOwnerInfo(pid: 999, imageName: 'other.exe'),
      );
      expect(detail, '端口 7890 仍被 other.exe（PID 999）占用，sing-box 未启动');
    });
  });

  group('waitForSingBoxApi', () {
    test('an answering probe means ready', () async {
      final detail = await waitForSingBoxApi(() async {}, pause: noPause);
      expect(detail, isNull);
    });

    test('a probe that answers after failures still means ready', () async {
      var attempts = 0;
      final detail = await waitForSingBoxApi(() async {
        if (++attempts < 3) {
          throw StateError('connection refused');
        }
      }, pause: noPause);
      expect(detail, isNull);
      expect(attempts, 3);
    });

    test('a silent probe yields the last error as detail', () async {
      final detail = await waitForSingBoxApi(
        () async => throw StateError('connection refused'),
        timeout: const Duration(milliseconds: 30),
        interval: const Duration(milliseconds: 5),
        pause: noPause,
      );
      expect(detail, isNotNull);
      expect(detail, contains('connection refused'));
    });
  });

  test('waitForValue gives up after the timeout', () async {
    var reads = 0;
    final result = await waitForValue<String>(
      read: () async {
        reads++;
        return 'connected';
      },
      target: 'disconnected',
      timeout: const Duration(milliseconds: 30),
      interval: const Duration(milliseconds: 5),
      pause: noPause,
    );
    expect(result, isFalse);
    expect(reads, greaterThan(1));
  });

  group('config writers', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('singbox-config-write');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('a native config is written byte for byte', () async {
      const text = '''
{
    "outbounds": [
        {"type": "vless", "tag": "节点", "server": "203.0.113.9", "server_port": 443, "uuid": "u"}
    ]
}
''';
      final stale = File('${dir.path}/degradations.json');
      await stale.writeAsString('[]');
      final path = await writeNativeSingBoxConfig(dir, text);
      expect(path, '${dir.path}/config.json');
      expect(
        await File(path).readAsBytes(),
        utf8.encode(text),
        reason: 'no re-encode: whitespace and wording survive verbatim',
      );
      expect(
        await stale.exists(),
        isFalse,
        reason: 'a rendered ledger must not be read as this config\u2019s own',
      );
    });

    test('a rendered config still lands beside its ledger', () async {
      final rendered = renderSingBoxFromClash({
        'proxies': [
          {
            'name': 'SS-1',
            'type': 'ss',
            'server': '203.0.113.2',
            'port': 8388,
            'cipher': 'aes-256-gcm',
            'password': 'pw',
          },
          {
            'name': 'OVPN',
            'type': 'openvpn',
            'server': '203.0.113.1',
            'port': 1194,
          },
        ],
      }, secret: 's');
      final path = await writeRenderedSingBoxConfig(dir, rendered);
      expect(await File(path).readAsString(), jsonEncode(rendered.config));
      final ledger =
          jsonDecode(await File('${dir.path}/degradations.json').readAsString())
              as List;
      expect(ledger, [
        for (final degradation in rendered.degradations) degradation.toJson(),
      ]);
      expect(ledger, isNotEmpty);
    });
  });
}
