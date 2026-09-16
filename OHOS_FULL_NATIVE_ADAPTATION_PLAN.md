# MgRead OHOS 全量原生适配计划

> 本文件是当前 OHOS 适配的执行计划，优先级高于 `OHOS_ADAPTATION_PLAN.md` 中关于“安全降级、暂不支持或不阻塞 HAP”的相应条款。原计划保留作为已完成阶段 1～6 的历史基线，不再作为本次完整适配的验收标准。

## 1. 本次要求与原计划的边界

### 1.1 原计划中的内容

`OHOS_ADAPTATION_PLAN.md` 是本次工作的输入基线，其中已经记录：

- OHOS Flutter 工程、API 26、HAP 构建、签名安装和最低交付回归已完成；
- Flutter Runtime Facade 和 OHOS MethodChannel/EventChannel 边界已经搭建；
- 当前 OHOS Runtime 尚未提供可验证的 Node 24.16.0 arm64 宿主；
- 音频、视频和扫码当前使用 `unsupported` 或稳定降级，不能宣称完整适配。

其中“在线数据源、音视频和扫码可以降级”“不阻塞 HAP 生成”“完整功能后置”等，是原计划的阶段性交付策略，不是本次新要求。

### 1.2 用户本次新增的强制要求

本次目标从“最低可交付版本”切换为“原仓库功能等价的 OHOS 完整适配”：

1. OHOS 原生接入 Node.js `24.16.0` Runtime，目标架构为 `ohos-arm64`。
2. 音频和视频统一使用 OHOS 原生 `AVPlayer` 能力，不以 `media_kit` 作为 OHOS 播放后端。
3. 相机和扫码使用 OHOS 原生相机及扫码能力，不以 `mobile_scanner` 的缺失实现或占位页作为交付。
4. 按原仓库现有公共 API、数据源协议、阅读器行为和生命周期语义完成适配；不是只复制页面或只让 HAP 启动。
5. 不做降级适配：不得用 `unsupported`、空实现、no-op、伪造成功、功能隐藏或“能启动即可”替代目标能力。

“百分百适配”在本计划中定义为“原仓库对外可观察功能和契约在 OHOS 上闭环一致”，不要求把 Android/Javet 或桌面进程模型逐行照搬到 OHOS；OHOS 内部可以使用符合平台约束的原生实现，但必须通过同一 Flutter 公共边界提供等价行为。

## 2. 目标、范围和硬性原则

### 2.1 最终交付目标

在 OHOS API 26、arm64 真机上，完成以下闭环：

```text
启动
 → Runtime 24.16.0 就绪
 → 安装/启停/调用原仓库数据源插件
 → 发现、搜索、详情、目录、正文、漫画资源和媒体资源
 → 小说/漫画阅读与进度恢复
 → 音频 AVPlayer 前后台播放
 → 视频 AVPlayer 播放与画面渲染
 → 相机扫码并完成局域网配对/同步/传输路由
 → 前后台、权限、网络变化和进程销毁后仍能正确收尾
```

### 2.2 不可违反的工程原则

- 保留 `PluginRuntime.invoke` 和现有 typed error/wire protocol；主应用不得获得 PID、端口、内部 URL、VM 或 Runtime 数据根。
- 每个应用进程只有一个 Node Runtime/VM；不引入 Worker、第二 VM、插件子进程、native addon 或自定义 loader。
- `packages/mg_read_source_api` 继续作为数据源宿主上下文和 WebView 类型的唯一公开声明包。
- 主应用业务数据仍由 `AppPersistence`、`ContentLibrary` 和各自 Store 持有；Runtime 私有目录不能成为书架、正文、进度或设置权威。
- 小说、漫画、音频、视频仍保持独立的公共模型、Controller、会话和生命周期；OHOS 原生层只实现宿主契约。
- 所有异步调用都要具备请求世代、取消、超时和关闭保护；原生资源、Stream、Timer、Surface 和监听器必须成对释放。
- 新增依赖必须先核对官方资料并精确固定版本；不能因为 OHOS 构建方便而升级全量 Flutter/package 依赖。
- 未完成原生实现前，目标功能保持“未交付”状态，不能改写成已完成或以降级结果通过验收。

## 3. 当前基线与差距

