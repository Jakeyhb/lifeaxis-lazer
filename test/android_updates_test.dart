import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lazer_nextgen/updates/android_update_checker.dart';
import 'package:lazer_nextgen/updates/android_update_dialog.dart';
import 'package:lazer_nextgen/updates/android_update_download.dart';
import 'package:lazer_nextgen/updates/android_update_manifest.dart';
import 'package:lazer_nextgen/updates/android_update_platform.dart';
import 'package:lazer_nextgen/updates/release_version.dart';

final List<int> _bytes = utf8.encode('test APK bytes, not a release');

Map<String, dynamic> _json() => <String, dynamic>{
  'versionCode': 9,
  'versionName': '2.0.0-beta.6',
  'apkUrl': 'https://lazer.lifeaxis.fun/lazer/Lazer-2.0.0-beta.6-9.apk',
  'notes': '新增应用内检查更新',
  'mandatory': false,
  'sha256': sha256.convert(_bytes).toString(),
  'sizeBytes': _bytes.length,
};

class _Platform extends AndroidUpdatePlatform {
  _Platform({this.directory = ''});

  final String directory;
  bool allowed = true;
  int verified = 0;
  int installations = 0;
  int permissionRequests = 0;
  String? rejection;

  @override
  Future<int> installedVersionCode() async => 8;

  @override
  Future<String> downloadDirectory() async => directory;

  @override
  Future<void> verify(String path, AndroidUpdateManifest manifest) async {
    verified++;
    if (rejection != null) {
      throw PlatformException(code: 'verification_failed', message: rejection);
    }
  }

  @override
  Future<bool> canInstall() async => allowed;

  @override
  Future<void> requestInstallPermission() async => permissionRequests++;

