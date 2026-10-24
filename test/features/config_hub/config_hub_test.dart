import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/features/config_hub/config_hub.dart';

const singboxSample = '''
{
  "outbounds": [
    {
      "type": "shadowsocks",
      "tag": "SS",
      "server": "1.2.3.4",
      "server_port": 8388,
      "method": "aes-256-gcm",
      "password": "password"
    },
    {
      "type": "vmess",
      "tag": "VMess",
      "server": "5.6.7.8",
      "server_port": 443,
      "uuid": "11111111-2222-3333-4444-555555555555",
      "security": "auto",
      "transport": {"type": "ws", "path": "/ws"}
    },
    {
      "type": "vless",
      "tag": "VLESS",
      "server": "9.9.9.9",
      "server_port": 443,
      "uuid": "22222222-3333-4444-5555-666666666666",
      "flow": "xtls-rprx-vision"
    },
    {
      "type": "trojan",
      "tag": "Trojan",
      "server": "10.0.0.1",
      "server_port": 443,
      "password": "trojanpass"
    },
    {
      "type": "hysteria2",
      "tag": "HY2",
      "server": "11.0.0.2",
      "server_port": 443,
      "password": "hy2pass",
      "obfs": {"type": "salamander", "password": "obfspass"}
    },
    {
      "type": "selector",
      "tag": "PROXY",
      "outbounds": ["SS", "VMess", "VLESS", "Trojan", "HY2"]
    },
    {
      "type": "urltest",
      "tag": "Auto",
      "outbounds": ["SS", "VMess"],
      "url": "https://www.gstatic.com/generate_204",
      "interval": "5m"
    },
    {"type": "direct", "tag": "DIRECT"},
    {"type": "block", "tag": "REJECT"}
  ]
}
''';

const shareLinksSample = '''
ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@1.2.3.4:8388#SSNode
vmess://eyJ2IjogIjIiLCAicHMiOiAiVm1lc3NOb2RlIiwgImFkZCI6ICI1LjYuNy44IiwgInBvcnQiOiAiNDQzIiwgImlkIjogIjExMTExMTExLTIyMjItMzMzMy00NDQ0LTU1NTU1NTU1NTU1NSIsICJhaWQiOiAiMCIsICJzY3kiOiAiYXV0byIsICJuZXQiOiAid3MiLCAidHlwZSI6ICJub25lIiwgImhvc3QiOiAiZXhhbXBsZS5jb20iLCAicGF0aCI6ICIvd3MiLCAidGxzIjogInRscyJ9
vless://22222222-3333-4444-5555-666666666666@9.9.9.9:443?security=reality&sni=example.com&fp=chrome&pbk=pubkey123&sid=abcd&type=tcp#VlessNode
trojan://trojanpass@10.0.0.1:443?sni=example.com#TrojanNode
hysteria2://hy2pass@11.0.0.2:443?obfs=salamander&obfs-password=obfspass&sni=example.com#Hy2Node
''';

const base64SubscriptionSample =
    'c3M6Ly9ZV1Z6TFRJMU5pMW5ZMjA2Y0dGemMzZHZjbVFAMS4yLjMuNDo4Mzg4I1NTTm9kZQp2bWVzczovL2V5SjJJam9nSWpJaUxDQWljSE1pT2lBaVZtMWxjM05PYjJSbElpd2dJbUZrWkNJNklDSTFMall1Tnk0NElpd2dJbkJ2Y25RaU9pQWlORFF6SWl3Z0ltbGtJam9nSWpFeE1URXhNVEV4TFRJeU1qSXRNek16TXkwME5EUTBMVFUxTlRVMU5UVTFOVFUxTlNJc0lDSmhhV1FpT2lBaU1DSXNJQ0p6WTNraU9pQWlZWFYwYnlJc0lDSnVaWFFpT2lBaWQzTWlMQ0FpZEhsd1pTSTZJQ0p1YjI1bElpd2dJbWh2YzNRaU9pQWlaWGhoYlhCc1pTNWpiMjBpTENBaWNHRjBhQ0k2SUNJdmQzTWlMQ0FpZEd4eklqb2dJblJzY3lKOSNWbWVzc05vZGUKdmxlc3M6Ly8yMjIyMjIyMi0zMzMzLTQ0NDQtNTU1NS02NjY2NjY2NjY2NjZAOS45LjkuOTo0NDM/c2VjdXJpdHk9cmVhbGl0eSZzbmk9ZXhhbXBsZS5jb20mZnA9Y2hyb21lJnBiaz1wdWJrZXkxMjMmc2lkPWFiY2QmdHlwZT10Y3AjVmxlc3NOb2RlCnRyb2phbjovL3Ryb2phbnBhc3NAMTAuMC4wLjE6NDQzP3NuaT1leGFtcGxlLmNvbSNUcm9qYW5Ob2RlCmh5c3RlcmlhMjovL2h5MnBhc3NAMTEuMC4wLjI6NDQzP29iZnM9c2FsYW1hbmRlciZvYmZzLXBhc3N3b3JkPW9iZnNwYXNzJnNuaT1leGFtcGxlLmNvbSNIeTJOb2Rl';