| 能力 | 当前仓库状态 | 本次必须达到 |
| --- | --- | --- |
| OHOS 工程/HAP | API 26 工程、debug/release HAP 和模拟器启动基线已存在 | arm64 真机 debug/release 可安装、启动、升级和卸载重装 |
| Node Runtime | OHOS Facade 已接入，但调用和管理仍返回 `unsupported`；无可验证 OHOS Node 24.16.0 二进制 | 单 Runtime/VM、精确 Node 24.16.0、插件全调用链和生命周期闭环 |
| 数据源插件 | 原仓库 Node Core、标准插件和 source API 已存在 | OHOS 上导入、安装、启停、更新、发现、搜索、详情、目录、内容、资源、取消和卸载行为等价 |
| 音频 | `mg_read_audio_player` 默认使用 `media_kit: 1.2.6`，OHOS 无原生实现 | AVPlayer 播放、队列、进度、恢复、音频焦点、后台/锁屏控制和关闭完整 |
| 视频 | `mg_read_video_player` 使用 `media_kit`/`media_kit_video`，OHOS 无原生实现 | AVPlayer、Surface/Texture 或 PlatformView、选集/清晰度、控制、全屏和生命周期完整 |
| 扫码 | 页面依赖 `mobile_scanner`，OHOS 当前不启动相机并显示提示 | 原生相机预览、权限、取景框、扫码、去重、停止/恢复和四类局域网二维码路由完整 |
| 平台能力 | OHOS capability flags 中仍有路径、文件、分享、链接、亮度、常亮等降级分支 | 对原仓库可见的平台能力逐项使用 OHOS 原生 API 或明确证明等价的 Flutter bridge |

## 4. 总体架构和职责划分

```text
Flutter UI / Reader / LAN Sync
          │ 既有公共 Dart API、MethodChannel/EventChannel
          ▼
OHOS Flutter plugins / native bridge
          ├─ Runtime host：Node.js 24.16.0 ohos-arm64，单 VM
          ├─ Media host：AVPlayer + AVSession/音频焦点 + Surface/Texture
          ├─ Camera host：相机预览 + 原生扫码 + 权限/生命周期
          └─ System host：沙箱、文件、分享、URI、亮度、常亮、包信息
          ▼
OHOS ArkTS/C++/系统能力
```

职责边界：

- `mgread_plugin_runtime`：维护 Flutter Facade、Supervisor、调用取消、进度事件和 typed 错误映射；OHOS 宿主拥有 Runtime 进程/VM 细节。
- `mg_read_node_runtime`：维护 Node Core、协议、插件 API、安装目录、catalog、HTTP/TLS/代理和 fixture；不把 OHOS 判断散落到各数据源。
- `mg_read_audio_player`：继续拥有跨平台音频会话和公共模型；新增可注入的 OHOS AVPlayer backend/host adapter，宿主仍拥有数据源和进度 Store。
- `mg_read_video_player`：继续拥有视频会话、选集和控制层；OHOS backend 负责 AVPlayer 和画面承载，不让 UI 直接接触原生对象。
- 局域网同步页面：继续拥有二维码载荷验证和业务路由；OHOS 相机扫码插件只负责预览、解码和返回标准扫描结果。
- 主应用：只使用公共 capability、Reader、Runtime、media 和 scanner API，不直接调用 ArkTS/C++ 私有方法。

## 5. 分阶段实施计划

### 阶段 0：冻结基线、契约和验收矩阵

目标：在动原生实现前，把“原仓库百分百适配”变成可逐项验证的清单。

工作项：

1. 固定当前上游 commit、目标分支、Flutter/Dart/DevEco/API 26、Node/npm 版本和 arm64 架构。
2. 从原仓库公共入口和直接测试整理功能矩阵：核心业务、Runtime、数据源、阅读器、音频、视频、局域网同步、权限、生命周期和异常。
3. 为每个能力记录：Flutter 入口、公开模型、原生入口、状态事件、错误码、资源所有者、直接单测、OHOS 真机场景和证据文件。
4. 将现有 OHOS `unsupported` 分支标记为迁移清单，禁止在新实现中继续扩大。

产出：

- `OHOS_FULL_NATIVE_ADAPTATION_PLAN.md`（本文件）；
- 更新后的功能矩阵和 native bridge 设计记录；
- 阶段 0 的源 commit、工具链和依赖锁定证据。

通过条件：所有原仓库公开能力都有 owner、实现位置和验证入口；未定义清晰的能力不得进入“已完成”。

### 阶段 1：OHOS 原生能力 PoC 和技术路线冻结

目标：先用最小独立样例验证三个最高风险点，不在主应用中用猜测推进。

