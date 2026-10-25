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
  });

  final CoreSwitchFailure? failure;
  final CoreSwitchStage? failedStage;

  /// True when the previously running core runs again, or was never touched.
  final bool restored;

  bool get succeeded => failure == null;
}

typedef CoreSwitchStep = Future<CoreSwitchFailure?> Function();

/// Runs a core switch in stage order, restoring the original core after any failure past preflight.
Future<CoreSwitchOutcome> runCoreSwitch({
  required CoreSwitchStep preflight,
  required Future<bool> Function() stopCurrent,
  required CoreSwitchStep startTarget,
  required CoreSwitchStep applyTarget,
  required Future<bool> Function() restoreOriginal,
  required void Function(CoreSwitchStage stage) onStage,
}) async {
  CoreSwitchFailure? preflightFailure;
  try {
    preflightFailure = await preflight();
  } catch (_) {
    preflightFailure = CoreSwitchFailure.unknown;
  }
  if (preflightFailure != null) {
    return CoreSwitchOutcome(failure: preflightFailure, restored: true);
  }

  Future<CoreSwitchOutcome> fail(
    CoreSwitchFailure failure,
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
      failure: failure,
      failedStage: stage,
      restored: restored,
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
    return fail(CoreSwitchFailure.stopFailed, CoreSwitchStage.stopping);
  }

  Future<CoreSwitchFailure?> runStep(CoreSwitchStep step) async {
    try {
      return await step();
    } catch (_) {
      return CoreSwitchFailure.unknown;
    }
  }

  onStage(CoreSwitchStage.starting);
  final startFailure = await runStep(startTarget);
  if (startFailure != null) {
    return fail(startFailure, CoreSwitchStage.starting);
  }

  onStage(CoreSwitchStage.applying);
  final applyFailure = await runStep(applyTarget);
  if (applyFailure != null) {
    return fail(applyFailure, CoreSwitchStage.applying);
  }

  return const CoreSwitchOutcome(restored: true);
}
