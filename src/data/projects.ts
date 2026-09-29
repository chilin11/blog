export const GITHUB_USER = 'chilin11';
export const GITHUB_URL = `https://github.com/${GITHUB_USER}`;

export interface Project {
  /** GitHub 仓库名，也是文章 frontmatter 里的 repo 字段 */
  repo: string;
  summary: string;
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
    repo: 'little-play-arcade',
    summary: '「玩一会儿」零后端、零构建的静态小游戏站。从五子棋到 2048，打开就能玩。',
    language: 'JavaScript',
    stack: ['HTML / CSS / JS', 'Docker + Caddy'],
    variant: '',
    icon: '<path d="M7 7h10c2 0 3 2 3.5 4l1 6c.4 2-2 3-3.3 1.5L15 15H9l-3.2 3.5C4.5 20 2.1 19 2.5 17l1-6C4 9 5 7 7 7Z"/><path d="M8 9v5M5.5 11.5h5M16 10h.01M18 13h.01"/>',
  },
  {
    repo: 'HivisionID-X',
    summary: '可自部署的 AI 证件照工作台。智能构图、抠图换底、打印排版，一站完成。',
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
    language: 'Kotlin',
    stack: ['Jetpack Compose', 'Material 3'],
    variant: 'pill',
    icon: '<path d="m8 4-4 4a5 5 0 0 0 7 7l4-4a5 5 0 0 0-7-7ZM6 6l7 7"/><circle cx="17" cy="17" r="5"/><path d="M17 14v3h2"/>',
  },
  {
    repo: 'outfit-iq',
    summary: '拍张照片，听听 AI 的穿搭建议。跨平台的穿搭评分 App，帮你找到今天的好状态。',
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
