import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

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

abstract class SingBoxDownloader {
  Future<void> download(Uri url, File target, {SingBoxProgress? onProgress});
}

class HttpSingBoxDownloader implements SingBoxDownloader {
  @override
  Future<void> download(
    Uri url,
    File target, {
    SingBoxProgress? onProgress,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    client.userAgent = 'KFusion';
    try {
      final request = await client.getUrl(url);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw SingBoxBinaryException(
          '下载 sing-box 失败：服务器返回 ${response.statusCode}。',
        );
      }
      final total = response.contentLength > 0 ? response.contentLength : null;
      var received = 0;
      final sink = target.openWrite();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
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
          .download(singBoxZipUri(arch), zipFile, onProgress: onProgress)
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

  static Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } catch (_) {}
  }
}

final singBoxBinaryManager = SingBoxBinaryManager();
