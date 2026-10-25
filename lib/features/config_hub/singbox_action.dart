import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:kfusion/common/common.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/core/singbox/singbox_binary.dart';
import 'package:kfusion/core/singbox/singbox_runner.dart';
import 'package:kfusion/features/config_hub/core_kind.dart';
import 'package:kfusion/features/config_hub/core_switch.dart';
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
    this.switchStage,
    this.switchTarget,
    this.switchFrom,
    this.failure,
    this.failedStage,
    this.restored = false,
    this.stageDetail = '',
    this.failureDetail = '',
  });

  final SingBoxState state;
  final String message;
  final int unsupportedCount;

  /// Stage of an in-flight core switch; null outside one.
  final CoreSwitchStage? switchStage;

  /// The core a switch is heading to, or the one the last switch wanted.
  final CoreKind? switchTarget;

  /// The core that ran before the last switch, when one did.
  final CoreKind? switchFrom;

  /// Why the last switch failed; null when it succeeded or none ran.
  final CoreSwitchFailure? failure;

  /// The stage the last switch failed in; null when preflight rejected
  /// it before anything was touched.
  final CoreSwitchStage? failedStage;

  /// After a failed switch, whether the previous core is running again.
  final bool restored;

  /// Live detail for the current stage, such as a download percent.
  final String stageDetail;

  /// The failing layer's own message, shown under the failure sentence.
  final String failureDetail;
}

const int singBoxMixedPort = 7890;
const int singBoxClashApiPort = 9091;

final singBoxActionProvider =
    AsyncNotifierProvider<SingBoxAction, SingBoxStatus>(SingBoxAction.new);

typedef _PreparedSingBox = ({SingBoxRenderResult rendered, String secret});

class SingBoxAction extends AsyncNotifier<SingBoxStatus> {
  SingBoxRunner? _runner;
  SingBoxClashApi? _api;
  var _switching = false;

  static const _stopTimeout = Duration(seconds: 20);
  // Above the plugin's 40s poll, so Dart acts on the service's own verdict.
  static const _startTimeout = Duration(seconds: 45);
  static const _checkTimeout = Duration(seconds: 35);
  static const _applyTimeout = Duration(seconds: 30);

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

  Future<void> start() async {
    if (state.value?.state == SingBoxState.running) {
      return;
    }
    await switchCore(CoreKind.singbox);
  }

  /// Makes [target] the running core on the current profile: the profile
  /// is rendered for the target, the running core stops, the target
  /// starts and takes the profile over, and a failure anywhere restores
  /// the core that ran before.
  Future<void> switchCore(CoreKind target) async {
    if (_switching || state.value?.state == SingBoxState.starting) {
      return;
    }
    _switching = true;
    final before = state.value;
    try {
      await _runSwitch(target);
    } catch (error) {
      commonPrint.log(
        'Core switch failed unexpectedly: $error',
        logLevel: LogLevel.error,
      );
      state = AsyncData(
        SingBoxStatus(
          state: before?.state == SingBoxState.starting
              ? SingBoxState.idle
              : before?.state ?? SingBoxState.idle,
          message: before?.message ?? '',
          switchTarget: target,
          failure: CoreSwitchFailure.unknown,
        ),
      );
    } finally {
      _switching = false;
    }
  }

