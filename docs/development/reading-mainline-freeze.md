# 阅读主链路冻结

小说、漫画、音频、视频的生产阅读主链路已冻结。冻结边界覆盖主应用入口、生成路由、会话编排、数据源适配和
三个独立阅读/播放 package 的生产源码与 package 清单；测试、文档和冻结检查本身不在冻结范围内。

| 内容 | 主链路边界 |
| --- | --- |
| 小说、漫画 | `lib/features/reader`、主应用 `app_router.dart`/`app_startup.dart`、`mg_read_reader_ui/lib` |
| 音频 | `lib/features/media`、主应用 `app_router.dart`/`app_startup.dart`、`mg_read_audio_player/lib` |
| 视频 | `lib/features/media`、主应用 `app_router.dart`/`app_startup.dart`、`mg_read_video_player/lib` |

冻结意味着：不得修改、格式化、重构、替换依赖、调整公开 API、改变路由接线或新增生产文件。每次 Flutter
检查都会执行 `tools/check_reading_mainline_freeze.ps1`，并在 CI 中单独校验同一份 SHA-256 基线。

如确需改变主链路，必须先得到用户明确的解冻授权；解冻变更应单独说明影响范围、重新验证四条链路，并在同一
变更中更新 `reading-mainline-freeze.json`，不得以修改基线来掩盖未经授权的源码变化。
