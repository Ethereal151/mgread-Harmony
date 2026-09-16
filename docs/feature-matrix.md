# 功能基线矩阵

这是阶段 0 的源代码基线，不代表 OHOS 已验收。除非特别标注，OHOS 状态均为“未验证”。

| 功能域 | 源代码基线 | 现有验证线索 | OHOS 阶段 0状态 | 后续阶段 |
| --- | --- | --- | --- | --- |
| 应用启动、首页、路由 | 已存在 | `test/app/` | 未验证 | 1/2 |
| 主题、设置、个人资料 | 已存在 | `test/app/`、`test/features/profile/` | 已接入能力降级，待真机验证 | 2/3 |
| 书架、阅读历史 | 已存在 | `lib/features/library/`、对应 widget tests | 已接入 OHOS 沙箱路径，待真机验证 | 2 |
| 本地持久化、数据库、缓存 | 已存在 | `lib/core/persistence/`、`test/core/persistence/` | 已加入 EL2 沙箱路径和 HAP 内置 OHOS SQLite；模拟器冷启动与空书架加载通过 | 2 |
| 小说阅读器 | 已存在 | `lib/features/reader/data/content_library_source_text_reader.dart` | 本地链路可用，待真机验证 | 2 |
| 漫画阅读器、图片缓存 | 已存在 | `lib/features/reader/data/content_library_source_comic_reader.dart`、cache tests | 本地链路可用，待真机验证 | 2 |
| 在线数据源 / Node Runtime | Android/Windows 宿主和资源声明 | `packages/mgread_plugin_runtime/` | OHOS bridge 已接入，Node 24.16.0 arm64 待 PoC | 4 |
| 音频播放 | Flutter UI 和现有平台实现 | `packages/mg_read_audio_player/` | 未验证 | 5 |
| 视频播放 | Flutter UI 和现有平台实现 | `packages/mg_read_video_player/` | 未验证 | 5 |
| 扫码 | Android、Darwin、Web 实现 | `packages/mobile_scanner/` | 不支持 OHOS | 5 |
| 局域网同步 | 已存在 | `lib/features/lan_sync/`、现有同步测试 | 未验证 | 2/3 |
| 文件选择、分享、链接、亮度、常亮 | 依赖三方 Flutter plugins | `lib/platform/`、根 `pubspec.yaml` | 能力层已接入；亮度可用，其余缺失能力降级 | 3 |

## 阶段 0 结论

核心本地阅读业务已接入 OHOS 沙箱和 HAP 内置 SQLite，并已在 API 26 x86_64 模拟器完成安装、冷启动和空书架加载回归；缓存、进度及 arm64 真机仍需后续真实设备回归。在线数据源则等待 Node 24.16.0 OHOS arm64 PoC。
