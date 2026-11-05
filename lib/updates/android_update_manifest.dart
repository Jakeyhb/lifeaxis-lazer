import 'release_version.dart';

class AndroidUpdateManifest {
  const AndroidUpdateManifest({
    required this.versionCode,
    required this.versionName,
    required this.apkUri,
    required this.notes,
    required this.mandatory,
    required this.sha256,
    required this.sizeBytes,
  });

  static final Uri endpoint = Uri.parse(
    'https://updates.lifeaxis.fun/lazer/version.json',
  );
  static const String packageName = 'fun.lifeaxis.lazer';

  final int versionCode;
  final String versionName;
  final Uri apkUri;
  final String notes;
  final bool mandatory;
  final String sha256;
  final int sizeBytes;

  factory AndroidUpdateManifest.fromJson(Map<String, dynamic> json) {
    final Object? code = json['versionCode'];
    final Object? name = json['versionName'];
    final Object? url = json['apkUrl'];
    final Object? notes = json['notes'];
    final Object? mandatory = json['mandatory'];
    final Object? checksum = json['sha256'];
    final Object? size = json['sizeBytes'];
    final Uri? uri = url is String ? Uri.tryParse(url) : null;
    if (code is! int ||
        code <= 0 ||
        code > 2100000000 ||
        name is! String ||
        ReleaseVersion.parse(name) == null ||
        notes is! String ||
        notes.length > 65536 ||
        mandatory is! bool ||
        checksum is! String ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(checksum) ||
        size is! int ||
        size <= 0 ||
        size > 1024 * 1024 * 1024 ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host != endpoint.host ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.length != 2 ||
        uri.pathSegments.first != 'lazer' ||
        !RegExp(
          r'^[A-Za-z0-9][A-Za-z0-9._-]*\.apk$',
        ).hasMatch(uri.pathSegments.last) ||
        json['packageName'] != null && json['packageName'] != packageName) {
      throw const FormatException('更新清单无效或下载地址不受信任');
    }
    return AndroidUpdateManifest(
      versionCode: code,
      versionName: name,
      apkUri: uri,
      notes: notes,
      mandatory: mandatory,
      sha256: checksum.toLowerCase(),
      sizeBytes: size,
    );
  }

  Map<String, Object> verificationArguments(String path) => <String, Object>{
    'path': path,
    'versionCode': versionCode,
    'versionName': versionName,
    'sha256': sha256,
    'sizeBytes': sizeBytes,
  };
}
