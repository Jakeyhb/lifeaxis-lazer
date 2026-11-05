---
name: Lazer Android 下载页
description: 现有下载页源码的视觉与交互契约，不代表生产发布完成。
colors:
  clay: "#d97757"
  clay-hover: "#c6613f"
  paper: "#f0eee6"
  ink: "#141413"
  secondary: "#625f58"
  line: "#cccbc8"
  surface-light: "#faf9f5"
typography:
  display:
    fontSize: "clamp(64px, 8vw, 104px)"
    fontWeight: 700
    lineHeight: 1.05
    letterSpacing: "-.04em"
  headline:
    fontSize: "clamp(28px, 3.4vw, 44px)"
    lineHeight: 1.45
    letterSpacing: "-.025em"
  body:
    fontFamily: "MiSans, 'PingFang SC', sans-serif"
    fontSize: "16px"
    lineHeight: 1.95
rounded:
  retry: "8px"
  icon: "10px"
  download: "12px"
components:
  download:
    backgroundColor: "{colors.clay}"
    textColor: "{colors.ink}"
    rounded: "{rounded.download}"
    padding: "17px 24px"
  download-hover:
    backgroundColor: "{colors.clay-hover}"
  download-unavailable:
    backgroundColor: "{colors.line}"
    textColor: "{colors.secondary}"
  retry:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    rounded: "{rounded.retry}"
    padding: "10px 16px"
---

# Lazer 下载页设计契约

## Overview

**沿用规则。** 这是既有 Lazer 视觉世界的代码延伸，不是新品牌提案，也没有获批设计稿。依据为 `release/site/index.html`、`style.css`、`download.js`、`lib/theme/design_tokens.dart` 与 `PRODUCT.md`；实现事实优先于旧注释或风格联想。

暖纸底、墨色文字、陶土主操作与现有吉祥物，服务于 Android 下载、真实版本信息和安装说明。延续 Lazer 名称、应用图标（`assets/app_icon.png`）及现有吉祥物，不引入 FeelMating 文案或新美术方向。

**状态边界。** 完整生产快照已通过登录后的提供商产物清单恢复；用户已授权以独立包名和专用签名首发，不兼容上游升级链。`ci/release_android.py` 在打包时复制页面引用的图标、吉祥物和 MiSans 字体，并从真实 APK 生成 `version.json`；这些生成物不在页面模板目录手填。部署与验证以实际发布记录为准，不得将源码就绪写成线上可下载。

## Colors

### Primary
- 陶土 `clay` 仅用于可用的下载主操作，悬停使用 `clay-hover`；按钮文字为墨色，不改为白字。

### Neutral
- 暖纸 `paper` 承载整页；墨色 `ink` 用于标题、正文、重点分隔与焦点轮廓。
- 辅助文字 `secondary` 用于说明、状态和元数据标签；细线 `line` 用于分隔及不可用按钮底色；浅纸 `surface-light` 仅用于重试悬停底色。

**继承而非照搬规则。** 纸、墨、陶土、深陶土、细线及浅纸与应用令牌对应；网页辅助文字使用自身较深的颜色，不套用应用的浅灰标签色。当前网页仅有浅色模式。

## Typography

全页继承前述 MiSans 字体栈。本地字体声明仅含 Regular（400），采用交换显示（`font-display: swap`）；粗体允许浏览器合成（`font-synthesis: weight`），不宣称网页已加载应用的全部字重。应用各字体角色实际也指向 MiSans，不能因旧注释而改成衬线标题。

前述字号分别对应 Lazer 主标题、宣传短句与简介；小屏覆盖见 Layout。章节标题桌面（23px、700），元数据及安装说明（14px），更新说明（15px、行高 1.9），状态、图注与页脚（13px）。版本和大小使用等宽数字；更新说明保留换行，长文本与校验值允许任意位置折行。

## Layout