1. Node：验证 `ohos-arm64` 上 Node 24.16.0 的构建/加载方式、单 VM 启动、`process.versions.node`、CommonJS/ESM、文件、HTTP/HTTPS/TLS、关闭和低内存回调。
2. AVPlayer：验证网络/本地媒体、准备、播放、暂停、seek、缓冲、完成、错误、音频焦点、后台存活和视频 Surface 输出。
3. Camera/Scanner：验证相机权限、后置摄像头预览、帧采集或原生扫码、QR 解码、取景框、暂停/恢复和权限拒绝。
4. 验证 ArkTS 与 Flutter 的通道数据类型、EventChannel 背压、Surface/Texture 生命周期、应用切后台和异常销毁。
5. 记录 API 26 真机与模拟器差异；以 arm64 真机结果作为生产路线依据。

技术路线冻结标准：

- Node 只能选择一个可维护且可打包的 OHOS 宿主路线；不能同时保留两套未定义所有权的 VM 路线。
- 视频输出必须确定为 Flutter Texture、PlatformView 或等价的官方承载方式，并明确旋转、裁剪、全屏和释放责任。
- 扫码必须确定原生解码组件、支持的格式、帧率/分辨率、重复结果策略和错误映射。

若 PoC 失败：项目状态为“完整适配被阻塞”，必须继续解决工具链、ABI 或原生能力问题；不得退回最低交付计划。

### 阶段 2：Node 24.16.0 OHOS Runtime 完整移植

目标：让 OHOS 数据源能力与原仓库 Node Runtime 行为一致。

工作项：

1. 生成并固定 Node 24.16.0 OHOS arm64 构建产物，校验二进制、依赖库、签名、架构和 `process.versions`；产物不得从未经验证的预编译包冒充。
2. 实现 OHOS Runtime host：启动、ready、`invoke`、`cancelInvocation`、进度 EventChannel、`dispose`、崩溃检测、前后台和低内存处理。
3. 接入现有 Runtime Core 和 protocol marker `1.0`，不新增 Flutter 私有协议，不绕过 catalog owner。
4. 完成 Runtime 私有目录、插件 artifact、安装/升级/回滚、启停、卸载、development package 和传输。
5. 完成来源 HTTP/HTTPS/TLS、系统代理、临时 HTTP/HTTPS/SOCKS5 代理、Cookie、超时、取消和资源代理。
6. 按 `mg_read_source_api` 验证现有真实数据源：发现、搜索、详情、目录、正文、漫画页面、音频/视频资源、WebView provider（如原仓库能力要求）。
7. 验证一个应用进程只创建一个 Node Runtime/VM，并在冷启动、热启动、切后台、恢复、异常和低内存场景下可复用或可控关闭。

通过条件：Runtime ping/status/version、标准插件调用、插件安装升级、取消、重启恢复和资源访问全部在 arm64 真机通过；任何一项返回 `unsupported` 都不算阶段完成。

### 阶段 3：OHOS 系统与文件能力原生化

目标：消除平台 capability 层中的占位或 no-op，使原仓库业务可使用真实 OHOS 能力。

工作项：

- 应用沙箱、数据库、SQLite ABI、缓存、导入导出和文件选择使用 OHOS EL2/官方文件能力；校验跨盘、中文路径、大文件和卸载重装行为。
- 实现包信息、系统分享、外部 URI/浏览器、屏幕亮度、屏幕常亮、窗口/方向等对应的 OHOS bridge。
- 配置网络、文件、相机、媒体、通知/后台播放所需权限，并验证首次授权、拒绝、仅本次授权、撤销权限和系统设置返回。
- 对 `ffi`、SQLite、TLS、socket 和代理做 arm64 ABI 验证；不以 Windows 或 Android 的动态库成功代替 OHOS 证据。
- 保持业务页面不出现平台散落判断；能力状态只由统一平台抽象提供。

通过条件：原仓库依赖的每个 OHOS capability 都有真实调用和错误映射；无 `unsupported`/空实现分支参与正常目标流程。

### 阶段 4：音频 AVPlayer 和后台会话

目标：保留 `AudioPlayerEngine`/`AudioPlayerView.controlled` 公共契约，替换 OHOS 后端为 AVPlayer 原生实现。

工作项：

1. 在音频 package 内定义 backend adapter，不让 Flutter UI 直接持有 AVPlayer；由 OHOS plugin 负责创建、配置、监听、暂停和释放。
2. 对齐播放状态：资源加载、playing、buffering、completed、duration、position、音量、倍速、错误、重试和网络资源失败。
3. 对齐会话语义：队列、切歌、上一首/下一首、恢复章节位置、显式播放意图、过期异步结果、睡眠定时器和退出保存。
4. 接入 OHOS 音频焦点/中断、耳机或音频路由变化、锁屏控制、通知/媒体会话和后台播放生命周期。
5. 处理应用切后台、被系统回收、恢复、重复初始化、快速切歌、seek 与关闭竞态；确保进度 Store 在暂停、切歌、生命周期、退出和关闭时刷新。
6. 删除 OHOS 路径对 `media_kit` 的运行时依赖；保留其他平台后端和公共测试，不改变非 OHOS 行为。

