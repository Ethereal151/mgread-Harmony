# MgRead 鸿蒙适配计划

## 1. 适配目标

将源仓库 [lingy-Mg/mg_read](https://github.com/lingy-Mg/mg_read) 适配到 HarmonyOS，并上传至 [Ethereal151/mgread-Harmony](https://github.com/Ethereal151/mgread-Harmony)。

本阶段鸿蒙端不上架应用市场，验收终点是：

- DevEco Studio 可以打开 OHOS 工程；
- 本地可以生成 debug/release HAP；
- HAP 可以通过 DevEco Studio 或 hdc 安装；
- 应用能够启动并运行已适配的核心功能；
- 代码上传到目标仓库分支 oh-3.44.9-dev3.12.2。

AppGallery 上架、正式渠道签名、隐私合规材料和发布流水线后置，不作为本阶段阻塞条件。

## 当前执行状态

状态依据：用户确认已按原计划完成阶段 1。

| 阶段 | 状态 | 说明 |
| --- | --- | --- |
| 阶段 0：源代码和工具链基线 | 已完成前置工作 | 阶段 1 已能够执行，基线信息如未归档需补录 |
| 阶段 1：OHOS 工程和最小 HAP | 已完成 | 已完成工程创建、HAP 构建、安装和启动验证；具体设备、HAP 路径和日志待补录 |
| 阶段 2：核心 Flutter 业务 | 当前阶段 | 以阶段 1 的可启动 HAP 作为回归基线，开始适配本地书架和阅读功能 |
| 阶段 3：平台能力兼容层 | 待开始 | 阶段 2 验收通过后进入 |
| 阶段 4：mgread_plugin_runtime | 待开始 | 阶段 3 验收通过后进入 |
| 阶段 5：音频、视频和扫码 | 待开始 | 按阶段 4 的 Runtime 结果决定详细实现范围 |
| 阶段 6：集成验证和 HAP 交付 | 待开始 | 完成阶段 2～5 后执行最终回归 |

从现在开始不重复执行阶段 1；只有后续改动导致 HAP 启动、安装或生命周期回归失败时，才重新触发阶段 1 的相关验证。

## 2. 固定版本和原仓库约束

### 2.1 工具链

| 项目 | 固定值 |
| --- | --- |
| Flutter OHOS SDK | 3.44.9+ohos-0.0.1-canary1 |
| Flutter 分支 | oh-3.44.9-dev3.12.2 |
| Dart SDK | 3.12.2 |
| DevEco Studio | 26.0.0 |
| HarmonyOS SDK | API 26 |
| 首要架构 | arm64 真机 |
| 交付形式 | 本地 debug/release HAP |

### 2.2 原仓库版本要求

以源仓库当前版本要求为准，不在鸿蒙适配过程中随意升级 Flutter、Dart 或 package：

- 根应用版本保持 0.9.199+317；
- 根 pubspec.yaml 的 Dart SDK 约束保持 ^3.12.2；
- mg_read_audio_player 和 mg_read_video_player 的 Flutter 约束保持 >=3.44.0；
- 依赖版本以源仓库 pubspec.yaml 和 pubspec.lock 为准；
- 不为了适配 OHOS 直接升级全量依赖；
- 依赖不支持 OHOS 时，只进行最小范围替换或增加平台实现；
- 应用版本修改必须遵循原仓库版本维护方式，不手工改动版本号。

源仓库由主应用、Node.js 数据源 Runtime、Flutter Runtime facade、小说/漫画阅读器、音频播放器、视频播放器和数据源插件组成。原仓库首发平台为 Android、Windows 和 macOS，OHOS 需要增加独立平台实现。

## 3. 关键风险

### 3.1 Runtime 是最大风险

mgread_plugin_runtime 当前只声明 Android 和 Windows 平台，运行时资源主要覆盖 Android、Windows 和 macOS。Android 实现依赖 Kotlin、MethodChannel、Activity 生命周期和 Javet，不能直接作为 OHOS 实现使用。

源仓库的 Node Runtime 固定使用 Node 24.16.0，Android 采用 Javet，桌面端采用内置 Node 进程。OHOS 是否能够在 API 26、arm64 上稳定运行同版本 Node Runtime，必须通过真实设备 PoC 验证。

### 3.2 三方插件需要逐项验证

当前依赖中存在多个平台相关 package，包括 file_selector、path_provider、share_plus、url_launcher、screen_brightness、wakelock_plus、audio_service、media_kit、mobile_scanner、window_manager 和 ffi。它们是否支持当前 Flutter OHOS canary 分支，需要逐个构建验证。

### 3.3 本地 HAP 仍需要签名

不上架不等于不需要签名。本地安装仍需要 bundleName、模块配置、debug 或本地 release 签名，以及设备可接受的签名信息。优先使用 DevEco Studio 自动签名；不处理应用市场正式分发证书。

## 4. 实施阶段

### 阶段 0：建立源代码和工具链基线

1. 拉取 mg_read 并记录源仓库 commit hash。
2. 配置 Git remote：

   upstream = https://github.com/lingy-Mg/mg_read.git
   
   origin = https://github.com/Ethereal151/mgread-Harmony.git

3. 创建或切换分支 oh-3.44.9-dev3.12.2。
4. 确认 Flutter SDK、分支、Dart SDK、DevEco Studio、API 26、ohpm、hvigor 和 hdc。
5. 使用原仓库版本完成依赖解析和原平台基础构建。
6. 保存工具链、源 commit 和功能基线。

建议产出：

    docs/ohos-build.md
    docs/feature-matrix.md
    toolchain.lock

### 阶段 1：创建 OHOS 工程并生成最小 HAP

1. 使用固定 Flutter OHOS SDK 生成 ohos 工程。
2. 按 API 26 模板配置 bundleName、moduleName、版本信息、SDK、arm64 和签名。
3. 配置必要的网络、文件和媒体权限。
4. 在 DevEco Studio 中打开 ohos 目录并同步依赖。
5. 生成 debug HAP 并安装到设备。
6. 验证 Flutter Engine 初始化、启动、退出和后台恢复。

验收命令：

    flutter doctor
    flutter devices
    flutter build hap --debug
    hdc install <debug-hap-path>

阶段验收标准：

- DevEco Studio 能打开 ohos 工程；
- Flutter 能识别 OHOS 设备或模拟器；
- debug HAP 构建成功；
- HAP 可以安装；
- 应用能启动并显示 Flutter 页面。

阶段 1 完成记录：

- 状态：已完成；
- 完成依据：用户确认已按本计划完成阶段 1；
- 回归基线：阶段 1 验证通过的可启动 HAP；
- 待补录：Flutter/Dart 实际版本、源 commit、HAP 路径和 hash、虚拟器或真机型号、系统/API/架构、构建日志、安装日志和已修复 bug；
- 后续要求：阶段 2 的每次功能改动都必须使用该基线进行启动回归。

### 阶段 2：适配核心 Flutter 业务

优先恢复不依赖复杂原生能力的功能：

- 首页和路由；
- 主题和设置；
- 书架；
- 阅读历史；
- 本地数据库；
- 小说阅读器；
- 漫画阅读器；
- 图片和章节缓存；
- 返回键；
- 前后台生命周期；
- 阅读进度保存和恢复。

核心流程：

    启动应用
    → 打开书架
    → 导入或创建本地内容
    → 打开小说/漫画
    → 阅读并退出
    → 再次启动
    → 阅读进度和业务数据仍然存在

数据库和文件功能必须使用 OHOS 应用沙箱目录，不能依赖 Android、Windows 或 macOS 的路径假设。

阶段 2 当前执行方式：

1. 先使用阶段 1 HAP 完成一次基线回归，确认当前版本仍能安装和启动。
2. 按“本地数据库和路径 → 书架 → 阅读历史 → 小说阅读 → 漫画阅读 → 缓存和进度”的顺序分批适配。
3. 每完成一批改动，立即构建 debug HAP，并在 OHOS 虚拟器或真机安装验证。
4. 发现启动、白屏、布局、数据库、路径、返回键、生命周期或数据持久化问题时，先修复再进入下一批。
5. 每批修复后重新安装 HAP，回归已经通过的阶段 1 启动流程和阶段 2 核心流程。

### 阶段 3：建立平台能力兼容层

建议增加统一平台抽象，避免业务页面散落平台判断：

    lib/platform/platform_capabilities.dart
    lib/platform/ohos/
    lib/platform/stub/

| 能力 | 当前依赖 | OHOS 处理方向 |
| --- | --- | --- |
| 文件选择 | file_selector | 优先验证现有实现；不支持时接入 OHOS 文件选择器 |
| 应用目录 | path_provider | 改为 OHOS 沙箱路径 |
| 应用信息 | package_info_plus | 接入 bundle 信息查询或增加 OHOS 实现 |
| 系统分享 | share_plus | 接入 OHOS 系统分享能力 |
| 打开链接 | url_launcher | 接入系统 URI/浏览器能力 |
| 屏幕亮度 | screen_brightness | 接入 OHOS 屏幕亮度接口 |
| 保持唤醒 | wakelock_plus | 接入 OHOS 屏幕常亮能力 |
| 窗口管理 | window_manager | 移动端禁用或提供空实现 |
| FFI | ffi | 验证 sqlite 和其他 native ABI |
| 网络代理 | socks5_proxy | 验证 socket、TLS、代理和生命周期 |

第一版暂时无法支持的能力，可以使用条件编译、空实现或用户提示，但不能导致应用启动失败。

### 阶段 4：适配 mgread_plugin_runtime

目标是保留现有 Dart Facade 和 wire protocol，新增 OHOS 平台宿主。

建议增加：

    packages/mgread_plugin_runtime/ohos/
    packages/mgread_plugin_runtime/lib/src/ohos_supervisor.dart
    packages/mgread_plugin_runtime/lib/src/ohos_runtime_host.dart
    packages/mgread_plugin_runtime/lib/src/ohos_platform_io.dart

保持现有调用模型：

- invoke；
- cancelInvocation；
- dispose；
- 插件导入；
- 插件传输；
- 进度事件；
- typed Runtime 错误；
- protocol marker 1.0。

先实现最小 Runtime PoC，验证 Runtime 初始化、Node 版本、CommonJS/ESM、文件读写、HTTP/HTTPS/TLS、插件安装、invoke、取消、shutdown、前后台切换和低内存场景。

推荐架构：

    Flutter
      ↓ MethodChannel/EventChannel
    OHOS native/ArkTS host
      ↓
    Node Runtime 24.16.0 OHOS arm64 PoC
      ↓
    现有 wire protocol
      ↓
    数据源插件

如果 Node Runtime 在 API 26 上无法稳定运行，本阶段仍可以先交付本地阅读 HAP，在线数据源入口保留并提示暂不支持。若要求完整在线数据源功能，则必须继续完成 Node Runtime 的 OHOS 适配。

### 阶段 5：音频、视频和扫码

按以下顺序实施：

1. 音频前台播放；
2. 视频前台播放；
3. 音频后台播放和锁屏控制；
4. 扫码功能。

优先验证 media_kit、audio_service 和 mobile_scanner 在当前 Flutter OHOS SDK/API 26 下是否可以直接构建。

如果不能直接使用：

- 音频改用 OHOS AVPlayer；
- 视频改用 OHOS AVPlayer 加 Flutter Texture 或 PlatformView；
- 扫码改用 OHOS 相机/扫码能力；
- 暂时不支持的能力通过统一能力层降级，不阻塞 HAP 生成。

### 阶段 6：集成验证和 HAP 交付

静态验证：

    dart format <本次修改的 Dart 文件>
    flutter analyze
    flutter test
    flutter pub get

HAP 验证：

    flutter build hap --debug
    flutter build hap --release
    hdc install <debug-hap-path>
    hdc install <release-hap-path>

真机验证：

- 冷启动和热启动；
- 前后台切换；
- 返回键；
- 网络断开和恢复；
- 文件导入；
- 大章节和长文本；
- 图片缓存；
- 数据库读写；
- 阅读进度恢复；
- 音频/视频能力；
- 权限拒绝；
- 低内存后恢复；
- 卸载重装。

HAP 作为本地构建产物提供，不提交大体积临时产物和签名私钥到 GitHub。

## 5. Git 提交和上传计划

目标分支：

    oh-3.44.9-dev3.12.2

建议拆分提交：

    chore: import mg_read baseline
    chore: pin ohos flutter toolchain
    feat: add ohos application shell
    feat: adapt ohos storage and file access
    feat: add ohos platform capability layer
    feat: add ohos runtime host
    feat: adapt ohos audio and video
    test: add ohos smoke checks
    docs: add harmony build guide

上传前检查：

- 分支名称正确；
- 根应用版本未被修改；
- Dart、Flutter 和 package 版本符合原仓库要求；
- 未提交证书、私钥和本地配置；
- ohos 工程可以被 DevEco Studio 打开；
- debug/release HAP 均有构建记录；
- README 或构建文档包含本地打包命令。

## 6. 完成定义

### 最低可交付版本

- OHOS 工程存在；
- API 26 编译通过；
- 本地 debug/release HAP 生成成功；
- HAP 可以安装并启动；
- 首页、路由、主题、书架、本地数据库和阅读器可用；
- 暂不支持的在线数据源、音视频或扫码能力有明确降级提示；
- 代码已上传至 oh-3.44.9-dev3.12.2 分支。

### 完整适配版本

在最低可交付版本基础上，再增加 OHOS Node Runtime、在线数据源、插件安装、音频、视频、扫码和前后台生命周期稳定性。

## 7. 预计工作量

阶段 1 已完成，以下仅统计剩余工作量；后续若发生启动回归，只针对失败项重新执行阶段 1 的验证，不重复建设 OHOS 工程。

| 范围 | 预计工作量 |
| --- | ---: |
| 核心本地阅读功能 | 2～4 个工作日 |
| 平台插件兼容层 | 2～4 个工作日 |
| Runtime 初步适配 | 3～7 个工作日 |
| 音视频和扫码 | 2～5 个工作日 |
| 测试、文档和上传 | 1～2 个工作日 |

最低可交付版本剩余预计约 4～8 个工作日；如果要求完整在线数据源和音视频功能，Runtime 和平台插件的实际兼容情况可能将剩余周期延长至 7～13 个工作日以上。

## 8. 参考资料

- [MgRead 源仓库](https://github.com/lingy-Mg/mg_read)
- [MgRead 根 pubspec.yaml](https://raw.githubusercontent.com/lingy-Mg/mg_read/main/pubspec.yaml)
- [mgread_plugin_runtime pubspec.yaml](https://raw.githubusercontent.com/lingy-Mg/mg_read/main/packages/mgread_plugin_runtime/pubspec.yaml)
- [Runtime version matrix](https://raw.githubusercontent.com/lingy-Mg/mg_read/main/packages/mg_read_node_runtime/docs/runtime-version-matrix.md)
- [Harmony 目标仓库](https://github.com/Ethereal151/mgread-Harmony)
- [OpenHarmony Flutter 工具链说明](https://gitee.com/openharmony-sig/flutter_flutter/blob/06beef3c427a2e039530c1018c8ee7791028eb00/README.en.md)
