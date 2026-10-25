import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/features/config_hub/core_switch.dart';

void main() {
  group('runCoreSwitch', () {
    test(
      'a clean switch walks stopping, starting, applying in order',
      () async {
        final stages = <CoreSwitchStage>[];
        var restores = 0;
        final outcome = await runCoreSwitch(
          preflight: () async => null,
          stopCurrent: () async => true,
          startTarget: () async => null,
          applyTarget: () async => null,
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
          preflight: () async => CoreSwitchFailure.profileNotRenderable,
          stopCurrent: () async {
            stops++;
            return true;
          },
          startTarget: () async => null,
          applyTarget: () async => null,
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
        startTarget: () async => null,
        applyTarget: () async => null,
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
        preflight: () async => null,
        stopCurrent: () async => false,
        startTarget: () async {
          starts++;
          return null;
        },
        applyTarget: () async => null,
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
        preflight: () async => null,
        stopCurrent: () async => true,
        startTarget: () async => CoreSwitchFailure.binaryUnavailable,
        applyTarget: () async {
          applies++;
          return null;
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
        preflight: () async => null,
        stopCurrent: () async => true,
        startTarget: () async => null,
        applyTarget: () async => CoreSwitchFailure.applyFailed,
        restoreOriginal: () async => false,
        onStage: (_) {},
      );
      expect(outcome.failure, CoreSwitchFailure.applyFailed);
      expect(outcome.failedStage, CoreSwitchStage.applying);
      expect(outcome.restored, isFalse);
    });

    test('a raw exception from a step never escapes the runner', () async {
      final outcome = await runCoreSwitch(
        preflight: () async => null,
        stopCurrent: () async => true,
        startTarget: () async => throw StateError('Bad state: mihomo 未能停止'),
        applyTarget: () async => null,
        restoreOriginal: () async => true,
        onStage: (_) {},
      );
      expect(outcome.failure, CoreSwitchFailure.unknown);
      expect(outcome.failedStage, CoreSwitchStage.starting);
      expect(outcome.restored, isTrue);
    });

    test('a throwing restore leaves the outcome unrestored', () async {
      final outcome = await runCoreSwitch(
        preflight: () async => null,
        stopCurrent: () async => true,
        startTarget: () async => CoreSwitchFailure.startFailed,
        applyTarget: () async => null,
        restoreOriginal: () async => throw StateError('gone'),
        onStage: (_) {},
      );
      expect(outcome.failure, CoreSwitchFailure.startFailed);
      expect(outcome.restored, isFalse);
    });
  });
}
