# 造物记 · Design handoff

静态设计参考，直接打开 `index.html` / `post.html`。纯 HTML + CSS、内联 SVG，无 JS、远程字体或 CDN。方向：偏绿的炭黑底、荧光青柠点睛、工程感小字、大量留白；不要增加粒子背景、复杂动效或仪表盘式装饰。

## Tokens

- Dark：`--bg #101211`，`--surface #171a18`，`--surface-raised #1d211e`；`--text #eff3ed`，`--muted #9da79e`，`--line #2c332d`。
- 主色：`--accent #c5f277`，按钮文字 `--accent-ink #19230c`。大面积保持中性，主色用于 CTA、重点词与小标记。
- 字体：`--font-sans` 使用系统 UI / PingFang SC / Noto Sans SC / Microsoft YaHei；`--font-mono` 使用 ui-monospace / SFMono-Regular / Menlo / Consolas。中文正文保持 sans，项目名称、日期、技术标签使用 mono。
- 间距：`--space-1…9` = 4 / 8 / 12 / 16 / 24 / 32 / 48 / 72 / 104px。细部有光学校正，不必强制全部整数倍。
- 圆角：`--radius-sm/md/lg` = 8 / 16 / 24px；当前按钮与代码 8px，卡片 16px。
- Light：跟随 `prefers-color-scheme: light`，底色 #f7f8f4、文字 #20291f、强调色 #4b7018。设计以深色为主，检查时请模拟 dark。

## Components → Astro 拆分建议

| Class | Component / 用途 |
| --- | --- |
| `.container`, `.site-header`, `.brand`, `.site-nav`, `.site-footer` | BaseLayout / Header / Footer |
| `.hero`, `.eyebrow`, `.hero-art`, `.hero-actions` | 首页 Hero；网格和光晕仅作静态装饰 |
| `.section`, `.section-heading`, `.section-title` | 内容区标题，编号低对比 |
| `.project-grid`, `.project-card`, `.project-icon`, `.project-meta` | ProjectCard；SVG 为手绘线性图标 |
| `.article-list`, `.article-row` | PostList；日期、标题、简介与方向箭头 |
| `.about-strip` | 简短关于区 |
| `.post-shell`, `.post-header`, `.post-meta`, `.tag` | PostLayout 的标题与元数据 |
| `.project-info`, `.project-info-top` | 文章关联项目卡，保留 `dl` 语义 |
| `.prose`, `.code-panel`, `.code-header` | Markdown 阅读样式与代码块 |
| `.post-cta`, `.button`, `.text-link` | 文末 GitHub CTA 与通用链接 |

## Layout / responsive

- 首页宽度上限 1120px，桌面左右至少 32px；文章正文上限 760px。不要把长文拉到首页宽度。
- 桌面 Hero 为文本 + 320px 装饰；项目 2 列，间距 16px。卡片内容自然等高，元数据靠底。
- ≤760px：左右 20px、项目单列、隐藏 Hero 装饰、导航自然换行（无需汉堡菜单）；文章日期单独一行；CTA 与页脚堆叠。
- Hero 字号 36–56px，文章标题 29–42px；正文桌面 16px / 1.95、手机 15px / 1.95。
- 保留可见键盘焦点、真实链接、语义标题、`lang="zh-CN"`、viewport 与 reduced-motion 支持。代码块独立横向滚动，不能撑宽页面。

## Project accents

由 `.project-card` 的局部 `--project` 控制图标、语言点和 hover 边框；不要依赖颜色传达项目身份。

| Project | Variant | Dark accent | 含义 |
| --- | --- | --- | --- |
| little-play-arcade | 默认 | #c5f277 | 轻松、好玩 |
| HivisionID-X | `.photo` | #b6a4ef | 图像与 AI |
| Pill-O-Clock | `.pill` | #efbb7e | 温暖、日常提醒 |
| outfit-iq | `.outfit` | #86cdd9 | 清爽、个人风格 |

## Content / implementation notes

- 四个项目资料来自任务说明，链接指向对应 GitHub 仓库；保留 HivisionIDPhotos fork 归属。
- 所有文章标题、日期、正文、作者口吻均为设计示例，发布前请由作者确认；不能视为实际发布历史。首页仅第一篇跳转到示例正文，另两条标记为示例选题且不制造假链接。
- 代码为明确标注的最小 Caddy 配置示意，不是仓库真实部署说明。生产内容以 README 为准。
- Astro 可将项目整理为 typed data、文章整理为 content collection；沿用共享 CSS 和 DOM 层次。用 Shiki 替代手工代码着色，保持背景、边框和字号。
- 项目卡当前通过项目名称进入仓库，角落箭头为装饰。若实现整卡点击，请保留一个有名称的焦点目标，不添加嵌套链接。
- 已请求内置浏览器打开首页预览；该工具不提供截图、视口控制或渲染检查结果，因此未宣称完成桌面/手机视觉验收。建议后续检查 1440 / 768 / 390 / 320px，分别模拟深浅配色。
