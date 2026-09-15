# 功能基线矩阵

这是阶段 0 的源代码基线，不代表 OHOS 已验收。除非特别标注，OHOS 状态均为“未验证”。

| 功能域 | 源代码基线 | 现有验证线索 | OHOS 阶段 0状态 | 后续阶段 |
| --- | --- | --- | --- | --- |
| 应用启动、首页、路由 | 已存在 | `test/app/` | 未验证 | 1/2 |
| 主题、设置、个人资料 | 已存在 | `test/app/`、`test/features/profile/` | 未验证 | 2 |
| 书架、阅读历史 | 已存在 | `lib/features/library/`、对应 widget tests | 未验证 | 2 |
| 本地持久化、数据库、缓存 | 已存在 | `lib/core/persistence/`、`test/core/persistence/` | 未验证 | 2 |
| 小说阅读器 | 已存在 | `lib/features/reader/data/content_library_source_text_reader.dart` | 未验证 | 2 |
| 漫画阅读器、图片缓存 | 已存在 | `lib/features/reader/data/content_library_source_comic_reader.dart`、cache tests | 未验证 | 2 |
| 在线数据源 / Node Runtime | 仅 Android/Windows 宿主和资源声明 | `packages/mgread_plugin_runtime/` | 不支持 OHOS | 4 |
| 音频播放 | Flutter UI 和现有平台实现 | `packages/mg_read_audio_player/` | 未验证 | 5 |
| 视频播放 | Flutter UI 和现有平台实现 | `packages/mg_read_video_player/` | 未验证 | 5 |
| 扫码 | Android、Darwin、Web 实现 | `packages/mobile_scanner/` | 不支持 OHOS | 5 |
| 局域网同步 | 已存在 | `lib/features/lan_sync/`、现有同步测试 | 未验证 | 2/3 |
| 文件选择、分享、链接、亮度、常亮 | 依赖三方 Flutter plugins | 根 `pubspec.yaml` | 未验证 | 3 |

## 阶段 0 结论

核心本地阅读业务在源代码中完整存在，但当前还没有 OHOS 工程入口，因此不能把“源码存在”视为“鸿蒙可运行”。阶段 1 的最小闭环应优先验证 Flutter Engine 启动、应用沙箱路径和本地数据库，再逐项恢复在线数据源及平台能力。
