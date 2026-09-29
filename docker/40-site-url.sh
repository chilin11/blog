#!/bin/sh
# nginx 官方镜像启动时会自动执行 /docker-entrypoint.d/ 下的脚本。
# 把构建时的占位地址替换为 SITE_URL（例如 https://blog.example.com）。
# 未设置 SITE_URL 时替换为空，canonical 链接变为站内相对路径。
set -eu

PLACEHOLDER='https://site-url.invalid'
ROOT=/usr/share/nginx/html

url="${SITE_URL:-}"
url="${url%/}"
case "$url" in
  ''|http://*|https://*) ;;
  *) url="https://$url" ;;
esac

files="$(grep -rlF "$PLACEHOLDER" "$ROOT" 2>/dev/null || true)"
if [ -z "$files" ]; then
  echo "site-url: 占位符已替换过，跳过"
  exit 0
fi

escaped="$(printf '%s' "$url" | sed 's/[&|\\]/\\&/g')"
echo "$files" | while IFS= read -r f; do
  sed -i "s|$PLACEHOLDER|$escaped|g" "$f"
done

if [ -n "$url" ]; then
  echo "site-url: 站点地址设为 $url"
else
  echo "site-url: 未设置 SITE_URL，canonical 使用相对路径"
fi
