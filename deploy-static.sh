#!/usr/bin/env bash
# 在本地运行：本地 Astro 构建 → SSH 上传 → VPS 上 Caddy 提供静态访问。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="$REPO_DIR/.deploy-static.env"
REMOTE_ROOT=/var/www/blog-static
TARGET=''
SITE_URL=''
SSH_PORT=22
SETUP=0

log() { printf '==> %s\n' "$*"; }
die() { printf '错误：%s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'EOF'
在本地电脑的博客项目目录运行（不是在低配 VPS 上运行）：
  ./deploy-static.sh --setup root@服务器IP https://博客域名
  ./deploy-static.sh                         之后更新，复用已保存配置
  ./deploy-static.sh root@服务器IP https://博客域名
  ./deploy-static.sh --setup --port 2222 root@服务器IP https://博客域名

--setup  在 Debian / Ubuntu VPS 上安装 Caddy、配置站点；保留已有站点。
--port   SSH 端口，默认 22。SSH 密钥/别名/跳板配置可放 ~/.ssh/config。
无域名可用 http://服务器IP（仅 HTTP）。域名解析与防火墙需自行配置。
本地需要 Node.js >=22.12、npm、ssh、scp、tar；VPS 不需要 Node.js 或 Docker。
远程使用 root 或可免密码 sudo 的 SSH 用户。不会 git pull / push。
EOF
}

# 只读取脚本自己的键值配置，不 source 配置文件。
if [ -f "$CONF_FILE" ]; then
  while IFS='=' read -r key value; do
    case "$key" in
      TARGET) TARGET="$value" ;;
      SITE_URL) SITE_URL="$value" ;;
      SSH_PORT) SSH_PORT="$value" ;;
    esac
  done < "$CONF_FILE"
fi
POSITIONAL=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --setup) SETUP=1 ;;
    --port) [ "$#" -ge 2 ] || die "--port 后需要 SSH 端口"; SSH_PORT="$2"; shift ;;
    --*) die "未知选项：$1" ;;
    *) POSITIONAL+=("$1") ;;
  esac
  shift
done
if [ "${#POSITIONAL[@]}" -gt 0 ]; then
  [ "${#POSITIONAL[@]}" -eq 2 ] || die "请同时提供 SSH 地址与站点地址，或不传参数复用配置"
  TARGET="${POSITIONAL[0]}"
  SITE_URL="${POSITIONAL[1]}"
