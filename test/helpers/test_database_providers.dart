import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/providers.dart';

class TestGlobalRules extends GlobalRules {
  final List<Rule> initial;

  TestGlobalRules([this.initial = const []]);

  @override
  Stream<List<Rule>> build() => Stream.value(initial);
}

class TestIconSets extends IconSets {
  final List<IconSet> initial;

  TestIconSets([this.initial = const []]);

  @override
  Stream<List<IconSet>> build() => Stream.value(initial);
}

class TestClashProviders extends ClashProviders {
  final List<ClashProvider> initial;

  TestClashProviders([this.initial = const []]);

  @override
  Stream<List<ClashProvider>> build() => Stream.value(initial);
}
