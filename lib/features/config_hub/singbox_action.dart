import 'dart:async';
import 'dart:io';

import 'package:kfusion/common/common.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/core/singbox/singbox_runner.dart';
import 'package:kfusion/features/config_hub/core_kind.dart';
import 'package:kfusion/features/config_hub/singbox_render.dart';
import 'package:kfusion/models/models.dart';
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
  Future<SingBoxStatus> build() {
    return Future.value(const SingBoxStatus(state: SingBoxState.idle));
  }

  SingBoxClashApi? get api => _api;

  Future<void> start() async {
    if (!system.isWindows) {
      state = const AsyncData(
        SingBoxStatus(
          state: SingBoxState.error,
          message: 'Android 的 sing-box 运行时待 P3 接入，本轮仅支持导出配置。',
        ),
      );
      return;
    }
    state = const AsyncData(SingBoxStatus(state: SingBoxState.starting));
    try {
      final profile = ref.read(currentProfileProvider);
      if (profile == null) {
        throw StateError('没有选中的配置。');
      }
      final kind = ref.read(coreKindsProvider).value?[profile.id];
      if (kind != CoreKind.singbox) {
        throw StateError('当前配置的核心是 mihomo，请先在配置编辑中切换为 sing-box。');
      }
      if (ref.read(coreStatusProvider) == CoreStatus.connected) {
        throw StateError('mihomo 正在运行，请先停止 mihomo 再启动 sing-box。');
      }
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
      final yamlText = await readTextFileTask(
        await appPath.getProfilePath(profile.id.toString()),
      );
      if (yamlText == null || yamlText.isEmpty) {
        throw StateError('配置内容为空。');
      }
      final clashMap = _asMap(loadPlainYaml(yamlText));
      final secret = generateSingBoxSecret();
      final SingBoxRenderResult rendered = renderSingBoxFromClash(
        clashMap,
        secret: secret,
        tunEnabled: tunEnabled,
        clashApiPort: singBoxClashApiPort,
        mixedPort: singBoxMixedPort,
      );
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

  Future<void> stop() async {
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
