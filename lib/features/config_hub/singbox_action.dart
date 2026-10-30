import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:kfusion/common/common.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/core/singbox/singbox_binary.dart';
import 'package:kfusion/core/singbox/singbox_runner.dart';
import 'package:kfusion/features/config_hub/core_kind.dart';
import 'package:kfusion/features/config_hub/core_switch.dart';
import 'package:kfusion/features/config_hub/singbox_degradations.dart';
import 'package:kfusion/features/config_hub/singbox_native.dart';
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

/// A profile made ready for the kernel: a rendered config, or a
/// native one fed verbatim with its own declared panel endpoint.
typedef _PreparedSingBox = ({
  SingBoxRenderResult? rendered,
  String? nativeText,
  String secret,
  int apiPort,
  int mixedPort,
});

class SingBoxAction extends AsyncNotifier<SingBoxStatus> {
  SingBoxRunner? _runner;
  SingBoxClashApi? _api;
  var _switching = false;

  /// The mixed port the running config actually bound.
  var _appliedMixedPort = singBoxMixedPort;

  static const _stopTimeout = Duration(seconds: 20);
  static const _startTimeout = Duration(seconds: 45);
  // Above the plugin's 90s poll, so Dart acts on the service's own verdict.
  static const _singBoxStartTimeout = Duration(seconds: 95);
  // Covers the plugin's two 30s check attempts plus intent overhead.
  static const _checkTimeout = Duration(seconds: 75);
  static const _applyTimeout = Duration(seconds: 30);

