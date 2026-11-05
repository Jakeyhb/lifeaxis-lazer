# Lazer

## Platform

android

## Stack

Flutter / Dart，Android 原生桥接使用 Kotlin；下载页面使用独立静态 HTML、CSS 和 JavaScript。

## Product Purpose

在同一音乐播放器中使用网易云、Navidrome 与本地音乐，提供歌词与播放控制。

## Capabilities and Constraints

- Android 独立发行版包名为 `fun.lifeaxis.lazer`，可与上游官方版并存，不兼容上游升级链；最低系统要求取自实际 APK。
- 下载页与更新清单归属 `https://lazer.lifeaxis.fun/lazer/`，不读站点根目录清单。
- 正式更新必须维持原签名，安装由 Android 系统请求用户确认。
- 不上传用户业务数据，不为更新请求通知、媒体或文件管理权限。
- 共享下载站点的其他应用、历史 APK 和尚未发布的草稿必须严格隔离。

## Brand Commitments

使用现有 Lazer 名称、`assets/app_icon.png` 与应用暖纸色、陶土色设计令牌，不复用 FeelMating 的品牌文案。

## Evidence on Hand

`pubspec.yaml`、`android/app/build.gradle.kts`、`lib/theme/design_tokens.dart`、现有更新逻辑与测试。已在登录后的提供商控制台确认当前生产部署的完整 31 文件清单，并恢复隔离线上基线；用户授权独立首发后初始化专用签名并固定公开证书。未部署的地址不得视为可下载的发布链接。
