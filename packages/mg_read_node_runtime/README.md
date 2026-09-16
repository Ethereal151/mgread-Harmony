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
| `tools/build-ohos-node.sh` | 在 Linux x64 上构建并校验 Node 24.16.0 OHOS arm64 shared runtime |

Flutter 使用方从同级 [`mgread_plugin_runtime`](../mgread_plugin_runtime/README.md) 接入。数据源项目格式和
artifact 以根核心规范、公开类型和测试为准。

OHOS Runtime 构建必须使用 Node 源码的 `v24.16.0`、Linux x64 host tools 和 OHOS LLVM 交叉工具链：

```sh
OHOS_SDK_ROOT=/path/to/ohos-sdk \
OHOS_LLVM_ROOT=/path/to/ohos-llvm \
npm run build:ohos-node
```

脚本只接受 `v24.16.0`，校验 Node 官方源码包 SHA-256，并拒绝没有生成 `libnode.so` 的
executable-only 产物。产物还必须通过 OHOS native host、HAP 和 arm64 真机验证后才能启用
`supportsPluginRuntimeNode`。

开发和 AI 规则只在 [AGENTS.md](AGENTS.md) 维护。
