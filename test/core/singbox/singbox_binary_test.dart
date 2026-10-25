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
}
