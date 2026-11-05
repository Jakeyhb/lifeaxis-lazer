# Lazer Android 云端发布

## 当前边界

- 应用：Lazer LifeAxis 独立发行版，Flutter/Dart + Kotlin；Android 包名固定 `fun.lifeaxis.lazer`。原生 namespace 与平台通道名保留上游值，非 Android 平台标识不变。
- 下载目录固定 `/lazer/`。域名 `https://updates.lifeaxis.fun`，项目 `feelmating-updates`，Project ID `makers-ff4cnnfdp6cn`。
- 根目录属于 FeelMating，`/zaice/` 属于其他应用。不得覆盖它们，也不得因全量部署而删除历史链接。
- 本文中的目标地址不是上线证明。当前发布阻塞与验证实录见 `status-2026-11-05.md`。
- 用户于 2026-11-05 确认从未安装，并明确同意独立首发：为新包名首次创建专用签名，不覆盖上游正式版。两者可并存，但不共享数据或升级链。仍不提交代码、不创建分支、不部署其他服务。

## 正式签名与版本

正式发布必须有 `android/key.properties` 及其指向的独立发行版 keystore。密码只保留在本机忽略文件或安全配置中，不写入源码或发布记录。公开证书指纹固定于 `release/android-identity.json`，打包前检查 keystore，构建后与部署前后均检查 APK 签名。

首次打包使用 `--first-release`，要求线上 `/lazer/version.json` 为 404、本机无已打包正式版本，且完整线上快照不含任何 `/lazer/` 文件。后续必须提供本发行版的 `--baseline-apk`，校验同包名、同证书、versionCode 递增；不接受上游官方 APK 冒充兼容基准。

首次签名初始化脚本为 `ci/init_android_signing.py --initialize-independent-app`，已有任何签名材料时拒绝执行。私密材料位于 `~/.local/share/lazer-signing/fun.lifeaxis.lazer/`，另有本机备份 `~/Documents/Lazer-signing-backup/fun.lifeaxis.lazer/`。目录权限 0700、文件 0600，密码不出现在命令参数或日志。请再将备份安全复制到另一台设备；同一磁盘副本不防磁盘损坏。丢失原私钥将无法延续此独立发行版升级链，禁止重新生成后冒充原签名。

`ci/release_android.py`：

1. 缺独立签名配置或固定证书不匹配时立即停止，不触发 Gradle 的调试签名兜底。
2. 后续升级使用 `apksigner verify --print-certs` 验证本发行版基准 APK，拒绝调试包／调试证书；首发不伪造已有基准。
3. 读取源版本、线上 Lazer 清单（仅 404 可视为首次发布）与本机历史打包记录；下一 code 为这些 code 与正式基准 code 的最大值加一。
4. 自动运行原生音频构建及校验，再构建 ARM32 + ARM64 通用 release，强制 `lazerRequireReleaseSigning` 和 `lazerRequireNativeAudio`。
5. 从真实 APK 读取包名、versionCode、versionName、最低 API、ABI、证书，计算实际大小与 SHA-256；必须与基准签名一致、code 更高。
6. 生成带版本号的独立文件名、清单、页面及发布记录。成功后才递增 `pubspec.yaml`；不覆盖已有版本目录，不部署。

项目现有原生音频打包脚本要求 Python 3.10+；建议使用独立的 Python 3.12 虚拟环境，并确保其中的 `python3` 是该版本。另需 Flutter、JDK、Android SDK/NDK、CMake、Ninja 及原构建脚本要求的编译工具。

本机工具链可先加载：

```sh
source /Users/ripplejon/.local/share/lazer-toolchain/env.sh
python3.12 -m venv build/release-venv
source build/release-venv/bin/activate
flutter pub get
python3 ci/release_android.py --first-release
# 后续升级改为 --baseline-apk /absolute/path/to/previous-lifeaxis-release.apk
```

可用 `--version-name` 指定新的语义版本名称；`--notes` 指定真实更新说明文件。默认说明为 `release/notes.txt`，默认不强制更新。`--mandatory` 需要发布者明确选择，不建议仅因普通功能更新而阻断使用。

输出为 `build/releases/android/<versionCode>/`：

