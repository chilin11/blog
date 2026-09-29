# 静态博客镜像：Node 构建 → nginx 提供服务。
# 构建时站点地址用占位符，容器启动时由 SITE_URL 环境变量替换（见 docker/40-site-url.sh）。

# 构建产物与 CPU 架构无关，固定在构建机的原生平台上运行，多架构构建时无需模拟
FROM --platform=$BUILDPLATFORM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
ENV SITE_URL=https://site-url.invalid
RUN npm run build

FROM nginx:stable-alpine
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --chmod=755 docker/40-site-url.sh /docker-entrypoint.d/40-site-url.sh
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD wget -q --spider http://127.0.0.1/ || exit 1
