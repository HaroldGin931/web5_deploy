# 乡建 Demo Compose

## 前端生产构建

前端镜像在构建时执行 `pnpm build`，启动时使用 TanStack 锁定的 srvx 适配器运行
SSR 和服务端函数，不再运行 Vite 开发服务器。`XIANGJIAN_BACKEND_URL` 仍在启动时配置。
只有内容哈希命名的 `/assets/` 成功响应长期缓存；HTML 和服务端函数不加长期缓存。
更新网关配置后先执行 `nginx -t`，通过后热加载；不重建数据服务。

## 公开地址与图片

`./start.sh <域名或完整 origin>` 按部署目标设置 `PUBLIC_HOST`、`PUBLIC_SCHEME` 和
`PUBLIC_ORIGIN`。浏览器图片使用 `${PUBLIC_ORIGIN}/bsky/img/...`，游客帖子详情使用
同源 `/bsky/xrpc/app.bsky.feed.getPostThread`；网关仅开放这些 GET/HEAD 读取路径。
AppView 的内部服务身份用于容器通信，不作为浏览器图片地址。

升级已有部署时，可在服务器 `.env` 的 `XIANGJIAN_APPVIEW_IMAGE_ORIGINS` 中填写升级前
AppView 输出过的 origin（多个值逗号分隔）。前端服务只改写这些明确配置的旧图片来源，
不改写外站 CDN；不要把环境域名硬编码到产品代码。新部署不需要该兼容配置。
更新前备份 Compose 配置和当前镜像，构建固定 Git 提交后仅重建受影响服务，保留数据卷。

这套 Compose 在运行主机上直接从固定 Git 提交构建 Rice 和新版前端，
不需要上传本地 Docker 镜像。PDS、PLC、AppView 和 Post Cache 使用固定镜像摘要。

## 启动

```bash
# 本地测试
./start.sh localhost

# demo.wamo.social 服务器
./start.sh demo.wamo.social
```

本地入口是 <http://localhost:18080>，服务器入口是
<https://demo.wamo.social>。浏览器始终使用所选入口下的同源
`/api`、`/pds` 和 `/post`。

`start.sh` 第一次运行时会生成随机测试密钥和仅供 Docker 内部使用的证书，
构建 Rice 与前端，启动服务，并写入五名 mock 用户、一个任务和两条帖子。
`.env` 和 `certs/` 不进入 Git。

## 服务器首次安装

```bash
git clone --branch demo-wamo-social --single-branch \
  https://github.com/HaroldGin931/web5_deploy.git
cd web5_deploy/compose
./start.sh demo.wamo.social
```

以后更新部署配置：

```bash
git pull --ff-only
./start.sh demo.wamo.social
```

## 管理

```bash
docker compose --env-file .env -f compose.yml ps
docker compose --env-file .env -f compose.yml logs -f --tail=100
docker compose --env-file .env -f compose.yml down
```

只有需要完全重置 mock 数据时才执行：

```bash
docker compose --env-file .env -f compose.yml down -v
```

服务器上的 gateway 只监听 `127.0.0.1:18080`。外层 Traefik 负责把
`demo.wamo.social` 的 HTTPS 请求代理到该端口。

当前测试服务器的 Traefik 由 Nomad 管理，路由文件需要手动放入它的动态配置目录：

路由使用 Let’s Encrypt TLS-ALPN-01；Traefik 的静态配置需要先定义下面的 resolver，
并在首次加入时重启一次：

```yaml
certificatesResolvers:
  le-tls:
    acme:
      email: lisbon@appendonly.org
      storage: /letsencrypt/acme-tls.json
      tlsChallenge: {}
```

```bash
traefik_container=$(docker ps --filter name=traefik- --format '{{.ID}}' | head -n 1)
traefik_dynamic_dir=$(docker inspect "$traefik_container" \
  --format '{{range .Mounts}}{{if eq .Destination "/etc/traefik/dynamic"}}{{.Source}}{{end}}{{end}}')
sudo install -m 0644 demo-wamo-social.traefik.yaml \
  "$traefik_dynamic_dir/demo-wamo-social.yaml"
```

安装路由文件本身会由 Traefik 热加载。若 Nomad 更换了 Traefik allocation，
需要重新执行一次；正式持久化时应把 resolver 和同一份动态配置加入 Traefik 的部署模板。
