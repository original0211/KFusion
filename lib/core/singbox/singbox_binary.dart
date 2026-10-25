import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:win32_registry/win32_registry.dart';

import 'singbox_runner.dart';

/// The sing-box release the managed download installs.
const singBoxPinnedVersion = '1.14.4';

/// SHA-256 of the official Windows zips of [singBoxPinnedVersion], keyed by
/// CPU architecture: the asset digests of the SagerNet/sing-box v1.14.4
/// GitHub release (2026-10-25), re-verified against downloaded copies.
const singBoxZipSha256 = <String, String>{
  'amd64': '99185d75d314a07dbba4a130c8ad986cbeb629a07927975636b341ca61f991df',
  'arm64': '8cd0a4d0cd8cd480be5731ac31f17038969a42d12add9feb6e031fd43d85bbae',
};

String singBoxZipName(String arch) {
  return 'sing-box-$singBoxPinnedVersion-windows-$arch.zip';
}

Uri singBoxZipUri(String arch) {
  return Uri.parse(
    'https://github.com/SagerNet/sing-box/releases/download/'
    'v$singBoxPinnedVersion/${singBoxZipName(arch)}',
  );
}

String singBoxWindowsArch() {
  return Abi.current() == Abi.windowsArm64 ? 'arm64' : 'amd64';
}

/// Where the managed download lands: the third [singBoxCandidates] entry, so
/// the runner picks it up with no change.
String singBoxManagedPath(String homeDir) {
  return p.join(homeDir, 'singbox', 'sing-box.exe');
}

class SingBoxBinaryException implements Exception {
  SingBoxBinaryException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef SingBoxProgress = void Function(int received, int? total);

typedef SingBoxRouteReporter = void Function(String label);

/// One way to reach the download host. A download tries its routes in
/// order until one delivers the file.
class SingBoxDownloadRoute {
  const SingBoxDownloadRoute(this.label, this.proxy);

  /// User-facing name of the route: 系统代理 / 核心代理 / 直连.
  final String label;

  /// The `findProxy` answer for this route, e.g. `PROXY 127.0.0.1:7890`.
  final String proxy;
}

const singBoxDirectRoute = SingBoxDownloadRoute('直连', 'DIRECT');

typedef SingBoxSystemProxyReader = String? Function();

typedef SingBoxAppProxyReader = String? Function(Uri url);

/// Turns a WinINET `ProxyServer` value into a `findProxy` answer. The value
/// is either one `host:port` for every protocol or `protocol=host:port`
/// pairs separated by `;`; the download is HTTPS, so an `https` pair wins,
/// then an `http` pair, then the bare form. Null when nothing is usable.
String? proxyRouteFromProxyServer(String? server) {
  final trimmed = server?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  String? bare;
  String? http;
  String? https;
  for (final part in trimmed.split(';')) {
    final entry = part.trim();
    if (entry.isEmpty) continue;
    final eq = entry.indexOf('=');
    if (eq < 0) {
      bare ??= entry;
      continue;
    }
    final value = entry.substring(eq + 1).trim();
    switch (entry.substring(0, eq).trim().toLowerCase()) {
      case 'https':
        https ??= value;
      case 'http':
        http ??= value;
    }
  }
  final host = https ?? http ?? bare;
  if (host == null) return null;
  final cleaned = host.replaceFirst(RegExp(r'^https?://'), '');
  return cleaned.isEmpty ? null : 'PROXY $cleaned';
}

/// The current user's Windows system proxy (WinINET) as a `findProxy`
/// answer; null off Windows, when the proxy is off, or when only a PAC
/// script is configured (dart:io cannot evaluate PAC).
String? readWindowsSystemProxyRoute() {
  if (!Platform.isWindows) return null;
  try {
    final key = CURRENT_USER.open(
      r'Software\Microsoft\Windows\CurrentVersion\Internet Settings',
    );
    try {
      if (key.getInt('ProxyEnable') != 1) return null;
      return proxyRouteFromProxyServer(key.getString('ProxyServer'));
    } finally {
      key.close();
    }
  } catch (_) {
    return null;
  }
}

/// The routes one download tries, best first: the Windows system proxy is
/// the machine-wide choice the user already made, the app core's own proxy
/// follows, and a direct attempt always closes the list. Duplicates and
/// empty answers drop out.
List<SingBoxDownloadRoute> singBoxDownloadRoutes({
  String? systemProxy,
  String? appProxy,
}) {
  final routes = <SingBoxDownloadRoute>[];
  void add(String label, String? proxy) {
    final value = proxy?.trim() ?? '';
    if (value.isEmpty || value == 'DIRECT') return;
    if (routes.any((route) => route.proxy == value)) return;
    routes.add(SingBoxDownloadRoute(label, value));
  }

  add('系统代理', systemProxy);
  add('核心代理', appProxy);
  routes.add(singBoxDirectRoute);
  return routes;
}

class _RouteFailure implements Exception {
  _RouteFailure(this.error);

