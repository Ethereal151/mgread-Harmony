# 失效来源修复

## 先定位首个断点

先运行目标来源的声明检查、离线测试、必要的 live smoke 和 Node 单源 CLI，沿
`discover -> search -> detail -> catalog -> content -> resource` 记录首个失败阶段。修改前先分类：

1. 环境/构建：退出码 `127`、缺少 `tsc`、npm CLI、依赖或 PATH。核对固定 Node/npm、lock 和本地依赖；
   不能通过改解析器掩盖。
2. 站点/传输：DNS/TLS、超时、重定向、挑战页、`403/429`、上游资源 `404`。记录最终地址、状态、响应大小
   和耗时；HTTP 200 中的升级哨兵、验证壳或错误 HTML 也属于访问/上游状态，不得解析成空发现或假作品。
   这类证据本身不证明选择器有错。
3. 解析/契约：成功响应中的入口、选择器、分页、稳定 ID、分组或返回形状不符。用当前网页与最小 fixture
   同时确认后修。
4. 资源代理：内容链路成功但封面、漫画页图或媒体失败。检查登记的上游 URL、kind、headers 和 Runtime
   数据面；不要把 loopback proxy URL 当作上游地址。
5. 宿主/安装：`source_webview_*_unsupported`、`interactionRequired`、`plugin_damaged`、`source_not_found`、
   `source_list_empty` 分别表示临时宿主能力、需要可见交互或实际 EXE 安装状态；不能据此修改来源解析器。

一次 live 失败后保留首次报告；完成有证据的修改后只允许一次有界单源复跑，或在未修改时用一次复跑判断波动。
站点确实很慢时可依据实测延迟设置有上限的超时，但不能放宽结构断言，也不能把延长等待当成修复。构建或打包
若因明确的瞬时文件锁失败，先确认占用者和已完成步骤，只重跑失败步骤；不要借此重跑整条 live 链路刷绿。

## 用当前事实修复

涉及路由、DOM、脚本渲染、选择器或分页时读取
[real-page-browser-probing.md](real-page-browser-probing.md)。浏览器不可达时，CLI 只能证明传输状态；保留已有
fixture 并将线上结构标为待复核，不猜入口或替换域名。

- live 搜索从当前发现结果派生有界查询，并用稳定 ID 找回同一条目后继续详情与目录；不要用固定 `test`、
  硬编码内容 ID、标题、条目数或章节数制造通过。
- 搜索和发现若共享列表页，复用同一解析器。continuation 只能来自响应中的真实下一页链接、API cursor 或明确的
  分页字段；“结果数达到 pageSize”本身不能证明还有下一页。搜索在截断到 pageSize 前应优先精确标题/稳定 ID，
  对超长标题、书名号、卷标或作者后缀只生成少量自然派生查询。
- 对代理或协议问题，分别探测默认路由、公开 `proxyMode: direct`、HTTP/HTTPS 和最终重定向；只有对照证据证明
  环境代理导致 TLS/连接失败时才改用 direct。跨到无关 origin、DNS 失效或持续 socket reset 时保留外部阻塞，
  不猜新域名。
- 图片候选只取页面真实字段，完成 URL 归一化、origin allowlist、去重、顺序和 Referer/Accept 登记。
- 对确认的访问限制使用当前公开错误契约；`403/429`、挑战页、资源 `404`、瞬时超时和解析失败分别报告。
  没有新证据时不得靠猜文件名、域名或 headers 把外部失败伪装成修复。
- 隐藏 WebView 仍要求显示验证页时返回 `interactionRequired`；浏览器能看到 DOM 只证明页面事实，不等于 Node
  临时宿主或真实 App 已通过交互。页面需要脚本时使用公开同会话 API，不读取或导出 Cookie/令牌。

## 固化与验证

fixture 固定本次确认的入口、请求参数、分页、解析规则、资源描述和错误分支；live smoke 证明当前站点仍能完成
同一公开链路。按 [content-validation-matrix.md](content-validation-matrix.md)验证受影响的内容与资源类型，
再按 [source-testing-workflow.md](source-testing-workflow.md)完成来源自身、Node CLI 和 Windows App CLI 分层验证。

站点特有修复留在该来源及其 fixture；只有多个来源都需要、且公开宿主契约确实缺失时才修改 testkit、Runtime 或
Source API。来源不得读取、拼接或重写媒体字节来规避 MIME/签名问题；需要通用变换时必须走已有公开资源描述边界，
并同时验证 Runtime 数据面。

若修复暴露 testkit 缺少公开宿主行为，只补齐最小通用模拟并运行 testkit 自测、受影响来源和全源模式；
不得给单个插件增加绕过契约的专用成功路径。
