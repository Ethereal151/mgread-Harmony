# OHOS 构建基线

本文记录 MgRead 鸿蒙适配阶段 1～6 的源代码、工具链和构建验证结果。当前已完成签名 HAP 构建、模拟器安装启动和原生 AVPlayer/窗口亮度 bridge 的编译接入；在线 Runtime、真实媒体会话和扫码真机闭环仍未宣称完成。

## 源代码基线

- 上游仓库：`https://github.com/lingy-Mg/mg_read.git`
- 目标仓库：`https://github.com/Ethereal151/mgread-Harmony.git`
- 上游基线 commit：`d61464b6dbbd268eed0681ede1a776a51e9832b3`
- 目标仓库 `main` 当前 commit：`d8c014d11007efe78982b8166dc4cd2aada2677f`
- 工作分支：`oh-3.44.9-dev3.12.2`
- 根应用版本：`0.9.199+317`

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
- OHOS 工程已由 Flutter OHOS 工具链生成，包含 `AppScope` 和 `entry` 模块；应用版本固定为 `0.9.199`、versionCode 为 `317`，应用名称为 `MgRead`。
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

最近一次 VM 验证使用 `127.0.0.1:5555` API 26 x86_64 模拟器：

- `flutter build hap --debug --target-platform ohos-x64 --no-pub` 成功生成签名 HAP；
- `hdc install -r` 安装成功，`aa start -a EntryAbility -b com.ohos.mgread` 启动成功，应用进程保持存活；
- `hdc snapshot_display` 截图显示首页正常渲染；启动日志未出现 `mgread_ohos_media` 或 `screen_brightness_ohos` 原生插件错误；
- Dart 能力测试和局域网扫码页测试通过。模拟器只证明安装、启动、Flutter 注册和页面渲染，不替代音视频实际播放、后台音频、相机扫码或 arm64 真机结论。

## 已知限制

上游 commit 使用 Git LFS 管理 Node Runtime。当前远端对 Darwin arm64 和 Windows x64 runtime 二进制返回缺失对象（404），因此拉取基线时使用了 `GIT_LFS_SKIP_SMUDGE=1`。本次阶段 4 已加入 OHOS Flutter MethodChannel/EventChannel 宿主边界和 typed 错误映射，但没有把未经验证的 Node 24.16.0 OHOS arm64 二进制伪装成可用能力；在线数据源在 OHOS 上继续显示 `unsupported`，不阻塞本地书架和阅读。

## 阶段 2～4 代码适配记录

- 阶段 2：主应用的 metadata/content/file 三类持久化继续由 `AppPersistence`/`ContentLibrary` 拥有；OHOS 使用 EL2 `files/persistence` 沙箱目录，HAP 内置由 OHOS clang 编译的 `libsqlite3.so`（`x86_64` 与 `arm64-v8a`），避免 Linux 动态库和后台 isolate 假设。启动、路由、书架、历史、小说/漫画进度恢复仍复用现有业务实现。
- 阶段 3：新增 `lib/platform/platform_capabilities.dart`，集中描述 OHOS 文件选择、分享、包信息、外部链接、亮度、常亮、窗口和 Runtime 宿主能力；导入导出、版本展示、视频亮度/常亮和窗口初始化均按能力降级。
- 阶段 4：`mgread_plugin_runtime` 增加 OHOS 插件声明、MethodChannel、进度 EventChannel 和单例 supervisor。Native bridge 当前对 Runtime invoke 返回稳定 `unsupported`，待 Node 24.16.0 OHOS arm64 PoC 后只需替换 package 内宿主实现，不改变 Dart Facade/wire protocol。
- 阶段 4/5：新增 `mgread_ohos_media` 包，以 OHOS `AVPlayer` 承载音频和视频；音频、视频 package 仅通过 backend adapter 使用它，视频通过 Flutter Texture 输出 Surface。阶段 3 的 `screen_brightness_ohos` 已改为 `@ohos.window` 应用窗口亮度控制；全局系统亮度仍返回明确错误。

本次代码变更后的签名 x64 debug/release HAP 均已构建：

- debug：`build/ohos/hap/entry-default-signed-debug.hap`，SHA-256 为 `DE9EF43119D9A0088AA615A0D9987C208BC9D187E2AFD48815CFD487FDBA6E31`；
- release：`build/ohos/hap/entry-default-signed-release.hap`，SHA-256 为 `2A55076E1B7EF8C62A2C6CD08291999AEFFA03AD062927FA4A32CCEF4C53C31E`。

release HAP 已通过 `hdc install -r` 安装到 `127.0.0.1:5555`，`aa dump -a` 显示 `EntryAbility` 和 `com.ohos.mgread` 进程为 `FOREGROUND/READY`；布局树和截图已进入正常书架空状态。`integration_test/library_first_run_test.dart` 在该模拟器通过。

Windows 测试环境原先将系统 SQLite 按 `sqlite3.dll` 查找，导致 Drift 无法加载；根 `pubspec.yaml` 已按 `package:sqlite3` 的平台配置补充 `name_windows: winsqlite3`，随后持久化测试和应用启动组合测试均通过。
