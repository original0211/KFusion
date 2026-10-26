@TestOn('vm')
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/core/singbox/singbox_binary.dart';
import 'package:path/path.dart' as p;

class _FakeDownloader implements SingBoxDownloader {
  _FakeDownloader(this.bytes, {this.error, this.delay = Duration.zero});

  final List<int>? bytes;
  final Exception? error;
  final Duration delay;
  var calls = 0;
  Uri? lastUrl;

  @override
  Future<void> download(
    Uri url,
    File target, {
    SingBoxProgress? onProgress,
    SingBoxRouteReporter? onRoute,
    SingBoxAppProxyReader? appProxyRoute,
  }) async {
    calls++;
    lastUrl = url;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    final failure = error;
    if (failure != null) throw failure;
    onProgress?.call(3, 6);
    await target.writeAsBytes(bytes!);
    onProgress?.call(6, 6);
  }
}

List<int> buildZip(Map<String, List<int>> entries) {
  final archive = Archive();
  for (final MapEntry(:key, :value) in entries.entries) {
    archive.addFile(ArchiveFile(key, value.length, value));
  }
  return ZipEncoder().encode(archive);
}

void main() {
  late Directory tempDir;
  late List<int> goodZip;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kfusion-singbox-bin');
    goodZip = buildZip({
      'sing-box-1.14.4-windows-amd64/sing-box.exe': 'fake-exe'.codeUnits,
      'sing-box-1.14.4-windows-amd64/LICENSE': 'license'.codeUnits,
    });
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  SingBoxBinaryManager manager({
    SingBoxDownloader? downloader,
    bool Function(String path)? exists,
    String? digestOverride,
  }) {
    return SingBoxBinaryManager(
      downloader: downloader ?? _FakeDownloader(goodZip),
      exists: exists ?? (_) => false,
      arch: () => 'amd64',
      zipSha256: {
        'amd64': digestOverride ?? sha256.convert(goodZip).toString(),
      },
    );
  }

  Future<String> ensure(SingBoxBinaryManager binaryManager) {
    return binaryManager.ensure(executableDir: '/app', homeDir: tempDir.path);
  }

  test('an existing candidate is returned without downloading', () async {
    final downloader = _FakeDownloader(goodZip);
    final exeSide = p.join('/app', 'sing-box.exe');
    final result = await ensure(
      manager(downloader: downloader, exists: (path) => path == exeSide),
    );
    expect(result, exeSide);
    expect(downloader.calls, 0);
  });

  test('downloads, verifies and unpacks into the support directory', () async {
    final downloader = _FakeDownloader(goodZip);
    final progress = <(int, int?)>[];
    final result = await manager(downloader: downloader).ensure(
      executableDir: '/app',
      homeDir: tempDir.path,
      onProgress: (received, total) => progress.add((received, total)),
    );
    expect(downloader.calls, 1);
    expect(downloader.lastUrl, singBoxZipUri('amd64'));
    expect(result, singBoxManagedPath(tempDir.path));
    expect(await File(result).readAsString(), 'fake-exe');
    expect(progress, [(3, 6), (6, 6)]);
    final zipFile = File(
      p.join(tempDir.path, 'singbox', singBoxZipName('amd64')),
    );
    expect(await zipFile.exists(), isFalse);
  });

  test('a checksum mismatch deletes the zip and fails', () async {
    final binaryManager = manager(digestOverride: '0' * 64);
    await expectLater(
      ensure(binaryManager),
      throwsA(isA<SingBoxBinaryException>()),
    );
    expect(await File(singBoxManagedPath(tempDir.path)).exists(), isFalse);
    final zipFile = File(
      p.join(tempDir.path, 'singbox', singBoxZipName('amd64')),
    );
    expect(await zipFile.exists(), isFalse);
  });

  test('a zip without sing-box.exe fails and installs nothing', () async {
    final zip = buildZip({'readme.txt': 'hello'.codeUnits});
    final binaryManager = SingBoxBinaryManager(
      downloader: _FakeDownloader(zip),
      exists: (_) => false,
      arch: () => 'amd64',
      zipSha256: {'amd64': sha256.convert(zip).toString()},
    );
    await expectLater(
      ensure(binaryManager),
      throwsA(isA<SingBoxBinaryException>()),
    );
    expect(await File(singBoxManagedPath(tempDir.path)).exists(), isFalse);
  });

  test('a downloader failure surfaces as a retryable exception', () async {
    final binaryManager = manager(
      downloader: _FakeDownloader(null, error: Exception('boom')),
    );
    await expectLater(
      ensure(binaryManager),
      throwsA(
        isA<SingBoxBinaryException>().having(
          (e) => e.message,
          'message',
          contains('下载 sing-box 失败'),
        ),
      ),
    );
    expect(await File(singBoxManagedPath(tempDir.path)).exists(), isFalse);
  });

  test('concurrent ensure calls share one download', () async {
    final downloader = _FakeDownloader(
      goodZip,
      delay: const Duration(milliseconds: 50),
    );
    final binaryManager = manager(downloader: downloader);
    final results = await Future.wait([
      ensure(binaryManager),
      ensure(binaryManager),
    ]);
    expect(downloader.calls, 1);
    expect(results[0], results[1]);
    expect(results[0], singBoxManagedPath(tempDir.path));
  });

  test('the pinned digests match the official asset names', () {
    expect(singBoxZipSha256.keys, containsAll(<String>['amd64', 'arm64']));
    for (final digest in singBoxZipSha256.values) {
      expect(digest, matches(RegExp(r'^[0-9a-f]{64}$')));
    }
    expect(
      singBoxZipUri('arm64').path,
      endsWith('sing-box-1.14.4-windows-arm64.zip'),
    );
  });

  group('proxyRouteFromProxyServer', () {
    test('parses a bare host:port for every protocol', () {
      expect(
        proxyRouteFromProxyServer('127.0.0.1:7890'),
        'PROXY 127.0.0.1:7890',
      );
    });

    test('prefers the https pair of a per-protocol value', () {
      expect(
        proxyRouteFromProxyServer('http=127.0.0.1:1080;https=127.0.0.1:7890'),
        'PROXY 127.0.0.1:7890',
      );
    });

    test('falls back to the http pair and strips a scheme', () {
      expect(
        proxyRouteFromProxyServer('http=http://127.0.0.1:1080'),
        'PROXY 127.0.0.1:1080',
      );
    });

    test('returns null for empty values (PAC-only setups included)', () {
      expect(proxyRouteFromProxyServer(null), isNull);
      expect(proxyRouteFromProxyServer('  '), isNull);
      expect(proxyRouteFromProxyServer('https='), isNull);
    });
  });

  group('singBoxDownloadRoutes', () {
    test('orders system proxy, app proxy, then direct', () {
      final routes = singBoxDownloadRoutes(
        systemProxy: 'PROXY 127.0.0.1:7890',
        appProxy: 'PROXY localhost:7891',
      );
      expect(routes.map((route) => route.label), ['系统代理', '核心代理', '直连']);
    });

    test('drops duplicates, DIRECT answers and empty values', () {
      final routes = singBoxDownloadRoutes(
        systemProxy: 'PROXY 127.0.0.1:7890',
        appProxy: 'PROXY 127.0.0.1:7890',
      );
      expect(routes.map((route) => route.label), ['系统代理', '直连']);
      expect(singBoxDownloadRoutes(systemProxy: null, appProxy: 'DIRECT'), [
        singBoxDirectRoute,
      ]);
    });
  });

  group('HttpSingBoxDownloader routes', () {
    late Directory dir;
    late HttpServer origin;
    late HttpServer proxy;
    var originHits = 0;
    var proxyHits = 0;

    Future<void> serveOrigin(void Function(HttpRequest request) respond) async {
      origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      origin.listen((request) {
        originHits++;
        respond(request);
      });
    }

    Future<void> serveProxy({bool hang = false}) async {
      proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      proxy.listen((request) async {
        proxyHits++;
        if (hang) return;
        final client = HttpClient()..findProxy = (_) => 'DIRECT';
        try {
          final upstream = await client.getUrl(request.uri);
          final response = await upstream.close();
          request.response.statusCode = response.statusCode;
          await response.pipe(request.response);
        } finally {
          client.close();
        }
      });
    }

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('kfusion-singbox-http');
      originHits = 0;
      proxyHits = 0;
    });

    tearDown(() async {
      await origin.close(force: true);
      await proxy.close(force: true);
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    void serveBytes(HttpRequest request) {
      request.response.write('zip-bytes');
      request.response.close();
    }

    HttpSingBoxDownloader downloader({String? systemProxy}) {
      return HttpSingBoxDownloader(
        systemProxyRoute: () => systemProxy,
        stallTimeout: const Duration(milliseconds: 500),
      );
    }

    test('goes through the system proxy when one is set', () async {
      await serveOrigin(serveBytes);
      await serveProxy();
      final routes = <String>[];
      final target = File(p.join(dir.path, 'out.zip'));
      await downloader(systemProxy: 'PROXY 127.0.0.1:${proxy.port}').download(
        Uri.parse('http://127.0.0.1:${origin.port}/file'),
        target,
        onRoute: routes.add,
        appProxyRoute: (_) => null,
      );
      expect(await target.readAsString(), 'zip-bytes');
      expect(proxyHits, 1);
      expect(routes, ['系统代理']);
    });

    test('falls back to direct when the system proxy is dead', () async {
      await serveOrigin(serveBytes);
      await serveProxy();
      final routes = <String>[];
      final target = File(p.join(dir.path, 'out.zip'));
      await downloader(systemProxy: 'PROXY 127.0.0.1:1').download(
        Uri.parse('http://127.0.0.1:${origin.port}/file'),
        target,
        onRoute: routes.add,
        appProxyRoute: (_) => null,
      );
      expect(await target.readAsString(), 'zip-bytes');
      expect(originHits, 1);
      expect(routes, ['系统代理', '直连']);
    });

    test('uses the app core route when no system proxy is set', () async {
      await serveOrigin(serveBytes);
      await serveProxy();
      final routes = <String>[];
      final target = File(p.join(dir.path, 'out.zip'));
      await downloader().download(
        Uri.parse('http://127.0.0.1:${origin.port}/file'),
        target,
        onRoute: routes.add,
        appProxyRoute: (_) => 'PROXY 127.0.0.1:${proxy.port}',
      );
      expect(await target.readAsString(), 'zip-bytes');
      expect(proxyHits, 1);
      expect(routes, ['核心代理']);
    });

    test('a stalled hop counts as failed and the next route runs', () async {
      await serveOrigin(serveBytes);
      await serveProxy(hang: true);
      final routes = <String>[];
      final target = File(p.join(dir.path, 'out.zip'));
      await downloader(systemProxy: 'PROXY 127.0.0.1:${proxy.port}').download(
        Uri.parse('http://127.0.0.1:${origin.port}/file'),
        target,
        onRoute: routes.add,
        appProxyRoute: (_) => null,
      );
      expect(await target.readAsString(), 'zip-bytes');
      expect(routes, ['系统代理', '直连']);
    });

    test('a server error does not hop to the next route', () async {
      await serveOrigin((request) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.close();
      });
      await serveProxy();
      final target = File(p.join(dir.path, 'out.zip'));
      await expectLater(
        downloader(systemProxy: 'PROXY 127.0.0.1:${proxy.port}').download(
          Uri.parse('http://127.0.0.1:${origin.port}/file'),
          target,
          appProxyRoute: (_) => null,
        ),
        throwsA(
          isA<SingBoxBinaryException>().having(
            (e) => e.message,
            'message',
            contains('服务器返回 404'),
          ),
        ),
      );
      expect(originHits, 1);
    });

    test('names every attempted route when all of them fail', () async {
      await serveOrigin(serveBytes);
      await serveProxy();
      final target = File(p.join(dir.path, 'out.zip'));
      await expectLater(
        downloader(systemProxy: 'PROXY 127.0.0.1:1').download(
          Uri.parse('http://127.0.0.1:1/file'),
          target,
          appProxyRoute: (_) => null,
        ),
        throwsA(
          isA<SingBoxBinaryException>().having(
            (e) => e.message,
            'message',
            allOf(contains('已依次尝试'), contains('系统代理'), contains('直连')),
          ),
        ),
      );
      expect(await target.exists(), isFalse);
    });
  });
}
