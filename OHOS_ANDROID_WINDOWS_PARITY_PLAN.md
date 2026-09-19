# 鸿蒙端 Android/Windows 完全功能对齐适配计划

## 1. 目标与完成定义

目标是让鸿蒙端在用户可见功能上达到 Android 手机和 Windows PC 的完整能力集合。凡是 HarmonyOS 已提供公开原生能力的功能，必须由 ArkTS/C++ 原生模块实现，Flutter 只负责业务编排、状态管理和类型化协议。

完成前不得把“可以启动 HAP”“Dart 单测通过”或“有一个 Flutter fallback”作为完全适配依据。

完全对齐的最低标准：

1. 本地书架、阅读、历史、进度、导入导出全部可用。
2. 数据源插件能够完成安装、启停、搜索、详情、目录、正文、资源和交互验证。
3. 音频支持后台播放、锁屏控制、蓝牙按键、通知、音频焦点和中断恢复。
4. 视频支持完整播放、Texture 渲染、进度、倍速、亮度、常亮和全屏。
5. 局域网配对、发现、双向同步、插件包和应用包传输全部闭环。
6. 鸿蒙 HAP 更新至少能完成下载、校验和系统确认安装。
7. 所有 OHOS 原生能力都有真机验收证据，而不是只有 Dart 单测或模拟器启动记录。
8. 原生能力异常时返回稳定错误码和用户可理解的提示。

## 2. 强制实施原则

### 2.1 原生优先

只要 OHOS 有公开系统 API，就必须使用 OHOS 原生实现：

- 文件选择、保存：`@ohos.file.picker`。
- 分享、打开外部链接：Want、`ACTION_SEND_DATA`、`ACTION_VIEW_DATA`。
- 包信息：`@ohos.bundle.bundleManager`。
- 网络状态：Network Kit 的 `NetConnection`、默认网络和网络事件。
- 扫码：HMS ScanKit。
- 音视频：`@ohos.multimedia.media` 的 `AVPlayer`。
- 锁屏媒体控制：AVSession Kit。
- 音频焦点：Audio Kit 音频会话。
- 常亮、窗口亮度：`@ohos.window`。
- 插件浏览器：ArkWeb 原生 Web 组件和 Cookie/Profile 能力。

Flutter 通用插件只能在 OHOS 没有对应公开能力时使用，不能用 `file_selector`、`share_plus`、`url_launcher`、`mobile_scanner`、`audio_service` 或 `media_kit` 替代已有的 OHOS 原生能力。

### 2.2 原生模块负责生命周期

原生模块负责权限、Ability 上下文、系统对象、监听器、资源释放和线程切换。Flutter 侧只能看到：

- 不可变请求模型。
- 不可变结果模型。
- 稳定错误码。
- 有界事件流。
- 可取消的 Future/调用。

禁止 Flutter 页面直接保存 OHOS 原生对象或依赖 MethodChannel 的隐式状态。

### 2.3 能力探测优先于静态判断

扩展 `PlatformCapabilities`，增加真实探测结果：

- `supportsOhosRuntime`
- `supportsOhosWebView`
- `supportsOhosBackgroundAudio`
- `supportsOhosAppUpdate`
- `supportsOhosNetworkEvents`

每项至少返回 `available`、`reason`、`apiVersion` 和 `architecture`。页面根据能力结果显示或隐藏功能，不得分散使用 `Platform.operatingSystem == 'ohos'` 判断。

## 3. 功能对齐矩阵

| 能力 | OHOS 原生所有者 | Flutter 边界 | 完成标准 |
| --- | --- | --- | --- |
| 文件导入/导出 | `mgread_ohos_system` + `DocumentViewPicker` | `ImportExportFilePicker` | `.mgread` 导入、导出、取消、权限失败均可用 |
| 文件分享 | `mgread_ohos_system` + Want URI 授权 | `shareFile(path)` | 分享目标选择、URI 授权、失败恢复 |
| 外部 URL | `mgread_ohos_system` + `startAbility` | `openExternalUri(uri)` | 浏览器/外部页面可打开，目标不存在有提示 |
| 包信息/设备信息 | `mgread_ohos_system` | 版本和设备标签查询 | 版本名、版本号、设备名稳定显示 |
| 网络状态 | 新增 OHOS Network Bridge | `LanSyncNetworkEnvironment` | 网络变化实时触发同步暂停/恢复 |
| 二维码 | `mgread_ohos_scanner` + ScanKit | `OhosBarcodeScanner` | 配对、同步、应用传输四类二维码完整回传 |
| 音频播放 | `mgread_ohos_media` + AVPlayer | `AudioPlaybackBackend` | 前台播放、暂停、跳转、倍速、缓冲、错误事件 |
| 音频后台 | 新增 `mgread_ohos_audio_session` | `AndroidAudioBackgroundService` 的平台抽象 | 锁屏、蓝牙、通知、焦点和中断完整可用 |
| 视频播放 | `mgread_ohos_media` + AVPlayer Texture | `VideoPlaybackBackend` | 首帧、缓冲、Surface、全屏、常亮、亮度和释放 |
| 插件 Runtime | OHOS arm64 Node Host | `PluginRuntime` | Runtime 启动、安装、启停、传输、诊断稳定 |
| 插件 WebView | 新增 `OhosBrowserSessionHost` + ArkWeb | `ctx.webview` 协议 | 搜索、详情、目录、正文和交互型来源可用 |
| 局域网同步 | Network Kit + Dart 同步层 | 现有配对/传输协议 | Android/Windows/OHOS 双向同步全通过 |
| 应用更新 | HAP 下载校验 + 系统确认安装 | `AppUpdateService` | 至少完成用户确认式安装闭环 |
| 桌面开发插件 | OHOS 文档选择器/开发包模式 | Runtime artifact API | 移动端可导入开发包；Windows 保留目录热更新 |

