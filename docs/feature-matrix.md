# 功能基线矩阵

这是 MgRead 的 OHOS 功能基线矩阵。标记为“最低交付”的能力已通过代码测试或 API 26 x64 模拟器回归；需要 arm64 真机、真实数据源或真实相机的能力仍单独标注限制。

| 功能域 | 源代码基线 | 现有验证线索 | OHOS 状态 | 后续阶段 |
| --- | --- | --- | --- | --- |
| 应用启动、首页、路由 | 已存在 | `test/app/`、`integration_test/library_first_run_test.dart` | arm64 真机首次启动通过（2026-09-19），完整冷启动/升级迁移待回归 | 5 |
| 主题、设置、个人资料 | 已存在 | `test/app/`、`test/features/profile/` | 已接入能力降级，待真机验证 | 2/3 |
| 书架、阅读历史 | 已存在 | `lib/features/library/`、对应 widget tests | 已接入 OHOS 沙箱路径，待真机验证 | 2 |
| 本地持久化、数据库、缓存 | 已存在 | `lib/core/persistence/`、`test/core/persistence/` | 已加入 EL2 沙箱路径和 HAP 内置 OHOS SQLite；arm64 真机首次启动与空书架加载通过，缓存/迁移待回归 | 2/5 |
| 小说阅读器 | 已存在 | `lib/features/reader/data/content_library_source_text_reader.dart` | 本地链路可用，待真机验证 | 2 |
| 漫画阅读器、图片缓存 | 已存在 | `lib/features/reader/data/content_library_source_comic_reader.dart`、cache tests | 本地链路可用，待真机验证 | 2 |
| 在线数据源 / Node Runtime | Android/Windows 宿主和资源声明 | `packages/mgread_plugin_runtime/`、`integration_test/ohos_runtime_smoke_test.dart` | Node 24.16.0 arm64 真机 ping 通过；ArkWeb smoke 与 5 个本地验收 fixture 全链路通过；至少 5 个真实来源和 Cookie/Profile 隔离仍待验收 | 1 |
| 音频播放 | Flutter UI 和现有平台实现 | `packages/mg_read_audio_player/`、`packages/mgread_ohos_media/`、`integration_test/ohos_media_smoke_test.dart` | arm64 真机 AVPlayer 音频控制通过；锁屏、蓝牙、焦点和中断实机证据待补 | 2 |
| 视频播放 | Flutter UI 和现有平台实现 | `packages/mg_read_video_player/`、`packages/mgread_ohos_media/`、`integration_test/ohos_video_smoke_test.dart` | arm64 真机 Texture/首帧/窗口恢复通过；长时间播放、旋转和后台恢复证据待补 | 2 |
| 扫码 | Android、Darwin、Web 实现 | `packages/mgread_ohos_scanner/`、`lib/features/lan_sync/presentation/lan_sync_qr_scanner_page.dart` | 已接入 HMS ScanKit 默认系统 UI；arm64 真机已验证拉起、后置相机预览和取消回传，有效载荷路由待继续验证 | 6/7 |
| 局域网同步 | 已存在 | `lib/features/lan_sync/`、现有同步测试、`integration_test/ohos_paired_sync_*` | Network Kit 地址探测和协议单测通过；Android/Windows/OHOS 三组真实双向同步待设备组合 | 3 |
| 文件选择、分享、链接、亮度、常亮 | 依赖三方 Flutter plugins | `lib/platform/`、根 `pubspec.yaml`、`packages/screen_brightness_ohos/` | 文件/分享/链接/常亮按能力降级；亮度为 OHOS 窗口级 adapter，系统全局亮度不宣称支持 | 3/7 |

## 阶段 0 结论

核心本地阅读业务已接入 OHOS 沙箱和 HAP 内置 SQLite；2026-09-19 在 arm64 真机完成 Runtime smoke、ArkWeb smoke、Stage 2 五 fixture、音频、视频和首次启动测试。真实来源、媒体系统控制、三组跨设备同步、有效二维码路由和完整本地回归仍保持未完成状态，不能仅凭这些自动化结果宣称完全对齐。
