# 鸿蒙端与 Android / Windows PC 缺口适配计划

## 1. 计划目的

本文针对当前鸿蒙端尚未达到 Android 手机和 Windows PC 用户可见能力集合的部分，给出可执行的补齐顺序、交付物和验收门禁。

本计划不把“能够启动 HAP”“Dart 单测通过”或“存在 Flutter fallback”视为完成。发布目标是 HarmonyOS arm64 真机；OHOS x86_64 模拟器只用于启动、本地阅读和基础原生能力验证。

现状依据：

- [OHOS 功能基线矩阵](docs/feature-matrix.md)
- [OHOS 构建与验证基线](docs/ohos-build.md)
- [鸿蒙端 Android/Windows 完全功能对齐适配计划](OHOS_ANDROID_WINDOWS_PARITY_PLAN.md)
- [Runtime 与平台宿主规范](docs/core.md#runtime-与平台宿主)

## 2. 适配范围和不追求的等价项

### 2.1 必须达到的用户可见结果

- 本地书架、历史、进度、导入导出和小说/漫画阅读可用。
- 在线数据源能够安装、启停、搜索、查看详情、目录、正文、资源和交互验证。
- 音频能够前台及后台播放，并支持锁屏、蓝牙、通知、音频焦点和中断恢复。
- 视频能够稳定首帧播放，支持进度、倍速、Texture、亮度、常亮、全屏、旋转和释放。
- 局域网配对、发现、双向同步、插件包传输和应用包传输能够闭环。
- 鸿蒙应用更新至少能够完成下载、完整校验和用户可执行的安装或应用市场跳转闭环。
- OHOS 原生桥在 arm64 真机上有直接验收证据，错误能够映射为稳定错误码和用户提示。

### 2.2 不要求复制 Windows 专属实现

以下能力属于 Windows PC 开发工作流，不作为鸿蒙缺陷处理：

- 任意开发目录选择。
- 目录文件监听和目录热更新。
- Windows 本地开发构建和批量全链路验证。
- WebView2 专属 CDP 调试通道。
- Windows 窗口管理和桌面更新进程。

鸿蒙应提供等价的移动端流程：通过 OHOS 文件选择器导入已构建的 `.mgplugin` / `.mgplugin.js`，并提供插件状态、诊断、启停、升级、卸载和导出能力。

## 3. 缺口总览

| 优先级 | 缺口 | 当前状态 | 目标状态 |
| --- | --- | --- | --- |
| P0 | arm64 Node Runtime 与真实数据源链路 | 有 OHOS 宿主代码；x86_64 为明确 stub；真实数据源发布级验收未完成 | arm64 真机 Runtime 稳定，至少 5 个代表性来源完成完整链路 |
| P0 | ArkWeb Cookie / JS / 交互验证 | ArkWeb 宿主和 Flutter 边界已存在，真实来源闭环仍需验收 | 每个来源隔离 Cookie/Profile，支持导航、JS、HTML、交互、取消和崩溃恢复 |
| P0 | 后台音频会话 | AVPlayer / AVSession 已有实现；锁屏、蓝牙、焦点和后台生命周期未完成真机验收 | 与 Android 后台音频用户体验等价 |
| P1 | 视频窗口和生命周期 | AVPlayer、Texture、首帧、窗口亮度和全屏已有代码；旋转、后台恢复和长时间播放证据不足 | 首帧、缓冲、旋转、全屏、常亮、亮度、返回和销毁全部稳定 |
| P1 | 局域网同步和网络事件 | Network Kit 事件桥及跨设备测试入口已有；真实互通仍需验收 | Android ↔ OHOS、Windows ↔ OHOS、OHOS ↔ OHOS 均完成双向同步 |
| P1 | 扫码业务闭环 | ScanKit 拉起、相机和取消已验证；有效配对、同步、应用传输载荷仍需验证 | 四类二维码均能正确回传并进入对应业务流程 |
| P1 | 插件移动端管理 | 文件选择器和导入路径已有；完整状态、诊断和升级流程需补齐 | 移动端通过开发包完成安装、启停、升级、卸载、诊断和导出 |
| P1 | 应用更新安装闭环 | 当前明确返回 `app_update_market_fallback_required` | 完成用户确认式 HAP 安装；若平台限制，只实现并验收应用市场兜底 |
| P2 | 全局系统亮度 | 仅支持应用窗口亮度 | UI 明确展示“应用窗口亮度”；不把全局亮度作为鸿蒙完全对齐门槛 |
| P2 | 本地阅读完整真机回归 | 模拟器冷启动、空书架和基础持久化已验证 | 真机完成缓存、进度恢复、长章节、图片和升级迁移回归 |

## 4. 分阶段实施计划

### 阶段 0：冻结验收基线

目标：把“代码存在”“测试存在”“真实设备通过”分开记录。

工作项：

1. 为每项能力记录 `available`、`reason`、API 版本、ABI、设备型号和验收日期。
2. 统一区分：未实现、架构不支持、用户取消、权限拒绝、系统失败和网络失败。
3. 为 arm64 真机、x86_64 模拟器、Android 真机和 Windows PC 建立相同的验收清单。
4. 每次真机测试保存测试名称、设备信息、HAP 版本、结果和失败阶段；禁止只记录“启动成功”。

交付物：

- 更新 `docs/feature-matrix.md`，每一行增加真实验证状态。
- 输出一份 arm64 验收记录，覆盖本计划的 P0/P1 项。
- 所有能力探测均能解释不可用原因。

完成门槛：没有可复现的验收入口时，不得把能力标记为“已完成”。

### 阶段 1：arm64 Runtime 与 ArkWeb 数据源链路

目标：先恢复鸿蒙最核心的在线内容能力。

工作项：

1. 固化 Node 24.16.0 OHOS arm64 构建、`libnode.so`、头文件和构建参数。
2. 在 CI 或受控构建机上验证 `MGREAD_NODE_ROOT`、ABI、Node 版本和 HAP 打包结果。
3. 保留 x86_64 stub，但在 UI 和诊断中明确显示“仅本地阅读，不属于发布目标”。
4. 完成 Runtime 启动、重启、调用取消、插件安装、启停、传输和诊断链路。
5. 完成 ArkWeb 的页面打开、显示、隐藏、关闭、导航、JS、HTML、点击、输入、按键、等待文本、获取 URL 和超时清理。
6. 每个插件使用独立 Cookie/Profile；WebView 崩溃或 Ability 重建后能够重新建立会话。
7. 使用至少 5 个代表性真实来源完成发现、搜索、详情、目录、正文和资源链路，其中至少 2 个需要 Cookie/JS，至少 1 个需要 `interaction_required`。

验收入口：

- `integration_test/ohos_runtime_smoke_test.dart`
- `integration_test/ohos_browser_session_smoke_test.dart`
- `integration_test/ohos_stage2_runtime_arkweb_test.dart`
- 真实数据源的 arm64 真机验收记录

完成门槛：arm64 真机 Runtime ping、插件安装和真实来源全链路通过；Runtime 失败不能拖垮首页、书架和本地阅读。

### 阶段 2：后台音频与视频窗口能力

目标：让媒体能力达到 Android 的主要用户体验，并证明生命周期安全。

工作项：

1. 为 OHOS AVSession 补齐标题、作者、封面、时长、进度、播放状态和播放速率同步。
2. 验证锁屏播放/暂停/跳转、上一首/下一首、蓝牙按键和有线耳机事件。
3. 接入音频焦点和音频中断；来电、闹钟或其他音频抢占后按策略暂停或恢复。
4. 验证应用切后台、回前台、Ability 重建、系统回收和手动暂停时的状态一致性。
5. 完成视频 Texture 与 AVPlayer Surface 的绑定、首帧、缓冲、结束、错误和释放事件。
6. 完成视频全屏、横竖屏、返回键、常亮、应用窗口亮度和后台恢复验证。
7. 为媒体会话增加重复打开、快速切换、网络中断和长时间播放测试。

验收入口：

- `integration_test/ohos_media_smoke_test.dart`
- `integration_test/ohos_video_smoke_test.dart`
- Android 对照测试：`integration_test/android_audio_background_playback_test.dart`
- arm64 真机锁屏、蓝牙、来电/闹钟和横竖屏记录

完成门槛：音频无法在锁屏状态接受系统控制，或视频无法稳定首帧/释放时，阶段不通过。

### 阶段 3：网络事件、扫码和局域网同步

目标：完成鸿蒙与 Android/Windows PC 的真实互通。

工作项：

1. 使用 Network Kit 监听默认网络、Wi-Fi、热点、网线转接和网络断开/恢复。
2. 网络不可用时停止广播和同步，网络恢复后按既有策略自动恢复。
3. 验证配对二维码、设备发现、配对密钥保存、删除和重新配对。
4. 验证书架、阅读进度、插件包三类双向同步。
5. 分别完成 Android ↔ OHOS、Windows ↔ OHOS、OHOS ↔ OHOS。
6. 使用真实二维码完成配对、同步和应用传输，不以固定 fixture 载荷代替业务闭环。
7. 检查无 Wi-Fi、切换网络、弱网、断网、重复连接和对端异常时的阶段错误提示。

验收入口：

- `integration_test/ohos_paired_sync_host_test.dart`
- `integration_test/ohos_paired_sync_cross_device_test.dart`
- `integration_test/lan_sync_page_test.dart`
- `integration_test/ohos_app_transfer_host_test.dart`
- `integration_test/ohos_app_transfer_client_test.dart`
- `integration_test/ohos_runtime_smoke_test.dart`

完成门槛：三组真实设备组合都能完成至少一次双向书架、进度和插件同步；网络切换不能造成永久 loading 或错误成功。

### 阶段 4：应用更新和移动端插件管理

目标：补齐目前鸿蒙端最明确的功能缺口。

工作项：

1. 明确普通 HAP 是否允许通过系统确认流程安装；不要假设签名级 Bundle Installer 权限可用。
2. 如果可行，实现 HAP 下载、大小校验、SHA-256、包名、版本号、签名检查、用户确认安装和失败清理。
3. 如果不可行，实现“检测新版本 → 校验包 → 跳转应用市场”的完整用户流程，并在能力矩阵中明确标注与 Android 自更新的差异。
4. OHOS 插件管理统一使用文件选择器导入 `.mgplugin` / `.mgplugin.js`。
5. 增加插件版本、状态、大小、Runtime 诊断、启停、升级、卸载和导出入口。
6. 插件导入失败时区分文件类型错误、版本冲突、校验失败、Runtime 失败和用户取消。

验收入口：

- `integration_test/ohos_app_transfer_host_test.dart`
- `integration_test/ohos_app_transfer_client_test.dart`
- 插件管理页面测试和 arm64 真机手工验收

完成门槛：应用更新必须有用户可执行的最终动作；若只能跳市场，不能继续宣称“鸿蒙自更新与 Android 等价”。

### 阶段 5：本地阅读真机回归与发布门禁

目标：证明平台降级不会破坏已接入的本地能力。

工作项：

1. 首次启动、冷启动、后台恢复和 HAP 升级迁移。
2. 书架导入导出、分享、历史、小说进度、漫画进度和图片缓存。
3. 长章节、大图片、缓存不足、文件不存在、权限拒绝和用户取消。
4. 无 Runtime、无 WebView、无网络、无媒体能力时，首页和本地阅读仍可用。
5. 对所有 P0/P1 能力生成最终验收记录，并更新能力快照和功能矩阵。

## 5. 发布门禁

以下任一项未通过，鸿蒙端只能标记为“部分适配”：

- arm64 真机无法启动并响应 Node Runtime ping。
- 至少一个真实数据源无法完成搜索、详情、目录、正文和资源链路。
- Cookie/JS 或交互型来源无法完成真实闭环。
- 音频无法在锁屏状态接受系统媒体控制，或中断恢复状态错误。
- 视频首帧、Texture、全屏、旋转或释放存在已知阻断问题。
- 三组局域网组合中任一组无法完成双向同步。
- 扫码只能打开相机，不能把真实载荷路由到对应业务。
- HAP 只能下载校验，既没有用户确认安装，也没有可用的应用市场兜底。
- OHOS 原生桥只有 Dart 单测或模拟器记录，没有 arm64 真机证据。
- x86_64 模拟器被误报为支持在线 Runtime。

## 6. 推荐执行顺序

```text
阶段 0 验收基线
        ↓
阶段 1 arm64 Runtime + ArkWeb + 真实数据源
        ↓
阶段 2 后台音频 + 视频窗口生命周期
        ↓
阶段 3 网络事件 + 扫码 + 三组局域网互通
        ↓
阶段 4 HAP 更新 + 移动端插件管理
        ↓
阶段 5 本地阅读真机回归 + 发布门禁
```

阶段 1 是最高优先级，因为在线数据源、插件管理和部分局域网能力都依赖 Runtime 可用；阶段 2 和阶段 3 可以并行开发，但最终验收必须在同一套 arm64 真机上完成。

## 7. 本地执行同步记录（2026-09-19）

以下内容已按本计划落地到代码，并同步到 [`docs/feature-matrix.md`](docs/feature-matrix.md) 与 [`docs/ohos-build.md`](docs/ohos-build.md)。

| 阶段 | 已完成的本地适配 | 当前证据 | 状态 |
| --- | --- | --- | --- |
| 阶段 1 | arm64 Node 24.16.0 宿主、Runtime ping、ArkWeb 页面操作、请求 deadline/cancel 清理 | `ohos_runtime_smoke_test.dart`、`ohos_browser_session_smoke_test.dart`、`ohos_stage2_runtime_arkweb_test.dart` | arm64 真机通过；5 个 fixture 通过，真实来源仍待验收 |
| 阶段 2 | AVPlayer 音频/视频桥、Texture、后台 Ability 生命周期、中断暂停/恢复 | `ohos_media_smoke_test.dart`、`ohos_video_smoke_test.dart` | 音频控制和视频首帧/窗口恢复 arm64 真机通过；锁屏/蓝牙/焦点证据待补 |
| 阶段 3 | Network Kit 地址探测、网络可用性事件边界、现有二维码载荷校验路由 | `platform_lan_sync_network_environment_test.dart`、`ohos_runtime_smoke_test.dart` | 代码与本机网络探测通过；三组跨设备和有效二维码待验收 |
| 阶段 4 | HAP 下载后大小/SHA-256 校验、包名校验、应用市场 fallback；插件文件选择和错误映射保持可用 | `platform_app_update_service_test.dart`、插件管理页面 | 代码测试通过；应用市场真机跳转待验收 |
| 阶段 5 | 首次启动、首页、空书架和 OHOS EL2 持久化路径保持可用 | `library_first_run_test.dart` | arm64 真机首次启动通过；缓存、进度、迁移和异常场景待回归 |

本次同步提交为 `005e0156`（`完成鸿蒙平台能力适配与真机验收`）。未通过真实来源、另一台设备、真实二维码或应用市场确认的项目继续保留为“待验收”，不改写为已完成。
