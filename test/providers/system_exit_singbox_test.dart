import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/core/controller.dart';
import 'package:kfusion/core/desktop/model.dart';
import 'package:kfusion/core/interface.dart';
import 'package:kfusion/core/singbox/singbox_runner.dart';
import 'package:kfusion/features/config_hub/singbox_action.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/state.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';

class _MockCoreHandlerInterface extends Mock implements CoreHandlerInterface {}

class _RecordingSingBoxAction extends SingBoxAction {
  _RecordingSingBoxAction({required this.running});

  final bool running;
  var stopCalls = 0;

  @override
  Future<SingBoxStatus> build() async =>
      SingBoxStatus(state: running ? SingBoxState.running : SingBoxState.idle);

  @override
  SingBoxClashApi? get api => null;

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

/// Exercises the real exit steps except cleanup/window/exit, so the
/// production closeCore wiring itself is what is under test.
class _ExitSystemAction extends SystemAction {
  final calls = <String>[];

  @override
  Future<void> cleanupExitResources(bool needSave) async =>
      calls.add('cleanup');

  @override
  Future<void> closeWindow() async => calls.add('window');

  @override
  Future<void> exitApplication() async => calls.add('exit');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({ProviderContainer container, _RecordingSingBoxAction singBox})>
  boot({required bool singBoxRunning}) async {
    final core = _MockCoreHandlerInterface();
    when(() => core.close()).thenAnswer(
      (_) async => const CoreLifecycleResult(
        revision: 1,
        outcome: CoreLifecycleOutcome.applied,
      ),
    );
    final singBox = _RecordingSingBoxAction(running: singBoxRunning);
    final action = _ExitSystemAction();
    final container = ProviderContainer(
      overrides: [
        systemActionProvider.overrideWith(() => action),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        singBoxActionProvider.overrideWith(() => singBox),
      ],
    );
    globalState.container = container;
    addTearDown(container.dispose);
    await container.read(singBoxActionProvider.future);
    return (container: container, singBox: singBox);
  }

  test('exit stops a running sing-box before the app goes away', () async {
    final (:container, :singBox) = await boot(singBoxRunning: true);

    await container.read(systemActionProvider.notifier).handleExit();

    expect(singBox.stopCalls, 1);
  });

  test('exit leaves an idle sing-box action untouched', () async {
    final (:container, :singBox) = await boot(singBoxRunning: false);

    await container.read(systemActionProvider.notifier).handleExit();

    expect(singBox.stopCalls, 0);
  });
}