  final Object error;
}

abstract class SingBoxDownloader {
  Future<void> download(
    Uri url,
    File target, {
    SingBoxProgress? onProgress,
    SingBoxRouteReporter? onRoute,
    SingBoxAppProxyReader? appProxyRoute,
  });
}

class HttpSingBoxDownloader implements SingBoxDownloader {
  HttpSingBoxDownloader({
    SingBoxSystemProxyReader? systemProxyRoute,
    this.stallTimeout = const Duration(seconds: 60),
  }) : _systemProxyRoute = systemProxyRoute ?? readWindowsSystemProxyRoute;

  final SingBoxSystemProxyReader _systemProxyRoute;

  /// A hop that delivers no bytes for this long counts as failed.
  final Duration stallTimeout;

  @override
  Future<void> download(
    Uri url,
    File target, {
    SingBoxProgress? onProgress,
    SingBoxRouteReporter? onRoute,
    SingBoxAppProxyReader? appProxyRoute,
  }) async {
    final routes = singBoxDownloadRoutes(
      systemProxy: _systemProxyRoute(),
      appProxy: appProxyRoute?.call(url),
    );
    for (final route in routes) {
      onRoute?.call(route.label);
      try {
        await _downloadVia(url, target, route.proxy, onProgress: onProgress);
        return;
      } on _RouteFailure {
        await _deleteQuietly(target);
      }
    }
    throw SingBoxBinaryException(
      '下载 sing-box 失败：已依次尝试'
      '${routes.map((route) => route.label).join('、')}，均未成功。'
      '请检查网络后重试。',
    );
  }