- 桌面页头、正文、页脚居中，最大宽度（1160px），左右各留（48px）。首屏为文案／吉祥物双栏（1.4:1），栏距（64px）、最小高度（670px）；下载直接跟随简介。
- 版本与安装说明延续双栏（1.4:1），栏距（80px）；元数据采用标签／数值两列，标签宽（110px）。不把信息拆成装饰卡片。
- 小屏断点（≤760px）：左右留白（20px），首屏和说明区均为单栏，下载按钮占满宽度；主标题（76px）、宣传短句（32px）、章节标题（22px）。简介移除桌面专用换行。
- 吉祥物桌面等比展示，高（475px）；小屏右对齐，容器高（225px），图高（285px）、底部负边距（−90px），形成局部露出的构图，不换成新插画。

## Elevation & Depth

**纸面规则。** 现有页面无阴影、渐变或悬浮卡片；用细线（1px）和留白分区。版本区上沿为墨色，其余分隔为细线色。与应用无阴影的层次语言一致，不照搬应用的深色页脚或其他未使用表面。

## Shapes

页面分区平直开放，图标、下载与重试按钮分别使用前述圆角；不是胶囊按钮。网页下载按钮四角均圆，不照搬应用仅底部圆角的填充按钮令牌。下载图形使用现有描边 SVG，品牌图像保持原素材。

## Components

- **导航与语义：** 保留“前往下载”跳转链接、版本说明锚点、标题层级、元数据定义列表、原生 SHA-256 折叠区和吉祥物替代文字；源码外链保留 `noopener noreferrer`。键盘焦点使用墨色轮廓（3px、偏移 6px）。
- **下载状态：** 初始无 `href`，标记 `aria-disabled="true"`；加载区使用 `aria-busy`，状态文字以礼貌级实时播报。仅验证通过后显示“下载 Android 版”并赋予链接；失败显示“暂时无法获取安装包”与重试。下载最小高度（58px），重试（44px）。
- **目录隔离：** 只以当前页面 URL 解析相对 `./version.json`，添加时间戳；请求不缓存、不带凭据、拒绝重定向，超时（10 秒）。禁止改读站点根目录或其他应用清单；现有 CSP 将资源和连接限制在同源。
- **可信清单：** 启用下载前验证版本名／构建号、更新说明、强制更新标志、SHA-256、体积、包名 `fun.lifeaxis.lazer`、最低 API（≥26）及受支持 ABI。APK 仅接受指定 HTTPS 源 `updates.lifeaxis.fun` 下 `/lazer/` 的单层 `.apk` 文件名，拒绝凭据、查询串及片段。清单有格式和长度检查；界面仅展示其中的版本、系统要求、大小、架构、说明与校验值，不额外推导发布承诺。
- **纯文本规则：** 所有清单文字使用 `textContent`，不解析 HTML；下载地址通过验证后单独赋给链接。系统要求来自 `minSdk`（26 显示 Android 8.0，其余显示 API 级别），禁止硬编码未知 APK 参数。
- **失败关闭规则：** 每次加载先移除下载链接；请求、解析或校验失败均保持不可下载，无脚本同样不提供备用链接。保留同签名覆盖安装及签名冲突时停止、不要卸载旧版的说明；网页不声称已验证 APK 签名或文件哈希，应用内校验说明不等于生产验证完成。
- **轻动效：** 可用下载按钮悬停变色并上移（2px），按下复位，过渡（160ms、ease-out）。减少动态偏好关闭过渡与平滑滚动；现有悬停位移仍存在，不写成完全无动效。

## Do's and Don'ts

- 保持“获取信息 → 验证 → 开放下载”的顺序；以真实清单更新信息，不手填版本、大小、系统要求或校验值。
- 保持桌面／移动端的信息顺序、长文本折行、键盘焦点和错误重试；源码描述不是已完成浏览器验收的证明。
- 不增加未经证实的功能、用户量、评分、支持平台或安全保证；不把目标发布地址当成已上线成果。
- 不用历史 APK、其他应用链接或猜测地址兜底；正式签名与完整生产快照补齐前，不宣称发布完成。