fi
[ -n "$TARGET" ] && [ -n "$SITE_URL" ] || { usage; die "首次请提供 SSH 地址和站点地址"; }
[[ "$TARGET" =~ ^([A-Za-z0-9_][A-Za-z0-9_.-]*@)?[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] \
  || die "SSH 地址需为 user@host 或 ~/.ssh/config 中的别名，不含空格或命令字符"
[[ "$SSH_PORT" =~ ^[0-9]{1,5}$ ]] || die "SSH 端口无效"
(( 10#$SSH_PORT >= 1 && 10#$SSH_PORT <= 65535 )) || die "SSH 端口必须为 1–65535"
SITE_URL="${SITE_URL%/}"
[[ "$SITE_URL" =~ ^https?://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] \
  || die "站点地址需为 http://主机名 或 https://域名，不含路径、端口或命令字符"
ADDRESS="${SITE_URL#*://}"
if [[ "$SITE_URL" == http://* ]]; then ADDRESS="http://$ADDRESS"; fi

for bin in node npm ssh scp tar; do command -v "$bin" >/dev/null || die "本地缺少 $bin"; done
node -e 'const [major,minor]=process.versions.node.split(".").map(Number);process.exit(major>22||(major===22&&minor>=12)?0:1)' \
  || die "本地 Node.js 需要 >=22.12"
SSH=(ssh -p "$SSH_PORT" -o ConnectTimeout=15 "$TARGET")
SCP=(scp -P "$SSH_PORT" -o ConnectTimeout=15)
# 参数均已严格校验；远程非 root 用户通过免密码 sudo 执行。
remote() {
  local action="$1" stage="${2:-none}"
  "${SSH[@]}" "if [ \"\$(id -u)\" -eq 0 ]; then exec bash -s -- '$action' '$REMOTE_ROOT' '$ADDRESS' '$SITE_URL' '$stage'; else exec sudo -n bash -s -- '$action' '$REMOTE_ROOT' '$ADDRESS' '$SITE_URL' '$stage'; fi" <<'REMOTE_SCRIPT'
set -euo pipefail
action="$1"; root="$2"; address="$3"; url="$4"; stage="$5"
marker="$root/.managed-by-blog-static"
fail() { printf 'VPS 错误：%s\n' "$*" >&2; exit 1; }
check_site() {
  [ -f "$marker" ] && [ -f "$root/.site-url" ] || fail "请先使用 --setup 初始化静态站点"
  [ "$(cat "$root/.site-url")" = "$url" ] || fail "站点地址与 VPS 已保存配置不同，请用 --setup 确认变更"
}
case "$action" in
  setup)
    command -v apt-get >/dev/null || fail "自动初始化仅支持 Debian / Ubuntu"
    command -v systemctl >/dev/null || fail "需要 systemd 来管理 Caddy"
    if [ -e "$root" ] && [ ! -f "$marker" ] && [ -n "$(ls -A "$root")" ]; then
      fail "$root 已有未由本脚本管理的内容，不会覆盖"
    fi
    if ! command -v caddy >/dev/null; then
      export DEBIAN_FRONTEND=noninteractive
      apt-get update
      apt-get install -y caddy
    fi
    mkdir -p "$root/releases" /etc/caddy
    fragment=/etc/caddy/blog-static.caddy
    if [ -f "$fragment" ] && ! grep -qFx '# managed-by: blog/deploy-static.sh' "$fragment"; then
      fail "$fragment 已有自定义内容，不会覆盖"
    fi
    work="$(mktemp -d)"
    had_fragment=0
    [ ! -f "$fragment" ] || { cp -p "$fragment" "$work/old-fragment"; had_fragment=1; }
    had_main=0
    [ ! -f /etc/caddy/Caddyfile ] || { cp -p /etc/caddy/Caddyfile "$work/old-main"; had_main=1; }
    committed=0
    rollback() {
      if [ "$committed" -eq 0 ]; then
        if [ "$had_fragment" -eq 1 ]; then cp -p "$work/old-fragment" "$fragment"; else rm -f "$fragment"; fi
        if [ "$had_main" -eq 1 ]; then cp -p "$work/old-main" /etc/caddy/Caddyfile; else rm -f /etc/caddy/Caddyfile; fi
      fi
      rm -rf "$work"
    }
    trap rollback EXIT
    printf '# managed-by: blog/deploy-static.sh\n%s {\n    root * %s/current\n    encode gzip\n    file_server\n}\n' "$address" "$root" > "$fragment"
    chmod 644 "$fragment"
    if [ "$had_main" -eq 1 ]; then cp "$work/old-main" "$work/new-main"; else : > "$work/new-main"; fi
    if ! grep -qE '^[[:space:]]*import[[:space:]]+/etc/caddy/blog-static\.caddy[[:space:]]*$' "$work/new-main"; then
      printf '\n# blog static site (keep existing sites above)\nimport /etc/caddy/blog-static.caddy\n' >> "$work/new-main"
    fi
    install -m 644 "$work/new-main" /etc/caddy/Caddyfile
    caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile || fail "Caddy 配置校验失败，恢复原配置；请检查已有域名或端口冲突"
    systemctl enable --now caddy
    systemctl reload caddy || fail "Caddy 重载失败，恢复原配置"
    committed=1
    touch "$marker"
    printf '%s\n' "$url" > "$root/.site-url"
    echo 'VPS 初始化完成（仅 Caddy；无 Docker / Node.js）'
    ;;
  check)
    check_site
    command -v tar >/dev/null || fail "VPS 缺少 tar"
    command -v caddy >/dev/null || fail "VPS 缺少 Caddy，请重新 --setup"
    systemctl is-active --quiet caddy || fail "Caddy 未运行"
    ;;
  publish)
    check_site
    [[ "$stage" =~ ^/tmp/blog-upload\.[A-Za-z0-9]+$ ]] || fail "无效上传目录"
    [ -f "$stage/site.tar.gz" ] || fail "上传包缺失"
    release="$(mktemp -d "$root/releases/release.XXXXXXXX")"
    trap 'rm -rf "$release"' EXIT
    tar -xzf "$stage/site.tar.gz" -C "$release"
    [ -s "$release/index.html" ] || fail "上传包缺少 index.html"
    # 避免切换前已打开的页面找不到旧版本的哈希静态资源。
    if [ -d "$root/current/_astro" ]; then
      mkdir -p "$release/_astro"
      cp -an "$root/current/_astro/." "$release/_astro/"
    fi
    chmod -R a+rX "$release"
    chmod a+rx "$root" "$root/releases"
    [ ! -e "$root/current" ] || [ -L "$root/current" ] || fail "current 不是脚本管理的软链接，拒绝覆盖"
    previous="$(readlink "$root/current" 2>/dev/null || true)"
    link="$root/.next-$(basename "$release")"
    ln -s "$release" "$link"
    mv -Tf "$link" "$root/current"
    trap - EXIT
    # 明确保留当前和切换前的版本，不依赖可能相同的时间戳。
    find "$root/releases" -mindepth 1 -maxdepth 1 -type d -name 'release.*' \
      | while IFS= read -r old; do
        if [ "$old" != "$release" ] && [ "$old" != "$previous" ]; then rm -rf "$old"; fi
      done
    echo '静态文件已发布，无需重启 Caddy'
    ;;
  *) fail "未知操作" ;;
esac
REMOTE_SCRIPT
}

cd "$REPO_DIR"
log "在本地安装依赖并构建：$SITE_URL"
npm ci --no-audit --no-fund
SITE_URL="$SITE_URL" npm run build
[ -s dist/index.html ] || die "构建产物缺少 dist/index.html"
LOCAL_TMP="$(mktemp -d)"
REMOTE_TMP=''
cleanup() {
  rm -rf "$LOCAL_TMP"
  if [[ "$REMOTE_TMP" =~ ^/tmp/blog-upload\.[A-Za-z0-9]+$ ]]; then
    "${SSH[@]}" "rm -rf -- '$REMOTE_TMP'" </dev/null >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
# 构建产物不包含用户上传或服务器配置。
tar -czf "$LOCAL_TMP/site.tar.gz" -C dist .
if [ "$SETUP" -eq 1 ]; then
  log "初始化 VPS 的 Caddy（保留已有站点）"
  remote setup
fi
log "检查远程站点和 Caddy"
remote check
REMOTE_TMP="$("${SSH[@]}" 'mktemp -d /tmp/blog-upload.XXXXXXXX')"
[[ "$REMOTE_TMP" =~ ^/tmp/blog-upload\.[A-Za-z0-9]+$ ]] || die "远程临时目录响应无效"
log "上传静态文件到 $TARGET"
"${SCP[@]}" "$LOCAL_TMP/site.tar.gz" "$TARGET:$REMOTE_TMP/site.tar.gz"
remote publish "$REMOTE_TMP"
# 仅在发布成功后记住设置；不会保存 SSH 密码或私钥。
umask 077
printf 'TARGET=%s\nSITE_URL=%s\nSSH_PORT=%s\n' "$TARGET" "$SITE_URL" "$SSH_PORT" > "$CONF_FILE"
log "发布完成：$SITE_URL；下次运行 ./deploy-static.sh 即可更新"
