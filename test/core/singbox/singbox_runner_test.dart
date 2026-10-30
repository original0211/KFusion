@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/core/singbox/singbox_runner.dart';

class _FakeProcess implements RunningProcess {
  final _exitCompleter = Completer<int>();
  var killCount = 0;
  var killed = false;

  final _stdoutController = StreamController<List<int>>();
  final _stderrController = StreamController<List<int>>();

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  Future<int> get exitCode => _exitCompleter.future;

  void finish([int code = 0]) {
    if (!_exitCompleter.isCompleted) _exitCompleter.complete(code);
  }

  Future<void> close() async {
    await _stdoutController.close();
    await _stderrController.close();
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killCount++;
    killed = true;
    finish(143);
    return true;
  }
}

class _FakeLauncher implements ProcessLauncher {
  _FakeProcess? last;

  @override
  Future<RunningProcess> start(
    String executable,
    List<String> args, {
    String? workingDirectory,
  }) async {
    last = _FakeProcess();
    return last!;
  }
}

class _FakeBackend implements CoreBackend {
  _FakeBackend({this.running = false, this.failStart = false});

  var running = false;
  var stopCount = 0;
  var startCount = 0;
  final bool failStart;

  @override
  bool get isRunning => running;

  @override
  Future<void> stop() async {
    stopCount++;
    running = false;
  }

