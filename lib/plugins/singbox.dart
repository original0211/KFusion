import 'package:flutter/services.dart';
import 'package:kfusion/common/common.dart';

// The channel prefix follows the native package name, as on the Kotlin side.
const singBoxChannelName = 'com.follow.clash/singbox';

class SingBoxService {
  SingBoxService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(singBoxChannelName);

  final MethodChannel _channel;

  // An empty string means success; anything else is the failure message.
  Future<String> start(String configPath) async {
    final result = await _channel.invokeMethod<String>('start', {
      'configPath': configPath,
    });
    return result ?? '';
  }

  // Validates the config with the real libbox in the service process,
  // without starting anything; same empty-means-success contract as start.
  Future<String> checkConfig(String configPath) async {
    final result = await _channel.invokeMethod<String>('checkConfig', {
      'configPath': configPath,
    });
    return result ?? '';
  }

  Future<bool> stop() async {
    final result = await _channel.invokeMethod<bool>('stop');
    return result ?? false;
  }

  Future<bool> isRunning() async {
    final result = await _channel.invokeMethod<bool>('isRunning');
    return result ?? false;
  }
}

SingBoxService? _singBoxService;

SingBoxService? get singBoxService =>
    system.isAndroid ? (_singBoxService ??= SingBoxService()) : null;