通过条件：前台、后台、锁屏、音频中断、网络失败、恢复进度、连续队列和资源释放场景在 arm64 真机通过；不存在“按钮成功但没有 `playing=true`”的假成功。

### 阶段 5：视频 AVPlayer、画面承载和系统交互

目标：保留 `mg_read_video_player` 的公共会话与控制行为，使用 OHOS AVPlayer 输出可交互画面。

工作项：

1. 实现 AVPlayer backend：prepare、play、pause、seek、buffering、完成、错误、重试、播放速率、音量和进度。
2. 建立 Flutter 与 OHOS Surface/Texture/PlatformView 的单一承载通道，处理尺寸、裁剪、旋转、黑屏、首帧、重建和释放。
3. 对齐 `groupId + episodeId` 选集模型；按当前选集解析签名/会话型资源，不触发整场播放器无谓 reload。
4. 对齐清晰度/线路选择、切集、恢复进度、播放意图、音频与视频互斥、保存和退出行为。
5. 按原仓库已有能力实现全屏、方向、系统常亮、返回键和 PiP（若该公共契约纳入基线）；权限或系统限制必须有真实错误反馈，不得静默隐藏。
6. 验证弱网、断网恢复、网络代理、长视频、快速切集、后台切换和旋转配置变化。

通过条件：可见首帧、播放/暂停/seek/缓冲/完成/错误状态一致；画面与控制层在切页、重建、全屏和退出后没有泄漏、黑屏或旧会话覆盖。

### 阶段 6：原生相机扫码与局域网同步闭环

目标：替换 `mobile_scanner` 的 OHOS 缺失路径，完成相机到业务路由的真实闭环。

工作项：

1. 实现 OHOS 原生相机预览和扫码 plugin，提供 Flutter 所需的 preview view、扫描事件、相机状态、Torch/镜头能力（若公共 API 暴露）和错误事件。
2. 配置并动态申请相机权限；处理授权、拒绝、永久拒绝、系统设置返回、切后台和页面销毁。
3. 对齐扫描页的取景框/scan window、横竖屏、预览比例、后置摄像头、重复结果去重、暂停/恢复和资源释放。
4. 解码并返回原仓库使用的二维码文本，交由现有载荷校验和路由逻辑处理，不在原生层复制配对、同步或 App 传输业务。
5. 完整验证 `auto`、`sync`、`pairing`、`appTransfer` 四类用途，包括错误二维码、过期二维码、非法地址、多地址和重复扫描。
6. 扫码成功后分别进入配对、同步接收或 App 传输流程，验证局域网连接、握手、确认、传输、失败重试和取消。

通过条件：真实相机能预览并识别测试二维码；四类载荷路由和异常流程通过；离开页面、权限变化、切后台和重复打开不残留相机占用。

### 阶段 7：全量业务回归、性能和发布交付

目标：以原仓库行为为参照完成 OHOS 真机证据闭环。

回归范围：

- 冷启动、热启动、首次运行、主题、设置、书架、历史、数据库、导入导出、小说/漫画阅读、缓存和进度恢复；
- Runtime 插件安装、更新、启停、发现、搜索、详情、目录、正文、漫画图片、媒体资源、取消和卸载；
- 音频前后台/锁屏会话、视频画面/全屏/切集、相机扫码/局域网配对/同步/传输；
- 网络断开恢复、代理、权限拒绝、旋转、内存压力、进程恢复、应用升级和卸载重装；
- arm64 真机至少覆盖一台正式目标设备；API 26 模拟器只作为辅助证据，不能代替真机结论。

性能与稳定性：

- 记录 Runtime 启动耗时、首个数据源调用耗时、阅读首内容耗时、媒体首帧/首声耗时、扫码首结果耗时和内存峰值；
- 对长文本、大漫画、长音频、长视频、连续切集、反复进出扫码页和反复前后台执行 soak 测试；
- 检查原生句柄、Surface、相机、播放器、Stream、Timer、临时文件和 Node Runtime 是否全部释放；
- 记录崩溃、ANR、白屏、黑屏、无声、旧结果覆盖新会话、权限死循环和数据丢失问题，修复后再进入发布验收。

