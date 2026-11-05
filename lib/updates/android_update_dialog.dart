import 'dart:async';

import 'package:flutter/material.dart';

import '../animation/apple_modal.dart';
import '../l10n/app_localizations.dart';
import '../utils/byte_format.dart';
import '../widgets/spring_buttons.dart';
import 'android_update_download.dart';
import 'android_update_manifest.dart';

Future<void> showAndroidUpdateDialog(
  BuildContext context,
  AndroidUpdateManifest manifest,
) => showAppleDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (BuildContext context) => AndroidUpdateDialog(manifest: manifest),
);

class AndroidUpdateDialog extends StatefulWidget {
  const AndroidUpdateDialog({super.key, required this.manifest, this.download});

  final AndroidUpdateManifest manifest;
  final AndroidUpdateDownload? download;

  @override
  State<AndroidUpdateDialog> createState() => _AndroidUpdateDialogState();
}

class _AndroidUpdateDialogState extends State<AndroidUpdateDialog>
    with WidgetsBindingObserver {
  late final AndroidUpdateDownload download;

  @override
  void initState() {
    super.initState();
    download =
        widget.download ?? AndroidUpdateDownload(manifest: widget.manifest);
    download.addListener(_refresh);
    WidgetsBinding.instance.addObserver(this);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) {
      unawaited(download.onResumed());
    }
  }

  Future<void> _primary() async {
    switch (download.phase) {
      case AndroidUpdatePhase.ready:
      case AndroidUpdatePhase.installerOpened:
        await download.install();
      case AndroidUpdatePhase.needsPermission:
        await download.requestPermission();
      default:
        await download.download();
    }
  }

  Future<void> _cancelOrClose() async {
    if (download.installing) return;
    if (download.busy) {
      await download.cancel();
      return;
    }
    if (!widget.manifest.mandatory && mounted) {
      Navigator.of(context).pop();
    }
  }

  String get _primaryLabel => switch (download.phase) {
    AndroidUpdatePhase.downloading => '正在下载…',
    AndroidUpdatePhase.verifying => '正在校验…',
    AndroidUpdatePhase.ready => '安装更新',
    AndroidUpdatePhase.needsPermission => '允许安装更新',
    AndroidUpdatePhase.installerOpened => '重新打开安装界面',
    AndroidUpdatePhase.failed => '重试下载',
    AndroidUpdatePhase.cancelled => '重新下载',
    AndroidUpdatePhase.idle => '下载更新',
  };

  String get _status =>
      download.error ??
      switch (download.phase) {
        AndroidUpdatePhase.idle => '下载后将校验 SHA-256、包名、版本和签名。安装需要你在系统界面确认。',
        AndroidUpdatePhase.downloading =>
          '正在下载 ${formatBytes(download.receivedBytes)} / ${formatBytes(widget.manifest.sizeBytes)}',
        AndroidUpdatePhase.verifying => '正在验证完整性与签名，请稍候…',
        AndroidUpdatePhase.ready => '安装包校验通过，可以安全地交给系统安装。',
        AndroidUpdatePhase.needsPermission =>
          'Android 需要你允许 Lazer“安装未知应用”。此权限仅用于更新，不会静默安装；拒绝不会影响听歌。授权后返回这里继续安装。',
        AndroidUpdatePhase.installerOpened => '已打开系统安装界面，请在系统界面确认安装。',
        AndroidUpdatePhase.cancelled => '下载已取消，你可以稍后重新下载。',
        AndroidUpdatePhase.failed => '更新失败，请重试。',
      };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return PopScope(
      canPop: !widget.manifest.mandatory && !download.installing,
      child: AlertDialog(
        title: Text(context.tr('发现新版本')),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Lazer ${widget.manifest.versionName}',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  '${formatBytes(widget.manifest.sizeBytes)} · build ${widget.manifest.versionCode}',
                  style: theme.textTheme.bodySmall,
                ),
                if (widget.manifest.mandatory) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(context.tr('此版本需要更新后继续使用')),
                ],
                const SizedBox(height: 20),
                Text(context.tr('更新说明'), style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                SelectableText(widget.manifest.notes),
                const SizedBox(height: 24),
                if (download.busy) ...<Widget>[
                  LinearProgressIndicator(
                    value: download.phase == AndroidUpdatePhase.downloading
                        ? download.progress.clamp(0, 1)
                        : null,
                    semanticsLabel: context.tr('更新下载进度'),
                  ),
                  const SizedBox(height: 12),
                ],
                Semantics(
                  liveRegion: download.phase != AndroidUpdatePhase.downloading,
                  child: Text(
                    context.tr(_status),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: download.error == null
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          if (!widget.manifest.mandatory || download.busy)
            SpringTextButton(
              onPressed: download.installing
                  ? null
                  : () => unawaited(_cancelOrClose()),
              child: Text(context.tr(download.busy ? '取消下载' : '稍后')),
            ),
          SpringFilledButton(
            onPressed: download.busy ? null : () => unawaited(_primary()),
            child: Text(context.tr(_primaryLabel)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    download.removeListener(_refresh);
    download.dispose();
    super.dispose();
  }
}