官方原生能力参考：

- [DocumentViewPicker](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-file-picker)
- [Network Kit 网络连接](https://developer.huawei.com/consumer/cn/doc/harmonyos-center-guides/faqs-network-61-0000002592784330)
- [AVPlayer](https://developer.huawei.com/consumer/en/doc/harmonyos-references/arkts-apis-media-t)
- [AVSession 接入](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/avsession-access-scene)
- [Window API](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-v5/application-window-fa-V5)
- [Bundle Installer 权限说明](https://developer.huawei.com/consumer/en/doc/harmonyos-references/V3/ibundleinstaller-0000001054358773-V3)

## 4. 分阶段实施计划

### 阶段 0：平台契约和验收基线

工作内容：

- 建立 Android、Windows、OHOS 功能矩阵和差异清单。
- 统一 OHOS MethodChannel/EventChannel 名称、请求版本和错误码。
- 为每项能力增加 native availability probe。
- 为每项能力建立 Flutter contract test、原生单元测试和真机验收用例。
- 把“未实现”“设备不支持”“用户取消”“权限拒绝”“系统失败”区分开。

交付物：

- `OhosCapabilitySnapshot`。
- OHOS 原生协议版本说明。
- 能力错误码表。
- Android/Windows/OHOS 三端验收清单。

### 阶段 1：系统原生能力层

扩展 `mgread_ohos_system`：

- `.mgread` 文件导入。
- `.mgread` 文件保存。
- `.mgplugin` 文件导入。
- 插件包导出和分享。
- 外部 URL 打开。
- 当前包版本和 build number。
- 设备型号/设备标签。
- 统一 native error mapping。

验收：

- 真机导入、导出、分享各类文件。
- 用户取消后页面不残留 loading。
- 无权限、系统无目标应用、文件不存在时都有明确提示。
- 进程重启后导入文件和持久化数据仍可读取。

### 阶段 2：数据源 Runtime 与 ArkWeb

这是最高优先级阶段。

当前 OHOS 已有 arm64 Node Host，但 x86_64 模拟器使用明确 stub。因此需要：

1. 固化 OHOS arm64 Node Runtime 构建、打包和版本校验流程。
2. 新增 `OhosBrowserSessionHost`，使用 ArkWeb 原生能力。
3. 每个插件独立 WebView 会话和 Cookie/Profile。
4. 实现页面导航、显示、隐藏、关闭、JS 执行、HTML 获取、点击、输入、按键、等待文本、获取 URL。
5. 实现请求取消、超时、页面销毁和 WebView 崩溃恢复。
6. 对接 Runtime 的 `ctx.webview` 和 `browser.session.v1`。
7. 对需要交互的来源支持页面显示、用户操作和回传。
8. 对 Android 已标记不支持的 CDP 能力，OHOS 第一阶段也可以返回 `unsupported`；Windows 专属 CDP 不强行复制。

验收：

- 至少 5 个代表性数据源完成发现、搜索、详情、目录、正文和资源链路。
- 至少 2 个需要 Cookie/JS 的来源完成真实 arm64 真机验证。
- 至少 1 个需要交互验证的来源完成 `interaction_required` 闭环。
- Runtime 异常不得导致首页、书架和本地阅读崩溃。
- x86_64 模拟器要么补齐 Node Runtime，要么明确标记为“仅本地阅读，不属于发布目标”。

### 阶段 3：后台音频和系统媒体会话

当前 OHOS 已有 AVPlayer 音频后端，但 Android 的 `AudioService` 只在 Android 启用，需要新增 OHOS 原生音频会话层。

工作内容：

- 创建和销毁 AVSession。
- 发布标题、作者、封面、时长、进度和播放状态。
- 支持播放、暂停、上一首、下一首、跳转和倍速。
- 处理锁屏控制、蓝牙按键和有线耳机事件。
- 接入音频焦点和音频中断。
- App 进入后台后保持播放。
- 网络恢复后恢复加载或返回分阶段失败。
- Flutter Controller 与 AVSession 双向同步。

验收场景：

- 锁屏播放、暂停、跳转、切换章节。
- 蓝牙耳机上一首/下一首。
- 来电、闹钟和其他音频抢占。
- 手动暂停后不能被错误自动恢复。
- 音频服务销毁后释放 AVSession、播放器和所有监听器。

### 阶段 4：视频和窗口能力

完善现有 `mgread_ohos_media`：

- 视频 Texture 与 AVPlayer Surface 生命周期绑定。
- 首帧、缓冲、播放失败、结束事件统一。
- 播放时窗口常亮。
- 使用 Window API 设置应用窗口亮度。
- 进入/退出视频全屏。
- 横竖屏切换。
- 返回键和页面销毁时释放 Surface。
- 后台切换时按 Android/Windows 当前策略暂停或恢复。

全局系统亮度不作为完成条件；鸿蒙只实现应用窗口亮度，并在 UI 中明确说明范围。

### 阶段 5：局域网同步

将当前通用 IPv4 探测替换为 OHOS Network Kit 原生事件桥：

- 默认网络查询。
- 网络可用/不可用事件。
- Wi‑Fi、热点、网线转接和移动网络识别。
- 可用于同步的局域网地址发现。
- 网络状态变化时自动暂停和恢复同步。

完成三组真实互通：

- Android ↔ OHOS。
- Windows ↔ OHOS。
- OHOS ↔ OHOS。

验证内容：

- 配对二维码。
- 书架同步。
- 阅读进度同步。
- 插件包传输。
- 应用包传输。
- 配对密钥持久化、删除和重新配对。
- 网络断开、切换和恢复。

### 阶段 6：HAP 应用更新

工作流程：

1. 获取当前 OHOS 包信息。
2. 局域网传输 HAP。
3. 校验文件大小、SHA-256、包名、版本号和签名信息。
4. 调用系统允许的安装确认流程。
5. 安装后重新启动并验证迁移结果。
6. 失败时保留旧版本并清理临时文件。

先做平台可行性验证：

- 如果普通应用可以拉起用户确认安装，实现“下载 + 校验 + 系统确认安装”。
- 如果只能通过应用市场，实现“检测版本 + 跳转应用市场”。
- 如果两者都不可用，不能宣称与 Android 自更新完全等价，必须在能力矩阵中明确标记。

不能把签名级 Bundle Installer 权限当作普通应用默认能力。

### 阶段 7：插件管理和自检

移动端实现等价能力：

- 通过 OHOS 文件选择器导入 `.mgplugin`。
- 查看插件版本、状态、大小和诊断信息。
- 启用、停用、升级和卸载。
- 运行单个数据源探测。
- 导出插件和诊断信息。

Windows 保留：

- 任意开发目录选择。
- 文件监听。
- 本地开发构建。
- 批量全链路验证。

如果要求界面和流程绝对一致，需要把 Runtime 公共契约从“开发目录”升级为“开发项目/开发包”。OHOS 沙箱不应直接复制 Windows 的任意目录监听模型。

### 阶段 8：真机回归与发布门禁

测试目标：

- HarmonyOS arm64 真机：正式发布目标。
- OHOS x86_64 模拟器：只做启动和本地能力验证，除非补齐 x86 Node Runtime。
- Android 真机。
- Windows PC。

必须执行：

- 首次启动和升级迁移。
- 书架导入、导出和分享。
- 小说、漫画、视频、音频完整链路。
- 后台音频、锁屏、蓝牙和音频中断。
- 数据源安装、启停、搜索、详情、目录、正文、Cookie 和交互验证。
- 三端局域网配对和双向同步。
- HAP 传输、校验和安装。
- 无网络、无权限、用户取消、系统回收和切后台恢复。
- 低内存、弱网、长章节和长时间播放。

## 5. 发布阻断条件

以下任一项未通过，不能标记为“完全功能对齐”：

- OHOS 真机无法完成需要 WebView 的真实数据源链路。
- 音频无法在锁屏状态接受系统媒体控制。
- 局域网无法正确感知网络变化。
- HAP 只能下载但没有用户可执行的安装闭环。
- OHOS 原生桥没有直接测试和真机证据。
- OHOS 仍通过通用 Flutter 插件替代已有 OHOS 原生能力。
- 只验证了模拟器，没有验证 arm64 真机。

## 6. 推荐实施顺序

1. OHOS ArkWeb + Runtime 数据源链路。
2. AVSession 后台音频。
3. Network Kit 局域网事件。
4. HAP 更新安装流程。
5. 插件自检和开发包流程。
6. 视频窗口体验和全面真机回归。
