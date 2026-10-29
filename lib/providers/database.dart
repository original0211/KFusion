import 'dart:async';

import 'package:collection/collection.dart';
import 'package:kfusion/common/common.dart';
import 'package:kfusion/database/database.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/models/models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'generated/database.g.dart';

Future<void> withRollback<T>({
  required T snapshot,
  required FutureOr<void> Function() action,
  required void Function(T snapshot) rollback,
}) async {
  try {
    await action();
  } catch (e, s) {
    rollback(snapshot);
    Error.throwWithStackTrace(e, s);
  }
}

Future<void> _persistOptimistically<T>(
  T previous,
  T next,
  T Function() read,
  void Function(T value) write,
  FutureOr<void> Function() action,
) async {
  write(next);
  try {
    await action();
  } catch (e, s) {
    if (identical(read(), next)) {
      write(previous);
    }
    Error.throwWithStackTrace(e, s);
  }
}

void _reportReread(Object error, StackTrace stackTrace) {
  commonPrint.log(
    'Database read-back failed: ${compactError(error)}, $stackTrace',
    logLevel: LogLevel.warning,
  );
}

void _reportOptimisticFailure(Object error, StackTrace stackTrace) {
  commonPrint.log(
    'Optimistic database write failed: ${compactError(error)}, $stackTrace',
    logLevel: LogLevel.warning,
  );
  dialogs.showNotifier(
    currentAppLocalizations.databaseWriteFailedTip,
    level: MessageLevel.error,
  );
}

/// Read-backs landing while a write is in flight can predate the write and
/// would briefly undo its optimistic value, so they wait for [idle]. One
/// turned away may carry a write made outside the notifier, so the rows are
/// read again once the writes settle.
class _Writes {
  final void Function() _reread;
  var _pending = 0;
  var _missed = false;

  _Writes(this._reread);

  bool get idle => _pending == 0;

  bool admit() {
    _missed |= !idle;
    return idle;
  }

  Future<void> track(Future<void> Function() write) async {
    _pending++;
    try {
      await write();
    } finally {
      _pending--;
      if (idle && _missed) {
        _missed = false;
        _reread();
      }
    }
  }
}

mixin OptimisticMixin<T> on AsyncNotifierMixin<T> {
  late final _writes = _Writes(_reread);
  Future<T> Function()? _query;

  Stream<T> settled(Stream<T> rows, Future<T> Function() query) {
    _query = query;
    return rows.where((_) => _writes.admit());
  }

  void _reread() {
    _query?.call().then((rows) {
      if (ref.mounted && _writes.admit()) {
        value = rows;
      }
    }, onError: _reportReread);
  }

  void optimistic(T next, FutureOr<void> Function() action) {
    unawaited(
      optimisticAsync(next, action).catchError(_reportOptimisticFailure),
    );
  }

  Future<void> optimisticAsync(T next, FutureOr<void> Function() action) {
    return _writes.track(
      () => _persistOptimistically(
        value,
        next,
        () => value,
        (v) => value = v,
        action,
      ),
    );
  }
}

@riverpod
Stream<List<Profile>> profilesStream(Ref ref) {
  return database.profilesDao.query().watch();
}

@Riverpod(keepAlive: true)
class Profiles extends _$Profiles {
  late final _writes = _Writes(_reread);

  @override
  List<Profile> build() {
    ref.listen(profilesStreamProvider, (_, next) {
      if (_writes.admit()) {
        state = next.value ?? [];
      }
    });
    return ref.read(profilesStreamProvider).value ?? [];
  }

  void _reread() {
    database.profilesDao.query().get().then((rows) {
      if (ref.mounted && _writes.admit()) {
        state = rows;
      }
    }, onError: _reportReread);
  }

  void _optimistic(List<Profile> next, FutureOr<void> Function() action) {
    unawaited(
      _optimisticAsync(next, action).catchError(_reportOptimisticFailure),
    );
  }

  var _queue = Future<void>.value();

