import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/core/singbox/singbox_runner.dart';
import 'package:kfusion/enum/enum.dart';
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

    test(
      'falls back to the executable file name without an image name',
      () async {
        final detail = await portOccupiedDetail(
          port: 7890,
          singBoxBinary: binary,
          findOwner: (_) async => const PortOwnerInfo(
            pid: 555,
            imageName: '',
            executablePath: r'C:\tools\proxy.exe',
          ),
        );
        expect(detail, '端口 7890 仍被 proxy.exe（PID 555）占用，sing-box 未启动');
      },
    );

    test('names a holder with neither image nor path as unknown', () async {
      final detail = await portOccupiedDetail(
        port: 7890,
        singBoxBinary: binary,
        findOwner: (_) async => const PortOwnerInfo(pid: 556, imageName: ''),
      );
      expect(detail, '端口 7890 仍被未知程序（PID 556）占用，sing-box 未启动');
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

  group('reclaimStartupOrphans', () {
    const binary = r'C:\app\sing-box.exe';

    test('does nothing when no binary is installed', () async {
      var calls = 0;
      await reclaimStartupOrphans(
        locateBinary: () async => null,
        reclaim: (_) async {
          calls++;
          return 0;
        },
        portFree: () async {
          calls++;
          return true;
        },
        occupiedDetail: (_) async => 'detail',
        info: (_) {},
        warning: (_) {},
      );
      expect(calls, 0);
    });

    test('logs the reclaim count and stays quiet on a free port', () async {
      final infos = <String>[];
      final warnings = <String>[];
      await reclaimStartupOrphans(
        locateBinary: () async => binary,
        reclaim: (path) async {
          expect(path, binary);
          return 2;
        },
        portFree: () async => true,
        occupiedDetail: (_) async => 'detail',
        info: infos.add,
        warning: warnings.add,
      );
      expect(infos, ['启动自检回收了 2 个遗留 sing-box 进程']);
      expect(warnings, isEmpty);
    });

    test('warns with the owner detail while the port stays occupied', () async {
      final warnings = <String>[];
      await reclaimStartupOrphans(
        locateBinary: () async => binary,
        reclaim: (_) async => 0,
        portFree: () async => false,
        occupiedDetail: (path) async {
          expect(path, binary);
          return '端口 7890 仍被其他程序占用（未能判定属主），sing-box 未启动';
        },
        info: (_) {},
        warning: warnings.add,
      );
      expect(warnings, ['启动自检：端口 7890 仍被其他程序占用（未能判定属主），sing-box 未启动']);
    });

    test('reports a locate failure instead of throwing', () async {
      final warnings = <String>[];
      await reclaimStartupOrphans(
        locateBinary: () async => throw StateError('disk gone'),
        reclaim: (_) async => 0,
        portFree: () async => true,
        occupiedDetail: (_) async => 'detail',
        info: (_) {},
        warning: warnings.add,
      );
      expect(warnings.single, contains('启动自检回收遗留 sing-box 失败'));
      expect(warnings.single, contains('disk gone'));
    });

    test('reports a reclaim failure instead of throwing', () async {
      final warnings = <String>[];
      await reclaimStartupOrphans(
        locateBinary: () async => binary,
        reclaim: (_) async => throw StateError('enum broke'),
        portFree: () async => true,
        occupiedDetail: (_) async => 'detail',
        info: (_) {},
        warning: warnings.add,
      );
      expect(warnings.single, contains('启动自检回收遗留 sing-box 失败'));
    });
  });

  group('syncModeToSingBox', () {
    Future<HttpServer> serve(
      void Function(String method, String path, String body) record, {
      int status = HttpStatus.noContent,
    }) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final body = await utf8.decodeStream(request);
        record(request.method, request.uri.path, body);
        request.response.statusCode = status;
        await request.response.close();
      });
      return server;
    }

    test('pushes the current mode to a rendered bearer', () async {
      final seen = <String>[];
      final server = await serve(
        (method, path, body) => seen.add('$method $path $body'),
      );
      addTearDown(server.close);
      final warnings = <String>[];
      await syncModeToSingBox(
        api: SingBoxClashApi(port: server.port, secret: 's'),
        rendered: true,
        mode: Mode.global,
        warning: warnings.add,
      );
      expect(seen, ['PATCH /configs {"mode":"Global"}']);
      expect(warnings, isEmpty);
    });

    test('pushes direct mode with sing-box spelling', () async {
      final seen = <String>[];
      final server = await serve(
        (method, path, body) => seen.add('$method $path $body'),
      );
      addTearDown(server.close);
      await syncModeToSingBox(
        api: SingBoxClashApi(port: server.port, secret: 's'),
        rendered: true,
        mode: Mode.direct,
        warning: (_) {},
      );
      expect(seen, ['PATCH /configs {"mode":"Direct"}']);
    });

    test('skips a native config and a missing bearer', () async {
      var hits = 0;
      final server = await serve((_, _, _) => hits++);
      addTearDown(server.close);
      final api = SingBoxClashApi(port: server.port, secret: 's');
      await syncModeToSingBox(
        api: api,
        rendered: false,
        mode: Mode.direct,
        warning: (_) {},
      );
      await syncModeToSingBox(
        api: null,
        rendered: true,
        mode: Mode.direct,
        warning: (_) {},
      );
      expect(hits, 0);
    });

    test('warns instead of throwing when the panel refuses', () async {
      final server = await serve((_, _, _) {}, status: HttpStatus.badRequest);
      addTearDown(server.close);
      final warnings = <String>[];
      await syncModeToSingBox(
        api: SingBoxClashApi(port: server.port, secret: 's'),
        rendered: true,
        mode: Mode.rule,
        warning: warnings.add,
      );
      expect(warnings.single, contains('sing-box 模式同步失败'));
    });
  });
}
