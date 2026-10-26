import 'dart:async';

/// The stage a core switch is currently in; the card names each one.
enum CoreSwitchStage { stopping, starting, applying, restoring }

enum CoreSwitchFailure {
  noProfile,
  profileUnreadable,
  profileNotRenderable,
  checkUnresponsive,
  stopFailed,
  startFailed,
  applyFailed,
  binaryUnavailable,
  adminRequired,
  channelUnavailable,
  platformUnsupported,
  unknown,
}

class CoreSwitchOutcome {
  const CoreSwitchOutcome({
    this.failure,
    this.failedStage,
    this.restored = false,
    this.detail = '',
  });

  final CoreSwitchFailure? failure;
  final CoreSwitchStage? failedStage;

  /// True when the previously running core runs again, or was never touched.
  final bool restored;

  /// The failing layer's own words, kept under the sentence the user reads.
  final String detail;

  bool get succeeded => failure == null;
}

class CoreSwitchStepResult {
  const CoreSwitchStepResult({this.failure, this.detail = ''});

  const CoreSwitchStepResult.ok() : failure = null, detail = '';

  final CoreSwitchFailure? failure;
  final String detail;
}

/// What the Android plugin returns when both native check attempts timed
/// out; mirrors SingBoxCheckGate.TIMEOUT_SENTINEL on the Kotlin side.
const singBoxCheckTimeoutSentinel = 'sing-box-check-timeout';

/// Maps a native checkConfig answer to a preflight outcome: silence after
/// the plugin's own retry is not a verdict on the profile itself.
CoreSwitchStepResult singBoxCheckOutcome(String checkError) {
  if (checkError.isEmpty) return const CoreSwitchStepResult.ok();
  if (checkError == singBoxCheckTimeoutSentinel) {
    return const CoreSwitchStepResult(
      failure: CoreSwitchFailure.checkUnresponsive,
    );
  }
  return CoreSwitchStepResult(
    failure: CoreSwitchFailure.profileNotRenderable,
    detail: checkError,
  );
}

/// The failure detail for a render that left sing-box no usable outbound:
/// what the renderer dropped, in its own terms (empty list = nothing dropped).
String singBoxNoUsableOutboundDetail(List<String> unsupported) {
  if (unsupported.isEmpty) {
    return '没有可供 sing-box 使用的代理出站，配置中仅有 direct/block 出站';
  }
  return '没有可用的代理出站；${_singBoxDropSummary(unsupported)}';
}

String _singBoxDropSummary(List<String> unsupported) {
  final nodePattern = RegExp(r'^proxy type "([^"]+)"');
  final protocols = <String, int>{};
  var unusableNodes = 0;
  var deadGroups = 0;
  var groupTypes = 0;
  var rejectMembers = 0;
  var rules = 0;
  var others = 0;
  for (final entry in unsupported) {
    final node = nodePattern.firstMatch(entry);
    if (node != null) {
      final type = node.group(1)!;
      protocols[type] = (protocols[type] ?? 0) + 1;
    } else if (entry.startsWith('wireguard node')) {
      unusableNodes++;
    } else if (entry.contains('has no usable member')) {
      deadGroups++;
    } else if (entry.startsWith('proxy-group type')) {
      groupTypes++;
    } else if (entry.startsWith('REJECT in proxy-group')) {
      rejectMembers++;
    } else if (entry.startsWith('rule ')) {
      rules++;
    } else {
      others++;
    }
  }
  final parts = <String>[];
  if (protocols.isNotEmpty) {
    final skipped = protocols.entries
        .map((entry) => '${entry.key} ×${entry.value}')
        .join('、');
    parts.add('节点协议不受 sing-box 支持：$skipped');
  }
  if (unusableNodes > 0) parts.add('节点不可用 ×$unusableNodes');
  if (deadGroups > 0) parts.add('分组无可用成员 ×$deadGroups');
  if (groupTypes > 0) parts.add('分组类型不受支持 ×$groupTypes');
  if (rejectMembers > 0) parts.add('REJECT 成员被跳过 ×$rejectMembers');
  if (rules > 0) parts.add('规则未翻译 ×$rules');
  if (others > 0) parts.add('其他未翻译项 ×$others');
  return parts.join('；');
}

typedef CoreSwitchStep = Future<CoreSwitchStepResult> Function();

/// Runs a core switch in stage order, restoring the original core after any failure past preflight.
Future<CoreSwitchOutcome> runCoreSwitch({
  required CoreSwitchStep preflight,
  required Future<bool> Function() stopCurrent,
  required CoreSwitchStep startTarget,
  required CoreSwitchStep applyTarget,
  required Future<bool> Function() restoreOriginal,
  required void Function(CoreSwitchStage stage) onStage,
}) async {
  CoreSwitchStepResult preflightResult;
  try {
    preflightResult = await preflight();
  } catch (_) {
    preflightResult = const CoreSwitchStepResult(
      failure: CoreSwitchFailure.unknown,
    );
  }
  if (preflightResult.failure != null) {
    return CoreSwitchOutcome(
      failure: preflightResult.failure,
      restored: true,
      detail: preflightResult.detail,
    );
  }

  Future<CoreSwitchOutcome> fail(
    CoreSwitchStepResult result,
    CoreSwitchStage stage,
  ) async {
    onStage(CoreSwitchStage.restoring);
    var restored = false;
    try {
      restored = await restoreOriginal();
    } catch (_) {
      restored = false;
    }
    return CoreSwitchOutcome(
      failure: result.failure,
      failedStage: stage,
      restored: restored,
      detail: result.detail,
    );
  }

  onStage(CoreSwitchStage.stopping);
  var stopped = false;
  try {
    stopped = await stopCurrent();
  } catch (_) {
    stopped = false;
  }
  if (!stopped) {
    return fail(
      const CoreSwitchStepResult(failure: CoreSwitchFailure.stopFailed),
      CoreSwitchStage.stopping,
    );
  }

  Future<CoreSwitchStepResult> runStep(CoreSwitchStep step) async {
    try {
      return await step();
    } catch (_) {
      return const CoreSwitchStepResult(failure: CoreSwitchFailure.unknown);
    }
  }

  onStage(CoreSwitchStage.starting);
  final startResult = await runStep(startTarget);
  if (startResult.failure != null) {
    return fail(startResult, CoreSwitchStage.starting);
  }

  onStage(CoreSwitchStage.applying);
  final applyResult = await runStep(applyTarget);
  if (applyResult.failure != null) {
    return fail(applyResult, CoreSwitchStage.applying);
  }

  return const CoreSwitchOutcome(restored: true);
}
