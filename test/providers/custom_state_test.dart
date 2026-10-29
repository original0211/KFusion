import 'dart:io';

import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('dialers', () {
    const landing = ProxyGroup(
      id: 3,
      name: 'Landing',
      type: GroupType.Selector,
      proxies: ['Home'],
    );
    const relay = ProxyGroup(
      id: 4,
      name: 'Relay',
      type: GroupType.Selector,
      proxies: ['Node'],
    );
    const home = CustomProxy(id: 9, definition: {'name': 'Home', 'type': 'ss'});

    test('the payload declares the named proxies with the profile dialers only '
        'and drops a looping one', () {
      const work = CustomProxy(
        id: 10,
        definition: {'name': 'Work', 'type': 'ss', 'dialer-proxy': 'Node'},
      );
      const unnamed = CustomProxy(
        id: 12,
        definition: {'name': 'Unnamed', 'type': 'ss'},
      );
      final payload = appProxiesPayload(
        [home, work, unnamed],
        dialers: {9: 'Landing'},
        groups: [
          landing.copyWith(proxies: ['Home', 'Work']),
          relay,
        ],
      );
      expect(payload, [
        home.definition,
        {'name': 'Work', 'type': 'ss'},
      ]);
      expect(
        appProxiesPayload(
          [home, work],
          dialers: {9: 'Work', 10: 'Home'},
          groups: [
            landing.copyWith(proxies: ['Home', 'Work']),
          ],
        ),
        [
          home.definition,
          {'name': 'Work', 'type': 'ss'},
        ],
      );
      expect(
        appProxiesPayload(
          [home],
          dialers: {9: 'Relay'},
          groups: const [landing, relay],
        ),
        [
          {'name': 'Home', 'type': 'ss', 'dialer-proxy': 'Relay'},
        ],
      );
    });

    test('include-all-proxies declares no app proxy of its own and drops a '
        'dialer it loops back through', () {
      const unnamed = CustomProxy(
        id: 12,
        definition: {'name': 'Unnamed', 'type': 'ss'},
      );
      const all = ProxyGroup(
        id: 6,
        name: 'All',
        type: GroupType.Selector,
        includeAllProxies: true,
      );
      expect(
        appProxiesPayload(
          [home, unnamed],
          dialers: {9: 'All', 12: 'Relay'},
          groups: const [all, landing],
        ),
        [home.definition],
      );
    });
  });

  test('customProxyTypes lists every type the core parses', () {
    final source = File('core/Clash.Meta/adapter/parser.go').readAsStringSync();
    expect(customProxyTypes, [
      for (final match in RegExp(
        r'^\tcase "([^"]+)":',
        multiLine: true,
      ).allMatches(source))
        match.group(1)!,
    ]);
  });

  group('proxy fields follow the option structs of the core', () {
    const root = 'core/Clash.Meta/adapter';
    final structs = {
      for (final file in Directory(
        '$root/outbound',
      ).listSync().whereType<File>())
        if (!file.path.endsWith('_test.go'))
          for (final match in RegExp(
            r'^type (\w+) struct \{\n([\s\S]*?)\n\}',
            multiLine: true,
          ).allMatches(file.readAsStringSync()))
            match.group(1)!: match.group(2)!,
    };
    final keyPattern = RegExp(r'proxy:"([^",]+)(,omitempty)?"');
    final typePattern = RegExp(
      r'^\t\w+\s+(\S+)\s+`proxy:"([^",]+)',
      multiLine: true,
    );
    final embeddedPattern = RegExp(r'^\t(\w+Option)$', multiLine: true);
    final bodies = {
      for (final match in RegExp(
        r'^\tcase "([^"]+)":\n\t\t\w+ := &outbound\.(\w+)\{',
        multiLine: true,
      ).allMatches(File('$root/parser.go').readAsStringSync()))
        match.group(1)!: [
          structs[match.group(2)]!,
          for (final embedded in embeddedPattern.allMatches(
            structs[match.group(2)]!,
          ))
            if (embedded.group(1) != 'BasicOption') structs[embedded.group(1)]!,
          structs['BasicOption']!,
        ].join('\n'),
    };
    Set<String> keysIn(String body, {bool required = false}) => {
      for (final match in keyPattern.allMatches(body))
        if (match.group(1) != '-' && (!required || match.group(2) == null))
          match.group(1)!,
    };
    Set<String> keysOf(String type, {bool required = false}) =>
        keysIn(bodies[type]!, required: required);

    test('every type the core parses has its struct', () {
      expect(bodies.keys, customProxyTypes);
    });

    test('a plugin offers only the plugin-opts keys it reads', () {
      List<ProxyField> optionsOf(String plugin) => CustomProxy(
        id: 0,
        definition: {'type': 'ss', 'plugin': plugin},
      ).options;
      expect(optionsOf('kcptun'), contains(ProxyField.pluginMode));
      expect(optionsOf('kcptun'), isNot(contains(ProxyField.pluginHost)));
      expect(optionsOf('shadow-tls'), contains(ProxyField.pluginHost));
      expect(optionsOf('shadow-tls'), isNot(contains(ProxyField.pluginMode)));
    });

    test('the form asks for the credentials each struct reads', () {
      const credentials = {'username', 'password', 'uuid'};
      for (final type in customProxyTypes) {
        expect(
          {
            for (final field in CustomProxy(
              id: 0,
              definition: {'type': type},
            ).credentials)
              field.path.single,
          },
          keysOf(type).intersection(credentials),
          reason: type,
        );
      }
    });

    test('the required keys are the ones each struct requires', () {
      for (final type in customProxyTypes) {
        expect(
          CustomProxy(id: 0, definition: {'type': type}).requiredKeys,
          keysOf(type, required: true).difference({'name'}),
          reason: type,
        );
      }
    });

    test('the form always shows every key a struct requires', () {
      // A PEM block does not fit a form row, and the form has no row for a
      // zerotier network yet.
      const notInForm = {
        'openvpn': {'ca'},
        'zerotier': {'network'},
      };
      for (final type in customProxyTypes) {
        final proxy = CustomProxy(id: 0, definition: {'type': type});
        expect(
          {for (final field in proxy.fields) field.path.single},
          containsAll(
            proxy.requiredKeys.difference({
              'server',
              'port',
              ...?notInForm[type],
            }),
          ),
          reason: type,
        );
      }
    });

    test('every field and option is a key its struct reads', () {
      for (final type in customProxyTypes) {
        final definitions = [
          {'type': type, 'plugin': 'obfs', 'obfs': 'salamander'},
          for (final network in CustomProxy(
            id: 0,
            definition: {'type': type},
          ).choicesOf(ProxyField.network))
            {'type': type, 'network': network},
        ];
        for (final definition in definitions) {
          final proxy = CustomProxy(id: 0, definition: definition);
          for (final field in [...proxy.fields, ...proxy.options]) {
            var body = bodies[type]!;
            for (final key in field.path) {
              expect(keysIn(body), contains(key), reason: '$type $field');
              final nested =
                  structs[[
                    for (final match in typePattern.allMatches(body))
                      if (match.group(2) == key) match.group(1)!,
                  ].first];
              if (nested == null) {
                break;
              }
              body = nested;
            }
            if (field.kind == ProxyFieldKind.choice) {
              expect(
                proxy.choicesOf(field),
                isNotEmpty,
                reason: '$type $field',
              );
            }
          }
        }
      }
    });

    test('every choice the form offers is a value the core names', () {
      final sources = [
        for (final directory in [
          'adapter',
          'component',
          'constant',
          'transport',
        ])
          for (final file in Directory(
            'core/Clash.Meta/$directory',
          ).listSync(recursive: true).whereType<File>())
            if (file.path.endsWith('.go') && !file.path.endsWith('_test.go'))
              file.readAsStringSync().toLowerCase(),
      ].join('\n');
      // These fields take their values from modules outside the submodule.
      const elsewhere = {
        'ss': {ProxyField.cipher},
        'vmess': {ProxyField.cipher},
        'hysteria2': {ProxyField.obfs},
      };
      for (final type in customProxyTypes) {
        final proxy = CustomProxy(id: 0, definition: {'type': type});
        for (final field in ProxyField.values) {
          if (elsewhere[type]?.contains(field) ?? false) {
            continue;
          }
          for (final choice in proxy.choicesOf(field)) {
            expect(
              sources,
              contains('"${choice.toLowerCase()}"'),
              reason: '$type $field $choice',
            );
          }
        }
      }
    });
  });

  test('a nested field adds and drops the maps that hold it, in any case the '
      'core reads', () {
    const proxy = CustomProxy(
      id: 0,
      definition: {'type': 'vless', 'network': 'ws'},
    );
    final withHost = proxy.withField(ProxyField.wsHost, 'cdn.example');

    expect(withHost.definition['ws-opts'], {
      'headers': {'Host': 'cdn.example'},
    });
    expect(withHost.valueOf(ProxyField.wsHost), 'cdn.example');
    expect(
      withHost.withField(ProxyField.wsHost, null).definition,
      proxy.definition,
    );

    const lower = CustomProxy(
      id: 0,
      definition: {
        'type': 'vless',
        'network': 'ws',
        'ws-opts': {
          'headers': {'host': 'a.example'},
        },
      },
    );
    expect(lower.valueOf(ProxyField.wsHost), 'a.example');
    expect(
      lower.withField(ProxyField.wsHost, 'b.example').definition['ws-opts'],
      {
        'headers': {'host': 'b.example'},
      },
    );
  });

  test('a changed value drops the options only the old one made available', () {
    const proxy = CustomProxy(
      id: 0,
      definition: {
        'type': 'vless',
        'network': 'ws',
        'ws-opts': {
          'path': '/a',
          'headers': {'Host': 'a.example'},
          'max-early-data': 2048,
        },
      },
    );

    expect(proxy.withField(ProxyField.network, 'grpc').definition, {
      'type': 'vless',
      'network': 'grpc',
      'ws-opts': {'max-early-data': 2048},
    });
    expect(
      const CustomProxy(
        id: 0,
        definition: {
          'type': 'hysteria2',
          'obfs': 'salamander',
          'obfs-password': 'pw',
        },
      ).withField(ProxyField.obfs, null).definition,
      {'type': 'hysteria2'},
    );
  });

  test('a new type keeps what it reads alike and starts from the values '
      'nearly every server takes', () {
    const proxy = CustomProxy(
      id: 0,
      definition: {
        'name': 'a',
        'type': 'ss',
        'cipher': 'aes-256-gcm',
        'password': 'pw',
        'udp-over-tcp': true,
      },
    );

    final vmess = proxy.withType('vmess');
    expect(vmess.definition, {
      'name': 'a',
      'type': 'vmess',
      'cipher': 'auto',
      'alterId': 0,
    });
    expect(vmess.definition.keys.first, 'name');
    expect(vmess.withType('ss').definition, {'name': 'a', 'type': 'ss'});
    expect(
      proxy
          .withField(ProxyField.cipher, 'aes-128-gcm')
          .withType('vmess')
          .definition['cipher'],
      'aes-128-gcm',
    );
    expect(proxy.withType('trojan').definition, {
      'name': 'a',
      'type': 'trojan',
      'password': 'pw',
    });
    expect(proxy.withType('ss'), same(proxy));
  });
}