const clashSample = '''
proxies:
  - name: "SS"
    type: ss
    server: 1.2.3.4
    port: 8388
    cipher: aes-256-gcm
    password: password
proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
      - "SS"
rules:
  - "MATCH,PROXY"
''';

void main() {
  test('sing-box sample maps nodes, groups and skips', () {
    final result = parseConfig(singboxSample);
    expect(result.profile.nodes.length, 5);
    expect(
      [for (final node in result.profile.nodes) node.type],
      ['ss', 'vmess', 'vless', 'trojan', 'hysteria2'],
    );
    final ss = result.profile.nodes.first;
    expect(ss.server, '1.2.3.4');
    expect(ss.port, 8388);
    expect(ss.params['cipher'], 'aes-256-gcm');
    expect(ss.params['password'], 'password');
    final vmess = result.profile.nodes[1];
    expect(vmess.params['uuid'], '11111111-2222-3333-4444-555555555555');
    expect(vmess.params['network'], 'ws');
    final hy2 = result.profile.nodes.last;
    expect(hy2.params['obfs'], 'salamander');
    expect(hy2.params['obfs-password'], 'obfspass');
    expect(result.profile.groups.length, 2);
    expect(result.profile.groups[0]['type'], 'select');
    expect(result.profile.groups[1]['type'], 'url-test');
    expect(result.skipped, ['DIRECT', 'REJECT']);
    expect(result.unsupported, isEmpty);
  });

  test('share links sample parses every protocol without field loss', () {
    final result = parseConfig(shareLinksSample);
    expect(result.profile.nodes.length, 5);
    final byType = {for (final node in result.profile.nodes) node.type: node};
    expect(byType['ss']!.params['password'], 'password');
    expect(byType['ss']!.port, 8388);
    expect(
      byType['vmess']!.params['uuid'],
      '11111111-2222-3333-4444-555555555555',
    );
    expect(byType['vmess']!.params['tls'], true);
    expect(byType['vless']!.params['uuid'], isNotEmpty);
    expect(byType['trojan']!.params['password'], 'trojanpass');
    expect(byType['hysteria2']!.params['password'], 'hy2pass');
    expect(result.unsupported, isEmpty);
  });

  test('base64 subscription decodes to the same link set', () {
    final result = parseConfig(base64SubscriptionSample);
    expect(detectFormat(base64SubscriptionSample), ConfigFormat.subscription);
    expect(result.profile.nodes.length, 5);
    expect(
      [for (final node in result.profile.nodes) node.type],
      ['ss', 'vmess', 'vless', 'trojan', 'hysteria2'],
    );
  });

  test('template replaces groups and rules but keeps proxies', () {
    final result = parseConfig(clashSample);
    final templated = applyTemplate(
      result.profile.toClashMap(),
      kfusionDefaultTemplate.id,
    );
    final proxies = templated['proxies'] as List;
    expect(proxies.length, 1);
    expect((proxies.first as Map)['name'], 'SS');
    final groups = templated['proxy-groups'] as List;
    expect(groups.length, 1);
    expect((groups.first as Map)['type'], 'url-test');
    expect((groups.first as Map)['proxies'], ['SS']);
    expect(templated['rules'], kfusionDefaultRules);
    final kept = applyTemplate(
      result.profile.toClashMap(),
      keepOriginalTemplate.id,
    );
    expect(kept['rules'], ['MATCH,PROXY']);
    expect((kept['proxy-groups'] as List).length, 1);
  });

  test('render produces Clash YAML with the three sections', () {
    final result = parseConfig(clashSample);
    final yaml = renderClashYaml(result.profile);
    expect(yaml, contains('proxies:'));
    expect(yaml, contains('proxy-groups:'));
    expect(yaml, contains('rules:'));
  });

  test('sniffing distinguishes the four input kinds', () {
    expect(detectFormat(clashSample), ConfigFormat.clash);
    expect(detectFormat(singboxSample), ConfigFormat.singbox);
    expect(detectFormat(base64SubscriptionSample), ConfigFormat.subscription);
    expect(detectFormat(shareLinksSample), ConfigFormat.shareLinks);
  });

  test('unsupported schemes are listed without aborting the batch', () {
    final result = parseConfig(
      'snell://user:pass@1.2.3.4:1234#Snell\n'
      'ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@1.2.3.4:8388#SSNode',
    );
    expect(result.profile.nodes.length, 1);
    expect(result.unsupported, ['snell://']);
  });
}