- `lazer/Lazer-<versionName>-<versionCode>-universal.apk`
- `lazer/version.json`，包含用户要求的七个字段及从 APK 读取的额外系统／签名元数据。
- `lazer/index.html`、样式、脚本、现有应用图标、吉祥物及 MiSans 字体。
- `release-record.json`，记录基准、源代码 revision/dirty 状态及每个发布文件的大小和 SHA-256；此文件不上传到站点。

## 从控制台清单恢复生产基线

2026-11-05 用户完成腾讯云控制台登录后，已在当前 production 部署的“构建产物”中确认根目录和每个子目录的全部文件、目录计数及无分页状态，记录为 `docs/releases/edgeone-inventory-2026-11-05.json`。这不同于根据本机共享目录推测线上文件。

`ci/export_production_baseline.py` 根据该提供商完整清单逐文件下载正式域名的真实内容、检查响应长度及 APK 结构、计算大小与 SHA-256，并在下载前后确认 production ID 不变；同时归档该部署的静态配置，生成部署脚本可读取的完整 receipt。不会复制共享目录中的额外文件，也不触发部署。

```sh
python3 ci/export_production_baseline.py \
  --inventory docs/releases/edgeone-inventory-2026-11-05.json \
  --output build/releases/production-baselines/dpca0j6vbwtg
```

本次已恢复 31 个文件、共 371406487 字节（含 26 个历史 APK），隔离目录及同级 `dpca0j6vbwtg-receipt.json` 已生成。命令拒绝覆盖已有基线；它要求清单仍属于当前 production。以后若生产 ID 变化，必须重新从登录后的提供商产物视图完整核对，而不能修改旧清单的 ID 冒充新清单。

## 下载页与应用内更新

### EdgeOne 大文件传输

首次整包静态部署 `dpychk8vjwyf` 在提供商输出检查阶段失败：单文件限制为 25 MiB，真实签名 APK 为 76678471 字节（73.13 MiB）。失败未切换生产部署，旧站点保持 `dpca0j6vbwtg`。

为避免新建外部存储或更换下载域名，`ci/edgeone_apk_transport.py` 在隔离暂存时将大 APK 原样切成每份最多 20 MiB 的静态 `.bin`，并生成仅匹配该不可变版本 APK 路径的 Edge Function。`release/apk_stream.js` 按顺序、带背压逐块转发，支持 GET／HEAD，取消时中止内部请求，异常或长度不符时中断响应；不在内存合并整包、不修改签名包、不上传账号／业务数据。网站与更新器仍使用同一个版本化 `.apk` URL，下载结果必须与构建 APK 的完整大小、SHA-256 和签名一致。

发布 receipt 区分实际静态 `files`、归档 `functions` 源文件和流式 `virtualFiles`；保留函数源码及每份分片，记录提供商真实路由配置。下一次发布必须使用同部署 ID 的成功快照与 receipt，复制既有函数和分片、校验所有历史虚拟 APK，禁止覆盖历史路由。所有上传文件在部署前额外检查 25 MiB 上限，函数代码不包含任何密钥。

页面源文件位于 `release/site/`，由打包脚本复制资源并生成真实清单。模板不包含猜测的版本号、包大小或 APK 地址。页面只读取自身相对 `./version.json`，检查解析后的目录；所有发布文字使用 `textContent`。失败时移除下载链接，提供重试，不回退到其他应用或历史文件。

应用中：设置 → 关于 → 检查更新。手动检查不受自动频率限制；启动／回到前台自动检查遵守每日成功间隔，自动失败后五分钟重试。检查状态与结果区分正在检查、已是最新、发现新版和失败。

下载有进度、取消和重试，只写私有 cache/updates；校验大小、SHA-256、包名、名称／数字版本及当前签名证书集合。安装前原生再次校验，使用非导出的 FileProvider 向系统安装器临时授予读取权限。未知来源授权在系统设置中由用户决定，返回后重新确认；系统安装仍需用户确认。

更新请求不携带账号、Cookie、业务数据或设备标识，清单仅带用于避免旧缓存的时间戳。新加权限只有 `REQUEST_INSTALL_PACKAGES`；不为更新索取通知、媒体或外部存储权限。网站／CDN仍可正常看到网络请求的 IP 等传输信息，不等于上传音乐业务数据。

## 完整线上基线：缺一不可

