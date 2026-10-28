import 'package:kfusion/common/common.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/config_hub/config_hub.dart';
import 'package:kfusion/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

const _profileDns = <String, dynamic>{
  'enable': true,
  'listen': '0.0.0.0:53',
  'nameserver': ['9.9.9.9'],
  'fallback-filter': {
    'geoip': false,
    'domain': ['keep.me'],
  },
};

const _dns = Dns(
  listen: ':1053',
  ipv6: true,
  nameserver: ['1.1.1.1'],
  fallbackFilter: FallbackFilter(geoip: true),
);

const _keys = {
  DnsOverrideKey.nameserver,
  DnsOverrideKey.fallbackFilterGeoip,
  DnsOverrideKey.ipv6,
};

Future<YamlMap> _dnsOf({
  required Map<String, dynamic> rawConfig,
  Dns dns = _dns,
  Set<DnsOverrideKey> keys = _keys,
  bool keepEmpty = false,
}) async {
  final result = await makeRealProfileTask(
    MakeRealProfileState(
      profilesPath: '/profiles',
      profileId: 1,
      rawConfig: rawConfig,
      realPatchConfig: const PatchClashConfig(),
      overrides: ProfileOverrides(dns: dns, dnsOverrideKeys: keys),
      keepEmptyDnsOverrides: keepEmpty,
      appendSystemDns: false,
      proxyGroups: const [],
      rules: const [],
      addedRules: const [],
      defaultUA: 'FlClash-Test',
    ),
  );
  final config = loadYaml(result.yaml) as YamlMap;
  return config['dns'] as YamlMap;
}

void main() {
  test('overrides only the selected DNS keys of an enabled profile', () async {
    final dns = await _dnsOf(rawConfig: {'dns': _profileDns});

    expect(dns['nameserver'], ['1.1.1.1']);
    expect(dns['ipv6'], true);
    expect(dns['listen'], '0.0.0.0:53');
    expect(dns['fallback-filter'], {
      'geoip': true,
      'domain': ['keep.me'],
    });
  });

  test('leaves an enabled profile alone without picked keys', () async {
    final dns = await _dnsOf(rawConfig: {'dns': _profileDns}, keys: {});

    expect(dns['nameserver'], ['9.9.9.9']);
    expect(dns.containsKey('ipv6'), isFalse);
    expect(dns['fallback-filter'], {
      'geoip': false,
      'domain': ['keep.me'],
    });
  });

  test(
    'fills the minimal defaults plus overrides for a profile without DNS',
    () async {
      final dns = await _dnsOf(rawConfig: {});

      expect(dns, {
        'enable': true,
        'enhanced-mode': 'fake-ip',
        'nameserver': ['1.1.1.1'],
        'proxy-server-nameserver': [
          'https://223.5.5.5/dns-query',
          'https://119.29.29.29/dns-query',
        ],
        'ipv6': true,
        'fallback-filter': {'geoip': true},
      });
    },
  );

  test('a key picked without a value writes nothing', () async {
    final dns = await _dnsOf(
      rawConfig: {'dns': _profileDns},
      dns: const Dns(nameserver: [], listen: ''),
      keys: {DnsOverrideKey.nameserver, DnsOverrideKey.listen},
    );

    expect(dns['nameserver'], ['9.9.9.9']);
    expect(dns['listen'], '0.0.0.0:53');
  });

  test('an app entry emptied over a subscription replaces its value, save '
      'nameserver', () async {
    final dns = await _dnsOf(
      rawConfig: {'dns': _profileDns},
      dns: const Dns(
        nameserver: [],
        listen: '',
        fallbackFilter: FallbackFilter(domain: []),
      ),
      keys: {
        DnsOverrideKey.nameserver,
        DnsOverrideKey.listen,
        DnsOverrideKey.fallbackFilterDomain,
      },
      keepEmpty: true,
    );

    expect(dns['nameserver'], ['9.9.9.9']);
    expect(dns['listen'], '');
    expect(dns['fallback-filter'], {'geoip': false, 'domain': []});
  });

  test('a hub-imported profile with a domain server gets a proxy-server '
      'nameserver from the baseline', () async {
    const source = '''
proxies:
  - name: domain-node
    type: vless
    server: node.example.com
    port: 443
    uuid: 00000000-0000-0000-0000-000000000000
  - name: ip-node
    type: vless
    server: 203.0.113.7
    port: 443
    uuid: 00000000-0000-0000-0000-000000000000
''';
    final parsed = parseConfig(source);
    final hubYaml = yaml.encode(
      applyTemplate(parsed.profile.toClashMap(), kfusionDefaultTemplate.id),
    );
    final rawConfig = <String, dynamic>{
      for (final entry in (loadPlainYaml(hubYaml) as Map).entries)
        entry.key.toString(): entry.value,
    };
    final result = await makeRealProfileTask(
      MakeRealProfileState(
        profilesPath: '/profiles',
        profileId: 1,
        rawConfig: rawConfig,
        realPatchConfig: const PatchClashConfig(),
        overrides: const ProfileOverrides(),
        keepEmptyDnsOverrides: true,
        appendSystemDns: false,
        proxyGroups: const [],
        rules: const [],
        addedRules: const [],
        defaultUA: 'FlClash-Test',
      ),
    );
    final config = loadYaml(result.yaml) as YamlMap;
    final dns = config['dns'] as YamlMap;
    expect(dns['proxy-server-nameserver'], baselineDns.proxyServerNameserver);
    final proxies = config['proxies'] as YamlList;
    expect(
      proxies.any(
        (proxy) => (proxy as YamlMap)['server'] == 'node.example.com',
      ),
      isTrue,
    );
  });
}
