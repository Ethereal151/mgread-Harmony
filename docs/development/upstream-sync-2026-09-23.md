# 主线同步鸿蒙适配报告

## 范围

- 上游主线：`upstream/main`，同步目标 `d6977260163ac0862d1a44802665e3afba2b6ce1`。
- 上次同步基线：`84763b16dc77075d95a983df40cf31436f38cc29`。
- 主线新增：105 个提交；当前下游原有同步合并已包含这些提交，本次在 `sync/upstream-d6977260` 上逐项审计并补齐鸿蒙适配。
- 未改写 `origin/main`，保留工作区中原有未提交改动。

## 主线新增提交

```text
c50130f6 修复漫画阅读器菜单中间区域关闭交互
ec9a80de feat: 增加书架目录自动更新设置
d10cec58 修复漫画阅读器手机系统栏显示
55d2ba6e fix: 静默同步并刷新阅读器目录
0d2cb76e 修复书架启动时 Provider 生命周期错误
515d16a6 重构阅读器与播放器设置页面
e9f458dc 优化章节切换的即时加载反馈
f7b3c193 接入应用主题色系统
29ebda4d 启用OLED冷黑深色模式
ab339144 完善应用主题模式与强调色联动
dafacc30 完善非阅读器页面主题适配
7dc7d282 修复18MD视频目录分组序号
e11aa80b docs: redesign GitHub project homepage
522d0f08 视频右侧手势改为系统音量
b145c785 实现跨数据源批量搜索聚合
489fad0c feat(视频播放器): 增加安卓 Anime4K 动漫增强
b564bffb 修复漫画下一章节失败后的会话锁死
0b67e369 修复书架空数据首屏引导
ba59f744 ci: add debounced cross-platform build verification
eeeeb9d8 支持阅读器按键与音量键翻页
7c99ac9c 收窄小说阅读器中间点击区域
789aa91b ci: create placeholder runtime asset directories
42c19157 ci: speed up cached release verification
83e46cad ci: publish successful version builds to GitHub Releases
c6b4c442 迁移番茄小说原生数据源
c13335ee 修复番茄发现图标契约
a87c24c8 修复橘子TV发现返回校验
73ce7538 优化漫画阅读器目录体验
afda87a2 丰富橘子TV发现首页
9f655976 修复橘子TV HLS 首帧播放
55cb8629 修复发现页分类等分按钮布局
0e98d63a 优化漫画章节预缓存
67ce9ace 重设计四类内容默认封面
3ddaac12 修复详情页不可用操作状态
2a857cfe 修复 UAA 漫画章节访问与图片加载
5c0fcdec 完善书架预加载与缓存进度
3507dfb5 fix: 修复全部搜索和独立搜索取消操作
e3f28791 修复小说阅读器深色配色区分度
12fcc79d feat: 增加番茄官方书架入口
e6d6c52f 修复阅读器主题隔离
6b9f7c78 feat: 接入番茄登录态书架读取
1a72d1a4 feat: 增加独立日夜主题配色
0a53612a 1
d3f0ce18 Merge branch 'main' of https://github.com/lingy-Mg/mg_read
38bd7eec feat: 增加搜索结果多种排序
82e2798c 听中国播放链接缓存失效重连
eda2cd28 漫画图片失败后自动重试
e2b48c2b fix: 调整搜索结果头部与热门搜索折叠
32b4f92d fix: 按搜索范围设置默认排序
ef271994 修复主题背景并改造悬浮底部导航
9a143494 修复首页背景边界残影
5c2ca80f 升级首页修复版本号
1edc204c 将意见反馈改为 GitHub 外部反馈
2b530680 漫画图片重试增加抖动与视口调度
41ff8f1c 修复阅读器加载状态栏色块
f2b103b8 优化漫画阅读手势翻页
50347793 修复音频播放器封面交接
8941e610 增加阅读器书籍刷新入口
85cdb718 调整阅读器来源条布局
5b2e8afd feat(reader): 增加无间距排版选项
8a44f0bc 重构阅读器字号调节控件
8709308a 完善漫画翻页设置
a7a4a81e 增加阅读器排版调试模式
c15f5b25 fix(reader): 对齐底部排版调试区域
73bdf51f 修复书架点击打开书籍详情
7b9390b3 扩展小说阅读器颜色主题
19b16191 修复底部导航内容遮挡与页面兼容
b2703497 优化底部导航宽度与玻璃效果
74909692 首页书架支持封面内显示信息
8af1b224 更新应用版本
5a16398a 修复阅读器设置悬停边界
a4a3d81e 修复书架默认阅读入口与详情菜单
5df2fe88 修复阅读器日夜主题切换记忆
42324280 超多更新
8901eb8d 优化漫画翻页动画
4423ff22 修复漫画章节标题浅色样式
9ea2efb3 修复阅读器沉浸式顶部安全区
e59f0e34 修复小说阅读器主题独立性
a9b4467a 调整音频播放器播放按钮位置
8221db41 消除首页模糊背景底部滤镜边缘
878095b4 修复音频播放器顶部按钮圆形布局
2b00fc3e 修复书架打开正在播放音频时重复解析
8372f371 增加音频资源地址解码与复制
3d55ecb8 超多更新
5b8e57bf Revert "消除首页模糊背景底部滤镜边缘"
51084551 Revert "修复首页背景边界残影"
3c6804c7 重构小说书籍详情并修复封面
40127b56 修复音乐封面全链路
432a3f76 完善数据源全链路检查技能
3915de92 明确新任务禁止创建工作树
eff1e2e5 修复音视频目录分组映射
e04a1103 超多数据源插件修复
807b45b2 完善数据源修复与验证技能
1140c4b4 完善数据源选择器顶部布局
260b1911 修复66漫画图片来源
84901faa 修复桌面视频后台播放生命周期
11227942 修复写真集文章分页解析
fa358376 视频播放器增加视频详情调试面板
f906f6aa 优化听中国目录并发加载
829412d0 重构数据源选择器界面
aef97eb2 将写真集分页拆分为独立章节
79b87326 显示音频章节来源地址
710e0c18 增加听中国章节持久缓存
a9725cdb 补充视频数据源真实播放验证
d6977260 修复音频详情同时显示来源与播放地址
```

