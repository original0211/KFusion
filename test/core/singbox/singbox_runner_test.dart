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
