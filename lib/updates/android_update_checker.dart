import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'android_update_manifest.dart';
import 'android_update_platform.dart';
import 'release_version.dart';
import 'update_checker.dart';

class AndroidUpdateChecker extends UpdateChecker {
  AndroidUpdateChecker({
    Future<http.Response> Function(Uri uri)? fetch,
    this.platform = const AndroidUpdatePlatform(),
  }) : _fetchManifest = fetch ?? _fetch,
       super(endpoint: AndroidUpdateManifest.endpoint);

  final Future<http.Response> Function(Uri uri) _fetchManifest;
  final AndroidUpdatePlatform platform;

  @override
  String get sourceLabel => '从 Lazer 更新站点检查版本';

  @override
  Future<AppRelease?> findUpdate(
    ReleaseVersion current, {
    bool includePrerelease = false,
  }) async {
    final int installed = await platform.installedVersionCode();
    final Uri uncached = endpoint.replace(
      queryParameters: <String, String>{
        't': DateTime.now().microsecondsSinceEpoch.toString(),
      },
    );
    final http.Response response = await _fetchManifest(
      uncached,
    ).timeout(timeout);
    if (response.statusCode != 200) {
      throw UpdateCheckException('更新站点返回 HTTP ${response.statusCode}');
    }
    if (response.bodyBytes.length > 131072) {
      throw const UpdateCheckException('更新清单过大');
    }
    final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const UpdateCheckException('更新清单格式错误');
    }
    final AndroidUpdateManifest manifest = AndroidUpdateManifest.fromJson(
      decoded,
    );
    if (manifest.versionCode <= installed) return null;
    final ReleaseVersion version = ReleaseVersion.parse(manifest.versionName)!;
    return AppRelease(
      tag: 'v${manifest.versionName}',
      version: version,
      name: 'Lazer ${manifest.versionName}',
      notes: manifest.notes,
      url: manifest.apkUri.toString(),
      prerelease: version.isPreRelease,
      android: manifest,
    );
  }

  static Future<http.Response> _fetch(Uri uri) async {
    final http.Client client = http.Client();
    try {
      final http.Request request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers.addAll(<String, String>{
          'Accept': 'application/json',
          'Cache-Control': 'no-cache, no-store',
        });
      final http.StreamedResponse response = await client
          .send(request)
          .timeout(const Duration(seconds: 8));
      final List<int> bytes = <int>[];
      await for (final List<int> chunk in response.stream.timeout(
        const Duration(seconds: 8),
      )) {
        if (bytes.length + chunk.length > 131072) {
          throw const UpdateCheckException('更新清单过大');
        }
        bytes.addAll(chunk);
      }
      return http.Response.bytes(bytes, response.statusCode);
    } finally {
      client.close();
    }
  }
}
