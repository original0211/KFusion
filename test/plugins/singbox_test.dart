import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/plugins/singbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(singBoxChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('start passes the config path and returns an empty success', () async {
    MethodCall? captured;
    messenger.setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return '';
    });
    final service = SingBoxService(channel: channel);
    final result = await service.start('/data/app/singbox/config.json');
    expect(result, '');
    expect(captured?.method, 'start');
    expect(captured?.arguments, {
      'configPath': '/data/app/singbox/config.json',
    });
  });

  test('start surfaces the native error message', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return 'VPN 权限未授予，sing-box 未启动';
    });
    final service = SingBoxService(channel: channel);
    expect(await service.start('/tmp/config.json'), 'VPN 权限未授予，sing-box 未启动');
  });

  test('stop and isRunning map native booleans', () async {
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return true;
    });
    final service = SingBoxService(channel: channel);
    expect(await service.stop(), isTrue);
    expect(await service.isRunning(), isTrue);
    expect(methods, ['stop', 'isRunning']);
  });

  test('null native results fall back to safe defaults', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    final service = SingBoxService(channel: channel);
    expect(await service.start('/tmp/config.json'), '');
    expect(await service.stop(), isFalse);
    expect(await service.isRunning(), isFalse);
  });
}