  @override
  Future<SingBoxStatus> build() async {
    if (system.isWindows) {
      unawaited(_reclaimStartupOrphans());
    }
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
        return mihomoProfileVerdict(yamlText);
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
      if (isNativeSingBoxConfig(yamlText)) {
        final native = prepareNativeSingBox(yamlText);
        final problem = native.problem;
        if (problem != null) {
          return CoreSwitchStepResult(
            failure: CoreSwitchFailure.profileNotRenderable,
            detail: problem,
          );
        }
        final doc = decodeSingBoxConfig(yamlText);
        if (system.isWindows &&
            doc != null &&
            nativeSingBoxUsesTun(doc) &&
            !await isWindowsAdmin()) {
          return const CoreSwitchStepResult(
            failure: CoreSwitchFailure.adminRequired,
          );
        }
        prepared = native.prepared;
      } else {
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
            return const CoreSwitchStepResult(
              failure: CoreSwitchFailure.profileNotRenderable,
              detail: '配置内容为空或不是可识别的 Clash 配置',
            );
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
            return CoreSwitchStepResult(
              failure: CoreSwitchFailure.profileNotRenderable,
              detail: singBoxNoUsableOutboundDetail(rendered.unsupported),
            );
          }
          prepared = (
            rendered: rendered,
            nativeText: null,
            secret: secret,
            apiPort: singBoxClashApiPort,
            mixedPort: singBoxMixedPort,
          );
        } catch (error) {
          // An unexpected throw is not a verdict on the profile, so the
          // card stays bare and the error lands in the log instead.
          commonPrint.log(
            'sing-box render failed during preflight: $error',
            logLevel: LogLevel.error,
          );
          return notRenderable;
        }
      }
      if (system.isAndroid) {
        // Strictly checked before any core stops, not after.
        final ready = prepared;
        if (ready == null) {
          return const CoreSwitchStepResult(failure: CoreSwitchFailure.unknown);
        }
        try {
          final configPath = await _writePreparedConfig(ready);
          final checkError = await singBoxService!
              .checkConfig(configPath)
              .timeout(_checkTimeout);
          final outcome = singBoxCheckOutcome(checkError);
          if (outcome.failure != null) {
            return outcome;
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
        return _boundedBool(() async {
          if (!await _stopSingBoxMechanics()) {
            return false;
          }
          if (!system.isWindows) {
            return true;
          }
          return CoreSwitch(
            portWaitTimeout: const Duration(seconds: 5),
          ).awaitPortFree(_appliedMixedPort);
        }());
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
            verifyStopped: () async {
              final settled = await waitForValue(
                read: () async => ref.read(isStartProvider),
                target: false,
                timeout: const Duration(seconds: 5),
                interval: const Duration(milliseconds: 200),
              );
              if (!settled) {
                return false;
              }
              return CoreSwitch(
                portWaitTimeout: const Duration(seconds: 5),
              ).awaitPortFree(prepared?.mixedPort ?? singBoxMixedPort);
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
            ProxyState(
              isStart: true,
              systemProxy: true,
              bassDomain: const [],
              port: prepared?.mixedPort ?? singBoxMixedPort,
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
            ProxyState(
              isStart: true,
              systemProxy: true,
              bassDomain: const [],
              port: ready.mixedPort,
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
                message: _runningMessage(ready),
                unsupportedCount: ready.rendered?.unsupported.length ?? 0,
              )
            : const SingBoxStatus(state: SingBoxState.idle),
      );
      if (target == CoreKind.singbox && ready != null && id != null) {
        final store = ref.read(singBoxDegradationStoreProvider);
        final rendered = ready.rendered;
        if (rendered != null) {
          await store.write(id, rendered.degradations);
        } else {
          await store.writeNative(id);
        }
        ref.invalidate(profileDegradationsProvider(id));
      }
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
    if (isNativeSingBoxConfig(yamlText)) {
      return prepareNativeSingBox(yamlText).prepared;
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
      return (
        rendered: rendered,
        nativeText: null,
        secret: secret,
        apiPort: singBoxClashApiPort,
        mixedPort: singBoxMixedPort,
      );
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

  String _runningMessage(_PreparedSingBox ready) {
    final rendered = ready.rendered;
    if (rendered == null) {
      return system.isAndroid
          ? 'sing-box 运行中（Android TUN，原生配置直通，面板 127.0.0.1:${ready.apiPort}）'
          : 'sing-box 运行中，系统代理 127.0.0.1:${ready.mixedPort}（原生配置直通）';
    }
    final unsupportedNote = rendered.unsupported.isEmpty
        ? ''
        : '（${rendered.unsupported.length} 条规则或节点未翻译，见导出说明）';
    return system.isAndroid
        ? 'sing-box 运行中（Android TUN，面板 127.0.0.1:$singBoxClashApiPort）$unsupportedNote'
        : 'sing-box 运行中，系统代理 127.0.0.1:$singBoxMixedPort$unsupportedNote';
  }

  Future<String> _writePreparedConfig(_PreparedSingBox ready) async {
    final homeDir = await appPath.homeDirPath;
    final configDir = Directory('$homeDir${Platform.pathSeparator}singbox');
    final nativeText = ready.nativeText;
    if (nativeText != null) {
      return writeNativeSingBoxConfig(configDir, nativeText);
    }
    return writeRenderedSingBoxConfig(configDir, ready.rendered!);
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
        final configPath = await _writePreparedConfig(prepared);
        startError = await service
            .start(configPath)
            .timeout(_singBoxStartTimeout);
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
      _api = SingBoxClashApi(port: prepared.apiPort, secret: prepared.secret);
      // RUNNING alone is not readiness; the panel API has to answer.
      final probeDetail = await waitForSingBoxApi(() => _api!.getProxies());
      if (probeDetail != null) {
        return CoreSwitchStepResult(
          failure: CoreSwitchFailure.startFailed,
          detail: probeDetail,
        );
      }
      await _syncModeToSingBox(prepared);
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
        corroborationPort: prepared.mixedPort,
        onEvent: (message) =>
            commonPrint.log(message, logLevel: LogLevel.warning),
      );
      if (!await CoreSwitch().awaitPortFree(prepared.mixedPort)) {
        return CoreSwitchStepResult(
          failure: CoreSwitchFailure.startFailed,
          detail: await portOccupiedDetail(
            port: prepared.mixedPort,
            singBoxBinary: binary,
          ),
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
        config:
            prepared.rendered?.config ??
            decodeSingBoxConfig(prepared.nativeText ?? '') ??
            const {},
        configText: prepared.nativeText,
        configDir: configDir,
        apiPort: prepared.apiPort,
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
      _appliedMixedPort = prepared.mixedPort;
      _api = SingBoxClashApi(port: prepared.apiPort, secret: prepared.secret);
      await _syncModeToSingBox(prepared);
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
        ProxyState(
          isStart: false,
          systemProxy: false,
          bassDomain: const [],
          port: _appliedMixedPort,
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

  var _startupReclaimDone = false;

  Future<void> _reclaimStartupOrphans() async {
    if (_startupReclaimDone) {
      return;
    }
    _startupReclaimDone = true;
    await reclaimStartupOrphans(
      locateBinary: () async {
        final homeDir = await appPath.homeDirPath;
        return findSingBoxBinary(
          singBoxCandidates(
            executableDir: appPath.executableDirPath,
            homeDir: homeDir,
            storedPath: await Preferences().getSingBoxBinaryPath(),
          ),
        );
      },
      reclaim: (binary) async {
        final homeDir = await appPath.homeDirPath;
        final configPath =
            '$homeDir${Platform.pathSeparator}singbox'
            '${Platform.pathSeparator}config.json';
        return reclaimOrphanedSingBoxProcesses(
          executable: binary,
          configPath: configPath,
          corroborationPort: singBoxMixedPort,
          onEvent: (message) =>
              commonPrint.log(message, logLevel: LogLevel.warning),
        );
      },
      portFree: () => CoreSwitch(
        portWaitTimeout: const Duration(seconds: 2),
      ).awaitPortFree(singBoxMixedPort),
      occupiedDetail: (binary) =>
          portOccupiedDetail(port: singBoxMixedPort, singBoxBinary: binary),
      info: (message) => commonPrint.log(message),
      warning: (message) =>
          commonPrint.log(message, logLevel: LogLevel.warning),
    );
  }

  Future<void> _syncModeToSingBox(_PreparedSingBox prepared) async {
    await syncModeToSingBox(
      api: _api,
      rendered: prepared.rendered != null,
      mode: ref.read(patchClashConfigProvider).mode,
      warning: (message) =>
          commonPrint.log(message, logLevel: LogLevel.warning),
    );
  }

  Future<void> _handleCrash(int code, List<String> tail) async {
    _runner = null;
    _api = null;
    await systemProxyQueue?.apply(
      ProxyState(
        isStart: false,
        systemProxy: false,
        bassDomain: const [],
        port: _appliedMixedPort,
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

/// The mihomo preflight verdict for a stored profile: a native
/// sing-box config is refused in plain words, not fed to mihomo.
CoreSwitchStepResult mihomoProfileVerdict(String text) {
  const notRenderable = CoreSwitchStepResult(
    failure: CoreSwitchFailure.profileNotRenderable,
  );
  if (isNativeSingBoxConfig(text)) {
    return const CoreSwitchStepResult(
      failure: CoreSwitchFailure.profileNotRenderable,
      detail: '该配置是 sing-box 原生配置，mihomo 无法使用，请切换到 sing-box 核心',
    );
  }
  try {
    final parsed = loadPlainYaml(text);
    if (parsed is! Map || parsed.isEmpty) {
      return notRenderable;
    }
  } catch (_) {
    return notRenderable;
  }
  return const CoreSwitchStepResult.ok();
}

/// Makes a native config ready to hand to the kernel verbatim; it
/// must bring its own clash_api for the panel and readiness probe.
({String? problem, _PreparedSingBox? prepared}) prepareNativeSingBox(
  String text,
) {
  final problem = nativeSingBoxConfigProblem(text);
  if (problem != null) {
    return (problem: problem, prepared: null);
  }
  final doc = decodeSingBoxConfig(text)!;
  final api = nativeSingBoxClashApi(doc);
  if (api == null) {
    return (
      problem: '原生配置未声明 clash_api（experimental.clash_api），Vessel 无法接管其面板',
      prepared: null,
    );
  }
  return (
    problem: null,
    prepared: (
      rendered: null,
      nativeText: text,
      secret: api.secret,
      apiPort: api.port,
      mixedPort: nativeSingBoxMixedPort(doc) ?? singBoxMixedPort,
    ),
  );
}

/// Writes a rendered config beside its degradation ledger.
Future<String> writeRenderedSingBoxConfig(
  Directory configDir,
  SingBoxRenderResult rendered,
) async {
  await configDir.create(recursive: true);
  final configFile = File(
    '${configDir.path}${Platform.pathSeparator}config.json',
  );
  await configFile.writeAsString(jsonEncode(rendered.config));
  final degradationsFile = File(
    '${configDir.path}${Platform.pathSeparator}degradations.json',
  );
  await degradationsFile.writeAsString(
    jsonEncode([
      for (final degradation in rendered.degradations) degradation.toJson(),
    ]),
  );
  return configFile.path;
}

/// Writes a native config byte for byte, dropping a stale ledger.
Future<String> writeNativeSingBoxConfig(
  Directory configDir,
  String text,
) async {
  await configDir.create(recursive: true);
  final configFile = File(
    '${configDir.path}${Platform.pathSeparator}config.json',
  );
  await configFile.writeAsString(text);
  final staleLedger = File(
    '${configDir.path}${Platform.pathSeparator}degradations.json',
  );
  if (await staleLedger.exists()) {
    await staleLedger.delete();
  }
  return configFile.path;
}

/// Stops a running mihomo through the run-state chain before a sing-box start.
Future<void> ensureMihomoStopped({
  required bool Function() mihomoRunning,
  required Future<bool> Function() stopMihomo,
  Future<bool> Function()? verifyStopped,
}) async {
  if (!mihomoRunning()) {
    return;
  }
  if (!await stopMihomo()) {
    throw StateError('mihomo 未能停止，sing-box 未启动，避免双核心同时运行。');
  }
  if (verifyStopped != null && !await verifyStopped()) {
    throw StateError('mihomo 已应答停止，但运行状态或端口尚未释放，sing-box 未启动。');
  }
}

/// Startup self-check for a sing-box left holding the mixed port.
Future<void> reclaimStartupOrphans({
  required Future<String?> Function() locateBinary,
  required Future<int> Function(String binary) reclaim,
  required Future<bool> Function() portFree,
  required Future<String> Function(String binary) occupiedDetail,
  required void Function(String message) info,
  required void Function(String message) warning,
}) async {
  try {
    final binary = await locateBinary();
    if (binary == null) {
      return;
    }
    final reclaimed = await reclaim(binary);
    if (reclaimed > 0) {
      info('启动自检回收了 $reclaimed 个遗留 sing-box 进程');
    }
    if (!await portFree()) {
      warning('启动自检：${await occupiedDetail(binary)}');
    }
  } catch (error) {
    warning('启动自检回收遗留 sing-box 失败：$error');
  }
}

/// A rendered config starts on sing-box's default mode, so the app's mode is pushed.
Future<void> syncModeToSingBox({
  required SingBoxClashApi? api,
  required bool rendered,
  required Mode mode,
  required void Function(String message) warning,
}) async {
  if (!rendered || api == null) {
    return;
  }
  try {
    await api.patchMode(singBoxClashModeName(mode));
  } catch (error) {
    warning('sing-box 模式同步失败：$error');
  }
}

/// The panel client of the bearing core when it is sing-box;
/// mihomo-addressed calls would land on a stopped listener instead.
SingBoxClashApi? bearingSingBoxApi(Ref ref) {
  if (ref.read(singBoxActionProvider).value?.state != SingBoxState.running) {
    return null;
  }
  return ref.read(singBoxActionProvider.notifier).api;
}

/// The spelling sing-box's clash mode list carries for [mode].
String singBoxClashModeName(Mode mode) {
  return switch (mode) {
    Mode.rule => 'Rule',
    Mode.global => 'Global',
    Mode.direct => 'Direct',
  };
}

/// Names an occupied port's holder: this app's leftover sing-box,
/// its mihomo core process, or a foreign program by image name.
Future<String> portOccupiedDetail({
  required int port,
  required String singBoxBinary,
  Future<PortOwnerInfo?> Function(int port)? findOwner,
}) async {
  final owner = await (findOwner ?? findListeningPortOwner)(port);
  if (owner == null) {
    return '端口 $port 仍被其他程序占用（未能判定属主），sing-box 未启动';
  }
  if (owner.executablePath.isNotEmpty &&
      windowsPathsEqual(owner.executablePath, singBoxBinary)) {
    return '端口 $port 仍被上次运行遗留的 sing-box（PID ${owner.pid}）占用，sing-box 未启动';
  }
  final imageName = owner.imageName.isNotEmpty
      ? owner.imageName
      : owner.executablePath.split('\\').last;
  if (imageName.toLowerCase() == 'kfusioncore.exe') {
    return '端口 $port 仍被本应用 mihomo 核心进程（PID ${owner.pid}）占用，sing-box 未启动';
  }
  if (imageName.isEmpty) {
    return '端口 $port 仍被未知程序（PID ${owner.pid}）占用，sing-box 未启动';
  }
  return '端口 $port 仍被 $imageName（PID ${owner.pid}）占用，sing-box 未启动';
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
