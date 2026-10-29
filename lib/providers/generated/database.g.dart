// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../database.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(profilesStream)
final profilesStreamProvider = ProfilesStreamProvider._();

final class ProfilesStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Profile>>,
          List<Profile>,
          Stream<List<Profile>>
        >
    with $FutureModifier<List<Profile>>, $StreamProvider<List<Profile>> {
  ProfilesStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'profilesStreamProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$profilesStreamHash();

  @$internal
  @override
  $StreamProviderElement<List<Profile>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Profile>> create(Ref ref) {
    return profilesStream(ref);
  }
}

String _$profilesStreamHash() => r'ea944e081294567f0f63286e95e4e66cdc650383';

@ProviderFor(Profiles)
final profilesProvider = ProfilesProvider._();

final class ProfilesProvider
    extends $NotifierProvider<Profiles, List<Profile>> {
  ProfilesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'profilesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$profilesHash();

  @$internal
  @override
  Profiles create() => Profiles();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<Profile> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<Profile>>(value),
    );
  }
}

String _$profilesHash() => r'60f47803bd141627e5354018339d13704b00d31e';

abstract class _$Profiles extends $Notifier<List<Profile>> {
  List<Profile> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<Profile>, List<Profile>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<Profile>, List<Profile>>,
              List<Profile>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(ClashProviders)
final clashProvidersProvider = ClashProvidersProvider._();

final class ClashProvidersProvider
    extends $StreamNotifierProvider<ClashProviders, List<ClashProvider>> {
  ClashProvidersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'clashProvidersProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$clashProvidersHash();

  @$internal
  @override
  ClashProviders create() => ClashProviders();
}

String _$clashProvidersHash() => r'00588fa9c7300d3319d97d61962e898d29497188';

abstract class _$ClashProviders extends $StreamNotifier<List<ClashProvider>> {
  Stream<List<ClashProvider>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<List<ClashProvider>>, List<ClashProvider>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<ClashProvider>>, List<ClashProvider>>,
              AsyncValue<List<ClashProvider>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(IconSets)
final iconSetsProvider = IconSetsProvider._();

final class IconSetsProvider
    extends $StreamNotifierProvider<IconSets, List<IconSet>> {
  IconSetsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'iconSetsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$iconSetsHash();

  @$internal
  @override
  IconSets create() => IconSets();
}

String _$iconSetsHash() => r'fe06735ac9d8c8968278e163a3fcd5a3c0deb1d9';

abstract class _$IconSets extends $StreamNotifier<List<IconSet>> {
  Stream<List<IconSet>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<IconSet>>, List<IconSet>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<IconSet>>, List<IconSet>>,
              AsyncValue<List<IconSet>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(profileGroupsCount)
final profileGroupsCountProvider = ProfileGroupsCountFamily._();

final class ProfileGroupsCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, Stream<int>>
    with $FutureModifier<int>, $StreamProvider<int> {
  ProfileGroupsCountProvider._({
    required ProfileGroupsCountFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'profileGroupsCountProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$profileGroupsCountHash();

  @override
  String toString() {
    return r'profileGroupsCountProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<int> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<int> create(Ref ref) {
    final argument = this.argument as int;
    return profileGroupsCount(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ProfileGroupsCountProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$profileGroupsCountHash() =>
    r'c82d409c32b5467619c51bba28b2066b6ea09c59';

final class ProfileGroupsCountFamily extends $Family
    with $FunctionalFamilyOverride<Stream<int>, int> {
  ProfileGroupsCountFamily._()
    : super(
        retry: null,
        name: r'profileGroupsCountProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ProfileGroupsCountProvider call(int profileId) =>
      ProfileGroupsCountProvider._(argument: profileId, from: this);

  @override
  String toString() => r'profileGroupsCountProvider';
}
