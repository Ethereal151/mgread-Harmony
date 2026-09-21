# OHOS 构建基线

本文记录 MgRead 鸿蒙适配阶段 1～6 的源代码、工具链和构建验证结果。当前已完成签名 HAP 构建、arm64 真机启动、Node Runtime/ArkWeb fixture、AVPlayer 音视频 smoke 和窗口亮度 bridge 验证；真实来源、系统媒体控制、跨设备互通和有效扫码业务仍未宣称完成。

## 源代码基线

- 上游仓库：`https://github.com/lingy-Mg/mg_read.git`
- 目标仓库：`https://github.com/Ethereal151/mgread-Harmony.git`
- 上游基线 commit：`d61464b6dbbd268eed0681ede1a776a51e9832b3`
- 目标仓库 `main` 当前 commit：`d8c014d11007efe78982b8166dc4cd2aada2677f`
- 工作分支：`oh-3.44.9-dev3.12.2`
- 根应用版本：`0.9.205+323`

工作区已配置以下 remote：

```text
upstream  https://github.com/lingy-Mg/mg_read.git
origin    https://github.com/Ethereal151/mgread-Harmony.git
```

## 工具链

固定版本和本机路径见仓库根目录 [`toolchain.lock`](../toolchain.lock)。当前检查结果：

- Flutter OHOS：`3.44.9+ohos-0.0.1-canary1`
- Dart：`3.12.2`
- Node.js：`24.16.0`
- DevEco Studio：`26.0.0.821`（计划固定版本 `26.0.0`，build `261.23567.138.36.2600821`）
- HarmonyOS SDK：API `26`
- ohpm：`26.0.0.630`
- hvigor：`6.26.4`
- hdc：`3.2.0f`

`flutter doctor -v` 已识别 HarmonyOS toolchain。当前已启动 DevEco Studio 的 Mate 70 Pro+ API 26 模拟器，Flutter 识别为 `127.0.0.1:5555`、`ohos-x64`、`Ohos OpenHarmony-7.0.0.105 (API 26)`。

## 已完成的基线检查

在上游 commit 上执行过：

```powershell
flutter pub get
flutter analyze
flutter test
flutter build windows --debug
flutter build hap --debug
```

结果：

- `flutter pub get` 成功。解析过程中产生了 6 个传递依赖的版本漂移；为遵循源仓库锁文件约束，`pubspec.lock` 已恢复为上游内容。
- `flutter analyze` 以 3 个 warning 结束，均为上游现有代码 warning，不是 OHOS 改动引入。
- `flutter test` 在 669 个通过、28 个失败时停止。已观察到 golden 像素差异、局域网同步超时/跨设备测试失败和一个书架组件 finder 失败；失败反馈为测试运行产物，未纳入提交。
- Windows debug 构建被本机 Windows Developer Mode 未开启阻塞，Flutter 提示缺少 symlink 支持。
- OHOS 工程已由 Flutter OHOS 工具链生成，包含 `AppScope` 和 `entry` 模块；应用版本为 `0.9.201`、versionCode 为 `319`，应用名称为 `MgRead`。
- `ohos/entry/src/main/module.json5` 保留网络权限，Flutter 入口使用标准 `FlutterAbility` 和 `FlutterPage`。
- 由于仓库位于 `D:` 而 pub 缓存位于 `C:`，OHOS Hvigor 对跨盘插件绝对路径校验失败。`ohos/hvigorconfig.ts` 在注入原生模块前，把跨盘 OHOS 插件复制到根目录下的忽略目录 `.flutter_ohos_plugins/`，再提供盘内相对路径。
- 当前 Windows 未开启 Developer Mode，`flutter pub get` 会提示缺少 symlink 支持；已使用 `--no-pub` 完成原生构建验证。日常构建前建议在 Windows 设置中开启 Developer Mode。
- 在当前 DevEco 安装布局下，构建命令需要把 `DEVECO_SDK_HOME`、`HOS_SDK_HOME` 和 `OHOS_SDK_HOME` 指向 `D:\DevEco Studio\sdk`（不是 `...\sdk\default`）。
- DevEco 26 在 Windows 下通过 `hvigorw.js` 同步工程时，内置 `ohpm.bat` 会触发批处理递归。`ohos/tools/ohpm-safe.cmd` 直接启动同一 DevEco 进程对应的 ohpm Node 入口；`hvigorconfig.ts` 仅对本工程配置该包装器。

