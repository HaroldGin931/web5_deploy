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
docker compose --env-file .env ps
docker compose --env-file .env logs -f --tail=100
docker compose --env-file .env down
```

只有需要完全重置 mock 数据时才执行：

```bash
docker compose --env-file .env down -v
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

## 注册与 Semi 登录配置

入口：账号密码继续使用 `/login`；可用的手机号／邮箱注册显示在 `/register`。
Semi 凭据与加密密钥配置齐全后，登录页才显示「使用 Semi 登录」。
`GET /auth/semi/options` 只返回可用通道、测试模式和 handle 域名，不返回密钥。

在服务器 `/home/ubuntu/xiangjian-demo/compose/.env` 中补充
[.auth.env.example](.auth.env.example) 的变量；**保留现有数据库、PDS 等配置，不覆盖文件**。
使用服务器编辑器填写，文件权限保持 `600`，不提交 Git，不放入前端 `VITE_*` 变量。

- **Semi**：`SEMI_CLIENT_ID`、`SEMI_CLIENT_SECRET` 是 Semi OAuth 应用凭据。
  在 Semi 后台登记回调 **`https://demo.wamo.social/auth/semi/callback`**；部署其他域名时
  按对应 `PUBLIC_ORIGIN` 替换。Compose 自动设置该回调和前端 `/semi-callback`，浏览器只接收
  一次性票据，由前端服务端换取 Rice/PDS 各自的会话。授权失败显示明确错误，保留来源详情。
- **Rice 加密密钥**：`RICE_LINK_ENC_KEY` 用来加密 Semi 对应的 PDS 账号密码，
  不是 Semi 提供的 API key 或签名私钥。已有 `semi_links` 数据必须沿用原密钥并妥善备份。
  仅全新部署、尚无绑定数据时，用 `openssl rand -base64 32` 生成后填入；不要每次部署重新生成。
- **短信注册**：阿里云四项 `ALIYUN_SMS_ACCESS_KEY_ID`、`ALIYUN_SMS_ACCESS_KEY_SECRET`、
  `ALIYUN_SMS_SIGN_NAME`、`ALIYUN_SMS_TEMPLATE_CODE` 必須齐全；模板参数名称为 `code`。
- **邮箱注册**：填写 `SMTP_RELAY`、`SMTP_PORT`、`SMTP_USERNAME`、`SMTP_PASSWORD`、
  `SMTP_SENDER_ADDRESS`；使用 STARTTLS（默认 587 端口）。发送地址应是服务商验证过的地址。
  邮件和短信相互独立，只配邮件也可以注册。
- **未配置时**：真实模式下未配置的通道不显示为注册选项，直接调用也返回 `503`；
  不会把验证码打印到日志后假报「已发送」，不创建模拟登录会话。

保存配置后只重建受影响服务（这里的镜像应已包含对应代码）。不运行会写入 mock 数据的 `start.sh`：

```bash
cd /home/ubuntu/xiangjian-demo/compose
chmod 600 .env
export PUBLIC_HOST=demo.wamo.social PUBLIC_SCHEME=https PUBLIC_ORIGIN=https://demo.wamo.social
docker compose --env-file .env up -d --no-deps rice
# 网关路由有变更时，先检查并加载；只改凭据无需加载网关。
docker compose --env-file .env exec -T gateway nginx -t
docker compose --env-file .env exec -T gateway nginx -s reload
curl --fail --silent https://demo.wamo.social/auth/semi/options
```

Mock 边界：后端 `SemiAuthControllerTest` 使用现有 Req.Test 模拟授权服务，Mox 模拟 PDS，
验证 PKCE、错误 state、一次性票据及 Rice/PDS 身份；注册测试模拟发送通道，不打真实服务商。
这只能证明本地协议链路，不能证明服务商配置、短信到达或真实授权成功。
需要手工走隔离环境验证码时才显式设置 `RICE_VERIFICATION_MODE=log`，界面会标明测试模式，
验证码只写该服务器日志；结束后恢复 `live`。Semi 没有生产环境模拟登录开关。
真实密钥由部署者填入后，再验收首次注册、同账号再次登录、取消授权及从详情登录返回。

## 已恢复的历史 PDS 数据

恢复沿用现有数据库与服务；旧活动标签仍是帖子，不进入新 Rice 任务、活动或账本。
服务器 `.env` 的 `COMPOSE_FILE` 可包含私有恢复配置（历史 handle 的容器网络别名）。
更新和重建请用 `docker compose --env-file .env ...`，不要用 `-f compose.yml` 绕过该配置。
这些由账号资料生成的别名、原始备份、数据库文件和身份记录均不提交 Git。

`BSKY_DB_POSTGRES_SCHEMA` 与备份的 AppView schema 一致；
`PDS_SERVICE_HANDLE_DOMAINS` 同时保留新注册域和已恢复账号域。
`POST_CACHE_VISITOR` / `POST_CACHE_VISITOR_PASSWORD` 是无内容的索引访客服务账号，
与真实用户、Rice 账户和 mock 种子无关。恢复环境关闭 `ALLOW_UAT_MOCK_SEED`，
不要运行 `start.sh` 重写测试账号或证书。