  /// Writes run in turn and each writes the rows as the state holds them then,
  /// so a put issued before a rewrite landed writes it along, not over it.
  Future<void> _serial(Future<void> Function() write) {
    final run = _queue.then((_) => write());
    _queue = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _putLatest(Iterable<int> ids) async {
    for (final id in ids) {
      if (state.getProfile(id) case final profile?) {
        await database.profiles.put(profile.toCompanion());
      }
    }
  }

  Future<void> _optimisticAsync(
    List<Profile> next,
    FutureOr<void> Function() action,
  ) {
    return _writes.track(
      () => _persistOptimistically(
        state,
        next,
        () => state,
        (v) => state = v,
        action,
      ),
    );
  }

  Profile labeled(Profile profile) => state.optimizeLabel(profile);

  /// A new provider label follows into custom profiles whatever path set it.
  void put(Profile profile) {
    final newProfile = labeled(profile);
    final previousLabel = state.getProfile(profile.id)?.realLabel;
    var next = state.copyAndPut(newProfile, (item) => item.id == newProfile.id);
    if (newProfile.type == ProfileType.custom ||
        previousLabel == null ||
        previousLabel == newProfile.realLabel) {
      _optimistic(next, () => _serial(() => _putLatest([newProfile.id])));
      return;
    }
    final names = {previousLabel: newProfile.realLabel};
    final users = [
      for (final item in next)
        if (item.type == ProfileType.custom)
          if (item.copyWith(
                overrides: item.overrides.renamedProxyProviders(names),
              )
              case final user when user != item)
            user,
    ];
    for (final user in users) {
      next = next.copyAndPut(user, (item) => item.id == user.id);
    }
    _optimistic(
      next,
      () => _serial(
        () => database.transaction(() async {
          await database.proxyGroupsDao.renameUse(
            await database.profilesDao.customIds().get(),
            oldName: previousLabel,
            newName: newProfile.realLabel,
          );
          await _putLatest([for (final user in users) user.id, newProfile.id]);
        }),
      ),
    );
  }

  /// Applies the changes [body] returns to the state too, so a put landing
  /// before the rows read back writes them rather than the profile as it was.
  Future<void> rewriteCustom(
    Future<Map<int, Profile Function(Profile profile)>> Function() body,
  ) {
    return _writes.track(() async {
      (List<Profile>, List<Profile>)? applied;
      try {
        await _serial(
          () => database.transaction(() async {
            final changes = await body();
            final current = state;
            final next = [
              for (final item in current) changes[item.id]?.call(item) ?? item,
            ];
            applied = (current, next);
            state = next;
            for (final (index, item) in next.indexed) {
              if (item != current[index]) {
                await database.profiles.put(item.toCompanion());
              }
            }
            for (final MapEntry(key: id, value: change) in changes.entries) {
              if (current.getProfile(id) != null) {
                continue;
              }
              if (await database.profilesDao.get(id) case final row?) {
                if (change(row) case final changed when changed != row) {
                  await database.profiles.put(changed.toCompanion());
                }
              }
            }
          }),
        );
      } catch (e, s) {
        if (applied case (
          final previous,
          final next,
        ) when identical(state, next)) {
          state = previous;
        }
        Error.throwWithStackTrace(e, s);
      }
    });
  }

  Future<void> del(int id) {
    return _optimisticAsync(
      state.where((e) => e.id != id).toList(),
      () => _serial(() => database.deleteProfile(id)),
    );
  }

  void updateProfile(int profileId, Profile Function(Profile profile) builder) {
    final index = state.indexWhere((element) => element.id == profileId);
    if (index == -1) return;
    final newProfile = builder(state[index]);
    if (newProfile == state[index]) return;
    final next = List<Profile>.from(state);
    next[index] = newProfile;
    _optimistic(next, () => _serial(() => _putLatest([profileId])));
  }

  void reorder(List<Profile> profiles) {
    final next = List<Profile>.from(profiles);
    final moved = <int>[];
    next.forEachIndexed((index, item) {
      if (item.order != index) {
        next[index] = item.copyWith(order: index);
        moved.add(item.id);
      }
    });
    _optimistic(
      next,
      () => _serial(() => database.transaction(() => _putLatest(moved))),
    );
  }

  @override
  bool updateShouldNotify(List<Profile> previous, List<Profile> next) {
    return !profileListEquality.equals(previous, next);
  }
}

@riverpod
class ClashProviders extends _$ClashProviders
    with AsyncNotifierMixin, OptimisticMixin {
  @override
  Stream<List<ClashProvider>> build() {
    final query = database.clashProvidersDao.query();
    return settled(query.watch(), query.get);
  }

  @override
  List<ClashProvider> get value => state.value ?? [];

  void put(ClashProvider provider) {
    final next = List<ClashProvider>.from(value);
    final index = next.indexWhere((item) => item.id == provider.id);
    final renamedFrom = index != -1 && next[index].label != provider.label
        ? next[index].label
        : null;
    if (index != -1) {
      next[index] = provider;
    } else {
      next.add(provider);
    }
    if (renamedFrom == null) {
      optimistic(
        next,
        () => database.clashProviders.put(provider.toCompanion()),
      );
      return;
    }
    final names = {renamedFrom: provider.label};
    optimistic(
      next,
      () => ref.read(profilesProvider.notifier).rewriteCustom(() async {
        final profileIds = await database.profilesDao.customIds().get();
        await database.rulesDao.renameRuleProvider(
          profileIds,
          oldName: renamedFrom,
          newName: provider.label,
        );
        await database.clashProviders.put(provider.toCompanion());
        return {
          for (final id in profileIds)
            id: (profile) => profile.copyWith(
              overrides: profile.overrides.renamedRuleSets(names),
            ),
        };
      }),
    );
  }

  void del(int id) {
    final next = List<ClashProvider>.from(value);
    final index = next.indexWhere((item) => item.id == id);
    if (index == -1) return;
    next.removeAt(index);
    optimistic(
      next,
      () => database.clashProviders.remove((t) => t.id.equals(id)),
    );
  }

  void order(int oldIndex, int newIndex) {
    final next = value.copyAndReorder(oldIndex, newIndex);
    final changed = <ClashProvidersCompanion>[];
    next.forEachIndexed((index, item) {
      if (item.order != index) {
        next[index] = item.copyWith(order: index);
        changed.add(item.toCompanion(index));
      }
    });
    optimistic(next, () => database.clashProvidersDao.putAll(changed));
  }

  @override
  bool updateShouldNotify(
    AsyncValue<List<ClashProvider>> previous,
    AsyncValue<List<ClashProvider>> next,
  ) {
    return !clashProviderListEquality.equals(previous.value, next.value);
  }
}

@Riverpod(keepAlive: true)
class IconSets extends _$IconSets with AsyncNotifierMixin, OptimisticMixin {
  @override
  Stream<List<IconSet>> build() {
    final query = database.iconSetsDao.query();
    return settled(query.watch(), query.get);
  }

