part of '../state.dart';

/// Drops a dialer that leads back to its proxy; mihomo would loop on it.
List<Map<String, dynamic>> appProxiesPayload(
  Iterable<CustomProxy> proxies, {
  required Map<int, String> dialers,
  required List<ProxyGroup> groups,
}) {
  final named = {for (final group in groups) ...?group.proxies};
  final chain = {
    for (final proxy in proxies)
      if (named.contains(proxy.name)) proxy.name: ?dialers[proxy.id],
  };
  final looping = _DialLoops(groups, chain).looping;
  final payload = <Map<String, dynamic>>[];
  for (final proxy in proxies) {
    if (!named.contains(proxy.name)) {
      continue;
    }
    final dialer = chain[proxy.name];
    if (dialer != null && !looping.contains(proxy.name)) {
      payload.add({...proxy.definition, 'dialer-proxy': dialer});
      continue;
    }
    if (dialer != null) {
      commonPrint.log(
        'Dropped the dialer of ${proxy.name}: $dialer leads back to it',
        logLevel: LogLevel.warning,
      );
    }
    payload.add({...proxy.definition}..remove('dialer-proxy'));
  }
  return payload;
}

/// Tarjan's components of [edges], numbered as they close, so an edge never
/// leads to a component numbered higher than its own.
List<int> _componentsOf(List<List<int>> edges) {
  final index = List.filled(edges.length, -1);
  final low = List.filled(edges.length, 0);
  final component = List.filled(edges.length, -1);
  final stack = <int>[];
  var visited = 0;
  var closed = 0;
  void connect(int node) {
    index[node] = low[node] = visited++;
    stack.add(node);
    for (final next in edges[node]) {
      if (index[next] == -1) {
        connect(next);
        low[node] = min(low[node], low[next]);
      } else if (component[next] == -1) {
        low[node] = min(low[node], index[next]);
      }
    }
    if (low[node] != index[node]) {
      return;
    }
    int item;
    do {
      item = stack.removeLast();
      component[item] = closed;
    } while (item != node);
    closed++;
  }

  for (var node = 0; node < edges.length; node++) {
    if (index[node] == -1) {
      connect(node);
    }
  }
  return component;
}

bool _takesInEveryProxy(ProxyGroup group) =>
    group.includeAllProxies == true &&
    (group.filter ?? '').isEmpty &&
    (group.excludeFilter ?? '').isEmpty &&
    (group.excludeType ?? '').isEmpty;

class _DialerGraph {
  final declared = <String>{};
  final chained = <String, String>{};
  final members = <String, List<String>>{};
  final groupNames = <String>{};
  final takingEveryProxy = <String>{};
  final parents = <String, List<String>>{};

  _DialerGraph(Iterable<ProxyGroup> groups, Map<String, String> dialers) {
    for (final group in groups) {
      declared.addAll(group.proxies ?? const <String>[]);
    }
    for (final MapEntry(key: name, value: dialer) in dialers.entries) {
      if (declared.contains(name)) {
        chained[name] = dialer;
        members[name] = [dialer];
      }
    }
    for (final group in groups) {
      final takesAll = _takesInEveryProxy(group);
      members[group.name] = [...?group.proxies, if (takesAll) ...chained.keys];
      groupNames.add(group.name);
      if (takesAll) {
        takingEveryProxy.add(group.name);
      } else {
        takingEveryProxy.remove(group.name);
      }
    }
    for (final MapEntry(key: name, value: items) in members.entries) {
      for (final item in items) {
        parents.putIfAbsent(item, () => []).add(name);
      }
    }
  }

  /// The proxy's own dialer is the dial being checked, never a way back.
  Set<String> Function(String target) loopsOf(String proxy) {
    if (!declared.contains(proxy)) {
      return (_) => const {};
    }
    final passesThrough = groupNames.contains(proxy);
    final takenIn = !chained.containsKey(proxy);
    final reaching = <String>{};
    final pending = [...?parents[proxy], if (takenIn) ...takingEveryProxy];
    while (pending.isNotEmpty) {
      final name = pending.removeLast();
      if ((passesThrough || name != proxy) && reaching.add(name)) {
        pending.addAll(parents[name] ?? const []);
      }
    }
    return (target) {
      if (target == proxy) {
        return {proxy};
      }
      final loop = <String>{};
      void walk(String name) {
        if (!reaching.contains(name) || !loop.add(name)) {
          return;
        }
        for (final next in members[name] ?? const <String>[]) {
          walk(next);
        }
        if (takenIn && takingEveryProxy.contains(name)) {
          walk(proxy);
        }
      }

      walk(target);
      return loop;
    };
  }
}