  Future<void> _downloadVia(
    Uri url,
    File target,
    String proxy, {
    SingBoxProgress? onProgress,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    client.userAgent = 'KFusion';
    client.findProxy = (_) => proxy;
    try {
      final request = await client.getUrl(url);
      final response = await request.close().timeout(stallTimeout);
      if (response.statusCode != HttpStatus.ok) {
        // The server answered, so the route works; hopping cannot fix this.
        throw SingBoxBinaryException(
          '下载 sing-box 失败：服务器返回 ${response.statusCode}。',
        );
      }
      final total = response.contentLength > 0 ? response.contentLength : null;
      var received = 0;
      final sink = target.openWrite();
      try {
        await for (final chunk in response.timeout(stallTimeout)) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    } on SingBoxBinaryException {
      rethrow;
    } catch (e) {
      throw _RouteFailure(e);
    } finally {
      // A timed-out hop leaves its request hanging; force the client shut
      // so the next route starts immediately.
      client.close(force: true);
    }
  }
}

bool _extractSingBoxExe(String zipPath, String targetPath) {
  final archive = ZipDecoder().decodeBytes(File(zipPath).readAsBytesSync());
  for (final file in archive) {
    if (p.posix.basename(file.name) != 'sing-box.exe') continue;
    final content = file.readBytes();
    if (content == null) return false;
    File(targetPath).writeAsBytesSync(content, flush: true);
    return true;
  }
  return false;
}

/// Finds an existing binary through [singBoxCandidates]; when none is
/// present, downloads the pinned official build, verifies its SHA-256 and
/// unpacks `sing-box.exe` into the support directory. Calls share one
/// in-flight attempt.
class SingBoxBinaryManager {
  SingBoxBinaryManager({
    SingBoxDownloader? downloader,
    bool Function(String path)? exists,
    String Function()? arch,
    Map<String, String> zipSha256 = singBoxZipSha256,
    Future<bool> Function(String zipPath, String targetPath)? extract,
    this.downloadTimeout = const Duration(minutes: 10),
  }) : downloader = downloader ?? HttpSingBoxDownloader(),
       _exists = exists,
       _arch = arch ?? singBoxWindowsArch,
       _zipSha256 = zipSha256,
       _extract = extract;

  final SingBoxDownloader downloader;
  final bool Function(String path)? _exists;
  final String Function() _arch;
  final Map<String, String> _zipSha256;
  final Future<bool> Function(String zipPath, String targetPath)? _extract;
  final Duration downloadTimeout;

  Future<String>? _inFlight;

  Future<String> ensure({
    required String executableDir,
    required String homeDir,
    String? storedPath,
    SingBoxProgress? onProgress,
    SingBoxRouteReporter? onRoute,
    SingBoxAppProxyReader? appProxyRoute,
  }) {
    final running = _inFlight;
    if (running != null) return running;
    late final Future<String> future;
    future =
        _ensure(
          executableDir: executableDir,
          homeDir: homeDir,
          storedPath: storedPath,
          onProgress: onProgress,
          onRoute: onRoute,
          appProxyRoute: appProxyRoute,
        ).whenComplete(() {
          if (identical(_inFlight, future)) _inFlight = null;
        });
    _inFlight = future;
    return future;
  }

  Future<String> _ensure({
    required String executableDir,
    required String homeDir,
    String? storedPath,
    SingBoxProgress? onProgress,
    SingBoxRouteReporter? onRoute,
    SingBoxAppProxyReader? appProxyRoute,
  }) async {
    final existing = findSingBoxBinary(
      singBoxCandidates(
        executableDir: executableDir,
        homeDir: homeDir,
        storedPath: storedPath,
      ),
      exists: _exists,
    );
    if (existing != null) return existing;
    final arch = _arch();
    final expected = _zipSha256[arch];
    if (expected == null) {
      throw SingBoxBinaryException('不支持的 Windows 架构：$arch。');
    }
    final dir = Directory(p.join(homeDir, 'singbox'));
    await dir.create(recursive: true);
    final zipFile = File(p.join(dir.path, singBoxZipName(arch)));
    final targetPath = singBoxManagedPath(homeDir);
    try {
      await downloader
          .download(
            singBoxZipUri(arch),
            zipFile,
            onProgress: onProgress,
            onRoute: onRoute,
            appProxyRoute: appProxyRoute,
          )
          .timeout(
            downloadTimeout,
            onTimeout: () {
              throw SingBoxBinaryException('下载 sing-box 超时，请检查网络后重试。');
            },
          );
    } on SingBoxBinaryException {
      rethrow;
    } catch (e) {
      throw SingBoxBinaryException('下载 sing-box 失败，请检查网络后重试。（$e）');
    }
    final digest = await sha256.bind(zipFile.openRead()).first;
    if (digest.toString() != expected) {
      await _deleteQuietly(zipFile);
      throw SingBoxBinaryException('下载的 sing-box 压缩包校验不符，已删除，请重试。');
    }
    final extract = _extract ?? _extractInIsolate;
    final tempExe = File('$targetPath.download');
    final extracted = await extract(zipFile.path, tempExe.path);
    if (!extracted || !tempExe.existsSync()) {
      await _deleteQuietly(tempExe);
      await _deleteQuietly(zipFile);
      throw SingBoxBinaryException('下载的 sing-box 压缩包里没有可用的 sing-box.exe。');
    }
    await tempExe.rename(targetPath);
    await _deleteQuietly(zipFile);
    return targetPath;
  }

  static Future<bool> _extractInIsolate(String zipPath, String targetPath) {
    return Isolate.run(() => _extractSingBoxExe(zipPath, targetPath));
  }
}

Future<void> _deleteQuietly(File file) async {
  try {
    await file.delete();
  } catch (_) {}
}

final singBoxBinaryManager = SingBoxBinaryManager();
