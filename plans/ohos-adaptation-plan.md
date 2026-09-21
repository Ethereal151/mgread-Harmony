# 鸿蒙适配计划

## 目标与范围

本计划只以当前代码实现、公开契约和直接测试入口为基线，不以说明文档中的完成描述或测试名称推断完成度。

## 2026-09-21 执行状态与官方能力边界

本轮已按下列结论更新实现和能力清单：

- 已落地：OHOS `transport:http` 通过 ArkWeb 页面 `fetch` 执行，沿用页面 Cookie、重定向和请求上下文；取消会标记 job、停止 ArkWeb 页面并丢弃迟到结果；Runtime 来源代理支持 OHOS 系统代理读取、自定义代理优先和关闭后的恢复；ArkWeb 自定义代理使用 SDK API 15+ 的 `ProxyController`，支持 HTTP、HTTPS 和 SOCKS（将应用层 SOCKS5 映射为 ArkWeb 的 `socks`）；AVPlayer 的 `CACHED_DURATION` 毫秒事件已映射为 Dart 的真实 `bufferedPosition`。
- 稳定不支持：命名 WebView Profile 隔离、AVPlayer 会话级播放器代理、OHOS 全局系统音量写入、音量键翻页和 AVPlayer 内 Anime4K。它们均已在能力清单中为 `false`，并由 UI 隐藏或保留播放器内部音量，不再静默成功。
- 官方依据：华为 [ArkWeb Web 组件文档](https://developer.huawei.com/consumer/en/doc/harmonyos-references/arkts-basic-components-web)公开普通/隐身模式和应用级 Cookie 管理，没有本项目所需的命名持久 Profile 契约；[音量管理文档](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V5/volume-management-V5)明确系统音量只能读取/监听、不能由普通应用直接调节，而 [Media API](https://developer.huawei.com/consumer/en/doc/harmonyos-references-V3/js-apis-media-0000001281201038-V3) 的 `setVolume` 是播放器/音频流音量；华为 [NetStack 请求配置](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/capi-netstack-http-requestoptions)虽从 API 20 提供 `Http_RequestOptions.httpProxy`，但它属于独立 HTTP 客户端，公开的 API 26 [AVPlayer 文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-media-avplayer)没有会话级代理入口，因此不能把来源代理 API 冒充播放器代理；华为 [媒体 FAQ 的 AVPlayer HLS 示例](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-media-7)使用 `AVPlayer.url = '...m3u8'`，本轮已按该入口补齐但 API 26 arm64 真机仍返回 `avplayer_state_error`；[Audio Session 管理](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/audio-session-management)和 [AVSession API](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/avsession-api)是后台/中断恢复的官方路径，原生已注册 AVSession 与 audioInterrupt；[AVCodec surface 播放文档](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/video-decoding-play-remote)说明图像处理能力属于独立解码渲染链路，不能把 AVPlayer 状态字段冒充 shader；[ArkUI 按键事件文档](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V13/arkts-common-events-device-input-event-V13)描述的是有焦点组件和外设键事件，不能构成手机物理音量键可稳定拦截的产品契约。
- 当前证据：签名 arm64 HAP 已构建并通过 `hdc install -r` 安装；2026-09-21 在 `PLA-AL10`（`192.168.3.48:45975`、HarmonyOS 7.0/API 26、`arm64-v8a`）重新通过 Runtime、ArkWeb、5 个 Stage 2 fixture、音频、视频、首次运行首页和阅读器启动/系统返回保存时序。音频过程中发现并修复了 OHOS `play()` 异步状态竞态：原生现在等待 `playing` 再返回，修复后的真机音频 smoke 已通过。
- 2026-09-22 增量验收：`library_reader_start_test.dart` 在同一 arm64 真机重新构建、安装并通过“书架进入 Reader”和“系统返回后保存并刷新书架”两条用例；有效同步二维码到“接收临时数据”的业务路由回归测试也已通过。一次 HDC 端口转发失败经重启 HDC 后恢复，不属于应用失败。
- Runtime 生命周期与能力补充：`integration_test/ohos_runtime_lifecycle_test.dart` 在同一 arm64 真机完成首次 ping、原生 `restart` 和同一 Facade 恢复 ping，并校验两轮 `runtime_facade_invoke_started/completed` 诊断及敏感字段不出现在诊断文本；`ohos_runtime_smoke_test.dart` 同时直接断言 9 项 OHOS 产品能力的可用/不支持状态；测试专用 `debugDispose()` 不纳入真机验收，因为会关闭 Flutter 调试通道。
- 当前模拟器复验：`127.0.0.1:5555` OHOS x64 模拟器上的 ArkWeb 浏览、AVPlayer 音频、视频纹理/窗口恢复、首次运行首页和 x64 Runtime 稳定降级共 5 组 integration test 均通过，并且每组均重新构建、安装并启动签名 HAP；x64 Runtime 仍按架构限制保持 `unsupported`。
- 来源快速检查（固定 Node，不能替代真实 MgRead EXE 或 OHOS 真机）：56 个来源中 28 个 `passed`、6 个 `partial`、22 个因站点阻断/交互验证/资源不可达或 testkit 能力边界失败；报告为 `artifacts/source-tests/quick-all-20260921-deps.json`。Windows Release 主程序实际检查尚未执行，因为当前 Windows 未启用 Flutter 所需的符号链接支持。

### 2026-09-21 验收矩阵快照

| 表面 | 状态 | 当前证据 | 尚缺证据或边界 |
| --- | --- | --- | --- |
| Runtime | `pass` | `ohos_runtime_smoke_test.dart` 在 arm64 真机通过 Node host、Runtime ping、Network Kit 地址和 9 项产品能力状态；`ohos_runtime_lifecycle_test.dart` 补充原生 restart、同一 Facade 恢复、两轮诊断和敏感字段检查；`ohos_stage2_runtime_arkweb_test.dart` 补充受控长耗时调用取消后 `cancelled`、后续调用恢复和插件卸载后列表确认；x64 模拟器仍稳定返回 `runtime_architecture_unavailable` | 无新的 Runtime 功能缺口；x64 仅按发布约束保持 unsupported |
| ArkWeb | `pass` | `ohos_browser_session_smoke_test.dart` 和 `ohos_stage2_runtime_arkweb_test.dart` 在 arm64 真机通过页面导航、HTML、5 个 fixture、资源代理、Cookie/JS 和 `interaction_required` 恢复 | 代理路由在来源网络和音视频边界分别验收，ArkWeb 本身无新增阻塞 |
| 来源网络/代理 | `partial` | OHOS HTTP、系统/自定义来源代理单测；固定 Node `--jitless` 四项回归通过，包含原生直连、gzip、显式 HTTP/SOCKS5、环境 HTTP 代理、NO_PROXY 和 Runtime 配置切换；无 WebAssembly fallback 已补原生直连、HTTP 代理和 SOCKS5 代理通道并支持 gzip 解压；`ohos_real_source_smoke_test.dart` 在 `PLA-AL10` arm64 真机通过 35ge、德奇、番茄、米读、书库 365 五个真实来源的插件导入、发现、搜索、详情、目录和正文链路；`ohos_browser_proxy_smoke_test.dart` 在同一 arm64 真机通过本地 LAN HTTP 代理命中验证 | 真实系统代理、非 loopback NO_PROXY 和 HTTPS CONNECT 代理的 arm64 专项证据仍需单独验收；播放器代理继续按 OHOS SDK 不支持处理 |
| 音频 | `partial` | arm64 真机 AVPlayer 普通资源播放/暂停/跳转/倍速 smoke 通过；OHOS `play()` 状态竞态已修复；x64 复验也通过 | 代理资源、切歌、后台 AVSession 和系统中断恢复 |
| 视频 | `partial` | arm64 真机 Texture、首帧、进度、`CACHED_DURATION -> bufferedPosition`、窗口恢复和 Unified Streaming H.264 HLS 播放通过；x64 复验也通过；Apple BipBop HLS 返回 `open_failed / avplayer_state_error`，Mux x36xhzz HLS 可打开但 `play` 超时，Mux tears-of-steel HLS 返回 `open_failed / avplayer_state_error`，均保留为兼容性边界 | OHOS 播放器代理、全屏、系统中断和真实系统音量边界的播放证据；HLS 已有至少一条 arm64 成功样本，但外部流兼容性仍不统一 |
| Reader/主应用 | `partial` | arm64 真机首次运行首页、阅读器启动、系统返回、退出前保存/书架刷新通过；音量键不支持公开 API 测试；OHOS 外链桥接成功/拒绝/异常 fake-platform 测试；既有扫码 UI 证据；`lan_sync_page_qr_test.dart` 已补齐有效同步二维码进入“接收临时数据”业务路由的回归验证 | 真实内容完整阅读迁移、文件导入/导出/分享和反馈页面真机闭环 |
| 跨设备同步/HAP 传输 | `pass` | 协议、QR 载荷、恢复和容量单测；x64 OHOS 与 MI 8 Android 的正向、反向同步通过；`PLA-AL10` arm64 OHOS Host 与 MI 8 Android peer 的双向同步及 HAP 包传输/校验/用户确认边界通过；arm64 OHOS Host↔Windows Client 双向书架/插件同步均通过 | OHOS↔OHOS 按用户明确要求跳过，不作为本轮完成门禁；不上架，因此 HAP 市场跳转也按用户要求跳过 |
| OHOS SDK 明确不支持能力 | `pass` | Capability flags、arm64 真机 9 项状态断言、UI 隐藏和公开 API 直接测试；官方 API 边界已记录 | 无；这些能力按 `unsupported` 管理，不冒充可用 |

因此，“计划内可实现项”的代码实现已完成；上面列出的 OHOS SDK 能力边界属于有证据的 `unsupported`，不是遗留的静默空操作。当前总验收状态仍为 `partial`：播放器代理、系统中断和本地阅读完整迁移仍未全部满足完成定义；有效二维码业务路由已补齐自动化验证，来源代理、HLS、真实跨设备同步和 HAP 传输也已补齐对应证据，OHOS↔OHOS 与不上架的 HAP 市场跳转均已按用户要求明确跳过，不计入本轮阻塞项。

目标是让 OpenHarmony（以下简称 OHOS）在需要的产品能力上达到 Android 基线，并明确哪些能力需要 Windows 级别的额外能力，哪些能力保持平台差异。

本轮范围包含：

- 插件 Runtime 与 ArkWeb 会话；
- 来源 HTTP、系统代理和播放器代理；
- OHOS 音视频后端与播放器控制；
- 阅读器平台能力；
- 外部系统 Intent 和运行时诊断；
- OHOS arm64 真机验收与回归证据。

明确不包含：

- HAP 应用内自更新。当前不以上架应用市场为前提，因此暂不实现 HAP 安装器，也不把它计入鸿蒙适配完成度；
- OHOS 开发目录热加载。Android 同样只支持导入已校验的插件 artifact，移动端保持这一产品策略；
- 只有 Windows 才有的 WebView2 专属能力，除非产品明确要求 OHOS 也必须提供同等能力。

## 适配前代码基线（历史记录）

以下表格保留适配启动时的事实，用于说明任务来源；当前完成状态以本文件顶部的“2026-09-21 执行状态与官方能力边界”和后续验收记录为准。

### 已具备基础实现

- ArkWeb 已覆盖 `page.open/show/hide/close/navigate/evaluate/html/fetch/click/input/key/waitText/getUrl`；
- 插件 artifact 导入、导出、传输校验和 Runtime 重启链路已有 OHOS Supervisor；
- 文件选择、分享、外部 URI、扫码、局部亮屏/沉浸式阅读和基础局域网同步已有 OHOS 原生桥接；
- OHOS AVPlayer 已支持基础音视频打开、播放、暂停、跳转、倍速、音量、队列和 AVSession；
- OHOS Node Runtime 已有 arm64 原生实现，但 x86 stub 会稳定返回架构不可用。

这些内容只能说明“代码路径存在”，不能直接说明真实设备上的完整链路已经通过。

### 明确未完全适配项与已收口边界

| 优先级 | 能力 | 当前代码事实 | 对比基线 |
| --- | --- | --- | --- |
| P0 | 来源 HTTP 传输 | 已完成：OHOS `transport:http` 通过 ArkWeb 页面 `fetch`，并有 arm64 五个真实来源直连验收。 | Android/Windows 仍保留各自原生路径。 |
| P0 | WebView Profile/Cookie 隔离 | 命名持久 Profile 隔离保持 `unsupported`：华为公开 ArkWeb API 没有本项目所需的命名持久 Profile 契约；Cookie/JS 和页面生命周期仍按应用级 WebView 管理。 | Android 使用 WebView multi-profile；Windows 为插件创建独立 profile 目录。 |
| P0 | Runtime/播放器代理 | Runtime 系统代理、自定义来源代理和 Node 无 WASM 代理通道已实现；OHOS AVPlayer HTTP 播放器代理按 SDK 能力明确为 `unsupported`，UI 不再把它当成可用。 | Android/Windows 具备播放器 HTTP 代理路径。 |
| P0 | 视频缓冲位置 | 已完成：OHOS 原生 `CACHED_DURATION` 毫秒事件映射为 Dart `bufferedPosition`，arm64 普通视频真实 smoke 通过。 | MediaKit 后端提供真实缓冲位置。 |
| P0 | 系统音量 | 保持 `unsupported`：华为公开音量管理能力允许普通应用读取/监听，不提供本应用直接设置系统媒体音量的契约；公开 API 与 UI 已直接表达该边界。 | Android/Windows 有系统音量通道。 |
| P1 | WebView 取消 | 已完成：取消会标记 job、停止 ArkWeb 页面并丢弃迟到结果；arm64 受控长调用得到稳定 `cancelled`，后续调用恢复。 | Android/Windows 会停止网络或 WebView 工作。 |
| P1 | 视频增强 | 保持 `unsupported`：OHOS AVPlayer 没有本项目所需 Anime4K shader 链路；能力标志、UI 和公开调用均不报告伪成功。 | Android/Windows MediaKit 支持 Anime4K。 |
| P1 | 反馈外链 | 已完成：`feedback_page.dart` 通过 `openExternalUri`，OHOS 走 `OhosSystemClient.openUri`；已有成功、拒绝和异常测试。 | Android/Windows 使用 `url_launcher` 外部应用模式。 |
| P1 | Android 风格音量键翻页 | 保持 `unsupported`：OHOS 没有稳定拦截手机物理音量键的公开应用契约；能力标志和 UI 已隐藏该选项。 | 这是 OHOS 相对 Android 的缺口；Windows 也不要求该能力。 |
| P2 | Runtime 诊断 | 已完成：OHOS facade/native restart、诊断快照、敏感字段过滤和恢复链路均已验收。 | Android 诊断字段更多，但不影响 OHOS 公开契约。 |
| P2 | Runtime 架构覆盖 | OHOS x86 stub 明确要求 arm64 真机；模拟器或 x86 环境不能运行嵌入式 Node。 | 作为发布限制管理，不把 x86 当作已支持环境。 |
| 条件项 | `page.cdp` | OHOS 没有实现；Android 也明确返回 `unsupported`。 | Windows WebView2 支持 CDP。若 Android 是移动基线，不把 CDP 作为 OHOS 阻塞项。 |

## 实施顺序

### 阶段 0：固定基线与能力声明

目标：先把“未支持”“部分支持”和“已支持”变成代码可判断的状态，避免 UI 显示出鸿蒙实际上不能完成的操作。

任务：

1. 为 OHOS 建立适配能力清单，至少覆盖：
   - `sourceHttpTransport`；
   - `webViewProfileIsolation`；
   - `webViewCancellation`；
   - `sourceSystemProxy`；
   - `playerHttpProxy`；
   - `videoBufferedPosition`；
   - `videoEnhancement`；
   - `systemVolume`；
   - `readerVolumeKeys`。
2. 未实现的能力必须让 UI 隐藏、置灰或显示稳定的“不支持”状态，不允许点击后静默成功。
3. 在 capability 变更时同步更新直接测试，不把产品说明文档作为能力来源。

建议落点：

- `lib/platform/platform_capabilities.dart`；
- `lib/features/media/application/source_video_playback_platform_controller.dart`；
- `packages/mg_read_reader_ui/lib/src/platform/reader_platform.dart`；
- 相关设置页和播放器设置组件。

完成标准：每一个 OHOS 平台能力都有一个明确结果：真实可用、稳定不支持，或明确降级；没有“UI 可操作但实际空操作”的路径。

### 阶段 1：补齐 Runtime 与 ArkWeb 会话

#### 1.1 实现 `transport:http`

目标：使使用旧版 `browser.session.v1` 的来源在 OHOS 上能够完成 HTTP 请求，并保持 Android/Windows 的响应语义。

任务：

1. 在 `OhosArkWebHost.ets` 删除对 `transport == http` 的无条件拒绝。
2. 选择并固定实现路径：
   - 优先复用当前 WebView Profile 的 Cookie、UA 和重定向语义；
   - 如果使用 ArkWeb 页面 `fetch`，必须保证 HTTP 状态码、最终 URL、响应头、文本/JSON/base64 响应类型和取消语义与公开契约一致；
   - 如果使用 OHOS 原生 HTTP，必须解决当前 WebView Cookie 与请求 Cookie 的同步边界，不能让来源读取或导出宿主 Cookie。
3. 为请求增加明确的 deadline、取消和迟到结果清理。
4. 保留 `html`、`webview` 和 `interaction` 的现有语义，避免修复 HTTP 时改变页面可见性。

主要文件：

- `packages/mgread_plugin_runtime/ohos/src/main/ets/com/mgread/mgread_plugin_runtime/OhosArkWebHost.ets`；
- `packages/mgread_plugin_runtime/lib/src/ohos_supervisor.dart`；
- 如需公开参数，先检查 `packages/mg_read_source_api` 的现有 contract，不在主应用复制类型。

验收：同一来源分别使用 `http`、`html`、`webview`，验证状态码、最终 URL、Cookie 会话、重定向、JSON/base64 和失败码一致。

#### 1.2 补齐 WebView Profile/Cookie 隔离

目标：不同插件之间不能共享 ArkWeb Cookie、缓存或登录态。

任务：

1. 确认 ArkWeb 可用的 profile/context 隔离 API 和生命周期。
2. 将当前 `Map<string, OhosArkWebPlatformView>` 扩展为带 profile 身份的 session 记录。
3. 每个 `pluginId` 创建稳定、可回收的独立 profile；`close` 时释放页面，但按契约保留可复用 session 所需的 profile 状态。
4. 明确 Cookie 清理、Runtime 重启和插件卸载时的 profile 回收策略。
5. 添加两个插件相同域名登录态互不污染的测试。

验收：插件 A 设置 Cookie 后，插件 B 不能读取；同一插件重新打开仍可复用自身 Cookie；关闭和卸载行为符合预期。

#### 1.3 让取消真正到达原生工作

目标：取消不只是丢弃 Flutter 结果，而是尽快终止排队、HTTP、JavaScript 和 WebView 等待。

任务：

1. 为每个原生 job 保存可取消的请求句柄或 AbortController。
2. `cancel` 时主动终止：
   - ArkWeb 加载；
   - 页面 `fetch`；
   - 长时间 `evaluate`；
   - `waitText` 轮询；
   - OHOS 原生 HTTP 请求（如果 1.1 采用原生 HTTP）。
3. deadline、`page.close`、Runtime dispose 使用同一套清理逻辑。
4. 清理完成后不得让迟到 Promise 写入永久结果或覆盖新一代 session。

验收：对导航、页面 fetch、waitText 和 HTTP 请求分别在执行中取消，原生请求停止，最终只产生一次稳定的 `cancelled` 结果。

#### 1.4 CDP 的决策

默认按 Android 移动基线处理：OHOS 返回稳定 `unsupported`，并隐藏只依赖 CDP 的功能。

只有在产品要求 OHOS 与 Windows 完全对齐时才启动第二阶段：确认 ArkWeb DevTools Protocol 能力，设计权限、连接生命周期和错误映射，再增加 `page.cdp`。

### 阶段 2：补齐来源代理与播放器代理

#### 2.1 系统代理

目标：OHOS 没有自定义来源代理时，Runtime 来源 HTTP 能使用系统代理；有自定义代理时使用自定义配置，关闭后恢复系统代理。

任务：

1. 在 `mgread_ohos_system` 增加读取当前网络代理的稳定方法，返回应用层已有的 `HTTP_PROXY`、`HTTPS_PROXY`、`NO_PROXY` 语义。
2. 在 `packages/mgread_plugin_runtime/lib/src/system_proxy.dart` 增加 OHOS 分支。
3. 调整 `FlutterNetworkProxyManager.runtimeSourceProxyUri()`，不要把系统代理逻辑硬编码为 Android-only。
4. 覆盖直连、HTTP 代理、HTTPS 代理、NO_PROXY、loopback 和读取失败回退。

验收：OHOS 真机切换系统代理后，新建来源请求使用新路由；应用自定义代理优先；关闭自定义代理后恢复系统代理；系统代理读取失败不阻塞启动。

#### 2.2 音视频自定义代理

目标：用户配置的 HTTP 音频/视频代理在 OHOS 播放器后端真实生效，或者在无法支持时明确禁用。

任务：

1. 评估 OHOS AVPlayer 对 HTTP proxy 的真实 API 能力，不先假设可以照搬 MediaKit 的 `http-proxy`。
2. 若原生支持：扩展 `OhosMediaClient.openAudio/openVideo` 和 `MgReadOhosMediaPlugin.ets`，把代理作为会话级参数传入，并验证重定向、Range 和 HLS。
3. 若原生不支持：在能力清单中标记 `playerHttpProxy=false`，隐藏音视频代理设置或给出稳定提示；不能继续把 `proxyUri` 传入后静默忽略。
4. 保持 Runtime 来源代理和播放器到 Runtime 本地资源的代理边界，不新增 Flutter 回环转发服务器。

验收：HTTP 代理下音频、普通视频、Range 视频和 HLS 各完成一次真实播放；代理不可用时显示可识别的失败，而不是无限缓冲。

### 阶段 3：补齐视频和系统控制

#### 3.1 缓冲位置

推荐先采用“真实数据优先”的实现：

1. 如果 AVPlayer 能提供已缓冲时长，新增明确的 `buffered` 事件并在 Dart 后端更新 `bufferedPosition`。
2. 如果只能提供百分比，则在原生层同时提供 duration，并在契约中明确百分比到时间的换算误差；不能把百分比伪装成精确缓冲时间。
3. 如果两者都不可用，隐藏二级缓冲轨道和缓冲详情，不保留始终为零的假数据。

涉及文件：

- `packages/mgread_ohos_media/ohos/src/main/ets/com/mgread/mgread_ohos_media/MgReadOhosMediaPlugin.ets`；
- `packages/mg_read_video_player/lib/src/backend/ohos_video_playback_backend.dart`；
- `packages/mg_read_video_player/lib/src/ui/video_player_chrome.dart`；
- `packages/mg_read_video_player/lib/src/ui/video_player_details_sheet.dart`。

#### 3.2 视频增强

短期建议：在 OHOS 未有真实 shader/增强实现前隐藏 Anime4K 开关，并将 `videoEnhancement` 标记为不支持。

长期若必须对齐 Android/Windows：为 OHOS 建立独立的 GPU/shader 实现，不能在 AVPlayer 后端中只更新状态字段。需要验证画面确实变化、性能、发热和销毁时资源释放。

验收：开启增强后必须有真实渲染证据；否则 UI 不展示该选项，调用也不能静默报告成功。

#### 3.3 系统音量

任务：

1. 在 `mgread_ohos_system` 增加读取和设置系统媒体音量的 native 方法。
2. 在 `source_video_playback_platform_controller.dart` 接入 OHOS 分支。
3. 处理权限、系统音量范围、后台/前台和设备无媒体音量 API 的回退。
4. 若 HarmonyOS API 无法满足稳定语义，则隐藏播放器系统音量控制，只保留播放器内部音量。

验收：真实设备上拖动播放器系统音量，系统音量和其他媒体应用观察到的值一致；退出播放器后音量设置仍符合系统行为。

### 阶段 4：补齐主应用集成遗漏

#### 4.1 外部 URI 统一走 OHOS 桥接

任务：

1. 将 `lib/features/profile/presentation/feedback_page.dart` 的直接 `launchUrl` 改为调用 `lib/platform/platform_system_actions.dart` 的 `openExternalUri`。
2. 搜索所有主应用层直接使用 `launchUrl` 的路径，逐个确认 OHOS 是否需要桥接；Reader package 的已有平台实现单独保留并验证。
3. 增加 OHOS fake-platform 测试，验证成功、失败和异常提示。

验收：反馈、来源详情、插件帮助和 Reader 外链在 OHOS 均通过同一桥接策略打开或显示稳定失败。

#### 4.2 音量键翻页

这项只作为 Android parity 任务，不是 Windows parity 任务。

任务：

1. 确认 OHOS ArkUI/Ability 是否能收到硬件音量键事件，并评估与系统音量调节的冲突。
2. 若可行，在 `NovelReaderUiPlugin.ets` 增加开关和事件回传，在 Dart 层只在 capability 为真时启用。
3. 若不可行，保持稳定不支持，并隐藏 Reader 设置中的音量键翻页选项；不要保留空操作按钮。

验收：开启后音量键只翻页、不误调系统音量；关闭后恢复系统音量行为；页面切换、后台和销毁时监听正确释放。

### 阶段 5：诊断、发布约束与真实验收

#### 5.1 Runtime 诊断

任务：

1. 为 OHOS Supervisor 增加与 Android 对齐的 invoke started/completed/rejected/bridge_failed/timeout/failed 诊断。
2. 对 WebView session 增加 transport、profile mode、cancel、timeout 和终止原因，但禁止记录 Cookie、令牌、完整 URL 查询参数和媒体签名。
3. 增加诊断 ring buffer 和 `latestDiagnostics` 快照测试。

#### 5.2 arm64 发布约束

任务：

1. 将 OHOS arm64 作为当前 Runtime 支持矩阵中的明确条件。
2. 启动时发现 native Node 不可用时，显示稳定的架构不支持状态，不进入半启动 Runtime。
3. CI 至少验证 x86 stub 的稳定错误和 arm64 构建产物存在；真实 Node/ArkWeb 链路必须在允许的 OHOS arm64 设备执行。

#### 5.3 真实验收矩阵

每项必须记录 `pass`、`partial`、`unsupported` 或 `not-run`，不能用单元测试替代真机证据。

| 表面 | 最低验收 |
| --- | --- |
| Runtime | 启动、首次调用、超时、取消、重启、插件导入、插件卸载和诊断快照。 |
| ArkWeb | 隐藏/显示/关闭、导航、HTML、脚本、页面 fetch、HTTP transport、点击、输入、按键、等待文本和 Cookie 隔离。 |
| 来源网络 | 直连、系统代理、自定义 HTTP/HTTPS/SOCKS5 代理、NO_PROXY、失败和恢复。 |
| 音频 | 普通资源、代理资源、播放/暂停/跳转/倍速/切歌、后台 AVSession、中断恢复。 |
| 视频 | 普通资源、Range、HLS、代理、首帧、进度、缓冲、全屏、系统音量和退出清理。 |
| Reader | 亮屏、沉浸式、视频窗口、音量键能力状态和外链。 |
| 主应用 | 反馈、来源详情、插件帮助、扫码、文件导入/导出、分享和局域网同步。 |

## 代码与测试落点

### Runtime/WebView

- 实现：`packages/mgread_plugin_runtime/ohos/src/main/ets/com/mgread/mgread_plugin_runtime/OhosArkWebHost.ets`；
- Facade：`packages/mgread_plugin_runtime/lib/src/ohos_supervisor.dart`；
- 对照：`packages/mgread_plugin_runtime/android/src/main/kotlin/com/mgread/mgread_plugin_runtime/AndroidBrowserSessionHost.kt`；
- 对照：`packages/mgread_plugin_runtime/lib/src/windows_browser_session_host.dart`；
- 现有直接测试：`packages/mgread_plugin_runtime/test/ohos_browser_session_host_test.dart`、`integration_test/ohos_browser_session_smoke_test.dart`、`integration_test/ohos_stage2_runtime_arkweb_test.dart`。

### 代理与系统桥接

- `packages/mgread_plugin_runtime/lib/src/system_proxy.dart`；
- `lib/features/network_proxy/application/flutter_network_proxy_manager.dart`；
- `packages/mgread_ohos_system/ohos/src/main/ets/`；
- `lib/platform/platform_system_actions.dart`；
- `lib/features/profile/presentation/feedback_page.dart`。

### 音视频

- `packages/mg_read_audio_player/lib/src/backend/ohos_audio_playback_backend.dart`；
- `packages/mg_read_video_player/lib/src/backend/ohos_video_playback_backend.dart`；
- `packages/mgread_ohos_media/ohos/src/main/ets/com/mgread/mgread_ohos_media/MgReadOhosMediaPlugin.ets`；
- `lib/features/media/application/source_audio_playback_service.dart`；
- `lib/features/media/application/source_video_player_launcher.dart`；
- `lib/features/media/application/source_video_playback_platform_controller.dart`；
- 现有直接测试：`packages/mg_read_audio_player/test/`、`packages/mg_read_video_player/test/`、`integration_test/ohos_media_smoke_test.dart`、`integration_test/ohos_video_smoke_test.dart`。

### Reader 与能力显示

- `packages/mg_read_reader_ui/lib/src/platform/reader_platform.dart`；
- `packages/mg_read_reader_ui/ohos/src/main/ets/com/example/novel_reader_ui/NovelReaderUiPlugin.ets`；
- Reader 相关 package 测试和 OHOS 真机 Integration Test。

## 完成定义

鸿蒙适配只能在以下条件全部满足后称为“本计划范围内完成”：

1. P0 项均有真实 OHOS arm64 设备证据；
2. 未支持能力在 UI 和公开 API 上都能稳定表达，不存在静默空操作；
3. WebView 的 HTTP、Profile、Cookie、取消和资源清理通过直接测试；
4. 来源代理和播放器代理分别验证，不能用来源 HTTP 成功代替播放器验证；
5. 视频首帧、播放进度、缓冲、系统音量和退出清理均有真实播放证据；
6. 诊断中不包含 Cookie、令牌、签名 URL 和完整敏感请求参数；
7. 快速检查、Flutter/package 测试、OHOS 构建和 OHOS 真机验收分组报告；任何未执行项只能标记为 `partial` 或 `not-run`。

HAP 自更新不参与以上完成定义。
