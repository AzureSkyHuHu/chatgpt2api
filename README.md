# ai2api

`ai2api` 是一个本地自托管的 AI API 服务，提供 OpenAI 兼容接口、图片生成/编辑能力、账号池管理、在线画图页面和基础运维配置。

当前推荐部署方式是：**Docker 镜像负责运行环境和依赖，宿主机代码通过 volume 挂载进容器**。

## 当前本地访问

- Web / API：`${AI2API_BASE_URL}`
- 本地直连示例：`http://127.0.0.1:18000`
- dnmp nginx 示例：`http://ai2api.test.com`
- API 前缀：`/v1`
- 默认容器名：`ai2api-local`
- 默认镜像名：`ai2api:local`

先设置访问地址变量：

```bash
export AI2API_BASE_URL=${AI2API_BASE_URL:-http://127.0.0.1:18000}
```

验证服务：

```bash
curl "$AI2API_BASE_URL/version"
```

通过 nginx 验证：

```bash
curl --noproxy '*' -H 'Host: ai2api.test.com' "${AI2API_NGINX_URL:-http://127.0.0.1}/version"
```

## 目录结构

```text
.
├── main.py                  # FastAPI 入口
├── api/                     # API 路由
├── services/                # 业务服务
├── utils/                   # 工具代码
├── web/                     # 前端 Next.js 静态导出项目
├── data/                    # 运行数据
├── docker-compose.mount.yml # 推荐：volume 挂载部署
├── docker-compose.local.yml # 完整镜像打包部署
└── Dockerfile
```

## 环境变量

复制示例配置：

```bash
cp .env.example .env
```

常用配置：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `CHATGPT2API_AUTH_KEY` | `chatgpt2api` | API / Web 登录认证密钥 |
| `CHATGPT2API_BASE_URL` | 空 | 生成外部可访问图片 URL 时使用 |
| `APP_CONTAINER_NAME` | `ai2api-local` | Docker 容器名 |
| `WEB_PORT` | `18000` | 宿主机访问端口 |
| `APP_DOCKER_NETWORK` | `dnmp-infra` | Docker 外部网络 |
| `STORAGE_BACKEND` | `postgres` | 存储后端：`json` / `sqlite` / `postgres` / `git` |
| `DATABASE_URL` | `postgresql://root:123456@PostgreSQL:5432/ai2api` | PostgreSQL / SQLite 连接地址 |

> 说明：环境变量名暂时保留 `CHATGPT2API_*`，这是为了兼容当前代码和已有配置。

## 首次启动

当前默认依赖 dnmp 的 PostgreSQL 容器，数据库连接为：

```text
postgresql://root:123456@PostgreSQL:5432/ai2api
```

在项目根目录执行：

```bash
docker network create dnmp-infra || true

# 确保 PostgreSQL 已有 ai2api 数据库；已存在时忽略错误即可。
docker exec PostgreSQL sh -lc 'createdb -U root ai2api 2>/dev/null || true'

docker compose -f docker-compose.mount.yml build app

docker compose -f docker-compose.mount.yml run --rm web-build

docker compose -f docker-compose.mount.yml up -d app
```

检查状态：

```bash
docker compose -f docker-compose.mount.yml ps
curl "$AI2API_BASE_URL/version"
```

登录验证：

```bash
curl -X POST "$AI2API_BASE_URL/auth/login" \
  -H 'Authorization: Bearer chatgpt2api'
```

## 日常更新

只改 Python 后端代码：

```bash
docker compose -f docker-compose.mount.yml restart app
```

改了前端代码：

```bash
docker compose -f docker-compose.mount.yml run --rm web-build
docker compose -f docker-compose.mount.yml restart app
```

改了 Python 依赖文件 `pyproject.toml` / `uv.lock`：

```bash
docker compose -f docker-compose.mount.yml build app
docker compose -f docker-compose.mount.yml up -d app
```

改了前端依赖文件 `web/package.json` / `web/bun.lock`：

```bash
docker compose -f docker-compose.mount.yml run --rm web-build
docker compose -f docker-compose.mount.yml restart app
```

## 前端构建

推荐使用 compose 内置的 Bun 工具容器：

```bash
docker compose -f docker-compose.mount.yml run --rm web-build
```

该命令会在 `web/` 下执行：

```bash
bun install --frozen-lockfile
bun run build
```

构建产物输出到：

```text
web/out
```

后端容器会把它挂载到：

```text
/app/web_dist
```

如果没有 `web/out`，API 可以启动，但 Web 页面可能返回 404。

## dnmp nginx

当前 dnmp nginx 配置文件：

```text
/opt/dnmp_other/services/nginx/conf.d/ai2api.conf
```

当前反代目标：

```text
ai2api-local:80
```

修改 nginx 配置后验证并重载：

```bash
docker exec nginx nginx -t
docker exec nginx nginx -s reload
```

## API 使用

所有受保护接口都需要：

```http
Authorization: Bearer <auth-key>
```

### 查看模型

```bash
curl "$AI2API_BASE_URL/v1/models" \
  -H 'Authorization: Bearer chatgpt2api'
```

### 图片生成

```bash
curl "$AI2API_BASE_URL/v1/images/generations" \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer chatgpt2api' \
  -d '{
    "model": "gpt-image-2",
    "prompt": "一只漂浮在太空里的猫",
    "n": 1,
    "response_format": "b64_json"
  }'
```

### 图片编辑

```bash
curl "$AI2API_BASE_URL/v1/images/edits" \
  -H 'Authorization: Bearer chatgpt2api' \
  -F 'model=gpt-image-2' \
  -F 'prompt=把这张图改成赛博朋克夜景风格' \
  -F 'n=1' \
  -F 'image=@./input.png'
```

## 存储后端

通过 `STORAGE_BACKEND` 切换存储方式：

- `json`：本地 JSON 文件
- `sqlite`：本地 SQLite 数据库
- `postgres`：PostgreSQL，当前本地默认使用 dnmp 的 PostgreSQL 容器
- `git`：Git 私有仓库，需要配置 `GIT_REPO_URL` 和 `GIT_TOKEN`

PostgreSQL 示例：

```env
STORAGE_BACKEND=postgres
DATABASE_URL=postgresql://root:123456@PostgreSQL:5432/ai2api
```

如果要临时切回 SQLite：

```env
STORAGE_BACKEND=sqlite
DATABASE_URL=sqlite:////app/data/accounts.db
```

## 常用排查命令

查看容器和端口：

```bash
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
ss -ltnp
```

查看日志：

```bash
docker logs -f ai2api-local
```

检查 compose 配置：

```bash
docker compose -f docker-compose.mount.yml config
docker compose -f docker-compose.local.yml config
```

检查 nginx：

```bash
docker exec nginx nginx -t
docker exec nginx nginx -T | grep -n ai2api -A40 -B5
```

## 备注

- 推荐优先使用 `docker-compose.mount.yml`。
- 当前默认存储为 PostgreSQL：`postgresql://root:123456@PostgreSQL:5432/ai2api`。
- `docker-compose.local.yml` 适合需要完整镜像交付时使用。
- 不建议提交 `web/node_modules`、`web/out`、`.venv` 等本地生成目录。
- 本地 `.venv/` 不是 Docker 部署必需项。
