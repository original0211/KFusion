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

  Future<void> _send(String method, String path, {Object? body}) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.openUrl(method, _uri(path));
      request.headers.set('Authorization', 'Bearer $secret');
      if (body != null) {
        request.headers.set('Content-Type', 'application/json');
        // Names are user-controlled text; write() would encode the string
        // as latin1 (the request default without a charset) and throw on
        // any code point above U+00FF, so send UTF-8 bytes explicitly.
        final bytes = utf8.encode(json.encode(body));
        request.contentLength = bytes.length;
        request.add(bytes);
      }
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(_sendErrorMessage(path, response.statusCode, text));
      }
    } finally {
      client.close();
    }
  }

  String _sendErrorMessage(String path, int statusCode, String body) {
    try {
      final decoded = json.decode(body);
      if (decoded is Map && decoded['message'] != null) {
        return 'sing-box clash_api $path -> $statusCode: ${decoded['message']}';
      }
    } catch (_) {}
    return 'sing-box clash_api $path -> $statusCode';
  }

  Future<Map<String, Object?>> getProxies() => _get('/proxies');

  /// Selects [proxyName] inside the selector [groupName] (PUT /proxies/{group}).
  Future<void> changeProxy(String groupName, String proxyName) {
    return _send(
      'PUT',
      '/proxies/${Uri.encodeComponent(groupName)}',
      body: {'name': proxyName == 'DIRECT' ? 'direct' : proxyName},
    );
  }

  /// Sets the clash mode (PATCH /configs); sing-box honours only listed modes.
  Future<void> patchMode(String mode) {
    return _send('PATCH', '/configs', body: {'mode': mode});
  }

  /// Drops every live connection (DELETE /connections).
  Future<void> closeConnections() => _send('DELETE', '/connections');

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

  /// Starts the binary on [config]; a native config passes
  /// [configText] instead and is written byte for byte, never
  /// re-encoded.
  Future<SingBoxStartResult> start({
    required String executable,
    required Map<String, Object?> config,
    String? configText,
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
      await configFile.writeAsString(configText ?? json.encode(config));
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

  /// Waits until [port] can be bound again; false when it stays occupied.
  Future<bool> awaitPortFree(int port) async {
    var free = await isPortFree(port);
    final deadline = DateTime.now().add(portWaitTimeout);
    while (!free && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(portPollInterval);
      free = await isPortFree(port);
    }
    return free;
  }

  Future<void> switchTo({
    required CoreBackend from,
    required CoreBackend to,
    required int releasedPort,
  }) async {
    if (from.isRunning) {
      await from.stop();
      if (!await awaitPortFree(releasedPort)) {
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

/// One entry of a process listing, reduced to what orphan matching needs.
class SingBoxProcessInfo {
  const SingBoxProcessInfo({
    required this.pid,
    required this.executablePath,
    required this.commandLine,
    this.verified = true,
  });

  final int pid;
  final String executablePath;
  final String commandLine;

  /// False when the listing channel could not read the command line.
  final bool verified;
}

bool windowsPathsEqual(String a, String b) {
  String normalize(String path) => path.replaceAll('/', '\\').toLowerCase();
  return normalize(a) == normalize(b);
}

/// Only this app's own binary started on this app's own config qualifies.
bool isAppSingBoxProcess(
  SingBoxProcessInfo info, {
  required String executable,
  required String configPath,
}) {
  String normalize(String path) => path.replaceAll('/', '\\').toLowerCase();
  return windowsPathsEqual(info.executablePath, executable) &&
      normalize(info.commandLine).contains(normalize(configPath));
}

/// The process holding a listening TCP port, as far as the system tools can name it.
class PortOwnerInfo {
  const PortOwnerInfo({
    required this.pid,
    required this.imageName,
    this.executablePath = '',
  });

  final int pid;
  final String imageName;
  final String executablePath;
}

typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

Future<ProcessResult> _runProcess(String executable, List<String> arguments) {
  return Process.run(executable, arguments);
}

/// Identifies the listener on [port] through netstat, tasklist and
/// Get-Process — channels that fail independently of the CIM listing.
Future<PortOwnerInfo?> findListeningPortOwner(
  int port, {
  ProcessRunner? run,
}) async {
  final runner = run ?? _runProcess;
  try {
    final netstat = await runner('netstat', ['-ano', '-p', 'TCP']);
    if (netstat.exitCode != 0) {
      return null;
    }
    final pid = _listeningPid(netstat.stdout as String, port);
    if (pid == null) {
      return null;
    }
    var imageName = '';
    var executablePath = '';
    try {
      final tasklist = await runner('tasklist', [
        '/FI',
        'PID eq $pid',
        '/FO',
        'CSV',
        '/NH',
      ]);
      imageName =
          RegExp(
            r'"([^"]+)"',
          ).firstMatch((tasklist.stdout as String).trim())?.group(1) ??
          '';
    } catch (_) {}
    try {
      final process = await runner('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        '(Get-Process -Id $pid).Path',
      ]);
      if (process.exitCode == 0) {
        executablePath = (process.stdout as String).trim();
      }
    } catch (_) {}
    return PortOwnerInfo(
      pid: pid,
      imageName: imageName,
      executablePath: executablePath,
    );
  } catch (_) {
    return null;
  }
}

int? _listeningPid(String netstatOutput, int port) {
  final pattern = RegExp(r':(\d+)\s+\S+\s+LISTENING\s+(\d+)');
  for (final match in pattern.allMatches(netstatOutput)) {
    if (int.tryParse(match.group(1)!) == port) {
      return int.tryParse(match.group(2)!);
    }
  }
  return null;
}

Future<List<SingBoxProcessInfo>> _listSingBoxProcesses() async {
  const script =
      "Get-CimInstance Win32_Process "
      "-Filter \"Name='sing-box.exe'\" | "
      'Select-Object ProcessId, ExecutablePath, CommandLine | '
      'ConvertTo-Json -Compress';
  final result = await Process.run('powershell', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    script,
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'PowerShell 进程枚举失败（exit ${result.exitCode}）：'
      '${(result.stderr as String).trim()}',
    );
  }
  final text = (result.stdout as String).trim();
  if (text.isEmpty) {
    return const [];
  }
  final decoded = json.decode(text);
  final entries = decoded is List ? decoded : [decoded];
  return [
    for (final entry in entries)
      if (entry is Map)
        SingBoxProcessInfo(
          pid: (entry['ProcessId'] as num?)?.toInt() ?? 0,
          executablePath: entry['ExecutablePath']?.toString() ?? '',
          commandLine: entry['CommandLine']?.toString() ?? '',
        ),
  ];
}

/// The fallback listing for when CIM will not answer: tasklist finds
/// the PIDs and Get-Process the paths, so entries come back unverified.
Future<List<SingBoxProcessInfo>> _listSingBoxProcessesFallback() async {
  final result = await Process.run('tasklist', [
    '/FI',
    'IMAGENAME eq sing-box.exe',
    '/FO',
    'CSV',
    '/NH',
  ]);
  if (result.exitCode != 0) {
    return const [];
  }
  final entries = <SingBoxProcessInfo>[];
  final pidPattern = RegExp(r'^"[^"]+","(\d+)"', multiLine: true);
  for (final match in pidPattern.allMatches(result.stdout as String)) {
    final pid = int.parse(match.group(1)!);
    var path = '';
    try {
      final process = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        '(Get-Process -Id $pid).Path',
      ]);
      if (process.exitCode == 0) {
        path = (process.stdout as String).trim();
      }
    } catch (_) {}
    entries.add(
      SingBoxProcessInfo(
        pid: pid,
        executablePath: path,
        commandLine: '',
        verified: false,
      ),
    );
  }
  return entries;
}

/// Kills this app's leftover sing-box processes; never blocks the start.
/// An enumeration failure is reported through [onEvent] and retried on
/// the fallback channel; a fallback entry qualifies only while it
/// holds [corroborationPort].
Future<int> reclaimOrphanedSingBoxProcesses({
  required String executable,
  required String configPath,
  Future<List<SingBoxProcessInfo>> Function()? listProcesses,
  Future<void> Function(int pid)? killProcess,
  void Function(String message)? onEvent,
  Future<List<SingBoxProcessInfo>> Function()? fallbackListProcesses,
  Future<PortOwnerInfo?> Function(int port)? findPortOwner,
  int? corroborationPort,
}) async {
  List<SingBoxProcessInfo> processes;
  try {
    processes = await (listProcesses ?? _listSingBoxProcesses)();
  } catch (error) {
    onEvent?.call('sing-box 进程枚举失败（$error），改走回退枚举');
    try {
      processes =
          await (fallbackListProcesses ?? _listSingBoxProcessesFallback)();
    } catch (fallbackError) {
      onEvent?.call('sing-box 回退枚举也失败（$fallbackError），本轮不回收遗留进程');
      return 0;
    }
  }
  var reclaimed = 0;
  PortOwnerInfo? owner;
  var ownerLookedUp = false;
  for (final info in processes) {
    if (info.pid <= 0) {
      continue;
    }
    var qualifies = isAppSingBoxProcess(
      info,
      executable: executable,
      configPath: configPath,
    );
    if (!qualifies &&
        !info.verified &&
        corroborationPort != null &&
        windowsPathsEqual(info.executablePath, executable)) {
      if (!ownerLookedUp) {
        ownerLookedUp = true;
        try {
          owner = await (findPortOwner ?? findListeningPortOwner)(
            corroborationPort,
          );
        } catch (_) {
          owner = null;
        }
      }
      qualifies = owner?.pid == info.pid;
    }
    if (!qualifies) {
      continue;
    }
    try {
      await (killProcess ?? _taskKill)(info.pid);
      reclaimed++;
    } catch (_) {}
  }
  return reclaimed;
}

Future<void> _taskKill(int pid) async {
  await Process.run('taskkill', ['/PID', '$pid', '/F']);
}
