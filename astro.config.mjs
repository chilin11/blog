// @ts-check
import { defineConfig } from 'astro/config';

export default defineConfig({
  // 站点地址用于 canonical 链接。deploy.sh 会根据域名自动设置 SITE_URL。
  site: process.env.SITE_URL || 'https://chilin11.github.io',
  markdown: {
    shikiConfig: {
      themes: { light: 'github-light', dark: 'vitesse-dark' },
      defaultColor: false,
    },
  },
});
