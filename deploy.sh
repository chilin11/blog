#!/usr/bin/env bash
# 在 VPS（Debian / Ubuntu）上一键部署或更新博客。
#
# 首次部署：  sudo ./deploy.sh blog.example.com
# 之后更新：  sudo ./deploy.sh
# 没有域名时先用 IP 访问（仅 HTTP）：sudo ./deploy.sh :80
# Docker / cloudflared：./deploy.sh --docker（配置见 .env.example）
# 查看帮助：./deploy.sh --help
#
# 脚本会做这些事（重复运行是安全的）：
#   1. 缺少时安装 git / rsync / Node.js 22 / Caddy
#   2. git pull 拉取最新代码
#   3. npm ci && npm run build
#   4. 把 dist/ 同步到 /var/www/blog
#   5. 写入 Caddy 配置并重载（Caddy 会自动申请 HTTPS 证书）
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_ROOT="${WEB_ROOT:-/var/www/blog}"
CONF_FILE="$REPO_DIR/.deploy.env"
CADDYFILE=/etc/caddy/Caddyfile
MARKER="# managed-by: blog/deploy.sh"
NODE_MAJOR=22

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m错误:\033[0m %s\n' "$*" >&2; exit 1; }


usage() {
  cat <<'EOF'
用法：
  ./deploy.sh --docker                 Docker 构建并部署 / 更新（读取 .env）
  sudo ./deploy.sh blog.example.com    Debian / Ubuntu + Caddy，自动 HTTPS
  sudo ./deploy.sh                     Caddy 更新，复用已保存的域名
  sudo ./deploy.sh :80                 Caddy HTTP 模式，通过服务器 IP 访问
  ./deploy.sh --help                   查看帮助

可选：--no-pull 或 SKIP_PULL=1 跳过拉取，用于部署当前本地代码。
Docker 需要 Docker Engine + Compose v2；默认监听 127.0.0.1:8080。
EOF
}

MODE=caddy
DOMAIN=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --docker) MODE=docker ;;
    --no-pull) SKIP_PULL=1 ;;
    --*) die "未知选项：$1（用 --help 查看用法）" ;;
    *) [ -z "$DOMAIN" ] || die "只能指定一个域名"; DOMAIN="$1" ;;
  esac
  shift
done

pull_code() {
  cd "$REPO_DIR"
  if [ "${SKIP_PULL:-0}" != 1 ] && git remote get-url origin >/dev/null 2>&1; then
    [ -z "$(git status --porcelain --untracked-files=no)" ] \
      || die "工作区存在未提交改动，请先提交；要部署本地代码，请使用 --no-pull"
    log "git pull --ff-only"
    git pull --ff-only || die "git pull 失败，请检查分支、网络和 git status；可用 --no-pull 部署当前代码"
  fi
  log "当前版本：$(git log -1 --format='%h %s' 2>/dev/null || echo unknown)"
}

if [ "$MODE" = docker ]; then
  [ -z "$DOMAIN" ] || die "Docker 模式请在 .env 中设置 SITE_URL，不使用域名参数"
  command -v git >/dev/null || die "请先安装 git"
  command -v docker >/dev/null || die "请先安装 Docker Engine 和 Compose v2"
  docker compose version >/dev/null 2>&1 || die "需要 Docker Compose v2"
  docker info >/dev/null 2>&1 || die "Docker 未启动或当前用户无权限访问"
  pull_code
  log "校验 Docker Compose 配置"
  docker compose -f "$REPO_DIR/docker-compose.yml" config --quiet
  log "从当前代码构建博客镜像"
  docker compose -f "$REPO_DIR/docker-compose.yml" build --pull blog
  log "启动博客并等待健康检查"
  docker compose -f "$REPO_DIR/docker-compose.yml" up -d --wait --wait-timeout 90 blog \
    || die "容器未健康，请执行 docker compose logs --tail=100 blog 查看原因"
  docker compose -f "$REPO_DIR/docker-compose.yml" ps blog
  log "Docker 部署完成；实际监听地址见上方 PORTS，默认 http://127.0.0.1:8080"
  log "通过已有 cloudflared / 反向代理连接该地址；SITE_URL 只设置页面 canonical，不会配置域名或 HTTPS"
  exit 0
fi
[ "$(id -u)" -eq 0 ] || die "请用 root 或 sudo 运行：sudo $0 $*"
command -v apt-get >/dev/null || die "目前只支持 Debian / Ubuntu（需要 apt-get）"

# ---------- 域名：参数 > 已保存的配置 ----------
# DOMAIN 已从参数解析；无参数时读取已保存配置。
if [ -z "$DOMAIN" ] && [ -f "$CONF_FILE" ]; then
  # shellcheck disable=SC1090
  . "$CONF_FILE"