  @override
  Future<void> start() async {
    startCount++;
    if (failStart) throw StateError('backend failed to start');
    running = true;
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kfusion-singbox');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('runner reports ready when clash_api answers', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(json.encode({'proxies': {}}));
      await request.response.close();
    });
    final launcher = _FakeLauncher();
    addTearDown(() => launcher.last?.close());
    final runner = SingBoxRunner(launcher: launcher);
    final result = await runner.start(
      executable: 'sing-box',
      config: const {
        'log': {'level': 'info'},
      },
      configDir: tempDir,
      apiPort: server.port,
      secret: 'secret',
    );
    expect(result.ok, isTrue);
    expect(runner.isRunning, isTrue);
    await runner.stop();
    expect(runner.isRunning, isFalse);
    expect(launcher.last?.killCount, 1);
  });

  test('runner writes a native config byte for byte', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(json.encode({'proxies': {}}));
      await request.response.close();
    });
    final launcher = _FakeLauncher();
    addTearDown(() => launcher.last?.close());
    final runner = SingBoxRunner(launcher: launcher);
    const nativeText = '''
{
    "outbounds": [
        {"type": "direct", "tag": "direct"}
    ]
}
''';
    final result = await runner.start(
      executable: 'sing-box',
      config: const {},
      configText: nativeText,
      configDir: tempDir,
      apiPort: server.port,
      secret: 'secret',
    );
    expect(result.ok, isTrue);
    expect(
      await File('${tempDir.path}/config.json').readAsString(),
      nativeText,
    );
    await runner.stop();
  });

  test(
    'runner times out and kills the process when api never answers',
    () async {
      final launcher = _FakeLauncher();
      addTearDown(() => launcher.last?.close());
      final runner = SingBoxRunner(
        launcher: launcher,
        readyTimeout: const Duration(milliseconds: 300),
        pollInterval: const Duration(milliseconds: 50),
      );
      final result = await runner.start(
        executable: 'sing-box',
        config: const {
          'log': {'level': 'info'},
        },
        configDir: tempDir,
        apiPort: 1,
        secret: 'secret',
      );
      expect(result.ok, isFalse);
      expect(runner.isRunning, isFalse);
      expect(launcher.last?.killed, isTrue);
    },
  );

  test('runner reports a crash with exit code', () async {
    final launcher = _FakeLauncher();
    addTearDown(() => launcher.last?.close());
    var crashCode = -1;
    final runner = SingBoxRunner(
      launcher: launcher,
      readyTimeout: const Duration(seconds: 5),
      pollInterval: const Duration(milliseconds: 50),
      onCrash: (code, _) => crashCode = code,
    );
    final future = runner.start(
      executable: 'sing-box',
      config: const {
        'log': {'level': 'info'},
      },
      configDir: tempDir,
      apiPort: 1,
      secret: 'secret',
    );
    while (launcher.last == null) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    launcher.last?.finish(1);
    final result = await future;
    expect(result.ok, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(crashCode, 1);
  });

  test('clash_api delay parses the delay field', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(json.encode({'delay': 42}));
      await request.response.close();
    });
    final api = SingBoxClashApi(port: server.port, secret: 'secret');
    expect(await api.delay('PROXY', 'https://example.com'), 42);
  });

  test(
    'core switch stops the old backend before starting the new one',
    () async {
      final order = <String>[];
      final from = _FakeBackend(running: true);
      final to = _FakeBackend();
      final switcher = CoreSwitch(isPortFree: (port) async => true);
      final wrappedFrom = _OrderBackend(from, order, 'from');
      final wrappedTo = _OrderBackend(to, order, 'to');
      await switcher.switchTo(
        from: wrappedFrom,
        to: wrappedTo,
        releasedPort: 9090,
      );
      expect(order, ['from-stop', 'to-start']);
      expect(to.isRunning, isTrue);
    },
  );

  test('core switch refuses when the old port never frees', () async {
    final from = _FakeBackend(running: true);
    final to = _FakeBackend();
    final switcher = CoreSwitch(
      isPortFree: (port) async => false,
      portWaitTimeout: const Duration(milliseconds: 100),
      portPollInterval: const Duration(milliseconds: 20),
    );
    await expectLater(
      switcher.switchTo(from: from, to: to, releasedPort: 9090),
      throwsStateError,
    );
    expect(to.startCount, 0);
  });

  test('core switch stops the new backend when its start fails', () async {
    final from = _FakeBackend();
    final to = _FakeBackend(failStart: true);
    final switcher = CoreSwitch(isPortFree: (port) async => true);
    await expectLater(
      switcher.switchTo(from: from, to: to, releasedPort: 9090),
      throwsStateError,
    );
    expect(to.stopCount, 1);
    expect(to.isRunning, isFalse);
  });

  test('awaitPortFree returns as soon as the port frees', () async {
    var probes = 0;
    final switcher = CoreSwitch(
      isPortFree: (port) async => ++probes >= 3,
      portWaitTimeout: const Duration(seconds: 5),
      portPollInterval: const Duration(milliseconds: 10),
    );
    expect(await switcher.awaitPortFree(7890), isTrue);
    expect(probes, 3);
  });

  test('awaitPortFree gives up after the wait budget', () async {
    final switcher = CoreSwitch(
      isPortFree: (port) async => false,
      portWaitTimeout: const Duration(milliseconds: 100),
      portPollInterval: const Duration(milliseconds: 20),
    );
    expect(await switcher.awaitPortFree(7890), isFalse);
  });

  test('orphan reclaim kills only this app binary on its own config', () async {
    const executable = r'C:\Users\me\AppData\KFusion\sing-box.exe';
    const configPath = r'C:\Users\me\AppData\KFusion\singbox\config.json';
    final killed = <int>[];
    final reclaimed = await reclaimOrphanedSingBoxProcesses(
      executable: executable,
      configPath: configPath,
      listProcesses: () async => const [
        SingBoxProcessInfo(
          pid: 101,
          executablePath: executable,
          commandLine: 'sing-box.exe run -c "$configPath"',
        ),
        SingBoxProcessInfo(
          pid: 102,
          executablePath: r'C:\other\sing-box.exe',
          commandLine: 'sing-box.exe run -c "$configPath"',
        ),
        SingBoxProcessInfo(
          pid: 103,
          executablePath: executable,
          commandLine: r'sing-box.exe run -c "C:\other\config.json"',
        ),
      ],
      killProcess: (pid) async => killed.add(pid),
    );
    expect(reclaimed, 1);
    expect(killed, [101]);
  });

  test('binary lookup returns the first existing candidate', () {
    final found = findSingBoxBinary([
      '/nope/sing-box',
      '/also-nope/sing-box',
    ], exists: (path) => path == '/also-nope/sing-box');
    expect(found, '/also-nope/sing-box');
    expect(findSingBoxBinary(['/nope/sing-box'], exists: (_) => false), isNull);
  });

  group('clash_api control surface', () {
    Future<
      ({
        int port,
        List<
          ({
            String method,
            String path,
            String body,
            List<int> bodyBytes,
            String? auth,
          })
        >
        requests,
      })
    >
    serveApi({
      required int statusCode,
      Map<String, Object?> responseBody = const {},
    }) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests =
          <
            ({
              String method,
              String path,
              String body,
              List<int> bodyBytes,
              String? auth,
            })
          >[];
      server.listen((request) async {
        final bodyBytes = await request.fold<List<int>>(
          <int>[],
          (bytes, chunk) => bytes..addAll(chunk),
        );
        requests.add((
          method: request.method,
          path: request.uri.path,
          body: utf8.decode(bodyBytes),
          bodyBytes: bodyBytes,
          auth: request.headers.value('Authorization'),
        ));
        request.response.statusCode = statusCode;
        if (responseBody.isNotEmpty) {
          request.response.headers.contentType = ContentType.json;
          request.response.write(json.encode(responseBody));
        }
        await request.response.close();
      });
      return (port: server.port, requests: requests);
    }

    test('changeProxy PUTs the selection to the selector group', () async {
      final api = await serveApi(statusCode: 204);
      final client = SingBoxClashApi(port: api.port, secret: 's3cr3t');
      await client.changeProxy('节点选择', 'HK-01');
      expect(api.requests, hasLength(1));
      final request = api.requests.single;
      expect(request.method, 'PUT');
      expect(request.path, '/proxies/${Uri.encodeComponent('节点选择')}');
      expect(json.decode(request.body), {'name': 'HK-01'});
      expect(request.auth, 'Bearer s3cr3t');
    });

    test(
      'changeProxy sends a flag-prefixed node name as UTF-8 bytes',
      () async {
        final api = await serveApi(statusCode: 204);
        final client = SingBoxClashApi(port: api.port, secret: 's3cr3t');
        await client.changeProxy('⚡ CF前置', '🇹🇼_台湾-05-01');
        expect(api.requests, hasLength(1));
        final request = api.requests.single;
        expect(request.method, 'PUT');
        expect(request.bodyBytes, utf8.encode('{"name":"🇹🇼_台湾-05-01"}'));
      },
    );

    test(
      'changeProxy sends a plain Chinese node name as UTF-8 bytes',
      () async {
        final api = await serveApi(statusCode: 204);
        final client = SingBoxClashApi(port: api.port, secret: 's3cr3t');
        await client.changeProxy('节点选择', '台湾-05-01');
        expect(api.requests, hasLength(1));
        expect(
          api.requests.single.bodyBytes,
          utf8.encode('{"name":"台湾-05-01"}'),
        );
      },
    );

    test('changeProxy surfaces the panel error message', () async {
      final api = await serveApi(
        statusCode: 400,
        responseBody: {'message': 'Selector update error: not found'},
      );
      final client = SingBoxClashApi(port: api.port, secret: 's3cr3t');
      await expectLater(
        client.changeProxy('Home', 'NOPE'),
        throwsA(
          isA<HttpException>().having(
            (e) => e.message,
            'message',
            contains('Selector update error: not found'),
          ),
        ),
      );
    });

    test('patchMode PATCHes the configs mode', () async {
      final api = await serveApi(statusCode: 204);
      final client = SingBoxClashApi(port: api.port, secret: 's3cr3t');
      await client.patchMode('Global');
      final request = api.requests.single;
      expect(request.method, 'PATCH');
      expect(request.path, '/configs');
      expect(json.decode(request.body), {'mode': 'Global'});
    });

    test('closeConnections DELETEs all connections', () async {
      final api = await serveApi(statusCode: 204);
      final client = SingBoxClashApi(port: api.port, secret: 's3cr3t');
      await client.closeConnections();
      final request = api.requests.single;
      expect(request.method, 'DELETE');
      expect(request.path, '/connections');
    });
  });

  group('orphan reclaim resilience', () {
    const executable = r'C:\Users\me\AppData\KFusion\sing-box.exe';
    const configPath = r'C:\Users\me\AppData\KFusion\singbox\config.json';

    test('an enumeration failure is reported, never silent', () async {
      final events = <String>[];
      final reclaimed = await reclaimOrphanedSingBoxProcesses(
        executable: executable,
        configPath: configPath,
        listProcesses: () async => throw StateError('CIM unavailable'),
        fallbackListProcesses: () async => const [],
        onEvent: events.add,
      );
      expect(reclaimed, 0);
      expect(events, hasLength(1));
      expect(events.single, contains('CIM unavailable'));
    });

    test(
      'a fallback orphan holding the port is reclaimed without a command line',
      () async {
        final killed = <int>[];
        final reclaimed = await reclaimOrphanedSingBoxProcesses(
          executable: executable,
          configPath: configPath,
          listProcesses: () async => throw StateError('CIM unavailable'),
          fallbackListProcesses: () async => const [
            SingBoxProcessInfo(
              pid: 777,
              executablePath: executable,
              commandLine: '',
              verified: false,
            ),
          ],
          findPortOwner: (port) async => const PortOwnerInfo(
            pid: 777,
            imageName: 'sing-box.exe',
            executablePath: executable,
          ),
          corroborationPort: 7890,
          killProcess: (pid) async => killed.add(pid),
          onEvent: (_) {},
        );
        expect(reclaimed, 1);
        expect(killed, [777]);
      },
    );

    test('an uncorroborated fallback process is left alone', () async {
      final killed = <int>[];
      final reclaimed = await reclaimOrphanedSingBoxProcesses(
        executable: executable,
        configPath: configPath,
        listProcesses: () async => throw StateError('CIM unavailable'),
        fallbackListProcesses: () async => const [
          SingBoxProcessInfo(
            pid: 777,
            executablePath: executable,
            commandLine: '',
            verified: false,
          ),
        ],
        findPortOwner: (port) async =>
            const PortOwnerInfo(pid: 999, imageName: 'other.exe'),
        corroborationPort: 7890,
        killProcess: (pid) async => killed.add(pid),
        onEvent: (_) {},
      );
      expect(reclaimed, 0);
      expect(killed, isEmpty);
    });
  });

  test('port owner lookup reads netstat and tasklist output', () async {
    Future<ProcessResult> run(String executable, List<String> args) async {
      if (executable == 'netstat') {
        return ProcessResult(
          1,
          0,
          '  TCP    127.0.0.1:7890         0.0.0.0:0              LISTENING       4321\r\n'
              '  TCP    127.0.0.1:7891         0.0.0.0:0              LISTENING       5555\r\n',
          '',
        );
      }
      if (executable == 'tasklist') {
        return ProcessResult(
          2,
          0,
          '"sing-box.exe","4321","Console","1","9,876 K"\r\n',
          '',
        );
      }
      if (executable == 'powershell') {
        return ProcessResult(
          3,
          0,
          r'C:\Users\me\AppData\KFusion\sing-box.exe'
              '\r\n',
          '',
        );
      }
      throw StateError('unexpected command $executable');
    }

    final owner = await findListeningPortOwner(7890, run: run);
    expect(owner, isNotNull);
    expect(owner!.pid, 4321);
    expect(owner.imageName, 'sing-box.exe');
    expect(owner.executablePath, r'C:\Users\me\AppData\KFusion\sing-box.exe');
  });
}

class _OrderBackend implements CoreBackend {
  _OrderBackend(this._inner, this._order, this._name);

  final _FakeBackend _inner;
  final List<String> _order;
  final String _name;

  @override
  bool get isRunning => _inner.isRunning;

  @override
  Future<void> stop() async {
    _order.add('$_name-stop');
    await _inner.stop();
  }

  @override
  Future<void> start() async {
    _order.add('$_name-start');
    await _inner.start();
  }
}
