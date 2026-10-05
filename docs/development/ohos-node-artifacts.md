# OHOS Node 源码交付迁移

本迁移只改变 Node/V8 源码和 public embedding header 的交付方式，不改变 Node/V8 版本、
`libnode.so`、Flutter/ArkTS 调用链或 JS 数据源协议。主构建链仍由
`ohos/hvigorfile.ts`、`ohos/entry/hvigorfile.ts` 和 Flutter 调用链拥有。

## 阶段 0 基线（2026-10-05，Asia/Shanghai）

- Node：26.10.0；固定 npm：11.19.1。
- 已存在的 arm64 `libnode.so`：148,558,896 bytes，SHA-256
  `7E278F3E1D35151B91C4A22836CE8314C25CD8CD016C9C43BEBA15D68FDBBC62`，ELF machine 183，SONAME `libnode.so`。
- 已存在的 x64 `libnode.so.147`：150,442,072 bytes，SHA-256
  `B9D34D7A8E24494B51AF1329A3D48101C0959D243A11F23608F7565B63E1A532`，ELF machine 62，SONAME `libnode.so.147`。
- 仓库当前跟踪的 Node/V8 native 文件：682 个，约 145,993 行；工作区完整
  `node-source` 目录为 750 个文件、约 10,079,410 bytes，源树 native 文件约 226,327 行。
- 工作区 `node-runtime` 共 465 个文件，约 303,198,346 bytes；其中重复的 Node public
  headers 是迁移目标。
- Runtime 基线：固定 Node 26.10.0 下 typecheck、构建及大部分协议/插件/资源/并发用例通过；
  `npm run verify` 最终为 147 项中 144 通过、3 失败。失败集中在既有开发插件热更新的
  `plugin_load_failed`/超时路径；开发插件 monitor 的独立复跑通过，未改变本迁移的 Node/V8、Artifact
  或 OHOS 构建边界，完整日志保留在 `.mgread-build/node-verify-fixed.log`。

## Artifact 契约

`packages/mg_read_node_runtime/tools/ohos-node-artifact.mjs` 生成并校验两个固定 Artifact。
每个 Artifact 至少包含：

```text
lib/<SONAME>
include/node/*
node-source/src/*
node-source/deps/v8/include/*
mgread-node-build.json
mgread-node-target.txt
mgread-node-soname.txt
manifest.json
```

`manifest.json` 保存 Node 版本、目标架构、SONAME、ELF machine、源树/头文件文件数、大小和
SHA-256、`libnode.so` 大小和 SHA-256、来源提交、构建工具链标识及生成时间。验证失败必须在
CMake/编译前停止。

## 构建切换

`tools/ohos-build-contract.ps1` 默认从 `.mgread-build/node-artifacts/` 查找两个 Artifact；也可以
用 `MGREAD_NODE_ARTIFACT_ROOT` 指向 Artifact 本身或缓存根。选择成功后，它设置：

```text
MGREAD_NODE_ROOT=<artifact-root>
MGREAD_NODE_SOURCE_ROOT=<artifact-root>/node-source
```

迁移期没有 Artifact 时仍允许旧仓库路径用于双路径比较；CI/发布和删除仓库 Node/V8 文件前必须
设置 `MGREAD_NODE_ARTIFACT_REQUIRED=true`。`.mgread-build/ohos/<variant>/variant.json` 会保留
实际输入模式和指纹，失败现场不覆盖。

## 删除旧输入前的门槛

必须先完成 arm64/x64 的 Artifact 校验、OHOS native host/HAP 双路径比较、Runtime 与 Flutter
回归，并在干净 Clone 通过外部 Artifact 构建。确认后才删除仓库中的 `node-source` tracked 文件和
`node-runtime` 重复 headers；`libnode.so` 是否迁移到外部由 Artifact 发布配置单独决定。
