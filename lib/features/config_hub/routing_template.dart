/// Routing templates for the universal import.
///
/// A template only ever replaces `proxy-groups` and `rules`; `proxies` are
/// always kept verbatim, so re-importing with a template can never drop a
/// node the user already had.
class RoutingTemplate {
  const RoutingTemplate({required this.id, required this.label});

  final String id;
  final String label;
}

const kfusionDefaultTemplate = RoutingTemplate(
  id: 'kfusion-default',
  label: 'KFusion 默认',
);

const keepOriginalTemplate = RoutingTemplate(
  id: 'keep-original',
  label: '保留原配置',
);

const routingTemplates = [kfusionDefaultTemplate, keepOriginalTemplate];

/// The rules of the KFusion default template. DIRECT is the built-in policy
/// here, not a proxy group: a group named DIRECT would shadow it.
const kfusionDefaultRules = [
  'GEOSITE,CN,DIRECT',
  'GEOIP,CN,DIRECT',
  'GEOIP,private,DIRECT',
  'MATCH,PROXY',
];

/// Applies [templateId] to a Clash config map and returns a new map.
Map<String, Object?> applyTemplate(
  Map<String, Object?> clashConfig,
  String templateId,
) {
  if (templateId == keepOriginalTemplate.id) {
    return Map<String, Object?>.from(clashConfig);
  }
  final proxies = [
    for (final entry in (clashConfig['proxies'] as List? ?? const []))
      if (entry is Map) entry,
  ];
  final names = [for (final proxy in proxies) proxy['name'].toString()];
  final result = Map<String, Object?>.from(clashConfig);
  result['proxy-groups'] = [
    {
      'name': 'PROXY',
      'type': 'url-test',
      'proxies': names,
      'url': 'https://www.gstatic.com/generate_204',
      'interval': 300,
    },
  ];
  result['rules'] = kfusionDefaultRules;
  return result;
}
