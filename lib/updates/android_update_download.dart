import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'android_update_manifest.dart';
import 'android_update_platform.dart';

enum AndroidUpdatePhase {
  idle,
  downloading,
  verifying,
  ready,
  needsPermission,
  installerOpened,
  cancelled,
  failed,
}

class AndroidUpdateDownload extends ChangeNotifier {
  AndroidUpdateDownload({
    required this.manifest,
    this.platform = const AndroidUpdatePlatform(),
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final AndroidUpdateManifest manifest;
  final AndroidUpdatePlatform platform;
  final http.Client Function() _clientFactory;
  AndroidUpdatePhase phase = AndroidUpdatePhase.idle;
  int receivedBytes = 0;
  String? error;
  http.Client? _client;
  File? _archive;
  int _generation = 0;
  bool _disposed = false;
  bool _awaitingPermission = false;
  bool _installing = false;

  bool get busy =>
      phase == AndroidUpdatePhase.downloading ||
      phase == AndroidUpdatePhase.verifying ||
      _installing;

  double get progress => receivedBytes / manifest.sizeBytes;
  bool get installing => _installing;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> download() async {
    if (busy || _disposed) return;
    final int generation = ++_generation;
    final File? previous = _archive;
    _archive = null;
    phase = AndroidUpdatePhase.downloading;
    receivedBytes = 0;
    error = null;
    _changed();
    await _remove(previous);
    if (generation != _generation || _disposed) return;
    final http.Client client = _clientFactory();
    _client = client;
    File? partial;
    File? complete;
    IOSink? sink;
    try {
      final String directory = await platform.downloadDirectory();
      if (generation != _generation) return;
      partial = File(
        '$directory/update-${manifest.versionCode}-${DateTime.now().microsecondsSinceEpoch}.apk.part',
      );
      final http.Request request = http.Request('GET', manifest.apkUri)
        ..followRedirects = false;
      final http.StreamedResponse response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200 ||
          response.contentLength != null &&
              response.contentLength != manifest.sizeBytes) {
        throw const FormatException('下载失败：服务器响应或安装包大小不符');
      }
      sink = partial.openWrite();
      DateTime lastProgress = DateTime.now();
      await for (final List<int> chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (generation != _generation) return;
        receivedBytes += chunk.length;
        if (receivedBytes > manifest.sizeBytes) {
          throw const FormatException('安装包超过清单声明的大小');
        }
        sink.add(chunk);
        final DateTime now = DateTime.now();
        if (now.difference(lastProgress).inMilliseconds >= 100) {
          lastProgress = now;
          _changed();
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (generation != _generation) return;
      if (receivedBytes != manifest.sizeBytes) {
        throw const FormatException('下载不完整，请重试');
      }
      phase = AndroidUpdatePhase.verifying;
      _changed();
      final Digest digest = await sha256.bind(partial.openRead()).first;
      if (generation != _generation) return;
      if (digest.toString() != manifest.sha256) {
        throw const FormatException('SHA-256 校验失败，已拒绝安装');
      }
      complete = await partial.rename(
        partial.path.substring(0, partial.path.length - 5),
      );
      partial = null;
      await platform.verify(complete.path, manifest);
      if (generation != _generation) return;
      _archive = complete;
      complete = null;
      phase = AndroidUpdatePhase.ready;
      _changed();
    } catch (failure) {
      if (generation == _generation && !_disposed) {
        phase = AndroidUpdatePhase.failed;
        error = _message(failure);
        _changed();
      }
    } finally {
      if (identical(_client, client)) _client = null;
      client.close();
      try {
        await sink?.close();
      } catch (_) {}
      await _remove(partial);
      await _remove(complete);
    }
  }

  Future<void> install() async {
    if (_disposed || busy || _archive == null) return;
    final int generation = _generation;
    _installing = true;
    error = null;
    _changed();
    try {
      final bool allowed = await platform.canInstall();
      if (generation != _generation || _disposed) return;
      if (!allowed) {
        phase = AndroidUpdatePhase.needsPermission;
      } else {
        await platform.install(_archive!.path, manifest);
        if (generation != _generation) return;
        phase = AndroidUpdatePhase.installerOpened;
      }
    } catch (failure) {
      if (generation == _generation && !_disposed) {
        error = _message(failure);
        phase = AndroidUpdatePhase.failed;
      }
    } finally {
      _installing = false;
      _changed();
    }
  }

  Future<void> requestPermission() async {
    if (_disposed || phase != AndroidUpdatePhase.needsPermission) return;
    _awaitingPermission = true;
    error = null;
    try {
      await platform.requestInstallPermission();
    } catch (failure) {
      _awaitingPermission = false;
      error = _message(failure);
      _changed();
    }
  }

  Future<void> onResumed() async {
    if (!_awaitingPermission || _disposed) return;
    _awaitingPermission = false;
    try {
      if (await platform.canInstall()) {
        await install();
      } else {
        error = '尚未允许安装。你可以稍后重试，其他功能不受影响。';
        _changed();
      }
    } catch (failure) {
      error = _message(failure);
      _changed();
    }
  }

  Future<void> cancel() async {
    ++_generation;
    _awaitingPermission = false;
    _client?.close();
    _client = null;
    if (phase != AndroidUpdatePhase.installerOpened) {
      await _remove(_archive);
    }
    _archive = null;
    phase = AndroidUpdatePhase.cancelled;
    error = null;
    _changed();
  }

  static String _message(Object failure) => switch (failure) {
    PlatformException(:final message) => message ?? '系统无法处理此更新',
    FormatException(:final message) => message,
    TimeoutException() => '下载超时，请检查网络后重试',
    _ => '更新失败，请检查网络或存储空间后重试',
  };

  static Future<void> _remove(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _client?.close();
    if (phase != AndroidUpdatePhase.installerOpened) {
      unawaited(_remove(_archive));
    }
    super.dispose();
  }
}