  Future<void> _runSwitch(CoreKind target) async {
    final singBoxRunning = await _singBoxRunningNow();
    final CoreKind? runningCore = singBoxRunning
        ? CoreKind.singbox
        : ref.read(isStartProvider)
        ? CoreKind.mihomo
        : null;
    if (runningCore == target) {
      state = AsyncData(
        target == CoreKind.singbox
            ? SingBoxStatus(
                state: SingBoxState.running,
                message: _plainRunningMessage(),
              )
            : const SingBoxStatus(state: SingBoxState.idle),
      );
      return;
    }
    final original =
        runningCore ??
        ref.read(activeCoreKindProvider).value ??
        CoreKind.mihomo;

    int? profileId;
    _PreparedSingBox? prepared;

    void emitStage(CoreSwitchStage stage, {String detail = ''}) {
      state = AsyncData(
        SingBoxStatus(
          state: SingBoxState.starting,
          switchStage: stage,
          switchTarget: target,
          switchFrom: runningCore,
          stageDetail: detail,
        ),
      );
    }

    Future<CoreSwitchStepResult> preflight() async {
      const notRenderable = CoreSwitchStepResult(
        failure: CoreSwitchFailure.profileNotRenderable,
      );
      final profile = ref.read(currentProfileProvider);
      if (profile == null) {
        return const CoreSwitchStepResult(failure: CoreSwitchFailure.noProfile);
      }
      profileId = profile.id;
      final yamlText = await readTextFileTask(
        await appPath.getProfilePath(profile.id.toString()),
      );
      if (yamlText == null || yamlText.isEmpty) {
        return const CoreSwitchStepResult(
          failure: CoreSwitchFailure.profileUnreadable,
        );
      }
      if (target == CoreKind.mihomo) {
        try {
          final parsed = loadPlainYaml(yamlText);
          if (parsed is! Map || parsed.isEmpty) {
            return notRenderable;
          }
        } catch (_) {
          return notRenderable;
        }
        return const CoreSwitchStepResult.ok();
      }
      if (system.isAndroid) {
        if (singBoxService == null) {
          return const CoreSwitchStepResult(
            failure: CoreSwitchFailure.channelUnavailable,
          );
        }
      } else if (!system.isWindows) {
        return const CoreSwitchStepResult(
          failure: CoreSwitchFailure.platformUnsupported,
        );
      }
      final tunEnabled =
          system.isAndroid || await Preferences().getSingBoxTunEnabled();
      if (system.isWindows && tunEnabled && !await isWindowsAdmin()) {
        return const CoreSwitchStepResult(
          failure: CoreSwitchFailure.adminRequired,
        );
      }
      try {
        final clashMap = _asMap(loadPlainYaml(yamlText));
        if (clashMap.isEmpty) {
          return notRenderable;
        }
        final secret = generateSingBoxSecret();
        final rendered = renderSingBoxFromClash(
          clashMap,
          secret: secret,
          tunEnabled: tunEnabled,
          clashApiPort: singBoxClashApiPort,
          mixedPort: singBoxMixedPort,
        );
        if (!_hasUsableOutbound(rendered)) {
          return notRenderable;
        }
        prepared = (rendered: rendered, secret: secret);
      } catch (_) {
        return notRenderable;
      }
      if (system.isAndroid) {
        // Strictly checked before any core stops, not after.
        final ready = prepared;
        if (ready == null) {
          return const CoreSwitchStepResult(failure: CoreSwitchFailure.unknown);
        }
        try {
          final configPath = await _writeSingBoxConfig(ready.rendered);
          final checkError = await singBoxService!
              .checkConfig(configPath)
              .timeout(_checkTimeout);
          if (checkError.isNotEmpty) {
            return CoreSwitchStepResult(
              failure: CoreSwitchFailure.profileNotRenderable,
              detail: checkError,
            );
          }
        } catch (_) {
          return const CoreSwitchStepResult(
            failure: CoreSwitchFailure.channelUnavailable,
          );
        }
      }
      return const CoreSwitchStepResult.ok();
    }

    Future<bool> stopCurrent() async {
      if (runningCore == CoreKind.singbox) {
        return _boundedBool(_stopSingBoxMechanics());
      }
      if (runningCore == CoreKind.mihomo) {
        try {
          await ensureMihomoStopped(
            mihomoRunning: () => ref.read(isStartProvider),
            stopMihomo: () async {
              try {
                return await ref
                    .read(setupActionProvider.notifier)
                    .setRunning(false);
              } catch (error) {
                commonPrint.log(
                  'Unable to stop mihomo during a core switch: $error',
                  logLevel: LogLevel.error,
                );
                return false;
              }
            },
          ).timeout(_stopTimeout);
          return true;
        } catch (_) {
          return false;
        }
      }
      return true;
    }

    Future<CoreSwitchStepResult> startTarget() async {
      if (target == CoreKind.singbox) {
        final ready = prepared;
        if (ready == null) {
          return const CoreSwitchStepResult(failure: CoreSwitchFailure.unknown);
        }
        return _startSingBoxMechanics(
          ready,
          onProgress: (detail) =>
              emitStage(CoreSwitchStage.starting, detail: detail),
        );
      }
      try {
        final started = await ref
            .read(setupActionProvider.notifier)
            .setRunning(true)
            .timeout(_startTimeout);
        if (!started || !ref.read(isStartProvider)) {
          return const CoreSwitchStepResult(
            failure: CoreSwitchFailure.startFailed,
          );
        }
        return const CoreSwitchStepResult.ok();
      } catch (_) {
        return const CoreSwitchStepResult(
          failure: CoreSwitchFailure.startFailed,
        );
      }
    }

    Future<CoreSwitchStepResult> applyTarget() async {
      const applyFailed = CoreSwitchStepResult(
        failure: CoreSwitchFailure.applyFailed,
      );
      if (target == CoreKind.singbox) {
        if (!system.isWindows) {
          return const CoreSwitchStepResult.ok();
        }
        try {
          await systemProxyQueue?.apply(
            const ProxyState(
              isStart: true,
              systemProxy: true,
              bassDomain: [],
              port: singBoxMixedPort,
            ),
          );
          return const CoreSwitchStepResult.ok();
        } catch (_) {
          return applyFailed;
        }
      }
      try {
        final applied = await ref
            .read(setupActionProvider.notifier)
            .applyProfile(force: true)
            .timeout(_applyTimeout);
        return applied ? const CoreSwitchStepResult.ok() : applyFailed;
      } catch (_) {
        return applyFailed;
      }
    }

    Future<bool> restoreOriginal() async {
      if (target == CoreKind.singbox) {
        if (await _singBoxRunningNow()) {
          await _boundedBool(_stopSingBoxMechanics());
        }
      } else if (ref.read(isStartProvider)) {
        try {
          await ref
              .read(setupActionProvider.notifier)
              .setRunning(false)
              .timeout(_stopTimeout);
        } catch (_) {}
      }
      if (runningCore == null) {
        return true;
      }
      if (original == CoreKind.mihomo) {
        if (ref.read(isStartProvider)) {
          return true;
        }
        try {
          final started = await ref
              .read(setupActionProvider.notifier)
              .setRunning(true)
              .timeout(_startTimeout);
          return started && ref.read(isStartProvider);
        } catch (_) {
          return false;
        }
      }
      if (await _singBoxRunningNow()) {
        return true;
      }
      final ready = prepared ?? await _prepareSingBox();
      if (ready == null) {
        return false;
      }
      final startResult = await _startSingBoxMechanics(ready);
      if (startResult.failure != null) {
        return false;
      }
      if (system.isWindows) {
        try {
          await systemProxyQueue?.apply(
            const ProxyState(
              isStart: true,
              systemProxy: true,
              bassDomain: [],
              port: singBoxMixedPort,
            ),
          );
        } catch (_) {
          return false;
        }
      }
      return true;
    }

    final outcome = await runCoreSwitch(
      preflight: preflight,
      stopCurrent: stopCurrent,
      startTarget: startTarget,
      applyTarget: applyTarget,
      restoreOriginal: restoreOriginal,
      onStage: emitStage,
    );

    if (outcome.succeeded) {
      await ref.read(activeCoreKindProvider.notifier).set(target);
      final id = profileId;
      if (id != null) {
        await ref.read(coreKindsProvider.notifier).setKind(id, target);
      }
      final ready = prepared;
      state = AsyncData(
        target == CoreKind.singbox && ready != null
            ? SingBoxStatus(
                state: SingBoxState.running,
                message: _runningMessage(ready.rendered),
                unsupportedCount: ready.rendered.unsupported.length,
              )
            : const SingBoxStatus(state: SingBoxState.idle),
      );
      return;
    }

    final singBoxNow = await _singBoxRunningNow();
    state = AsyncData(
      SingBoxStatus(
        state: singBoxNow ? SingBoxState.running : SingBoxState.idle,
        message: singBoxNow ? _plainRunningMessage() : '',
        switchTarget: target,
        switchFrom: runningCore,
        failure: outcome.failure,
        failedStage: outcome.failedStage,
        restored: outcome.restored,
        failureDetail: outcome.detail,
      ),
    );
  }