## 鸿蒙适配内容

- 阅读器按键/音量键翻页：使用 HarmonyOS API 16 `inputConsumer.on('keyPressed')` 原生消费音量上下键；关闭时 `off` 恢复系统音量调节，Dart capability、OHOS bridge 和测试同步。
- 视频资源链路：新增公开 HLS/普通视频资源类型，OHOS AVPlayer 按显式资源类型选择 `url` 或带请求头的媒体源，不依赖 Runtime 代理 URL 后缀。
- ArkWeb：`evaluate` 支持异步和多语句返回值；Runtime 资源文件写入使用截断模式；Node host 为浏览器请求分配可取消 ID，把 AbortSignal、OHOS jobId 和 ArkWeb `stop()` 串起来。
- 音视频：保留现有 AVPlayer、AVSession、后台播放、中断恢复、缓冲位置和窗口/方向行为；没有把 Android 专属 Anime4K 或桌面专属代码复制到 OHOS。
- 共享 Flutter/API：同步视频模型、来源视频映射、OHOS backend 及现有平台 capability；保留 OHOS 对播放器代理、增强和全局系统音量的稳定降级。
- 数据源/Runtime：公共 Source API 未新增私有宿主字段；Node Runtime、资源代理、HLS 重写和现有数据源测试保持通过。

## 未适配内容及边界

- Android Anime4K 动漫增强不迁移到 OHOS：主线明确为 Android 专属，OHOS 没有对应公开能力，继续保持 capability 不支持。
- “全局系统音量写入”不伪造为已支持：华为官方音量文档明确第三方应用不能直接调整全局系统音量；`AVVolumePanel` 是系统音量面板组件，不能等价替换当前播放器公开的百分比读写契约。因此 OHOS 保持 `systemVolume=false`，不显示会失败的系统音量手势；播放器自身 AVPlayer 音量和实体音量键仍可用。
- 未执行本轮签名/人工真机专项：当前工作区的无签名 arm64 HAP 构建已通过；签名配置属于本机敏感配置，未修改、未提交。需要再次连接设备并签名安装时，应由人工设备环境继续验收。

## 测试结果

- `flutter analyze --no-pub`：通过，仅保留已有 integration test 的 3 条 `avoid_print` 信息。
- 受影响 Flutter 测试：平台 capability、阅读器设置、视频 resilience/product tests 通过。
- Node Runtime：固定 Node 24.16.0 `typecheck` 通过；串行全套 133/133 通过。
- Source testkit：23/23 通过。
- OHOS：`flutter build hap --debug --target-platform ohos-arm64 --no-pub --no-codesign` 通过；未触碰签名文件、`build/`、`oh_modules/` 或临时调试目录。
- Windows 并行 Node 全套曾因文件监视器时序出现 1 个 flaky 失败；同一测试文件和串行全套均通过，未作为功能失败隐藏。

## 提交与发布

- 工作分支：`sync/upstream-d6977260`。
- 原有工作区改动未覆盖，也未加入本次提交。
- 完成最终检查后提交中文 commit，推送到 `origin` 同名 sync 分支并创建 PR；不自动合并。
