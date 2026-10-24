import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:kfusion/common/common.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/core/singbox/singbox_runner.dart';
import 'package:kfusion/features/config_hub/core_kind.dart';
import 'package:kfusion/features/config_hub/singbox_render.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/plugins/singbox.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SingBoxState { idle, starting, running, error }

class SingBoxStatus {
  const SingBoxStatus({
    required this.state,
    this.message = '',
    this.unsupportedCount = 0,
  });

  final SingBoxState state;
  final String message;
  final int unsupportedCount;
}

const int singBoxMixedPort = 7890;
const int singBoxClashApiPort = 9091;

final singBoxActionProvider =
    AsyncNotifierProvider<SingBoxAction, SingBoxStatus>(SingBoxAction.new);

class SingBoxAction extends AsyncNotifier<SingBoxStatus> {
  SingBoxRunner? _runner;
  SingBoxClashApi? _api;

  @override
  Future<SingBoxStatus> build() async {
    if (system.isAndroid) {
      final running = await singBoxService?.isRunning() ?? false;
      if (running) {
        return const SingBoxStatus(
          state: SingBoxState.running,
          message: 'sing-box 运行中（Android TUN）',
        );
      }
    }
    return const SingBoxStatus(state: SingBoxState.idle);
  }

  SingBoxClashApi? get api => _api;