/// Every dial of [dialers] at once: those that loop, and the groups each
/// loop passes through, from reachability between the graph's components
/// rather than one walk per dial.
class _DialLoops {
  final looping = <String>{};
  final throughGroups = <String, List<CustomIssue>>{};

  _DialLoops(Iterable<ProxyGroup> groups, Map<String, String> dialers) {
    final graph = _DialerGraph(groups, dialers);
    final dials = [
      for (final MapEntry(key: proxy, value: target) in dialers.entries)
        if (graph.declared.contains(proxy)) (proxy: proxy, target: target),
    ];
    if (dials.isEmpty) {
      return;
    }
    final ids = <String, int>{};
    for (final MapEntry(key: name, value: items) in graph.members.entries) {
      for (final item in [name, ...items]) {
        ids.putIfAbsent(item, () => ids.length);
      }
    }
    final edges = List.generate(ids.length, (_) => <int>[]);
    for (final MapEntry(key: name, value: items) in graph.members.entries) {
      edges[ids[name]!].addAll([for (final item in items) ids[item]!]);
    }
    final component = _componentsOf(edges);
    final count = component.fold(0, (count, item) => max(count, item + 1));
    final nodes = List.generate(count, (_) => <int>[]);
    for (final (node, item) in component.indexed) {
      nodes[item].add(node);
    }
    final words = (dials.length + 31) >> 5;
    final reaches = List.generate(count, (_) => Uint32List(words));
    final reachedFrom = List.generate(count, (_) => Uint32List(words));
    bool has(Uint32List bits, int dial) =>
        bits[dial >> 5] & (1 << (dial & 31)) != 0;
    void add(Uint32List bits, int dial) => bits[dial >> 5] |= 1 << (dial & 31);
    void merge(Uint32List into, Uint32List from) {
      for (var word = 0; word < words; word++) {
        into[word] |= from[word];
      }
    }

    for (final (dial, (:proxy, :target)) in dials.indexed) {
      add(reaches[component[ids[proxy]!]], dial);
      final node = ids[target];
      if (target != proxy && node != null) {
        add(reachedFrom[component[node]], dial);
      }
    }
    for (var item = 0; item < count; item++) {
      for (final node in nodes[item]) {
        for (final next in edges[node]) {
          if (component[next] != item) {
            merge(reaches[item], reaches[component[next]]);
          }
        }
      }
    }
    for (var item = count - 1; item >= 0; item--) {
      for (final node in nodes[item]) {
        for (final next in edges[node]) {
          if (component[next] != item) {
            merge(reachedFrom[component[next]], reachedFrom[item]);
          }
        }
      }
    }
    for (final (dial, (:proxy, :target)) in dials.indexed) {
      final node = ids[target];
      if (target == proxy ||
          node != null && has(reaches[component[node]], dial)) {
        looping.add(proxy);
      }
    }
    for (final name in graph.groupNames) {
      final node = ids[name]!;
      final item = component[node];
      final onLoop = nodes[item].length > 1 || edges[node].contains(node);
      for (final (dial, (:proxy, :target)) in dials.indexed) {
        final through = target == proxy
            ? name == proxy
            : (name == proxy ? onLoop : has(reaches[item], dial)) &&
                  has(reachedFrom[item], dial);
        if (through) {
          throughGroups
              .putIfAbsent(name, () => [])
              .add(CustomIssue.dialerLoop(proxy, target));
        }
      }
    }
  }
}

/// Names the core registers first; a group may still take GLOBAL.
const reservedProxyNames = {
  'DIRECT',
  'REJECT',
  'REJECT-DROP',
  'COMPATIBLE',
  'PASS',
  'PASS-RULE',
};

const reservedCustomProxyNames = {...reservedProxyNames, 'GLOBAL'};

final _unnamedLinkPattern = RegExp(r'^(-\d+)?$');

String linkProxyName(Map<String, dynamic> definition) {
  final name = definition['name']?.toString().trim() ?? '';
  if (!_unnamedLinkPattern.hasMatch(name)) {
    return name;
  }
  return definition['server']?.toString() ?? definition['type'].toString();
}

String _numberedName(String base, int index) =>
    '$base-${index.toString().padLeft(2, '0')}';

String freeProxyName(String base, Set<String> taken) {
  var name = base;
  for (var index = 1; !taken.add(name); index++) {
    name = _numberedName(base, index);
  }
  return name;
}
