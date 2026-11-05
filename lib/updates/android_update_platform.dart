import 'package:flutter/services.dart';

import 'android_update_manifest.dart';

class AndroidUpdatePlatform {
  const AndroidUpdatePlatform();

  static const MethodChannel channel = MethodChannel(
    'fun.lifeaxis.lazer/android_updates',
  );

  Future<int> installedVersionCode() async {
    final Map<Object?, Object?>? info = await channel
        .invokeMapMethod<Object?, Object?>('installedInfo');
    final Object? code = info?['versionCode'];
    if (code is! int || code <= 0) {
      throw const FormatException('无法读取已安装版本');
    }
    return code;
  }

  Future<String> downloadDirectory() async {
    final String? directory = await channel.invokeMethod<String>(
      'downloadDirectory',
    );
    if (directory == null || directory.isEmpty) {
      throw const FormatException('无法创建更新下载目录');
    }
    return directory;
  }

  Future<void> verify(String path, AndroidUpdateManifest manifest) => channel
      .invokeMethod<void>('verify', manifest.verificationArguments(path));

  Future<bool> canInstall() async =>
      await channel.invokeMethod<bool>('canInstall') ?? false;

  Future<void> requestInstallPermission() =>
      channel.invokeMethod<void>('requestInstallPermission');

  Future<void> install(String path, AndroidUpdateManifest manifest) => channel
      .invokeMethod<void>('install', manifest.verificationArguments(path));
}
