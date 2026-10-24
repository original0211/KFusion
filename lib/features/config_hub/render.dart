import 'package:kfusion/common/yaml.dart';
import 'package:kfusion/features/config_hub/ir.dart';

/// Renders an [IrProfile] to Clash YAML text, using the project's own
/// YAML writer. Node fields are only renamed to Clash names, never
/// rewritten, so the core receives exactly what was imported.
String renderClashYaml(IrProfile profile) {
  return yaml.encode(profile.toClashMap());
}
