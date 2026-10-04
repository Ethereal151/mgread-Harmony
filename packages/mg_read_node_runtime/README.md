# mg_read_node_runtime

MgRead 的 Node.js 插件 Runtime Core。它拥有固定 Node.js 执行环境、插件安装与调用和内部传输；同级
Flutter package `mgread_plugin_runtime` 拥有公开 Facade、Supervisor 与平台宿主。

## 组成

| 路径 | 用途 |
| --- | --- |
| `src/` | Node.js Runtime Core |
| `protocol/` | 内部协议 fixture |
| `probes/` | 平台与依赖探针 |
| `docs/runtime-version-matrix.md` | 当前固定版本、平台支持和待验证项 |
| `tools/build-ohos-node.sh` | 在 Linux x64 上构建并校验 Node 26.10.0 OHOS arm64/x64 shared runtime |

Flutter 使用方从同级 [`mgread_plugin_runtime`](../mgread_plugin_runtime/README.md) 接入。数据源项目格式和
artifact 以根核心规范、公开类型和测试为准。

OHOS Runtime 构建必须使用 Node 源码的 `v26.10.0`、Linux x64 host tools 和 OHOS LLVM 交叉工具链：

```sh
# Build the x64 runtime (the third argument selects the target ABI).
OHOS_SDK_ROOT=/path/to/ohos-sdk \
OHOS_LLVM_ROOT=/path/to/ohos-llvm \
npm run build:ohos-node -- v26.10.0 /path/to/work-root x64

# Stage the ABI candidate; publish it only after the matching Runtime checks pass.
npm run stage:ohos-node -- x64 /path/to/work-root/node-v26.10.0-openharmony-x64
```

脚本只接受 `v26.10.0`，校验 Node 官方源码包 SHA-256，并拒绝没有生成 `libnode.so` 的
executable-only 产物。arm64 与 x64 使用独立的 Node source/build output，避免连续构建时复用另一 ABI 的
GYP 配置。stage 命令校验 Node 头文件版本、共享库 ELF ABI/SONAME 和可用的构建 metadata 后，替换对应
架构的 `node-runtime/<abi>` 输入；HAP 会随 Node host 打包其 ELF `DT_NEEDED` 对应的 SONAME 文件。
两种 ABI 都必须通过 OHOS native host、HAP 和对应设备或模拟器验证后才能作为支持目标发布。

开发和 AI 规则只在 [AGENTS.md](AGENTS.md) 维护。
