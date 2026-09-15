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

### 3.4 每个阶段的强制验证门禁

阶段 1 至阶段 6 均必须执行同一套闭环，不允许只完成代码编译而跳过设备验证：

1. 完成本阶段约定的代码或工程改动。
2. 使用固定版本工具链构建对应的 debug HAP；能够构建 release HAP 时一并构建。
3. 在 OHOS 虚拟器或真实设备上安装并运行 HAP。优先使用 arm64 真机；没有真机时使用 API 26 兼容的虚拟器。
4. 按本阶段验证清单执行冒烟、功能、生命周期和异常场景测试。
5. 记录构建信息、设备信息、复现步骤、日志、影响范围和修复结果。
6. 修复发现的 bug 后重新构建、重新安装并回归本阶段用例。
7. 只有本阶段验证清单全部通过，或已明确记录为“暂不支持且有降级处理”，才能进入下一阶段。

每个阶段至少保留以下证据：

- 构建命令和成功结果；
- HAP 版本、文件 hash 和构建时间；
- 虚拟器/真机型号、系统版本、API 和架构；
- 测试结果和失败项；
- bug 修复提交或暂不支持说明；
- 修复后的回归结果。

建议在 docs/ohos-validation.md 中按阶段维护验证记录，避免只在最终阶段集中发现问题。

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

阶段 0 构建、设备验证和修复门禁：

- 验证固定 Flutter SDK、Dart SDK、DevEco Studio、API 26、ohpm、hvigor 和 hdc 能够协同工作；
- 完成源仓库原平台的依赖解析和基础构建，确保后续问题不是源代码基线问题；
- 使用 DevEco Studio 或 hdc 验证目标设备连接、安装权限和日志采集；
- 若工具链、设备连接或基础构建失败，先修复环境/基线问题并重复验证；
- 记录源 commit、工具链版本和验证结果后，才开始阶段 1。

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

阶段 1 构建、设备验证和修复门禁：

- 构建 debug HAP；签名配置可用时同时构建 release HAP；
- 在 API 26 虚拟器或 arm64 真机安装并启动；
- 验证首次启动、二次启动、后台切换、返回桌面、重新进入和退出；
- 收集 Flutter、ArkTS/Native、hvigor 和设备日志；
- 修复安装失败、白屏、闪退、签名、权限、生命周期和布局问题后重新构建并回归；
- 只有最小 HAP 在设备上稳定运行，才能进入阶段 2。

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

阶段 2 构建、设备验证和修复门禁：

- 每完成一组核心业务改动，先构建 debug HAP 并安装到虚拟器或真机；
- 验证首页、路由、主题、书架、本地数据库、小说阅读器和漫画阅读器；
- 重点验证冷启动、热启动、前后台切换、返回键、窗口变化、长文本、大图片和数据持久化；
- 对数据库损坏、空数据、重复启动和异常退出进行验证；
- 修复页面白屏、布局错位、数据丢失、崩溃和卡死问题后重新构建并完整回归核心流程；
- 阶段结束时形成一份可在设备上重复执行的核心功能冒烟清单。

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

阶段 3 构建、设备验证和修复门禁：

- 每完成一个平台能力，构建 debug HAP 并在虚拟器或真机安装验证；
- 逐项验证文件选择、沙箱路径、应用信息、系统分享、URL 打开、亮度、保持唤醒、网络代理和 FFI；
- 对权限拒绝、取消操作、重复调用、无网络、路径不可写和系统能力不可用进行验证；
- 修复 MethodChannel/ArkTS 通信、权限、路径、返回值和异常处理问题后重新构建并回归；
- 不支持的能力必须验证“不会崩溃、页面有提示、其他功能仍可用”。

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

阶段 4 构建、设备验证和修复门禁：

- 每完成一个 Runtime 子能力，构建 debug HAP 并安装到 API 26 虚拟器或 arm64 真机；
- 验证 Runtime ready、invoke、取消、超时、插件安装、文件读写、网络请求、异常返回和 dispose；
- 验证前后台切换、重复打开、异常退出、低内存和网络中断后的恢复；
- 使用设备日志定位 Runtime、线程、ABI、权限和生命周期问题；
- 修复后重新构建、重新安装并执行完整 Runtime 回归，不以桌面端或 Android 通过结果代替 OHOS 证据；
- Runtime 不可用时，验证本地阅读降级路径和用户提示后，才可将该阶段标记为完成。

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

阶段 5 构建、设备验证和修复门禁：

- 每完成音频、视频或扫码中的一个能力，构建 HAP 并在虚拟器或真机进行实际操作验证；
- 音频验证播放、暂停、拖动、切换、异常 URL 和页面退出；
- 视频验证播放、暂停、进度、全屏/返回、横竖屏和资源失败；
- 扫码验证相机权限允许、拒绝、重复扫描、取消和无结果场景；
- 收集播放器、相机、Flutter Engine 和 OHOS 系统日志；
- 修复黑屏、无声、卡顿、资源释放、权限和生命周期问题后重新构建并回归；
- 暂不支持的能力必须有稳定降级，不得影响本地阅读和 HAP 启动。

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

阶段 6 构建、设备验证和修复门禁：

- 至少完成一次 debug HAP 和一次 release HAP 的完整构建；
- 至少在一台 API 26 虚拟器或一台 arm64 真机完成安装和核心功能回归；
- 从全新安装、覆盖安装、卸载重装三个状态分别验证；
- 对本阶段发现的所有 bug 完成修复、重新构建和回归；
- 只有构建产物、设备验证记录和已知限制清单齐全，才能上传目标仓库。

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

| 范围 | 预计工作量 |
| --- | ---: |
| OHOS 工程、签名和 HAP 闭环 | 1～2 个工作日 |
| 核心本地阅读功能 | 2～4 个工作日 |
| 平台插件兼容层 | 2～4 个工作日 |
| Runtime 初步适配 | 3～7 个工作日 |
| 音视频和扫码 | 2～5 个工作日 |
| 测试、文档和上传 | 1～2 个工作日 |

最低可交付版本预计约 5～10 个工作日；如果要求完整在线数据源和音视频功能，Runtime 和平台插件的实际兼容情况可能将周期延长至 8～15 个工作日以上。

## 8. 参考资料

- [MgRead 源仓库](https://github.com/lingy-Mg/mg_read)
- [MgRead 根 pubspec.yaml](https://raw.githubusercontent.com/lingy-Mg/mg_read/main/pubspec.yaml)
- [mgread_plugin_runtime pubspec.yaml](https://raw.githubusercontent.com/lingy-Mg/mg_read/main/packages/mgread_plugin_runtime/pubspec.yaml)
- [Runtime version matrix](https://raw.githubusercontent.com/lingy-Mg/mg_read/main/packages/mg_read_node_runtime/docs/runtime-version-matrix.md)
- [Harmony 目标仓库](https://github.com/Ethereal151/mgread-Harmony)
- [OpenHarmony Flutter 工具链说明](https://gitee.com/openharmony-sig/flutter_flutter/blob/06beef3c427a2e039530c1018c8ee7791028eb00/README.en.md)