## 阶段 1/6 构建与签名

未签名的 x64 调试 HAP 已成功生成：`build/ohos/hap/entry-default-unsigned.hap`。可用以下命令验证 arm64 编译：

```powershell
$env:DEVECO_SDK_HOME = 'D:\DevEco Studio\sdk'
$env:HOS_SDK_HOME = 'D:\DevEco Studio\sdk'
$env:OHOS_SDK_HOME = 'D:\DevEco Studio\sdk'
flutter devices
flutter build hap --debug --target-platform ohos-arm64 --no-pub --no-codesign
```

要生成可安装调试 HAP，请在 DevEco Studio 以 `D:\Desktop\mgread\ohos` 作为工程根目录打开（不要打开仓库根目录 `D:\Desktop\mgread`）。如果 Project Structure 中包名为空或 Compatible SDK 显示异常，请关闭当前工程后重新导入该目录，并让 DevEco 重新同步工程模型；包名应从 `ohos/AppScope/app.json5` 读取为 `com.ohos.mgread`。然后进入 `File -> Project Structure -> Signing Configs`，勾选 `Automatically generate signature`，保存后执行：

```powershell
flutter build hap --debug --target-platform ohos-arm64 --no-pub
hdc install build/ohos/hap/entry-default-signed.hap
```

随后在模拟器上验证启动、退出、切后台和恢复。HAP、签名文件和本机配置不应提交到 Git。

## 当前验证结果

### 2026-09-21 增量适配验证

- 根据 HarmonyOS API 的 `webview.ProxyController`，ArkWeb 已支持应用级 HTTP/HTTPS/SOCKS 代理覆盖，并在清空自定义代理时调用 `removeProxyOverride` 恢复系统路由；播放器代理仍明确关闭，因为 AVPlayer 没有可用的会话级代理契约。
- 根据 HarmonyOS Media API 的 `BufferingInfoType.CACHED_DURATION`，OHOS AVPlayer 现在向 Flutter 发出毫秒级 `buffered` 事件，视频后端将其作为时间缓冲位置使用；`videoEnhancement` 和 `systemVolume` 继续保持明确不支持，UI 不显示对应控制。
- `readerVolumeKeys` 现在不仅由 OHOS capabilities 隐藏，公开 `MethodChannelReaderPlatform` 调用也返回稳定 `UnsupportedError`；对应 package 测试已通过，避免绕过 UI 后静默成功。
- `openExternalUri` 支持注入 OHOS fake capabilities；直接测试覆盖原生打开成功、原生拒绝和 `PlatformException`，反馈、来源详情与插件帮助共用同一外链桥接边界。
- `_OhosRuntimeSupervisor` 通过测试专用构造入口直接覆盖 invoke started/completed、rejected、bridge_failed 诊断，并验证 `latestDiagnostics` 是有界不可变快照。
- `OhosBrowserSessionHost.cancel()` 已有 MethodChannel 直接测试，确认活动 job 会向 ArkWeb 宿主发送 `cancel`，不是只在 Dart 侧丢弃迟到结果。
- `ohos_video_smoke_test.dart` 现在直接等待并校验 OHOS AVPlayer 的 `buffered` 事件为非负毫秒值；模拟器实测通过，覆盖 `CACHED_DURATION -> bufferedPosition` 链路。
- 本地能力/代理/Profile/Runtime 宿主单测：通过；签名 arm64 HAP：通过；`hdc install -r`：通过。增量安装后真机回归因 HDC 设备 `192.168.3.48:45975` 暂时离线，状态为 `not-run`，不将其冒充为真机通过。
- 当前 `127.0.0.1:5555` OHOS x64 模拟器复验：`ohos_browser_session_smoke_test.dart`、`ohos_media_smoke_test.dart`、`ohos_video_smoke_test.dart`、`library_first_run_test.dart` 和 `ohos_x64_runtime_stub_test.dart` 全部通过；本轮最新复验的 ArkWeb 与视频 smoke 也重新构建、安装并通过，期间清理过一次残留 `hdc fport` 后重试。每组均重新构建、安装并启动签名 HAP。模拟器证据不替代缺失的本轮 arm64 真机增量回归。
- 来源层固定 Node 快速检查报告：`artifacts/source-tests/quick-all-20260921-deps.json`，56 个来源中 28 个通过、6 个部分通过、22 个因外部站点/交互/资源或 testkit 能力边界失败；这不是 OHOS 真机验收。Windows Release 实际检查暂未执行，`flutter build windows --release --no-pub` 被当前系统未启用符号链接支持阻止。
- 独立 HAP 启动复验：当前 `build/ohos/hap/entry-default-signed.hap` SHA-256 为 `3143645E5DA44425D6A382306CFF6710C82543737D6B159BB5925D30F88BEE0C`；本轮源码已在 `127.0.0.1:5555` 安装并完成 ArkWeb smoke 及反向跨设备同步 Client，`hdc install -r`、`aa force-stop`、`aa start` 均成功，`aa dump -a` 显示 `com.ohos.mgread` 的 `EntryAbility` 处于前台且 `READY`。
- 本轮当前源码的无签名 arm64 构建：`flutter build hap --debug --target-platform ohos-arm64 --no-pub --no-codesign` 成功；`build/ohos/hap/entry-default-unsigned.hap` SHA-256 为 `44DECC19BB910D7721372304CA0DE8DED463BCB46BEE8C43CC69CF61A84A1D54`，HAP 清单包含 `libs/arm64-v8a/libnode.so`、`libmgread_node_host.so`、`libflutter.so` 和 `libsqlite3.so`。无签名产物仅证明 ABI/资源打包，不能代替签名安装与真机回归。