fi
[ -n "$DOMAIN" ] || die "首次部署请提供域名，例如：sudo $0 blog.example.com（没有域名可用 :80）"
DOMAIN="${DOMAIN#http://}"; DOMAIN="${DOMAIN#https://}"; DOMAIN="${DOMAIN%/}"
if [[ "$DOMAIN" == :* ]]; then
  [[ "$DOMAIN" =~ ^:[0-9]{1,5}$ ]] || die "无效端口，请使用 :80 或 :8080"
  port="${DOMAIN#:}"
  (( 10#$port >= 1 && 10#$port <= 65535 )) || die "端口必须在 1–65535 之间"
else
  [[ "$DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || die "请输入有效主机名，不要包含路径、端口或空格"
fi
[[ "$WEB_ROOT" =~ ^/[A-Za-z0-9_./-]+$ && "$WEB_ROOT" != / && "$WEB_ROOT" != *..* ]] \
  || die "WEB_ROOT 必须是非根目录的绝对路径，不能包含空格或 .."

if [[ "$DOMAIN" == :* ]]; then
  SITE_URL="http://localhost"   # 纯 IP / 端口模式，canonical 用占位
else
  SITE_URL="https://$DOMAIN"
fi

# ---------- 1. 依赖 ----------
export DEBIAN_FRONTEND=noninteractive
APT_UPDATED=0
apt_install() {
  if [ "$APT_UPDATED" -eq 0 ]; then apt-get update -qq; APT_UPDATED=1; fi
  apt-get install -y -qq "$@" >/dev/null
}

missing=()
for bin in git rsync curl gpg; do command -v "$bin" >/dev/null || missing+=("$bin"); done
if [ "${#missing[@]}" -gt 0 ]; then
  log "安装基础工具：${missing[*]}"
  pkgs=("${missing[@]/gpg/gnupg}")
  apt_install ca-certificates "${pkgs[@]}"
fi

node_ok() {
  command -v node >/dev/null || return 1
  node -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(a>22||(a===22&&b>=12)?0:1)'
}
if ! node_ok; then
  log "安装 Node.js $NODE_MAJOR"
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - >/dev/null
  apt-get install -y -qq nodejs >/dev/null
  APT_UPDATED=1
fi

if ! command -v caddy >/dev/null; then
  log "安装 Caddy"
  apt_install debian-keyring debian-archive-keyring apt-transport-https
  curl -fsSL 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -fsSL 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    > /etc/apt/sources.list.d/caddy-stable.list
  chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -qq
  apt-get install -y -qq caddy >/dev/null
fi

# ---------- 2. 拉取代码 ----------
git config --global --add safe.directory "$REPO_DIR" 2>/dev/null || true
pull_code

# ---------- 3. 构建 ----------
log "安装依赖并构建（SITE_URL=$SITE_URL）"
npm ci --no-audit --no-fund --loglevel=error
SITE_URL="$SITE_URL" npm run build --silent
[ -f dist/index.html ] || die "构建产物缺失：dist/index.html"

# ---------- 4. 发布 ----------
log "同步到 $WEB_ROOT"
mkdir -p "$WEB_ROOT"
rsync -a --delete-after dist/ "$WEB_ROOT/"
chmod -R a+rX "$WEB_ROOT"

# ---------- 5. Caddy ----------
if [ -f "$CADDYFILE" ] && ! grep -qF "$MARKER" "$CADDYFILE" \
   && ! grep -q '/usr/share/caddy' "$CADDYFILE"; then
  # 不是安装时的默认配置，也不是本脚本写的：不覆盖，避免破坏已有站点
  log "检测到自定义的 $CADDYFILE，未修改。请手动加入以下站点配置："
  PRINT_ONLY=1
fi

# 站点配置本体（不含标记，可直接复制进已有的 Caddyfile）
site_block() {
  cat <<EOF
$DOMAIN {
	root * $WEB_ROOT
	encode zstd gzip
	header /_astro/* Cache-Control "public, max-age=31536000, immutable"
	file_server
}
EOF
}

if [ "${PRINT_ONLY:-0}" = 1 ]; then
  echo; site_block; echo
  log "加入后执行：sudo systemctl reload caddy"
else
  tmp="$(mktemp)"
  { echo "$MARKER"; echo "# 由 deploy.sh 生成，重新部署时会被覆盖。"; site_block; } > "$tmp"
  caddy validate --adapter caddyfile --config "$tmp" >/dev/null 2>&1 \
    || { caddy validate --adapter caddyfile --config "$tmp"; rm -f "$tmp"; die "Caddy 配置校验失败"; }
  install -m 644 "$tmp" "$CADDYFILE"; rm -f "$tmp"
  if command -v systemctl >/dev/null && [ -d /run/systemd/system ]; then
    systemctl enable --now caddy >/dev/null 2>&1 || true
    systemctl reload caddy || systemctl restart caddy
  else
    log "未检测到 systemd，请手动启动：caddy run --config $CADDYFILE"
  fi
fi

printf 'DOMAIN=%q\n' "$DOMAIN" > "$CONF_FILE"
chmod 600 "$CONF_FILE"

log "部署完成：${SITE_URL/http:\/\/localhost/http://<服务器IP>}"