  Future<_PreparedSingBox?> _prepareSingBox() async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) {
      return null;
    }
    final yamlText = await readTextFileTask(
      await appPath.getProfilePath(profile.id.toString()),
    );
    if (yamlText == null || yamlText.isEmpty) {
      return null;
    }
    try {
      final clashMap = _asMap(loadPlainYaml(yamlText));
      if (clashMap.isEmpty) {
        return null;
      }
      final secret = generateSingBoxSecret();
      final rendered = renderSingBoxFromClash(
        clashMap,
        secret: secret,
        tunEnabled:
            system.isAndroid || await Preferences().getSingBoxTunEnabled(),
        clashApiPort: singBoxClashApiPort,
        mixedPort: singBoxMixedPort,
      );
      return (rendered: rendered, secret: secret);
    } catch (_) {
      return null;
    }
  }

  bool _hasUsableOutbound(SingBoxRenderResult rendered) {
    final endpoints = rendered.config['endpoints'];
    if (endpoints is List && endpoints.isNotEmpty) {
      return true;
    }
    final outbounds = rendered.config['outbounds'];
    if (outbounds is! List) {
      return false;
    }
    return outbounds.any(
      (outbound) =>
          outbound is Map &&
          outbound['type'] != 'direct' &&
          outbound['type'] != 'block',
    );
  }

  Future<bool> _singBoxRunningNow() async {
    if (system.isAndroid) {
      try {
        return await singBoxService?.isRunning() ??
            state.value?.state == SingBoxState.running;
      } catch (_) {
        return state.value?.state == SingBoxState.running;
      }
    }
    return _runner?.isRunning ?? false;
  }

  Future<bool> _boundedBool(Future<bool> future) async {
    try {
      return await future.timeout(_stopTimeout);
    } catch (_) {
      return false;
    }
  }

  String _plainRunningMessage() {
    return system.isAndroid
        ? 'sing-box 运行中（Android TUN）'
        : 'sing-box 运行中，系统代理 127.0.0.1:$singBoxMixedPort';
  }

  String _runningMessage(SingBoxRenderResult rendered) {
    final unsupportedNote = rendered.unsupported.isEmpty
        ? ''
        : '（${rendered.unsupported.length} 条规则或节点未翻译，见导出说明）';
    return system.isAndroid
        ? 'sing-box 运行中（Android TUN，面板 127.0.0.1:$singBoxClashApiPort）$unsupportedNote'
        : 'sing-box 运行中，系统代理 127.0.0.1:$singBoxMixedPort$unsupportedNote';
  }

  Future<String> _writeSingBoxConfig(SingBoxRenderResult rendered) async {
    final homeDir = await appPath.homeDirPath;
    final configDir = Directory('$homeDir${Platform.pathSeparator}singbox');
    await configDir.create(recursive: true);
    final configFile = File(
      '${configDir.path}${Platform.pathSeparator}config.json',
    );
    await configFile.writeAsString(jsonEncode(rendered.config));
    return configFile.path;
  }

  /// Starts the sing-box runtime on a prepared render; on Windows this is
  /// also where the binary is fetched, with progress going to [onProgress].
  Future<CoreSwitchStepResult> _startSingBoxMechanics(
    _PreparedSingBox prepared, {
    void Function(String detail)? onProgress,
  }) async {
    if (system.isAndroid) {
      final service = singBoxService;
      if (service == null) {
        return const CoreSwitchStepResult(
          failure: CoreSwitchFailure.channelUnavailable,
        );
      }
      String startError;
      try {
        final configPath = await _writeSingBoxConfig(prepared.rendered);
        startError = await service.start(configPath).timeout(_startTimeout);
      } catch (_) {
        return const CoreSwitchStepResult(
          failure: CoreSwitchFailure.startFailed,
        );
      }
      if (startError.isNotEmpty) {
        return CoreSwitchStepResult(
          failure: CoreSwitchFailure.startFailed,
          detail: startError,
        );
      }
      _api = SingBoxClashApi(
        port: singBoxClashApiPort,
        secret: prepared.secret,
      );
      // RUNNING alone is not readiness; the panel API has to answer.
      final probeDetail = await waitForSingBoxApi(() => _api!.getProxies());
      if (probeDetail != null) {
        return CoreSwitchStepResult(
          failure: CoreSwitchFailure.startFailed,
          detail: probeDetail,
        );
      }
      return const CoreSwitchStepResult.ok();
    }
    if (!system.isWindows) {
      return const CoreSwitchStepResult(
        failure: CoreSwitchFailure.platformUnsupported,
      );
    }
    try {
      final homeDir = await appPath.homeDirPath;
      final stored = await Preferences().getSingBoxBinaryPath();
      var lastPercent = -1;
      String? downloadRoute;
      final binary = await singBoxBinaryManager.ensure(
        executableDir: appPath.executableDirPath,
        homeDir: homeDir,
        storedPath: stored,
        appProxyRoute: (url) =>
            FlClashHttpOverrides.findProxyForReader(ref.read, url),
        onRoute: (label) => downloadRoute = label,
        onProgress: (received, total) {
          if (total == null || onProgress == null) return;
          final percent = received * 100 ~/ total;
          if (percent == lastPercent) return;
          lastPercent = percent;
          final route = downloadRoute;
          onProgress(route == null ? '$percent%' : '$percent% · $route');
        },
      );
      final configDir = Directory('$homeDir${Platform.pathSeparator}singbox');
      final configPath =
          '${configDir.path}${Platform.pathSeparator}config.json';
      // A leftover process would answer probes with a stale secret.
      await reclaimOrphanedSingBoxProcesses(
        executable: binary,
        configPath: configPath,
      );
      if (!await CoreSwitch().awaitPortFree(singBoxMixedPort)) {
        return const CoreSwitchStepResult(
          failure: CoreSwitchFailure.startFailed,
          detail: '端口 $singBoxMixedPort 仍被其他程序占用，sing-box 未启动',
        );
      }
      final runner = SingBoxRunner(
        launcher: IoProcessLauncher(),
        onCrash: (code, tail) {
          unawaited(_handleCrash(code, tail));
        },
      );
      final result = await runner.start(
        executable: binary,
        config: prepared.rendered.config,
        configDir: configDir,
        apiPort: singBoxClashApiPort,
        secret: prepared.secret,
      );
      if (!result.ok) {
        final tail = result.tailLines.isEmpty ? '' : result.tailLines.last;
        return CoreSwitchStepResult(
          failure: CoreSwitchFailure.startFailed,
          detail: [
            result.message,
            tail,
          ].where((part) => part.isNotEmpty).join(' · '),
        );
      }
      _runner = runner;
      _api = SingBoxClashApi(
        port: singBoxClashApiPort,
        secret: prepared.secret,
      );
      return const CoreSwitchStepResult.ok();
    } on SingBoxBinaryException catch (error) {
      return CoreSwitchStepResult(
        failure: CoreSwitchFailure.binaryUnavailable,
        detail: error.message,
      );
    } catch (_) {
      return const CoreSwitchStepResult(failure: CoreSwitchFailure.startFailed);
    }
  }

  /// Stops the sing-box runtime without touching status or the active
  /// kind; both stop attempts run even when the first one fails.
  Future<bool> _stopSingBoxMechanics() async {
    var stopped = true;
    if (system.isAndroid) {
      try {
        await singBoxService?.stop();
      } catch (_) {
        stopped = false;
      }
      _api = null;
      return stopped;
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
    } catch (_) {
      stopped = false;
    }
    try {
      await _runner?.stop();
    } catch (_) {
      stopped = false;
    }
    _runner = null;
    _api = null;
    return stopped;
  }

  Future<void> stop() async {
    await _stopSingBoxMechanics();
    await ref.read(activeCoreKindProvider.notifier).set(CoreKind.mihomo);
    state = const AsyncData(SingBoxStatus(state: SingBoxState.idle));
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

/// Stops a running mihomo through the run-state chain before a sing-box start.
Future<void> ensureMihomoStopped({
  required bool Function() mihomoRunning,
  required Future<bool> Function() stopMihomo,
}) async {
  if (!mihomoRunning()) {
    return;
  }
  if (!await stopMihomo()) {
    throw StateError('mihomo 未能停止，sing-box 未启动，避免双核心同时运行。');
  }
}

/// Polls [probe] until it answers; on timeout, the last error's text.
Future<String?> waitForSingBoxApi(
  Future<void> Function() probe, {
  Duration timeout = const Duration(seconds: 10),
  Duration interval = const Duration(milliseconds: 500),
  Future<void> Function(Duration duration)? pause,
}) async {
  final deadline = DateTime.now().add(timeout);
  Object? lastError;
  while (true) {
    try {
      await probe();
      return null;
    } catch (error) {
      lastError = error;
    }
    if (!DateTime.now().isBefore(deadline)) {
      return 'sing-box 已启动，但面板接口未响应（$lastError）';
    }
    await (pause?.call(interval) ?? Future<void>.delayed(interval));
  }
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