当前计划验收总状态：`partial`。代码适配和明确不支持能力的直接证据已完成；最终 `pass` 仍需要 arm64 真机增量回归及真实来源、代理音视频、系统中断、跨设备同步等外部门禁。

跨设备同步补充尝试：曾启动 OHOS x64 Host 并准备使用在线 MI 8 Android peer。首次 Android 构建受 DevEco JBR 缺失 `jlink.exe` 和 Kotlin 增量缓存跨盘路径影响；切换到本机 Temurin 17 后 APK 已成功构建并安装，但 OHOS 虚拟器位于 `10.0.2.15` NAT，经本机 HDC 映射的 `192.168.3.26:36979` 对手机连接超时，未进入同步断言，状态仍为 `not-run`。
- 随后通过 `adb reverse` + HDC `fport/rport` 回环映射完成两组真实 peer 同步：`ohos_paired_sync_host_test.dart` + `android_paired_sync_to_ohos_test.dart` 通过，`android_paired_sync_host_test.dart` + `ohos_paired_sync_cross_device_test.dart` 通过；两组均验证双向书架与插件计数。该证据使用 OHOS x64 虚拟器，不替代 arm64 真机回归，也不替代第二台 OHOS 真机的 HAP 传输验收。

2026-09-19 使用 DevEco IP 设备 `192.168.3.48:45975`（`PLA-AL10`、HarmonyOS `7.0.0.105`、API 26、`arm64-v8a`）完成以下直接验收：

- `integration_test/ohos_runtime_smoke_test.dart`：Node 24.16.0 arm64 host、Runtime ping、Network Kit 地址和能力降级通过；
- `integration_test/ohos_browser_session_smoke_test.dart`：ArkWeb 页面打开、导航和 HTML 获取通过；
- `integration_test/ohos_stage2_runtime_arkweb_test.dart`：5 个本地 fixture 的安装、发现、搜索、详情、目录、正文、资源代理、Cookie/JS 和 `interaction_required` 恢复通过；这不是 5 个真实外部数据源的替代证据；
- `integration_test/ohos_media_smoke_test.dart`、`integration_test/ohos_video_smoke_test.dart`：音频控制、视频 Texture/首帧/窗口恢复通过；
- `integration_test/library_first_run_test.dart`：首次启动首页和空书架通过；
- HAP 使用 `flutter build hap --debug --target-platform ohos-arm64 --no-pub` 成功签名并通过 `hdc install -r` 安装启动。

以下门禁仍需保留为未完成：真实来源至少 5 个全链路、锁屏/蓝牙/焦点与中断恢复、三组跨设备双向同步、有效二维码载荷路由、HAP 市场跳转真机确认和本地阅读完整迁移回归。

最近一次 VM 验证使用 `127.0.0.1:5555` API 26 x86_64 模拟器：

