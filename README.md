# chilin11 · 造物记

个人博客，基于 [Astro](https://astro.build) 构建的纯静态站点。

## 本地开发

需要 Node.js ≥ 22.12。

```bash
npm install
npm run dev        # http://localhost:4321，修改后自动刷新
npm run build      # 输出到 dist/
npm run preview    # 预览构建结果
npm test           # 部署脚本回归测试（不操作真实 Docker / 服务器）
```

写新文章：在 `src/content/posts/` 新建一个 `.md` 文件，frontmatter 参考现有文章。

### 添加 / 更新项目

项目资料在 `src/data/projects.ts`，首页项目总数与筛选数量自动计算。

- `repo`：GitHub 仓库名，链接自动指向 `chilin11/<repo>`。
- `summary`、`language`、`stack`：简介与技术栈。
- `category`：`tools`（AI 与工具）、`apps`（日常应用）、`web`（Web 实验）。
- `featured: true`：在首页工作台中展示，并标注「近期在做」。
- `variant`：卡片强调色，支持 `''`、`photo`、`pill`、`outfit`。
- Fork 用 `note` 标注来源；有文章时，文章的 `repo` 与仓库名一致，首页自动显示「开发手记」入口。

项目列表由本地数据生成，不依赖浏览器访问 GitHub API；新增仓库后按上面补一条数据再部署即可。关闭 JavaScript 时仍显示全部项目。

## 一键部署（推荐：Docker / cloudflared）

需要已安装并运行 **Docker Engine + Docker Compose v2（支持 `up --wait`）**，当前用户有 Docker 访问权限。不需要在服务器安装 Node.js。

### 首次部署

```bash
git clone https://github.com/chilin11/blog.git
cd blog
cp .env.example .env
# 编辑 .env，把 SITE_URL 换成你的博客公开地址
./deploy.sh --docker
```

默认监听 `http://127.0.0.1:8080`，可以让服务器上已有的 cloudflared 或反向代理指向它。`SITE_URL` 只设置 canonical，不会配置 DNS、隧道或 HTTPS。cloudflared 如果也在容器内运行，需按其网络配置连接博客，不能直接用该容器自己的 localhost。

### 日常更新

本地提交并推送修改后，在服务器项目目录执行同一条命令：

```bash
./deploy.sh --docker
```

脚本会 `git pull --ff-only` → 校验 Compose → 从当前源码构建镜像 → 启动并等待健康检查通过。不会覆盖 `.env`，不会清理其他容器。源码构建不依赖 Docker Hub 上的 `latest` 镜像。

部署尚未提交的本地代码（不拉取远程）：

```bash
./deploy.sh --docker --no-pull
```

常用维护命令：

```bash
docker compose ps
docker compose logs --tail=100 blog
docker compose down     # 停止本站
./deploy.sh --help
```

端口冲突时修改 `.env` 中的 `PORT`。需要通过公网 IP 直接访问 HTTP 时，可设 `BIND_HOST=0.0.0.0` 并放行对应端口；默认只监听本机更安全。

## 部署到 VPS（无需 Docker，Caddy 自动 HTTPS）

适用于 Debian / Ubuntu 服务器。部署脚本 `deploy.sh` 会自动安装 Node.js 22 和 [Caddy](https://caddyserver.com)（自动申请并续期 HTTPS 证书），然后构建站点并发布。

### 0. 准备（只做一次）

1. **域名解析**：在域名服务商那里添加一条 A 记录，把 `blog.example.com` 指向 VPS 的 IP（有 IPv6 的话再加一条 AAAA 记录）。解析生效后 Caddy 才能申请到证书，可以用 `ping blog.example.com` 检查是否已经解析到你的 IP。
2. **开放端口**：确保 80 和 443 端口可以访问。除了系统防火墙，云厂商控制台里的“安全组”也要放行。
   ```bash
   # 如果服务器启用了 ufw：
   sudo ufw allow 80,443/tcp
   ```

### 1. 首次部署

SSH 登录 VPS 后执行：

```bash
sudo git clone https://github.com/chilin11/blog.git /opt/blog
sudo /opt/blog/deploy.sh blog.example.com
```

把 `blog.example.com` 换成你的域名。完成后打开 `https://blog.example.com` 即可访问。第一次申请证书可能需要十几秒。

> 还没有域名？先用 `sudo /opt/blog/deploy.sh :80`，然后通过 `http://服务器IP` 访问（不带 HTTPS）。有域名后再执行一次 `deploy.sh 你的域名` 即可切换。

### 2. 日常更新

在本地写好文章并 `git push`，然后在 VPS 上执行：

```bash
sudo /opt/blog/deploy.sh
```

脚本会记住上次用的域名，自动完成 `git pull`、构建和发布。

也可以在本地一条命令完成更新（`root@1.2.3.4` 换成你的 SSH 地址）：

```bash
git push && ssh root@1.2.3.4 'sudo /opt/blog/deploy.sh'
```

### 脚本做了什么

| 步骤 | 说明 |
| --- | --- |
| 安装依赖 | 缺少时才安装：git、rsync、Node.js 22（NodeSource）、Caddy（官方 apt 源） |
| 拉取代码 | `git pull --ff-only` |
| 构建 | `npm ci && npm run build`，并把 `SITE_URL` 设为 `https://你的域名` |
| 发布 | 把 `dist/` 同步到 `/var/www/blog`（删除已不存在的旧文件） |
| Web 服务 | 生成 `/etc/caddy/Caddyfile` 并重载 Caddy |

脚本可以重复运行。如果 `/etc/caddy/Caddyfile` 已经被你手动改过（例如同一台机器上还有其他网站），脚本不会覆盖它，只会打印需要加入的站点配置。

可选环境变量：`WEB_ROOT`（发布目录，默认 `/var/www/blog`）、`SKIP_PULL=1`（跳过 `git pull`，也可用 `--no-pull`）。脚本默认拒绝拉取存在未提交改动的工作区，不会替你强制重置代码。

### 常见问题

- **HTTPS 打不开 / 证书申请失败**：检查域名是否已解析到本机，80 和 443 端口是否放行；查看日志：`sudo journalctl -u caddy -n 50 --no-pager`。
- **`git pull` 失败**：执行 `cd /opt/blog && sudo git status`，先提交或备份服务器上的改动，再检查当前分支和远程；仅需部署现有代码时使用 `sudo ./deploy.sh --no-pull`。
- **回滚到旧版本**：`cd /opt/blog && sudo git checkout <commit>`，再执行 `sudo SKIP_PULL=1 ./deploy.sh`。之后要恢复更新，先执行 `sudo git checkout main`。
