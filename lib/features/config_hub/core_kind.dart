import 'package:kfusion/common/preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum CoreKind {
  mihomo('mihomo'),
  singbox('singbox');

  const CoreKind(this.value);

  final String value;

  static CoreKind fromValue(String? value) {
    return CoreKind.values.firstWhere(
      (kind) => kind.value == value,
      orElse: () => CoreKind.mihomo,
    );
  }
}

final coreKindsProvider =
    AsyncNotifierProvider<CoreKindsNotifier, Map<int, CoreKind>>(
      CoreKindsNotifier.new,
    );

class CoreKindsNotifier extends AsyncNotifier<Map<int, CoreKind>> {
  @override
  Future<Map<int, CoreKind>> build() async {
    final raw = await Preferences().getCoreKindMap();
    return {
      for (final MapEntry(:key, :value) in raw.entries)
        key: CoreKind.fromValue(value),
    };
  }

  CoreKind kindOf(int profileId) {
    return state.value?[profileId] ?? CoreKind.mihomo;
  }

  Future<void> setKind(int profileId, CoreKind kind) async {
    final current = {...?state.value};
    current[profileId] = kind;
    state = AsyncData(current);
    await Preferences().setCoreKindMap({
      for (final MapEntry(:key, :value) in current.entries) key: value.value,
    });
  }
}

final activeCoreKindProvider =
    AsyncNotifierProvider<ActiveCoreKindNotifier, CoreKind>(
      ActiveCoreKindNotifier.new,
    );

class ActiveCoreKindNotifier extends AsyncNotifier<CoreKind> {
  @override
  Future<CoreKind> build() {
    return Preferences().getActiveCoreKind().then(CoreKind.fromValue);
  }

  Future<void> set(CoreKind kind) async {
    state = AsyncData(kind);
    await Preferences().setActiveCoreKind(kind.value);
  }
}