- `flutter build hap --debug --target-platform ohos-x64 --no-pub` 成功生成签名 HAP；
- `hdc install -r` 安装成功，`aa start -a EntryAbility -b com.ohos.mgread` 启动成功，应用进程保持存活；
- `hdc snapshot_display` 截图显示首页正常渲染；启动日志未出现 `mgread_ohos_media` 或 `screen_brightness_ohos` 原生插件错误；
- Dart 能力测试和局域网扫码页测试通过。模拟器只证明安装、启动和页面渲染；本机已在 `PLA-AL10`（HarmonyOS `7.0.0.105`、API 26、`arm64-v8a`）上验证 HAP 安装、启动、ScanKit 系统扫码 UI 拉起、扫码页取消回传和 ScanKit 进程退出。

## 已知限制

上游 commit 使用 Git LFS 管理 Node Runtime。当前远端对 Darwin arm64 和 Windows x64 runtime 二进制返回缺失对象（404），因此拉取基线时使用了 `GIT_LFS_SKIP_SMUDGE=1`。OHOS arm64 Node 24.16.0 宿主已在当前受控设备完成 ping 和 fixture 链路验证；x86_64 仍保留明确 stub，真实外部数据源验收前不能把 OHOS 在线能力标为发布完成。

## 阶段 2～4 代码适配记录

- 阶段 2：主应用的 metadata/content/file 三类持久化继续由 `AppPersistence`/`ContentLibrary` 拥有；OHOS 使用 EL2 `files/persistence` 沙箱目录，HAP 内置由 OHOS clang 编译的 `libsqlite3.so`（`x86_64` 与 `arm64-v8a`），避免 Linux 动态库和后台 isolate 假设。启动、路由、书架、历史、小说/漫画进度恢复仍复用现有业务实现。
- 阶段 3：新增 `lib/platform/platform_capabilities.dart`，集中描述 OHOS 文件选择、分享、包信息、外部链接、亮度、常亮、窗口和 Runtime 宿主能力；导入导出、版本展示、视频亮度/常亮和窗口初始化均按能力降级。
- 阶段 4：`mgread_plugin_runtime` 增加 OHOS 插件声明、MethodChannel、进度 EventChannel 和单例 supervisor；x86_64 返回稳定 `runtime_architecture_unavailable`，arm64 已接入 Node 24.16.0 native host，Dart Facade/wire protocol 不变。
- 阶段 4/5：新增 `mgread_ohos_media` 包，以 OHOS `AVPlayer` 承载音频和视频；音频、视频 package 仅通过 backend adapter 使用它，视频通过 Flutter Texture 输出 Surface。阶段 3 的 `screen_brightness_ohos` 已改为 `@ohos.window` 应用窗口亮度控制；全局系统亮度仍返回明确错误。
- 阶段 6：新增 `mgread_ohos_scanner` 包，使用 HMS ScanKit 默认系统 UI；Dart 页面只负责调用、取消/错误反馈和现有四类载荷校验路由，原生层不复制同步业务。真机已确认系统扫码 UI、后置相机预览和取消返回；有效载荷路由仍需准备配对二维码后继续做业务闭环。

本次代码变更后的签名 x64 debug/release HAP 均已构建：

- debug：`build/ohos/hap/entry-default-signed-debug.hap`，SHA-256 为 `DE9EF43119D9A0088AA615A0D9987C208BC9D187E2AFD48815CFD487FDBA6E31`；
- release：`build/ohos/hap/entry-default-signed-release.hap`，SHA-256 为 `2A55076E1B7EF8C62A2C6CD08291999AEFFA03AD062927FA4A32CCEF4C53C31E`。

release HAP 已通过 `hdc install -r` 安装到 `127.0.0.1:5555`，`aa dump -a` 显示 `EntryAbility` 和 `com.ohos.mgread` 进程为 `FOREGROUND/READY`；布局树和截图已进入正常书架空状态。`integration_test/library_first_run_test.dart` 在该模拟器通过。

Windows 测试环境原先将系统 SQLite 按 `sqlite3.dll` 查找，导致 Drift 无法加载；根 `pubspec.yaml` 已按 `package:sqlite3` 的平台配置补充 `name_windows: winsqlite3`，随后持久化测试和应用启动组合测试均通过。
