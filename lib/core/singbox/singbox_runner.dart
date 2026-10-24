import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

abstract class RunningProcess {
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]);
}

abstract class ProcessLauncher {
  Future<RunningProcess> start(
    String executable,
    List<String> args, {
    String? workingDirectory,
  });
}

class _IoRunningProcess implements RunningProcess {
  _IoRunningProcess(this._process);

  final Process _process;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    return _process.kill(signal);
  }
}

class IoProcessLauncher implements ProcessLauncher {
  @override
  Future<RunningProcess> start(
    String executable,
    List<String> args, {
    String? workingDirectory,
  }) async {
    final process = await Process.start(
      executable,
      args,
      workingDirectory: workingDirectory,
      runInShell: false,
    );
    return _IoRunningProcess(process);
  }
}

String generateSingBoxSecret() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

List<String> singBoxCandidates({
  required String executableDir,
  required String homeDir,
  String? storedPath,
}) {
  return [
    if (storedPath != null && storedPath.isNotEmpty) storedPath,
    p.join(executableDir, 'sing-box.exe'),
    p.join(homeDir, 'singbox', 'sing-box.exe'),
  ];
}

String? findSingBoxBinary(
  List<String> candidates, {
  bool Function(String path)? exists,
}) {
  final check = exists ?? (String path) => File(path).existsSync();
  for (final candidate in candidates) {
    if (check(candidate)) return candidate;
  }
  return null;
}

Future<bool> isWindowsAdmin() async {
  try {
    final result = await Process.run('net', ['session']);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

Future<bool> checkPortFree(int port) async {
  try {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await socket.close();
    return true;
  } catch (_) {
    return false;
  }
}

class SingBoxClashApi {
  SingBoxClashApi({required this.port, required this.secret});

  final int port;
  final String secret;

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: port,
      path: path,
      queryParameters: query,
    );
  }

  Future<Map<String, Object?>> _get(
    String path, [
    Map<String, String>? query,
  ]) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.getUrl(_uri(path, query));
      request.headers.set('Authorization', 'Bearer $secret');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw HttpException(
          'sing-box clash_api $path -> ${response.statusCode}',
        );
      }
      final decoded = json.decode(body);
      if (decoded is Map) {
        return {
          for (final MapEntry(:key, :value) in decoded.entries)
            key.toString(): value,
        };
      }
      return const {};
    } finally {
      client.close();
    }
  }

  Future<Map<String, Object?>> getProxies() => _get('/proxies');

  Future<int> delay(String proxyName, String url) async {
    final data = await _get(
      '/proxies/${Uri.encodeComponent(proxyName)}/delay',
      {'url': url, 'timeout': '5000'},
    );
    final value = data['delay'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    throw const FormatException('missing delay in clash_api response');
  }

  Future<Map<String, Object?>> getConnections() => _get('/connections');
}

class SingBoxStartResult {
  const SingBoxStartResult({
    required this.ok,
    this.message = '',
    this.tailLines = const [],
  });

  final bool ok;
  final String message;
  final List<String> tailLines;
}

class SingBoxRunner {
  SingBoxRunner({
    required this.launcher,
    this.readyTimeout = const Duration(seconds: 15),
    this.pollInterval = const Duration(milliseconds: 500),
    this.onCrash,
  });

  final ProcessLauncher launcher;
  final Duration readyTimeout;
  final Duration pollInterval;
  final void Function(int exitCode, List<String> tailLines)? onCrash;

  RunningProcess? _process;
  final List<String> _tailLines = [];
  var _stopping = false;

  bool get isRunning => _process != null;

  List<String> get tailLines => List.unmodifiable(_tailLines);

  void _recordLine(String line) {
    final trimmed = line.trimRight();
    if (trimmed.isEmpty) return;
    _tailLines.add(trimmed);
    if (_tailLines.length > 200) _tailLines.removeAt(0);
  }

  Future<SingBoxStartResult> start({
    required String executable,
    required Map<String, Object?> config,
    required Directory configDir,
    required int apiPort,
    required String secret,
  }) async {
    if (_process != null) {
      return const SingBoxStartResult(ok: false, message: 'sing-box 已在运行。');
    }
    _stopping = false;
    _tailLines.clear();
    try {
      await configDir.create(recursive: true);
      final configFile = File(p.join(configDir.path, 'config.json'));
      await configFile.writeAsString(json.encode(config));
      final process = await launcher.start(executable, [
        'run',
        '-c',
        configFile.path,
      ], workingDirectory: configDir.path);
      _process = process;
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_recordLine);
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_recordLine);
      unawaited(
        process.exitCode.then((code) {
          final wasRunning = _process == process;
          _process = null;
          if (wasRunning && !_stopping) {
            onCrash?.call(code, tailLines);
          }
        }),
      );
      final api = SingBoxClashApi(port: apiPort, secret: secret);
      final deadline = DateTime.now().add(readyTimeout);
      while (DateTime.now().isBefore(deadline)) {
        if (_process == null) {
          return SingBoxStartResult(
            ok: false,
            message: 'sing-box 启动后很快退出。',
            tailLines: tailLines,
          );
        }
        try {
          await api.getProxies();
          return const SingBoxStartResult(ok: true);
        } catch (_) {
          await Future<void>.delayed(pollInterval);
        }
      }
      await stop();
      return SingBoxStartResult(
        ok: false,
        message: 'sing-box 未能在 ${readyTimeout.inSeconds} 秒内就绪。',
        tailLines: tailLines,
      );
    } catch (e) {
      await stop();
      return SingBoxStartResult(ok: false, message: e.toString());
    }
  }

  Future<void> stop() async {
    final process = _process;
    if (process == null) return;
    _stopping = true;
    try {
      process.kill();
      await process.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (_) {}
    } finally {
      _process = null;
    }
  }
}

abstract class CoreBackend {
  bool get isRunning;
  Future<void> stop();
  Future<void> start();
}

class CoreSwitch {
  CoreSwitch({
    Future<bool> Function(int port)? isPortFree,
    this.portWaitTimeout = const Duration(seconds: 10),
    this.portPollInterval = const Duration(milliseconds: 250),
  }) : isPortFree = isPortFree ?? checkPortFree;

  final Future<bool> Function(int port) isPortFree;
  final Duration portWaitTimeout;
  final Duration portPollInterval;

  Future<void> switchTo({
    required CoreBackend from,
    required CoreBackend to,
    required int releasedPort,
  }) async {
    if (from.isRunning) {
      await from.stop();
      final deadline = DateTime.now().add(portWaitTimeout);
      var free = await isPortFree(releasedPort);
      while (!free && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(portPollInterval);
        free = await isPortFree(releasedPort);
      }
      if (!free) {
        throw StateError('旧核心未释放端口 $releasedPort，切换已中止。');
      }
    }
    try {
      await to.start();
    } catch (e) {
      try {
        await to.stop();
      } catch (_) {}
      rethrow;
    }
  }
}
