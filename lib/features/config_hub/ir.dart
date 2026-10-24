/// One outbound node, normalized to Clash field names.
///
/// [params] carries every remaining node field verbatim (cipher, password,
/// uuid, network options and so on); [name], [type], [server] and [port] are
/// kept as fields because routing templates and the UI address them directly.
class IrNode {
  const IrNode({
    required this.name,
    required this.type,
    required this.server,
    required this.port,
    this.params = const {},
  });

  final String name;
  final String type;
  final String server;
  final int port;
  final Map<String, Object?> params;

  /// The full Clash proxy map this node renders to.
  Map<String, Object?> toClashMap() => {
    'name': name,
    'type': type,
    'server': server,
    'port': port,
    ...params,
  };
}

/// The normalized form of any import payload.
class IrProfile {
  const IrProfile({
    this.nodes = const [],
    this.groups = const [],
    this.rules = const [],
  });

  final List<IrNode> nodes;
  final List<Map<String, Object?>> groups;
  final List<String> rules;

  /// The Clash config map this profile renders to, before any template.
  Map<String, Object?> toClashMap() => {
    'proxies': [for (final node in nodes) node.toClashMap()],
    if (groups.isNotEmpty) 'proxy-groups': groups,
    if (rules.isNotEmpty) 'rules': rules,
  };
}

/// The outcome of parsing one import payload.
class IrParseResult {
  const IrParseResult({
    required this.profile,
    this.unsupported = const [],
    this.skipped = const [],
  });

  final IrProfile profile;

  /// Protocol schemes or outbound types seen but not converted, in the form
  /// they appeared (for example `snell://` or `outbound type "naive"`).
  final List<String> unsupported;

  /// Outbounds deliberately dropped because they are not nodes, such as
  /// sing-box `direct` and `block` entries, by tag.
  final List<String> skipped;
}