交付物：

- arm64 debug/release HAP、构建命令、签名说明和 SHA-256；
- OHOS 真机测试报告、功能矩阵、失败项与修复记录；
- Node 24.16.0 OHOS arm64 构建/来源/许可证/校验记录；
- Runtime、AVPlayer、相机扫码原生 bridge 的架构和生命周期说明；
- 不提交 HAP、证书、私钥、本机路径配置和临时构建目录。

## 6. 验证门禁与完成定义

### 6.1 每阶段门禁

每个阶段必须分别报告以下五类证据，不能用其中一类替代另一类：

1. Dart/TypeScript/ArkTS/C++ 格式和静态检查；
2. package 单元/契约/fixture 测试；
3. OHOS native build 和 ABI 检查；
4. 已授权 OHOS API 26 arm64 真机 Integration Test；
5. HAP 安装、生命周期、性能和发布证据。

原有 Android/Windows/macOS 测试继续作为非回归证据；它们不能证明 OHOS 原生实现完成。OHOS Integration Test 必须使用语义、Finder 和稳定 `Key`，不能用坐标点击、桌面输入或 `adb input` 替代。

### 6.2 完整适配完成定义

只有同时满足以下条件，才可将项目标记为完成：

- Node Runtime 在 OHOS arm64 上真实运行，版本精确为 `24.16.0`，插件和 source API 调用链无 `unsupported`；
- 原仓库纳入范围的真实数据源能力全部可执行，并覆盖安装、发现、内容、资源、取消和生命周期；
- 音频和视频使用 OHOS AVPlayer 原生实现，状态、进度、后台/前台和资源释放符合公共契约；
- 相机扫码使用 OHOS 原生相机/扫码实现，并完成四类局域网二维码的实际业务路由；
- 平台能力层没有参与正常目标流程的空实现、占位页、伪成功或降级分支；
- 本地持久化、阅读器、同步、权限、网络、前后台和异常恢复全部通过 arm64 真机回归；
- debug/release HAP 可重复构建、安装、启动和升级，且没有提交敏感签名材料；
- 文档记录完整版本、构建、测试、设备、日志摘要和已知非阻塞问题；没有把未验证能力写成已完成。

未满足任一项时，状态只能是“进行中”或“被阻塞”，不得以“最低可交付版本”结项。

## 7. 提交拆分和版本策略

建议按公开边界拆分提交，便于逐阶段回滚和审查：

```text
docs: define ohos full native adaptation contract
feat(runtime): add verified node 24.16.0 ohos arm64 host
feat(runtime): complete ohos plugin and source lifecycle
feat(platform): implement ohos system capability bridges
feat(audio): add ohos avplayer backend and background session
feat(video): add ohos avplayer surface backend
feat(scanner): add ohos camera and qr scanning bridge
test(ohos): add native and arm64 integration evidence
docs(ohos): record full native build and verification results
```

只提交本次任务实际拥有的文件，保留其他工作区改动；禁止 `git add -A`、覆盖无关改动或提交签名私钥。根 Flutter 生产代码、用户可见资源或发布配置发生变化时，按仓库规则使用 `tools/update_flutter_version.ps1` 更新版本；仅文档、测试、工具、package、模板或独立数据源插件变化不升级根版本。

## 8. 风险、决策点和预估

最大风险是 Node 24.16.0 OHOS arm64 的可维护构建路线，以及 AVPlayer 的视频画面承载和后台媒体生命周期。它们必须在阶段 1 形成可重复 PoC，再进入主应用；不能靠静态依赖图、Android 产物或模拟器启动推断成功。

建议预估：

| 范围 | 预估 |
| --- | ---: |
| 基线矩阵和原生 PoC | 2～4 个工作日 |
| Node 24.16.0 OHOS arm64 Runtime 与插件闭环 | 7～15 个工作日 |
| 系统能力、文件和权限原生化 | 3～6 个工作日 |
| AVPlayer 音频及后台会话 | 4～8 个工作日 |
| AVPlayer 视频及画面承载 | 5～10 个工作日 |
| 相机扫码及局域网同步回归 | 3～6 个工作日 |
| 真机回归、性能、文档和 HAP 交付 | 4～8 个工作日 |

合计约 28～57 个工作日；若 Node ABI、视频 Surface、后台能力或系统扫码 API 需要额外移植，周期以阶段 1 的技术验证结果重新估算。该不确定性影响排期，不改变“完整原生适配、禁止降级”的验收标准。