共享目录 `/Users/ripplejon/Desktop/code/SoftLanding/edgeone-dist` **不是可信线上完整基线**。文件存在于本机不代表已发布；从首页爬取链接或只核对已知 APK 也不能证明不存在其他历史文件。

需要以下任一材料：

- EdgeOne 为当前 production 部署导出的完整静态文件快照及完整文件清单；
- 已记录成功的**同一个 production Deployment ID** 对应的完整上传快照、全部静态文件的大小／SHA-256 和原始部署配置。

`ci/deploy_android.py` 接受的 receipt 有 `projectId`、`deploymentId`、`completeSnapshot: true`、`source`（`provider-export` 或 `successful-full-snapshot`）、`files`（全部线上相对路径 → `sha256` / `sizeBytes`）、`config`（原 headers / redirects / caches）。这些字段描述的是已经证实的导出／部署事实，**不能手工给共享目录贴一个 completeSnapshot 标签来绕过门禁**。缺历史清单时必须去控制台获取原始归档或联系原发布者，不能靠猜测补齐。

暂存工具会：

- 复用已有 CLI 登录，读取当前 production ID，与归档记录严格对应。
- 核对当前静态路由与归档配置，逐文件从线上读取、核验完整清单的大小与哈希。
- 在新建隔离目录中只复制 receipt 中列出的文件，排除共享目录中未列出的草稿。
- 保留所有历史文件，仅新增／替换本次 Lazer 文件；已存在的版本 APK URL 一律拒绝覆盖。
- 合并仅作用于 `/lazer/` 页面及清单的禁缓存设置、补上 `/lazer` 到 `/lazer/` 的重定向；无法安全理解现有广泛缓存规则或非静态路由时停止。

只暂存、不部署的命令：

```sh
python3 ci/deploy_android.py \
  --baseline /absolute/path/to/proven-production-snapshot \
  --baseline-receipt /absolute/path/to/proven-production-receipt.json \
  --release build/releases/android/<versionCode> \
  --output build/releases/staging/review-<versionCode>
```

先检查隔离目录及其旁边的 `*-receipt.json`。真正发布必须选新的 output 路径，再加 `--deploy`，脚本会重新核对生产 ID，防止用已过期快照覆盖他人更新。存在并发发布者时还需协调发布窗口；“最后一次查询 ID”不是提供商级的原子写锁。

实际调用现有 CLI：

```sh
edgeone makers deploy <隔离完整快照目录> \
  -n feelmating-updates -e production --json --skip-ai-gateway-sync
```

不要把 `<隔离完整快照目录>/lazer` 单独部署成整个站点；也不要直接部署共享 edgeone-dist。默认不会提示重复登录；确实缺 CLI token 时才执行 `edgeone login`。

## 发布后验证与实录

成功部署不等于验证成功。脚本只有完成以下检查，才记录 `verified-production` 并输出正式可下载链接：

- 重新读取 production ID，保存到旁边的 receipt。
- 从正式域名逐文件重新校验完整基线与本次文件的大小／SHA-256，包括首页、其他应用和所有历史 APK。
- 确认清单响应包含 `Cache-Control: no-store`。
- 从清单中的正式 APK URL 再次下载，重新运行 APK 签名验证、包名／版本／系统元数据读取，并与原正式基准和清单比较。

若部署完成但 CDN尚未生效／验证失败，记录停留在 `deployed-verification-pending`；不可将该状态当成交付成功。保留 receipt 与受限权限的 CLI 部署日志以定位问题，不应盲目重复推送旧快照。

无论静态验证如何，仍应在装有原正式版的设备上验证覆盖升级、数据保留、取消下载、权限拒绝／授权返回和系统确认安装。测试签名或 debug 安装不等于正式升级兼容性验证。

## 检查命令

```sh
flutter analyze --no-pub
flutter test --no-pub test/android_updates_test.dart test/update_checker_test.dart
python3 -m unittest discover -s ci/tests -v
NODE_PATH=/path/to/installed/playwright/node_modules node ci/tests/download_page.test.cjs
```

浏览器测试使用标明为测试夹具的清单，拦截所有网络请求，不访问／部署正式域名；截图保存在 `build/download-preview/review/`。不把测试清单放入发布目录，也不拿测试 APK 冒充正式包。
