# Lazer Android 阿里云 OSS 下载站

## 当前边界

- 应用：Lazer 独立发行版，Android 包名 `fun.lifeaxis.lazer`。
- 下载目录固定 `/lazer/`，域名 `https://updates.lifeaxis.fun`。
- 站点文件由 `ci/release_android.py` 从真实 APK 生成：`index.html`、`style.css`、
  `download.js`、图标、吉祥物、MiSans 字体、`version.json` 和版本化 APK。
- 本文说明如何把生成的站点发布到自己的阿里云 OSS，不依赖共享的 EdgeOne 站点。

## 一次性配置

1. **创建 OSS Bucket**（例如 `lazer-downloads`），地域按需选择（如 `cn-hangzhou`）。
   桶权限保持私有，只通过静态网站托管或 CDN 回源读取。
2. **开启静态网站托管**：默认首页设为 `index.html`。
3. **绑定自定义域名** `updates.lifeaxis.fun`：OSS 控制台 → 静态网站托管 → 绑定自定义域名，
   并按提示添加 CNAME 解析。
4. **配置 HTTPS**：OSS 自定义域名的 HTTPS 需要阿里云 CDN（DCDN）承载：
   - 创建 CDN 域名 `updates.lifeaxis.fun`，源站指向该 OSS Bucket；
   - 申请免费 SSL 证书并开启 HTTPS；
   - 在 DNS 把 `updates.lifeaxis.fun` 的 CNAME 指向 CDN 分配的 CNAME。
5. **缓存规则**：`version.json` 不缓存，`*.apk` 长缓存，其余按默认。

## 发布

先用现有的打包脚本生成站点，再上传到 OSS：

```sh
# 首次发布（要求线上与本机均无本发行版历史）
python3 ci/release_android.py --first-release

# 后续升级（必须提供同包名、同签名的基准 APK）
python3 ci/release_android.py --baseline-apk /absolute/path/to/previous.apk

export OSS_ACCESS_KEY_ID=...
export OSS_ACCESS_KEY_SECRET=...
python3 ci/deploy_aliyun.py \
  --site build/releases/android/<versionCode>/lazer \
  --bucket lazer-downloads \
  --endpoint oss-cn-hangzhou.aliyuncs.com \
  --domain updates.lifeaxis.fun \
  --verify
```

- `--dry-run` 只打印将要上传的文件和缓存头，不写 OSS。
- `--verify` 在上传后从公网域名重新下载每个文件，核对大小与 SHA-256。
- 凭据只从环境变量读取，不写入仓库、日志或发布记录。

## 缓存头

| 文件 | Cache-Control |
| --- | --- |
| `version.json` | `no-store, no-cache, must-revalidate, max-age=0` |
| `index.html` | `no-cache` |
| `*.apk` | `public, max-age=31536000, immutable` |
| 其他 | `public, max-age=3600` |

## 应用内更新

Android 端在 **设置 → 关于 → 检查更新** 中读取
`https://updates.lifeaxis.fun/lazer/version.json`。清单会校验版本名／构建号、更新说明、
强制标志、SHA-256、体积、包名和最低 API；APK 只接受该域名下 `/lazer/` 的单层 `.apk`，
拒绝凭据、查询串和片段。下载后校验大小、SHA-256、包名、版本和签名，再由系统安装器
请求用户确认安装。

## 与 EdgeOne 部署的关系

`ci/deploy_android.py` 与 `release/apk_stream.js` 面向共享的 EdgeOne 站点：那里有
25 MiB 单文件限制，所以大 APK 需要分片流式传输。阿里云 OSS 没有该限制，APK 直接静态
托管即可，不需要分片。两套脚本共用 `ci/release_android.py` 的打包产物，可按需选择。
