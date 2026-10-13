#!/usr/bin/env bash
# VPS 入口：直接下载本脚本运行，无需 git clone / Docker / 本地电脑。
set -euo pipefail
log() { printf '==> %s\n' "$*"; }
die() { printf '错误：%s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'EOF'
Debian / Ubuntu VPS 一键部署（无需 git clone 或 Docker）：
  sudo bash install.sh blog.example.com   首次部署，Caddy 自动 HTTPS
  sudo bash install.sh                    更新，复用上次域名
  sudo bash install.sh :80                无域名，HTTP / IP 访问

自动下载 GitHub main 源码压缩包，在 VPS 安装 Node.js 并构建，发布后清理临时源码。
平时只运行 Caddy；低内存机器构建时仍需一定内存，不自动创建 swap。
域名解析与 80/443 防火墙需自行配置；不会关闭其他 Web 服务。
EOF
}
if [ "${1:-}" = --help ] || [ "${1:-}" = -h ]; then usage; exit 0; fi
[ "$#" -le 1 ] || die "只接受一个域名或 :80 参数"
[[ "${1:-}" != --* ]] || die "未知选项：$1"
[ "$(id -u)" -eq 0 ] || die "请用 sudo bash install.sh 或 root 运行"
command -v apt-get >/dev/null || die "仅支持 Debian / Ubuntu"
STATE_DIR="${BLOG_STATE_DIR:-/var/lib/blog-installer}"
[[ "$STATE_DIR" =~ ^/[A-Za-z0-9_./-]+$ && "$STATE_DIR" != / && "$STATE_DIR" != *..* ]] || die "无效配置目录"
DOMAIN="${1:-}"
if [ -z "$DOMAIN" ] && [ -f "$STATE_DIR/domain" ]; then DOMAIN="$(cat "$STATE_DIR/domain")"; fi
[ -n "$DOMAIN" ] || die "首次需要域名，例如 sudo bash install.sh blog.example.com；无域名用 :80"
DOMAIN="${DOMAIN#http://}"; DOMAIN="${DOMAIN#https://}"; DOMAIN="${DOMAIN%/}"
if [[ "$DOMAIN" == :* ]]; then
  [[ "$DOMAIN" =~ ^:[0-9]{1,5}$ ]] || die "无效端口"
  port="${DOMAIN#:}"
  (( 10#$port >= 1 && 10#$port <= 65535 )) || die "端口必须为 1–65535"
else
  [[ "$DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || die "域名不能包含路径、空格或命令字符"
fi
umask 077
mkdir -p "$STATE_DIR"
command -v flock >/dev/null || die "缺少 flock，请安装 util-linux"
exec 9>"$STATE_DIR/deploy.lock"
flock -n 9 || die "已有部署正在运行，请稍后再试"
missing=()
for bin in curl tar; do command -v "$bin" >/dev/null || missing+=("$bin"); done
if [ "${#missing[@]}" -gt 0 ]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq ca-certificates "${missing[@]}"
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
log "从 GitHub 下载最新源码（不使用 git）"
curl --fail --show-error --silent --location --retry 3 \
  https://codeload.github.com/chilin11/blog/tar.gz/refs/heads/main -o "$WORK/source.tar.gz"
mkdir "$WORK/source"
tar -xzf "$WORK/source.tar.gz" --strip-components=1 -C "$WORK/source"
for file in deploy.sh package.json package-lock.json src/pages/index.astro; do
  [ -s "$WORK/source/$file" ] || die "GitHub 源码包不完整：缺少 $file"
done
log "安装依赖、构建并部署（源码为临时目录）"
# npm/Caddy 发布目录需可被服务读取，不能继承入口的私有 umask。
mkdir "$WORK/build-tmp"
(umask 022; TMPDIR="$WORK/build-tmp" SKIP_PULL=1 bash "$WORK/source/deploy.sh" "$DOMAIN")
# 仅成功后保存设置，不执行配置文件中的 shell 内容。
printf '%s\n' "$DOMAIN" > "$STATE_DIR/domain.next"
chmod 600 "$STATE_DIR/domain.next"
mv -f "$STATE_DIR/domain.next" "$STATE_DIR/domain"
log "更新完成；下次重新下载并运行 install.sh 即可，无需再次填写域名"