  Future<({SingBoxRenderResult rendered, String secret})>
  _renderCurrentProfile({required bool tunEnabled}) async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) {
      throw StateError('没有选中的配置。');
    }
    final kind = ref.read(coreKindsProvider).value?[profile.id];
    if (kind != CoreKind.singbox) {
      throw StateError('当前配置的核心是 mihomo，请先在配置编辑中切换为 sing-box。');
    }
    final yamlText = await readTextFileTask(
      await appPath.getProfilePath(profile.id.toString()),
    );
    if (yamlText == null || yamlText.isEmpty) {
      throw StateError('配置内容为空。');
    }
    final clashMap = _asMap(loadPlainYaml(yamlText));
    final secret = generateSingBoxSecret();
    final rendered = renderSingBoxFromClash(
      clashMap,
      secret: secret,
      tunEnabled: tunEnabled,
      clashApiPort: singBoxClashApiPort,
      mixedPort: singBoxMixedPort,
    );
    return (rendered: rendered, secret: secret);
  }

  Future<void> start() async {
    state = const AsyncData(SingBoxStatus(state: SingBoxState.starting));
    if (system.isAndroid) {
      await _startAndroid();
      return;
    }
    if (!system.isWindows) {
      state = const AsyncData(
        SingBoxStatus(
          state: SingBoxState.error,
          message: '当前平台暂不支持 sing-box 运行时。',
        ),
      );
      return;
    }
    try {
      final homeDir = await appPath.homeDirPath;
      final stored = await Preferences().getSingBoxBinaryPath();
      final binary = findSingBoxBinary(
        singBoxCandidates(
          executableDir: appPath.executableDirPath,
          homeDir: homeDir,
          storedPath: stored,
        ),
      );
      if (binary == null) {
        throw StateError('未找到 sing-box 二进制，见 tools/singbox/README.md。');
      }
      final tunEnabled = await Preferences().getSingBoxTunEnabled();
      if (tunEnabled && !await isWindowsAdmin()) {
        throw StateError('开启 TUN 需要管理员权限，当前不是管理员，已拒绝启动。');
      }
      final (:rendered, :secret) = await _renderCurrentProfile(
        tunEnabled: tunEnabled,
      );
      if (ref.read(coreStatusProvider) == CoreStatus.connected) {
        throw StateError('mihomo 正在运行，请先停止 mihomo 再启动 sing-box。');
      }
      final configDir = Directory('$homeDir${Platform.pathSeparator}singbox');
      final runner = SingBoxRunner(
        launcher: IoProcessLauncher(),
        onCrash: (code, tail) {
          unawaited(_handleCrash(code, tail));
        },
      );
      final result = await runner.start(
        executable: binary,
        config: rendered.config,
        configDir: configDir,
        apiPort: singBoxClashApiPort,
        secret: secret,
      );
      if (!result.ok) {
        throw StateError(result.message);
      }
      _runner = runner;
      _api = SingBoxClashApi(port: singBoxClashApiPort, secret: secret);
      await systemProxyQueue?.apply(
        const ProxyState(
          isStart: true,
          systemProxy: true,
          bassDomain: [],
          port: singBoxMixedPort,
        ),
      );
      await ref.read(activeCoreKindProvider.notifier).set(CoreKind.singbox);
      final unsupportedNote = rendered.unsupported.isEmpty
          ? ''
          : '（${rendered.unsupported.length} 条规则或节点未翻译，见导出说明）';
      state = AsyncData(
        SingBoxStatus(
          state: SingBoxState.running,
          message:
              'sing-box 运行中，系统代理 127.0.0.1:$singBoxMixedPort$unsupportedNote',
          unsupportedCount: rendered.unsupported.length,
        ),
      );
    } catch (e) {
      state = AsyncData(
        SingBoxStatus(state: SingBoxState.error, message: e.toString()),
      );
    }
  }

  Future<void> _startAndroid() async {
    try {
      final service = singBoxService;
      if (service == null) {
        throw StateError('sing-box 方法通道不可用。');
      }
      final (:rendered, :secret) = await _renderCurrentProfile(
        tunEnabled: true,
      );
      if (ref.read(coreStatusProvider) == CoreStatus.connected) {
        await ref.read(coreHandlerProvider).stop();
        final stopped = await waitForValue<CoreStatus>(
          read: () async => ref.read(coreStatusProvider),
          target: CoreStatus.disconnected,
        );
        if (!stopped) {
          throw StateError('mihomo 未能停止，sing-box 未启动，避免双核心同时运行。');
        }
      }
      final homeDir = await appPath.homeDirPath;
      final configDir = Directory('$homeDir${Platform.pathSeparator}singbox');
      await configDir.create(recursive: true);
      final configFile = File(
        '${configDir.path}${Platform.pathSeparator}config.json',
      );
      await configFile.writeAsString(jsonEncode(rendered.config));
      final error = await service.start(configFile.path);
      if (error.isNotEmpty) {
        throw StateError(error);
      }
      _api = SingBoxClashApi(port: singBoxClashApiPort, secret: secret);
      await ref.read(activeCoreKindProvider.notifier).set(CoreKind.singbox);
      final unsupportedNote = rendered.unsupported.isEmpty
          ? ''
          : '（${rendered.unsupported.length} 条规则或节点未翻译，见导出说明）';
      state = AsyncData(
        SingBoxStatus(
          state: SingBoxState.running,
          message:
              'sing-box 运行中（Android TUN，面板 127.0.0.1:$singBoxClashApiPort）$unsupportedNote',
          unsupportedCount: rendered.unsupported.length,
        ),
      );
    } catch (e) {
      state = AsyncData(
        SingBoxStatus(state: SingBoxState.error, message: e.toString()),
      );
    }
  }

  Future<void> stop() async {
    if (system.isAndroid) {
      try {
        await singBoxService?.stop();
      } finally {
        _api = null;
        await ref.read(activeCoreKindProvider.notifier).set(CoreKind.mihomo);
        state = const AsyncData(SingBoxStatus(state: SingBoxState.idle));
      }
      return;
    }
    try {
      await systemProxyQueue?.apply(
        const ProxyState(
          isStart: false,
          systemProxy: false,
          bassDomain: [],
          port: singBoxMixedPort,
        ),
      );
      await _runner?.stop();
    } finally {
      _runner = null;
      _api = null;
      await ref.read(activeCoreKindProvider.notifier).set(CoreKind.mihomo);
      state = const AsyncData(SingBoxStatus(state: SingBoxState.idle));
    }
  }

  Future<void> _handleCrash(int code, List<String> tail) async {
    _runner = null;
    _api = null;
    await systemProxyQueue?.apply(
      const ProxyState(
        isStart: false,
        systemProxy: false,
        bassDomain: [],
        port: singBoxMixedPort,
      ),
    );
    await ref.read(activeCoreKindProvider.notifier).set(CoreKind.mihomo);
    state = AsyncData(
      SingBoxStatus(
        state: SingBoxState.error,
        message: 'sing-box 意外退出（退出码 $code）：${tail.isEmpty ? '无日志' : tail.last}',
      ),
    );
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map) {
    return {
      for (final MapEntry(:key, :value) in value.entries) key.toString(): value,
    };
  }
  return const {};
}

/// Polls [read] until it yields [target]; gives up after [timeout].
Future<bool> waitForValue<T>({
  required Future<T> Function() read,
  required T target,
  Duration timeout = const Duration(seconds: 15),
  Duration interval = const Duration(milliseconds: 200),
  Future<void> Function(Duration duration)? pause,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    if (await read() == target) {
      return true;
    }
    if (!DateTime.now().isBefore(deadline)) {
      return false;
    }
    await (pause?.call(interval) ?? Future<void>.delayed(interval));
  }
}