  @override
  Future<void> install(String path, AndroidUpdateManifest manifest) async {
    await verify(path, manifest);
    installations++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Android manifest trust boundary', () {
    test('requires actual numeric code, size, checksum and own path', () {
      final AndroidUpdateManifest manifest = AndroidUpdateManifest.fromJson(
        _json(),
      );
      expect(manifest.versionCode, 9);
      expect(
        manifest.verificationArguments('/private/test.apk')['sha256'],
        sha256.convert(_bytes).toString(),
      );
      final List<Map<String, Object?>> invalid = <Map<String, Object?>>[
        <String, Object?>{'versionCode': '9'},
        <String, Object?>{'versionCode': 0},
        <String, Object?>{'sizeBytes': -1},
        <String, Object?>{'sizeBytes': 1073741825},
        <String, Object?>{'mandatory': 'false'},
        <String, Object?>{'sha256': 'invalid'},
        <String, Object?>{'versionName': 'nextgen'},
        <String, Object?>{'notes': null},
        <String, Object?>{'packageName': 'other.app'},
      ];
      for (final Map<String, Object?> values in invalid) {
        expect(
          () => AndroidUpdateManifest.fromJson(_json()..addAll(values)),
          throwsFormatException,
          reason: values.toString(),
        );
      }
    });

    test('rejects foreign origins, redirects paths and root assets', () {
      for (final String url in <String>[
        'http://lazer.lifeaxis.fun/lazer/a.apk',
        'https://evil.example/lazer/a.apk',
        'https://lazer.lifeaxis.fun/a.apk',
        'https://lazer.lifeaxis.fun/zaice/a.apk',
        'https://lazer.lifeaxis.fun/lazer/sub/a.apk',
        'https://lazer.lifeaxis.fun/lazer/%2Fsecret.apk',
        'https://lazer.lifeaxis.fun/lazer/a.apk?token=x',
        'https://user@lazer.lifeaxis.fun/lazer/a.apk',
        'https://lazer.lifeaxis.fun:444/lazer/a.apk',
      ]) {
        expect(
          () => AndroidUpdateManifest.fromJson(_json()..['apkUrl'] = url),
          throwsFormatException,
          reason: url,
        );
      }
    });
  });

  group('Android checks', () {
    test('compares installed numeric code, not desktop semver', () async {
      Uri? requested;
      final AndroidUpdateChecker checker = AndroidUpdateChecker(
        platform: _Platform(),
        fetch: (Uri uri) async {
          requested = uri;
          return http.Response.bytes(utf8.encode(jsonEncode(_json())), 200);
        },
      );
      final release = await checker.findUpdate(ReleaseVersion.parse('99.0.0')!);
      expect(release?.android?.versionCode, 9);
      expect(release?.skipKey, 'android:9');
      expect(requested?.path, '/lazer/version.json');
      expect(requested?.queryParameters.keys, <String>['t']);
      expect(int.tryParse(requested!.queryParameters['t']!), isNotNull);
    });

    test('same code is current even if version name changes', () async {
      final checker = AndroidUpdateChecker(
        platform: _Platform(),
        fetch: (_) async => http.Response.bytes(
          utf8.encode(jsonEncode(_json()..['versionCode'] = 8)),
          200,
        ),
      );
      expect(await checker.findUpdate(ReleaseVersion.parse('1.0.0')!), isNull);
    });

    test('HTTP failures and malformed JSON are not latest status', () async {
      for (final response in <http.Response>[
        http.Response('not found', 404),
        http.Response('[]', 200),
        http.Response('{bad', 200),
      ]) {
        final checker = AndroidUpdateChecker(
          platform: _Platform(),
          fetch: (_) async => response,
        );
        await expectLater(
          checker.findUpdate(ReleaseVersion.parse('1.0.0')!),
          throwsA(isA<Exception>()),
        );
      }
    });
  });

  group('Android download and installation', () {
    late Directory directory;
    late _Platform platform;
    late AndroidUpdateDownload download;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('lazer-update-test-');
      platform = _Platform(directory: directory.path);
    });

    tearDown(() async {
      download.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await directory.delete(recursive: true);
    });

    void prepare({List<int>? bytes, int status = 200}) {
      download = AndroidUpdateDownload(
        manifest: AndroidUpdateManifest.fromJson(_json()),
        platform: platform,
        clientFactory: () => MockClient((request) async {
          expect(request.followRedirects, isFalse);
          expect(request.headers.keys, isNot(contains('authorization')));
          return http.Response.bytes(bytes ?? _bytes, status);
        }),
      );
    }

    test(
      'checks hash then native identity; revalidates before installation',
      () async {
        prepare();
        await download.download();
        expect(download.phase, AndroidUpdatePhase.ready);
        expect(download.progress, 1);
        expect(platform.verified, 1);
        await download.install();
        expect(download.phase, AndroidUpdatePhase.installerOpened);
        expect(platform.verified, 2);
        expect(platform.installations, 1);
        expect(directory.listSync().single.path, endsWith('.apk'));
      },
    );

    test(
      'corruption is rejected before native install and can retry',
      () async {
        prepare(bytes: List<int>.filled(_bytes.length, 0));
        await download.download();
        expect(download.phase, AndroidUpdatePhase.failed);
        expect(download.error, contains('SHA-256'));
        expect(platform.verified, 0);
        expect(directory.listSync(), isEmpty);
        await download.install();
        expect(platform.installations, 0);
        download.dispose();
        prepare();
        await download.download();
        expect(download.phase, AndroidUpdatePhase.ready);
      },
    );

    test('truncated data and redirects fail closed', () async {
      prepare(bytes: <int>[1, 2], status: 302);
      await download.download();
      expect(download.phase, AndroidUpdatePhase.failed);
      expect(platform.verified, 0);
      expect(directory.listSync(), isEmpty);
    });

    test('HTTP 200 with a wrong size is not accepted', () async {
      prepare(bytes: <int>[1, 2]);
      await download.download();
      expect(download.phase, AndroidUpdatePhase.failed);
      expect(platform.verified, 0);
      expect(directory.listSync(), isEmpty);
    });

    test('cancelling a streaming download cleans partial bytes', () async {
      final StreamController<List<int>> body = StreamController<List<int>>();
      final Completer<void> started = Completer<void>();
      download = AndroidUpdateDownload(
        manifest: AndroidUpdateManifest.fromJson(_json()),
        platform: platform,
        clientFactory: () => MockClient.streaming((request, requestBody) async {
          started.complete();
          return http.StreamedResponse(body.stream, 200);
        }),
      );
      final Future<void> operation = download.download();
      await started.future;
      body.add(_bytes.sublist(0, 4));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await download.cancel();
      body.add(_bytes.sublist(4));
      await body.close();
      await operation;
      expect(download.phase, AndroidUpdatePhase.cancelled);
      expect(platform.verified, 0);
      expect(directory.listSync(), isEmpty);
    });

    test('failed install revalidation never opens system installer', () async {
      prepare();
      await download.download();
      platform.rejection = '安装包版本与更新清单不一致';
      await download.install();
      expect(download.phase, AndroidUpdatePhase.failed);
      expect(download.error, platform.rejection);
      expect(platform.installations, 0);
      await download.cancel();
      expect(directory.listSync(), isEmpty);
    });

    test('native package/version/signature rejection deletes APK', () async {
      prepare();
      platform.rejection = '签名与已安装版本不兼容';
      await download.download();
      expect(download.phase, AndroidUpdatePhase.failed);
      expect(download.error, platform.rejection);
      expect(directory.listSync(), isEmpty);
    });

    test(
      'permission refusal is recoverable; returning after grant installs',
      () async {
        prepare();
        platform.allowed = false;
        await download.download();
        await download.install();
        expect(download.phase, AndroidUpdatePhase.needsPermission);
        await download.requestPermission();
        await download.onResumed();
        expect(download.error, contains('尚未允许'));
        expect(platform.installations, 0);
        await download.requestPermission();
        platform.allowed = true;
        await download.onResumed();
        expect(platform.permissionRequests, 2);
        expect(platform.installations, 1);
      },
    );

    test(
      'cancellation before first await never completes verification',
      () async {
        prepare();
        final operation = download.download();
        await download.cancel();
        await operation;
        expect(download.phase, AndroidUpdatePhase.cancelled);
        expect(platform.verified, 0);
        expect(directory.listSync(), isEmpty);
        await download.download();
        expect(download.phase, AndroidUpdatePhase.ready);
      },
    );
  });

  testWidgets('update dialog shows actual version, notes and actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AndroidUpdateDialog(
            manifest: AndroidUpdateManifest.fromJson(_json()),
          ),
        ),
      ),
    );
    expect(find.text('Lazer 2.0.0-beta.6'), findsOneWidget);
    expect(find.text('新增应用内检查更新'), findsOneWidget);
    expect(find.text('稍后'), findsOneWidget);
    expect(find.text('下载更新'), findsOneWidget);
    expect(find.textContaining('系统界面确认'), findsOneWidget);
  });
}
