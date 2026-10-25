import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/features/config_hub/singbox_action.dart';

void main() {
  Future<void> noPause(Duration duration) async {}

  test(
    'waitForValue returns true immediately when already at target',
    () async {
      var reads = 0;
      final result = await waitForValue<int>(
        read: () async => ++reads,
        target: 1,
        pause: noPause,
      );
      expect(result, isTrue);
      expect(reads, 1);
    },
  );

  test('waitForValue polls until the value reaches the target', () async {
    var reads = 0;
    final result = await waitForValue<String>(
      read: () async => ++reads >= 3 ? 'disconnected' : 'connected',
      target: 'disconnected',
      pause: noPause,
    );
    expect(result, isTrue);
    expect(reads, 3);
  });

  group('ensureMihomoStopped', () {
    test('does nothing when mihomo is not running', () async {
      var stops = 0;
      await ensureMihomoStopped(
        mihomoRunning: () => false,
        stopMihomo: () async {
          stops++;
          return true;
        },
      );
      expect(stops, 0);
    });

    test('proceeds once the stop chain answers', () async {
      var running = true;
      await ensureMihomoStopped(
        mihomoRunning: () => running,
        stopMihomo: () async {
          running = false;
          return true;
        },
      );
      expect(running, isFalse);
    });

    test('aborts the start when the stop goes unanswered', () async {
      await expectLater(
        ensureMihomoStopped(
          mihomoRunning: () => true,
          stopMihomo: () async => false,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'mihomo 未能停止，sing-box 未启动，避免双核心同时运行。',
          ),
        ),
      );
    });
  });

  group('waitForSingBoxApi', () {
    test('an answering probe means ready', () async {
      final detail = await waitForSingBoxApi(() async {}, pause: noPause);
      expect(detail, isNull);
    });

    test('a probe that answers after failures still means ready', () async {
      var attempts = 0;
      final detail = await waitForSingBoxApi(() async {
        if (++attempts < 3) {
          throw StateError('connection refused');
        }
      }, pause: noPause);
      expect(detail, isNull);
      expect(attempts, 3);
    });

    test('a silent probe yields the last error as detail', () async {
      final detail = await waitForSingBoxApi(
        () async => throw StateError('connection refused'),
        timeout: const Duration(milliseconds: 30),
        interval: const Duration(milliseconds: 5),
        pause: noPause,
      );
      expect(detail, isNotNull);
      expect(detail, contains('connection refused'));
    });
  });

  test('waitForValue gives up after the timeout', () async {
    var reads = 0;
    final result = await waitForValue<String>(
      read: () async {
        reads++;
        return 'connected';
      },
      target: 'disconnected',
      timeout: const Duration(milliseconds: 30),
      interval: const Duration(milliseconds: 5),
      pause: noPause,
    );
    expect(result, isFalse);
    expect(reads, greaterThan(1));
  });
}
