import 'package:kfusion/common/preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the simplified beginner UI is active. New installs default to
/// true; the toggle lives in the general settings page. Kept as a plain
/// AsyncNotifier (no code generation) so it needs no build_runner run.
final beginnerModeProvider =
    AsyncNotifierProvider<BeginnerModeNotifier, bool>(
      BeginnerModeNotifier.new,
    );

class BeginnerModeNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() {
    return Preferences().getBeginnerMode();
  }

  Future<void> set(bool value) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await Preferences().setBeginnerMode(value);
      return value;
    });
  }
}
