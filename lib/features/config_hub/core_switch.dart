import 'dart:async';

/// The stage a core switch is currently in; the card names each one.
enum CoreSwitchStage { stopping, starting, applying, restoring }

enum CoreSwitchFailure {
  noProfile,
  profileUnreadable,
  profileNotRenderable,
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
