import 'dart:async';

import 'package:drift/native.dart';
// `Profiles` names both a drift table and a notifier,
// so the schema side is imported behind a prefix.
import 'package:kfusion/database/database.dart' as db;
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/l10n/l10n.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/database.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';

/// Every notifier in `lib/providers/database.dart` writes optimistically: the
/// in-memory state is mutated first and the row is persisted afterwards through
/// [withRollback], which restores the pre-mutation snapshot when the write
/// fails. These tests drive the real drift schema on an in-memory executor so
/// both halves — the optimistic value and the rollback — are observable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const profileId = 1;

  late db.Database testDatabase;
  late ProviderContainer container;

  Profile profile(int id, {String label = '', int? order}) => Profile(
    id: id,
    label: label,
    autoUpdateDuration: Duration.zero,
    order: order,
  );

  setUpAll(() => AppLocalizations.load(const Locale('en')));

  setUp(() async {
    testDatabase = db.Database(NativeDatabase.memory());
    db.database = testDatabase;
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await testDatabase.close();
  });

  /// Subscribes to [provider] so it survives auto-dispose for the whole test,
  /// then waits for the backing drift stream to deliver its first row set.
  Future<void> keepAlive(ProviderListenable<Object?> provider) async {
    container.listen(provider, (_, _) {});
    await pumpEventQueue();
  }

  /// Most call sites wrap the persist step in `unawaited(...)`, so the failure
  /// never reaches the caller: the notifier logs it, and only after the
  /// rollback has already restored the snapshot.
  Future<void> captureWriteFailure(void Function() body) {
    final reported = Completer<void>();
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message?.contains('Optimistic database write failed') ?? false) {
        if (!reported.isCompleted) reported.complete();
      }
    };
    addTearDown(() => debugPrint = print);
    body();
    return reported.future.timeout(const Duration(seconds: 5));
  }

  /// `customStatement` does not raise a drift table-update notification, so the
  /// streams the notifiers watch keep serving their last good rows — which is
  /// what lets a test observe the rolled-back state rather than an error state.
  Future<void> breakTable(String table) =>
      testDatabase.customStatement('DROP TABLE $table');

  group('withRollback', () {
    test('rolls back with snapshot and rethrows async errors', () async {
      final error = StateError('write failed');
      final previous = [1, 2, 3];
      List<int>? rolledBack;

      await expectLater(
        withRollback(
          snapshot: previous,
          action: () async {
            throw error;
          },
          rollback: (value) => rolledBack = value,
        ),
        throwsA(same(error)),
      );

      expect(rolledBack, previous);
    });

    test('does not roll back when action succeeds', () async {
      var rollbackCalled = false;

      await withRollback(
        snapshot: [1, 2, 3],
        action: () async {},
        rollback: (_) => rollbackCalled = true,
      );

      expect(rollbackCalled, false);
    });
  });

  group('Profiles', () {
    late Profiles notifier;

    setUp(() async {
      await keepAlive(profilesProvider);
      notifier = container.read(profilesProvider.notifier);
    });

    List<Profile> read() => container.read(profilesProvider);

    test('put persists the row and the stream echoes it back', () async {
      notifier.put(profile(1, label: 'First'));

      expect(read().single.label, 'First');
      await pumpEventQueue();

      final rows = await testDatabase.profilesDao.query().get();
      expect(rows.single.label, 'First');
      expect(read().single.label, 'First');
    });

    test(
      'put de-duplicates a label already taken by another profile',
      () async {
        notifier.put(profile(1, label: 'Shared'));
        await pumpEventQueue();

        notifier.put(profile(2, label: 'Shared'));
        await pumpEventQueue();

        final labels = read().map((item) => item.label).toSet();
        expect(labels, {'Shared', 'Shared(1)'});
      },
    );

    test('a read-back during a write keeps the optimistic profile', () async {
      final rows = StreamController<List<Profile>>();
      addTearDown(rows.close);
      final scoped = ProviderContainer(
        overrides: [profilesStreamProvider.overrideWith((_) => rows.stream)],
      );
      addTearDown(scoped.dispose);
      scoped.listen(profilesProvider, (_, _) {});
      rows.add(const []);
      await pumpEventQueue();
      final landing = Completer<void>();
      final held = testDatabase.transaction(() => landing.future);

      scoped.read(profilesProvider.notifier).put(profile(1, label: 'Mine'));
      rows.add([profile(2, label: 'Theirs')]);
      await pumpEventQueue();
      expect(scoped.read(profilesProvider).map((item) => item.id), [1]);

      landing.complete();
      await held;
      await pumpEventQueue();
      rows.add([profile(1, label: 'Mine'), profile(2, label: 'Theirs')]);
      await pumpEventQueue();
      expect(scoped.read(profilesProvider).map((item) => item.id), [1, 2]);
    });

    test('put falls back to the id when the profile has no label', () async {
      // Profile.normal() leaves the label empty when the download exposed no
      // filename, and optimizeLabel is the only thing that names it.
      notifier.put(profile(42));
      await pumpEventQueue();

      expect(read().single.label, '42');
      final rows = await testDatabase.profilesDao.query().get();
      expect(rows.single.label, '42');
    });

    test(
      'put keeps the label when the same profile is written again',
      () async {
        notifier.put(profile(1, label: 'Stable'));
        await pumpEventQueue();

        notifier.put(profile(1, label: 'Stable'));
        await pumpEventQueue();

        expect(read().single.label, 'Stable');
      },
    );

    Profile custom(int id) =>
        profile(id, label: 'Custom $id').copyWith(type: ProfileType.custom);

    test(
      'a new label follows into the groups of every custom profile',
      () async {
        notifier.put(profile(1, label: 'Home'));
        for (final id in [2, 3]) {
          notifier.put(custom(id));
        }
        await pumpEventQueue();
        for (final id in [2, 3]) {
          await testDatabase.proxyGroups.put(
            ProxyGroup(
              id: id,
              name: 'Group',
              type: GroupType.Selector,
              use: const ['Home', 'Other'],
            ).toCompanion(id),
          );
        }

        notifier.put(profile(1, label: 'Away'));
        await pumpEventQueue();

        Future<List<String>?> use(int id) async =>
            (await testDatabase.proxyGroupsDao.query(id).get()).single.use;
        expect(await use(2), ['Away', 'Other']);
        expect(await use(3), ['Away', 'Other']);
      },
    );

    test('a new label follows into the provider options of every custom '
        'profile', () async {
      const options = ProxyProviderOptions(filter: 'HK');
      notifier.put(profile(1, label: 'Home'));
      for (final id in [2, 3]) {
        notifier.put(
          custom(id).copyWith(
            overrides: const ProfileOverrides(
              proxyProviders: {'Home': options},
            ),
          ),
        );
      }
      await pumpEventQueue();

      notifier.put(profile(1, label: 'Away'));
      await pumpEventQueue();

      Map<String, ProxyProviderOptions> optionsOf(int id) =>
          read().firstWhere((item) => item.id == id).overrides.proxyProviders;
      expect(optionsOf(2), {'Away': options});
      expect(optionsOf(3), {'Away': options});
      final rows = await testDatabase.profilesDao.query().get();
      expect(rows.firstWhere((item) => item.id == 3).overrides.proxyProviders, {
        'Away': options,
      });
    });

    test('a custom profile is never a provider, so its label renames '
        'nothing', () async {
      notifier.put(custom(2));
      await pumpEventQueue();
      await testDatabase.proxyGroups.put(
        const ProxyGroup(
          id: 9,
          name: 'Group',
          type: GroupType.Selector,
          use: ['Custom 2'],
        ).toCompanion(2),
      );

      notifier.put(custom(2).copyWith(label: 'Renamed'));
      await pumpEventQueue();

      final group = (await testDatabase.proxyGroupsDao.query(2).get()).single;
      expect(group.use, ['Custom 2']);
    });

    test('put restores the previous list when the write fails', () async {
      notifier.put(profile(1, label: 'Kept'));
      await pumpEventQueue();
      await breakTable('profiles');

      final failure = captureWriteFailure(
        () => notifier.put(profile(2, label: 'Lost')),
      );
      expect(read().map((item) => item.id), [2, 1], reason: 'optimistic');

      await failure;
      expect(read().map((item) => item.id), [1], reason: 'rolled back');
    });

    test('del awaits the write and rethrows after rolling back', () async {
      notifier.put(profile(1, label: 'Kept'));
      await pumpEventQueue();
      await breakTable('profiles');

      await expectLater(notifier.del(1), throwsA(isA<Exception>()));
      expect(read().map((item) => item.id), [1]);
    });

    test('del removes the row when the write succeeds', () async {
      notifier.put(profile(1, label: 'Gone'));
      await pumpEventQueue();

      await notifier.del(1);
      await pumpEventQueue();

      expect(read(), isEmpty);
      expect(await testDatabase.profilesDao.query().get(), isEmpty);
    });

    test('updateProfile ignores an id that is not in state', () async {
      notifier.put(profile(1, label: 'Only'));
      await pumpEventQueue();

      notifier.updateProfile(404, (item) => item.copyWith(label: 'Never'));
      await pumpEventQueue();

      expect(read().single.label, 'Only');
    });

    test('updateProfile applies the builder and persists it', () async {
      notifier.put(profile(1, label: 'Before'));
      await pumpEventQueue();

      notifier.updateProfile(1, (item) => item.copyWith(label: 'After'));
      expect(read().single.label, 'After');
      await pumpEventQueue();

      final rows = await testDatabase.profilesDao.query().get();
      expect(rows.single.label, 'After');
    });

    test(
      'updateProfile restores the previous list when the write fails',
      () async {
        notifier.put(profile(1, label: 'Before'));
        await pumpEventQueue();
        await breakTable('profiles');

        final failure = captureWriteFailure(
          () => notifier.updateProfile(
            1,
            (item) => item.copyWith(label: 'After'),
          ),
        );
        expect(read().single.label, 'After', reason: 'optimistic');

        await failure;
        expect(read().single.label, 'Before', reason: 'rolled back');
      },
    );

    test('reorder only writes the rows whose order actually changed', () async {
      notifier
        ..put(profile(1, label: 'One', order: 0))
        ..put(profile(2, label: 'Two', order: 1));
      await pumpEventQueue();

      notifier.reorder([
        profile(2, label: 'Two', order: 1),
        profile(1, label: 'One', order: 0),
      ]);
      await pumpEventQueue();

      final rows = await testDatabase.profilesDao.query().get();
      expect(rows.map((item) => item.id), [2, 1]);
      expect(rows.map((item) => item.order), [0, 1]);
    });

    test('reorder restores the previous order when the write fails', () async {
      notifier
        ..put(profile(1, label: 'One', order: 0))
        ..put(profile(2, label: 'Two', order: 1));
      await pumpEventQueue();
      await breakTable('profiles');

      final failure = captureWriteFailure(
        () => notifier.reorder([
          profile(2, label: 'Two', order: 1),
          profile(1, label: 'One', order: 0),
        ]),
      );
      expect(read().map((item) => item.id), [2, 1], reason: 'optimistic');

      await failure;
      expect(read().map((item) => item.id), [1, 2], reason: 'rolled back');
    });
  });

  group('ClashProviders', () {
    test(
      'renaming a set renames it wherever a custom profile names it',
      () async {
        const overrides = ProfileOverrides(
          dns: Dns(
            nameserverPolicy: {'rule-set:ads,cn': '223.5.5.5'},
            fakeIpFilter: ['rule-set:ads'],
          ),
          dnsOverrideKeys: {
            DnsOverrideKey.nameserverPolicy,
            DnsOverrideKey.fakeIpFilter,
          },
          sniffer: Sniffer(skipDomain: ['rule-set:ads']),
          snifferOverrideKeys: {SnifferOverrideKey.skipDomain},
        );
        await keepAlive(profilesProvider);
        await keepAlive(clashProvidersProvider);
        container
            .read(profilesProvider.notifier)
            .put(
              profile(
                profileId,
                label: 'Custom',
              ).copyWith(type: ProfileType.custom, overrides: overrides),
            );
        final providers = container.read(clashProvidersProvider.notifier);
        providers.put(const ClashProvider(id: 5, label: 'ads'));
        await pumpEventQueue();
        await testDatabase.rulesDao.putRule(
          const Rule(
            id: 9,
            ruleAction: RuleAction.RULE_SET,
            ruleProvider: 'ads',
            ruleTarget: 'REJECT',
            order: 'a',
          ),
          profileId: profileId,
        );

        providers.put(const ClashProvider(id: 5, label: 'block'));
        await pumpEventQueue();

        final rule =
            (await testDatabase.rulesDao.queryProfileRules(profileId).get())
                .single;
        expect(rule.ruleProvider, 'block');
        final row = (await testDatabase.profilesDao.query().get()).single;
        expect(row.overrides.ruleSets, {'block', 'cn'});
        expect(row.overrides.dns.nameserverPolicy.keys, ['rule-set:block,cn']);
        expect(row.overrides.dns.fakeIpFilter, ['rule-set:block']);
        expect(row.overrides.sniffer.skipDomain, ['rule-set:block']);
        expect(container.read(profilesProvider).single, row);
      },
    );
  });
}
