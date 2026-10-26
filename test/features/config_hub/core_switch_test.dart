import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/features/config_hub/core_switch.dart';

const _ok = CoreSwitchStepResult.ok();

CoreSwitchStepResult _failed(CoreSwitchFailure failure, [String detail = '']) {
  return CoreSwitchStepResult(failure: failure, detail: detail);
}

void main() {
  group('runCoreSwitch', () {
    test(
      'a clean switch walks stopping, starting, applying in order',
      () async {
        final stages = <CoreSwitchStage>[];
        var restores = 0;
        final outcome = await runCoreSwitch(
          preflight: () async => _ok,
          stopCurrent: () async => true,
          startTarget: () async => _ok,
          applyTarget: () async => _ok,
          restoreOriginal: () async {
            restores++;
            return true;
          },
          onStage: stages.add,
        );
        expect(outcome.succeeded, isTrue);
        expect(outcome.restored, isTrue);
        expect(restores, 0);
        expect(stages, [
          CoreSwitchStage.stopping,
          CoreSwitchStage.starting,
          CoreSwitchStage.applying,
        ]);
      },
    );

    test(
      'a preflight rejection touches nothing and needs no restore',
      () async {
        final stages = <CoreSwitchStage>[];
        var stops = 0;
        var restores = 0;
        final outcome = await runCoreSwitch(
          preflight: () async =>
              _failed(CoreSwitchFailure.profileNotRenderable),
          stopCurrent: () async {
            stops++;
            return true;
          },
          startTarget: () async => _ok,
          applyTarget: () async => _ok,
          restoreOriginal: () async {
            restores++;
            return true;
          },
          onStage: stages.add,
        );
        expect(outcome.failure, CoreSwitchFailure.profileNotRenderable);
        expect(outcome.failedStage, isNull);
        expect(outcome.restored, isTrue);
        expect(stops, 0);
        expect(restores, 0);
        expect(stages, isEmpty);
      },
    );

    test('a throwing preflight is reported as an unknown failure', () async {
      final outcome = await runCoreSwitch(
        preflight: () async => throw StateError('boom'),
        stopCurrent: () async => true,
        startTarget: () async => _ok,
        applyTarget: () async => _ok,
        restoreOriginal: () async => true,
        onStage: (_) {},
      );
      expect(outcome.failure, CoreSwitchFailure.unknown);
      expect(outcome.failedStage, isNull);
    });

    test('an unanswered stop aborts the switch and restores', () async {
      final stages = <CoreSwitchStage>[];
      var starts = 0;
      final outcome = await runCoreSwitch(
        preflight: () async => _ok,
        stopCurrent: () async => false,
        startTarget: () async {
          starts++;
          return _ok;
        },
        applyTarget: () async => _ok,
        restoreOriginal: () async => true,
        onStage: stages.add,
      );
      expect(outcome.failure, CoreSwitchFailure.stopFailed);
      expect(outcome.failedStage, CoreSwitchStage.stopping);
      expect(outcome.restored, isTrue);
      expect(starts, 0);
      expect(stages, [CoreSwitchStage.stopping, CoreSwitchStage.restoring]);
    });

    test('a failed start skips the apply and restores the original', () async {
      final stages = <CoreSwitchStage>[];
      var applies = 0;
      final outcome = await runCoreSwitch(
        preflight: () async => _ok,
        stopCurrent: () async => true,
        startTarget: () async => _failed(CoreSwitchFailure.binaryUnavailable),
        applyTarget: () async {
          applies++;
          return _ok;
        },
        restoreOriginal: () async => true,
        onStage: stages.add,
      );
      expect(outcome.failure, CoreSwitchFailure.binaryUnavailable);
      expect(outcome.failedStage, CoreSwitchStage.starting);
      expect(outcome.restored, isTrue);
      expect(applies, 0);
      expect(stages, [
        CoreSwitchStage.stopping,
        CoreSwitchStage.starting,
        CoreSwitchStage.restoring,
      ]);
    });

    test('a failed apply restores and reports the restore result', () async {
      final outcome = await runCoreSwitch(
        preflight: () async => _ok,
        stopCurrent: () async => true,
        startTarget: () async => _ok,
        applyTarget: () async => _failed(CoreSwitchFailure.applyFailed),
        restoreOriginal: () async => false,
        onStage: (_) {},
      );
      expect(outcome.failure, CoreSwitchFailure.applyFailed);
      expect(outcome.failedStage, CoreSwitchStage.applying);
      expect(outcome.restored, isFalse);
    });

    test('a raw exception from a step never escapes the runner', () async {
      final outcome = await runCoreSwitch(
        preflight: () async => _ok,
        stopCurrent: () async => true,
        startTarget: () async => throw StateError('Bad state: mihomo 未能停止'),
        applyTarget: () async => _ok,
        restoreOriginal: () async => true,
        onStage: (_) {},
      );
      expect(outcome.failure, CoreSwitchFailure.unknown);
      expect(outcome.failedStage, CoreSwitchStage.starting);
      expect(outcome.restored, isTrue);
    });

    test('a throwing restore leaves the outcome unrestored', () async {
      final outcome = await runCoreSwitch(
        preflight: () async => _ok,
        stopCurrent: () async => true,
        startTarget: () async => _failed(CoreSwitchFailure.startFailed),
        applyTarget: () async => _ok,
        restoreOriginal: () async => throw StateError('gone'),
        onStage: (_) {},
      );
      expect(outcome.failure, CoreSwitchFailure.startFailed);
      expect(outcome.restored, isFalse);
    });

    test('a step detail reaches the outcome untouched', () async {
      final outcome = await runCoreSwitch(
        preflight: () async => _ok,
        stopCurrent: () async => true,
        startTarget: () async => _failed(
          CoreSwitchFailure.startFailed,
          'FATAL[0000] unknown outbound type: block',
        ),
        applyTarget: () async => _ok,
        restoreOriginal: () async => true,
        onStage: (_) {},
      );
      expect(outcome.failure, CoreSwitchFailure.startFailed);
      expect(outcome.detail, 'FATAL[0000] unknown outbound type: block');
    });

    test('a preflight detail reaches the outcome untouched', () async {
      final outcome = await runCoreSwitch(
        preflight: () async => _failed(
          CoreSwitchFailure.profileNotRenderable,
          'checkConfig: legacy block outbound',
        ),
        stopCurrent: () async => true,
        startTarget: () async => _ok,
        applyTarget: () async => _ok,
        restoreOriginal: () async => true,
        onStage: (_) {},
      );
      expect(outcome.failure, CoreSwitchFailure.profileNotRenderable);
      expect(outcome.detail, 'checkConfig: legacy block outbound');
    });
  });

  group('singBoxCheckOutcome', () {
    test('an empty answer means the profile passed', () {
      expect(singBoxCheckOutcome('').failure, isNull);
    });

    test(
      'the timeout sentinel is unresponsiveness, not an invalid profile',
      () {
        final outcome = singBoxCheckOutcome(singBoxCheckTimeoutSentinel);
        expect(outcome.failure, CoreSwitchFailure.checkUnresponsive);
        expect(outcome.detail, isEmpty);
      },
    );

    test('a real check error still means the profile is not renderable', () {
      final outcome = singBoxCheckOutcome('unknown outbound type: block');
      expect(outcome.failure, CoreSwitchFailure.profileNotRenderable);
      expect(outcome.detail, 'unknown outbound type: block');
    });

    test('the pre-plugin-retry timeout wording is just an error string', () {
      final outcome = singBoxCheckOutcome('sing-box 配置校验超时');
      expect(outcome.failure, CoreSwitchFailure.profileNotRenderable);
      expect(outcome.detail, 'sing-box 配置校验超时');
    });
  });
}
