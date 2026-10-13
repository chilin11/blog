export const GITHUB_USER = 'chilin11';
export const GITHUB_URL = `https://github.com/${GITHUB_USER}`;

export const projectCategories = [
  { id: 'all', label: '全部项目' },
  { id: 'tools', label: 'AI 与工具' },
  { id: 'apps', label: '日常应用' },
  { id: 'web', label: 'Web 实验' },
] as const;

export interface Project {
  /** GitHub 仓库名，也是文章 frontmatter 里的 repo 字段 */
  repo: string;
  name?: string;
  /** 私有项目允许展示简介，但不生成 GitHub 源码入口 */
  private?: boolean;
  summary: string;
  category: 'tools' | 'apps' | 'web';
  featured?: boolean;
  featuredSummary?: string;
  language: string;
  stack: string[];
  /** 对应 CSS 里的项目强调色变体：'' | 'photo' | 'pill' | 'outfit' */
  variant: '' | 'photo' | 'pill' | 'outfit';
  /** 24×24 线性 SVG 图标内部路径 */
  icon: string;
  note?: string;
  extra?: { label: string; value: string; href?: string }[];
}

export const projects: Project[] = [
  {
    repo: 'cpa-mini-usage',
    summary: '轻量的 CPA 原生用量面板。查看 Claude / Codex 配额、请求记录和 API 等价费用估算，不需要额外的 Web 服务。',
    category: 'tools',
    featured: true,
    featuredSummary: '让配额与用量一目了然',
    language: 'Go',
    stack: ['CPA v8 插件', '原生用量面板'],
    variant: 'outfit',
    icon: '<path d="M4 4v16h16M8 16v-5M12 16V7M16 16v-8M20 16V4"/>',
  },
  {
    repo: 'remotecontrol',
    name: 'Remote Control',
    summary: '用浏览器查看和控制自己的电脑桌面。原生画面采集与视频串流，支持键鼠操作；通过可信局域网、HTTPS 或 VPN 访问。',
    category: 'tools',
    featured: true,
    featuredSummary: '把自己的桌面带到浏览器里',
    language: 'C# / Swift',
    stack: ['Node.js', 'WebSocket'],
    variant: 'photo',
    icon: '<rect x="3" y="4" width="18" height="13" rx="2"/><path d="M8 21h8M12 17v4M9 8l6 3-6 3V8Z"/>',
  },
  {
    repo: 'loom-vault',
    name: 'Loom Vault · 密语',
    summary: '离线优先的 Android 密码笔记。本地加密保存，支持加密备份、私有云端密文同步，以及设备端生物识别快捷解锁。',
    category: 'apps',
    language: 'Java',
    stack: ['Android', 'Node.js'],
    variant: 'pill',
    note: '个人实验 · 未经专业安全审计，请保留独立备份',
    icon: '<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V6a4 4 0 0 1 8 0v4M12 14v3"/>',
  },
  {
    repo: 'TaskWhisper',
    summary: '把「记得提醒我」变成具体计划。用自然语言创建健康提醒，AI 解析后在 Android 本地调度通知。',
    category: 'apps',
    language: 'Kotlin',
    stack: ['Jetpack Compose', 'Room'],
    variant: 'pill',
    note: 'MVP',
    icon: '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4M10 8l2 2 3-3"/>',
  },
  {
    repo: 'little-play-arcade',
    summary: '「玩一会儿」零后端、零构建的静态小游戏站。从五子棋到 2048，打开就能玩。',
    category: 'web',
    language: 'JavaScript',
    stack: ['HTML / CSS / JS', 'Docker + Caddy'],
    variant: '',
    icon: '<path d="M7 7h10c2 0 3 2 3.5 4l1 6c.4 2-2 3-3.3 1.5L15 15H9l-3.2 3.5C4.5 20 2.1 19 2.5 17l1-6C4 9 5 7 7 7Z"/><path d="M8 9v5M5.5 11.5h5M16 10h.01M18 13h.01"/>',
  },
  {
    repo: 'HivisionID-X',
    summary: '可自部署的 AI 证件照工作台。智能构图、抠图换底、打印排版，一站完成。',
    category: 'tools',
    language: 'Python',
    stack: ['FastAPI', 'Docker 多架构镜像'],
    variant: 'photo',
    note: 'Fork · HivisionIDPhotos',
    icon: '<rect x="3" y="4" width="18" height="16" rx="3"/><circle cx="12" cy="10" r="3"/><path d="M7 18c0-5 10-5 10 0M6 7h.01M18 7h.01"/>',
    extra: [
      { label: '上游项目', value: 'Zeyi-Lin/HivisionIDPhotos', href: 'https://github.com/Zeyi-Lin/HivisionIDPhotos' },
      { label: 'Docker', value: 'chilin11/hivisionid-x', href: 'https://hub.docker.com/r/chilin11/hivisionid-x' },
    ],
  },
  {
    repo: 'Pill-O-Clock',
    summary: '简单可靠的 Android 服药闹钟。精确提醒与桌面小组件，让按时吃药少一点操心。',
    category: 'apps',
    language: 'Kotlin',
    stack: ['Jetpack Compose', 'Material 3'],
    variant: 'pill',
    icon: '<path d="m8 4-4 4a5 5 0 0 0 7 7l4-4a5 5 0 0 0-7-7ZM6 6l7 7"/><circle cx="17" cy="17" r="5"/><path d="M17 14v3h2"/>',
  },
  {
    repo: 'outfit-iq',
    summary: '拍张照片，听听 AI 的穿搭建议。跨平台的穿搭评分 App，帮你找到今天的好状态。',
    category: 'apps',
    language: 'TypeScript',
    stack: ['Expo', 'React Native'],
    variant: 'outfit',
    icon: '<path d="m8 4-5 3 3 5 2-1v9h8v-9l2 1 3-5-5-3c0 4-8 4-8 0Z"/><path d="m18 2 .5 1.5L20 4l-1.5.5L18 6l-.5-1.5L16 4l1.5-.5Z"/>',
  },
];

export const repoUrl = (repo: string) => `${GITHUB_URL}/${repo}`;
export const findProject = (repo: string) => projects.find((p) => p.repo === repo);
export const formatDate = (d: Date) =>
  `${d.getUTCFullYear()}.${String(d.getUTCMonth() + 1).padStart(2, '0')}.${String(d.getUTCDate()).padStart(2, '0')}`;
export const isoDate = (d: Date) => d.toISOString().slice(0, 10);
