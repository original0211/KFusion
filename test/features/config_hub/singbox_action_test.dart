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
