#!/usr/bin/env bash
# 在 VPS（Debian / Ubuntu）上一键部署或更新博客。
#
# 首次部署：  sudo ./deploy.sh blog.example.com
# 之后更新：  sudo ./deploy.sh
# 没有域名时先用 IP 访问（仅 HTTP）：sudo ./deploy.sh :80
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

[ "$(id -u)" -eq 0 ] || die "请用 root 或 sudo 运行：sudo $0 $*"
command -v apt-get >/dev/null || die "目前只支持 Debian / Ubuntu（需要 apt-get）"

# ---------- 域名：参数 > 已保存的配置 ----------
DOMAIN="${1:-}"
if [ -z "$DOMAIN" ] && [ -f "$CONF_FILE" ]; then
  # shellcheck disable=SC1090
  . "$CONF_FILE"
fi
[ -n "$DOMAIN" ] || die "首次部署请提供域名，例如：sudo $0 blog.example.com（没有域名可用 :80）"
DOMAIN="${DOMAIN#http://}"; DOMAIN="${DOMAIN#https://}"; DOMAIN="${DOMAIN%/}"
printf 'DOMAIN=%q\n' "$DOMAIN" > "$CONF_FILE"

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
cd "$REPO_DIR"
git config --global --add safe.directory "$REPO_DIR" 2>/dev/null || true
if [ "${SKIP_PULL:-0}" != 1 ] && git remote get-url origin >/dev/null 2>&1; then
  log "git pull"
  git pull --ff-only || die "git pull 失败。服务器上的代码被改动过？可执行 git status 查看，或用 SKIP_PULL=1 跳过拉取"
fi
log "当前版本：$(git log -1 --format='%h %s' 2>/dev/null || echo unknown)"

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

log "部署完成：${SITE_URL/http:\/\/localhost/http://<服务器IP>}"
