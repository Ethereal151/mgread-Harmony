# OHOS 构建基线

本文记录 MgRead 鸿蒙适配阶段 0 的源代码、工具链和原平台基线。阶段 0 不生成 OHOS 工程，也不包含 HAP；OHOS 工程和 HAP 生成属于阶段 1。

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

`flutter doctor -v` 已识别 HarmonyOS toolchain，当前 Flutter 连接设备只有 Windows desktop 和 Edge，尚未连接 OHOS 真机或模拟器。

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
- OHOS debug 构建被阻塞，因为当前仓库还没有 `ohos/` entry module。

## 阶段 1 入口

下一阶段应使用固定 Flutter OHOS SDK 生成 `ohos/` 工程，按 API 26 配置 bundle/module/签名和 arm64，然后重新执行：

```powershell
flutter devices
flutter build hap --debug
flutter build hap --release
hdc install <hap-path>
```

HAP、签名文件和本机配置不应提交到 Git。

## 已知限制

上游 commit 使用 Git LFS 管理 Node Runtime。当前远端对 Darwin arm64 和 Windows x64 runtime 二进制返回缺失对象（404），因此拉取基线时使用了 `GIT_LFS_SKIP_SMUDGE=1`。OHOS Runtime 适配前需要单独确认 Node Runtime 资源的可获取性和 arm64 兼容性。