  @override
  List<IconSet> get value => state.value ?? [];

  void put(IconSet iconSet) {
    final next = List<IconSet>.from(value);
    final index = next.indexWhere((item) => item.id == iconSet.id);
    if (index != -1) {
      next[index] = iconSet;
    } else {
      next.add(iconSet);
    }
    optimistic(next, () => database.iconSets.put(iconSet.toCompanion()));
  }

  void del(int id) {
    optimistic(
      value.where((item) => item.id != id).toList(),
      () => database.iconSets.remove((t) => t.id.equals(id)),
    );
  }

  void order(int oldIndex, int newIndex) {
    final next = value.copyAndReorder(oldIndex, newIndex);
    final changed = <IconSetsCompanion>[];
    next.forEachIndexed((index, item) {
      if (item.order != index) {
        next[index] = item.copyWith(order: index);
        changed.add(item.toCompanion(index));
      }
    });
    optimistic(next, () => database.iconSetsDao.putAll(changed));
  }

  @override
  bool updateShouldNotify(
    AsyncValue<List<IconSet>> previous,
    AsyncValue<List<IconSet>> next,
  ) {
    return !iconSetListEquality.equals(previous.value, next.value);
  }
}

@riverpod
Stream<int> profileGroupsCount(Ref ref, int profileId) {
  return database.proxyGroupsDao.profileGroupsCount(profileId).watchSingle();
}
