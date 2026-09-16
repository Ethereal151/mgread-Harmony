# 功能基线矩阵

这是 MgRead 的 OHOS 功能基线矩阵。标记为“最低交付”的能力已通过代码测试或 API 26 x64 模拟器回归；需要 arm64 真机、真实数据源或真实相机的能力仍单独标注限制。

| 功能域 | 源代码基线 | 现有验证线索 | OHOS 状态 | 后续阶段 |
| --- | --- | --- | --- | --- |
| 应用启动、首页、路由 | 已存在 | `test/app/` | 未验证 | 1/2 |
| 主题、设置、个人资料 | 已存在 | `test/app/`、`test/features/profile/` | 已接入能力降级，待真机验证 | 2/3 |
| 书架、阅读历史 | 已存在 | `lib/features/library/`、对应 widget tests | 已接入 OHOS 沙箱路径，待真机验证 | 2 |
| 本地持久化、数据库、缓存 | 已存在 | `lib/core/persistence/`、`test/core/persistence/` | 已加入 EL2 沙箱路径和 HAP 内置 OHOS SQLite；模拟器冷启动与空书架加载通过 | 2 |
| 小说阅读器 | 已存在 | `lib/features/reader/data/content_library_source_text_reader.dart` | 本地链路可用，待真机验证 | 2 |
| 漫画阅读器、图片缓存 | 已存在 | `lib/features/reader/data/content_library_source_comic_reader.dart`、cache tests | 本地链路可用，待真机验证 | 2 |
| 在线数据源 / Node Runtime | Android/Windows 宿主和资源声明 | `packages/mgread_plugin_runtime/` | OHOS bridge 已接入，Node 24.16.0 arm64 待 PoC | 4 |
| 音频播放 | Flutter UI 和现有平台实现 | `packages/mg_read_audio_player/`、`packages/mgread_ohos_media/` | 已接入 OHOS AVPlayer backend 和 EventChannel；HAP 已在 x64 模拟器安装启动，真实媒体/后台会话待真机 | 4/7 |
| 视频播放 | Flutter UI 和现有平台实现 | `packages/mg_read_video_player/`、`packages/mgread_ohos_media/` | 已接入 OHOS AVPlayer + Flutter Texture backend；HAP 已在 x64 模拟器安装启动，首帧/旋转/后台待真机 | 5/7 |
| 扫码 | Android、Darwin、Web 实现 | `packages/mobile_scanner/` | OHOS 页面明确提示并不启动相机 | 5 |
| 局域网同步 | 已存在 | `lib/features/lan_sync/`、现有同步测试 | 未验证 | 2/3 |
| 文件选择、分享、链接、亮度、常亮 | 依赖三方 Flutter plugins | `lib/platform/`、根 `pubspec.yaml`、`packages/screen_brightness_ohos/` | 文件/分享/链接/常亮仍按真实能力降级；亮度已接入 OHOS 窗口级 adapter，系统全局亮度不宣称支持 | 3/7 |

## 阶段 0 结论

核心本地阅读业务已接入 OHOS 沙箱和 HAP 内置 SQLite，并已在 API 26 x86_64 模拟器完成安装、冷启动、首次启动集成测试和空书架加载回归；缓存、进度及 arm64 真机仍需后续真实设备回归。音频/视频已完成原生 bridge 的代码和 HAP 编译接入，但真实媒体、后台会话和首帧仍待设备证据；在线数据源等待 Node 24.16.0 OHOS arm64 PoC，扫码等待可用 SDK 与真机相机验证。
