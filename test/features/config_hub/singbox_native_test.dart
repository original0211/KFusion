import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/features/config_hub/core_switch.dart';
import 'package:kfusion/features/config_hub/singbox_action.dart';
import 'package:kfusion/features/config_hub/singbox_native.dart';

const _native = '''
{
    "log": {"level": "info"},
    "inbounds": [
        {"type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": 7891},
        {"type": "tun", "tag": "tun-in", "address": ["172.19.0.1/30"]}
    ],
    "outbounds": [
        {"type": "vless", "tag": "V1", "server": "203.0.113.9", "server_port": 443, "uuid": "00000000-0000-0000-0000-000000000001"},
        {"type": "direct", "tag": "direct"}
    ],
    "experimental": {
        "clash_api": {"external_controller": "127.0.0.1:9190", "secret": "s3cr3t"}
    }
}
''';

const _clashYaml = '''
proxies:
  - {name: SS-1, type: ss, server: 203.0.113.2, port: 8388, cipher: aes-256-gcm, password: pw}
''';

void main() {
  group('recognition', () {
    test('a sing-box JSON is native; clash and share links are not', () {
      expect(isNativeSingBoxConfig(_native), isTrue);
      expect(isNativeSingBoxConfig(_clashYaml), isFalse);
      expect(isNativeSingBoxConfig('ss://abc@203.0.113.2:8388#x'), isFalse);
      expect(isNativeSingBoxConfig('{"log": {"level": "info"}}'), isFalse);
    });

    test('decode yields the top-level object or null', () {
      expect(decodeSingBoxConfig(_native)?['outbounds'], isA<List>());
      expect(decodeSingBoxConfig('not json'), isNull);
      expect(decodeSingBoxConfig('[1, 2]'), isNull);
    });
  });

  group('structural verdict', () {
    test('a sound native config has no problem', () {
      expect(nativeSingBoxConfigProblem(_native), isNull);
    });

    test('garbage is refused in plain words', () {
      expect(nativeSingBoxConfigProblem('{oops'), contains('JSON'));
      expect(nativeSingBoxConfigProblem('"text"'), contains('顶层'));
      expect(
        nativeSingBoxConfigProblem('{"outbounds": []}'),
        contains('outbounds'),
      );
    });

    test('a config with only utility outbounds has nothing to run', () {
      expect(
        nativeSingBoxConfigProblem(
          '{"outbounds": [{"type": "direct", "tag": "d"}]}',
        ),
        contains('direct/block'),
      );
    });

    test('an endpoint counts as a usable exit', () {
      expect(
        nativeSingBoxConfigProblem(
          '{"outbounds": [{"type": "direct", "tag": "d"}],'
          ' "endpoints": [{"type": "wireguard", "tag": "wg"}]}',
        ),
        isNull,
      );
    });
  });

  group('declared endpoints', () {
    test('clash_api, mixed port and tun come from the config itself', () {
      final doc = decodeSingBoxConfig(_native)!;
      final api = nativeSingBoxClashApi(doc);
      expect(api?.port, 9190);
      expect(api?.secret, 's3cr3t');
      expect(nativeSingBoxMixedPort(doc), 7891);
      expect(nativeSingBoxUsesTun(doc), isTrue);
    });

    test('a config without clash_api offers the app no panel', () {
      final doc = decodeSingBoxConfig(
        '{"outbounds": [{"type": "vless", "tag": "V"}]}',
      )!;
      expect(nativeSingBoxClashApi(doc), isNull);
      expect(nativeSingBoxMixedPort(doc), isNull);
      expect(nativeSingBoxUsesTun(doc), isFalse);
    });

    test('a controller without a port falls back to the sing-box default', () {
      final doc = decodeSingBoxConfig(
        '{"experimental": {"clash_api": {"external_controller": "127.0.0.1"}}}',
      )!;
      expect(nativeSingBoxClashApi(doc)?.port, 9090);
    });
  });

  group('preparation', () {
    test('a native config is prepared verbatim, on its own endpoints', () {
      final result = prepareNativeSingBox(_native);
      expect(result.problem, isNull);
      final prepared = result.prepared!;
      expect(prepared.nativeText, _native);
      expect(prepared.rendered, isNull);
      expect(prepared.apiPort, 9190);
      expect(prepared.secret, 's3cr3t');
      expect(prepared.mixedPort, 7891);
    });

    test('a native config without clash_api cannot be taken over', () {
      final result = prepareNativeSingBox(
        '{"outbounds": [{"type": "vless", "tag": "V", "server": "203.0.113.9",'
        ' "server_port": 443, "uuid": "u"}]}',
      );
      expect(result.prepared, isNull);
      expect(result.problem, contains('clash_api'));
    });

    test('a broken native config names its problem', () {
      final result = prepareNativeSingBox('{"outbounds": []}');
      expect(result.prepared, isNull);
      expect(result.problem, contains('outbounds'));
    });
  });

  group('the mihomo verdict', () {
    test('a native profile is refused with the reason spelled out', () {
      final verdict = mihomoProfileVerdict(_native);
      expect(verdict.failure, CoreSwitchFailure.profileNotRenderable);
      expect(verdict.detail, contains('sing-box 原生配置'));
    });

    test('a clash profile still passes, as before', () {
      expect(mihomoProfileVerdict(_clashYaml).failure, isNull);
    });

    test('an empty profile is still not renderable, without detail', () {
      final verdict = mihomoProfileVerdict('');
      expect(verdict.failure, CoreSwitchFailure.profileNotRenderable);
      expect(verdict.detail, isEmpty);
    });
  });
}
