# AGENTS.md

本文档用于约束本项目中的 AI / 自动化开发行为，并记录当前推荐的本地 Docker 部署方式。

## 基本原则

- 先读现有代码和配置，再修改；优先沿用项目已有结构。
- 改动保持小而直接，不做无关重构。
- 不要回滚或覆盖用户已有改动。
- 除非用户明确要求，不要自行提交 git commit。
- 涉及 Docker 构建时，优先说明将执行的命令；全量构建可能较慢，不要无意义反复重建。

## 项目结构

- 后端：Python 3.13 + FastAPI，入口 `main.py`。
- API 路由：`api/`。
- 业务服务：`services/`。
- 工具代码：`utils/`。
- 前端：`web/`，Next.js 静态导出，构建产物为 `web/out`。
- 容器内前端静态目录：`/app/web_dist`。

## Docker 部署模式

本项目当前推荐小项目部署方式是：

> Docker 镜像只负责运行环境和依赖，宿主机代码通过 volume 挂载进容器。

使用文件：

```bash
docker-compose.mount.yml
```

这个模式下：

- 改 Python 后端代码后，不需要重新 build，只需要重启容器。
- 改前端代码后，不需要重新 build 镜像，但需要重新生成 `web/out`。
- 改 Python 依赖文件 `pyproject.toml` / `uv.lock` 后，需要重新 build 环境镜像。
- 改前端依赖文件 `web/package.json` / `web/bun.lock` 后，需要重新安装前端依赖并重新构建前端。

完整打包镜像仍保留：

```bash
docker-compose.local.yml
```

它会把代码和前端构建产物都打进镜像，适合需要完整镜像交付时使用。

当前默认存储后端为 PostgreSQL，连接 dnmp 网络内的 `PostgreSQL` 容器：

```text
STORAGE_BACKEND=postgres
DATABASE_URL=postgresql://root:123456@PostgreSQL:5432/ai2api
```

## 端口

默认宿主机端口为：

```text
18000
```

访问：

```text
${AI2API_BASE_URL:-http://127.0.0.1:18000}
```

如果需要临时换端口：

```bash
WEB_PORT=18001 docker compose -f docker-compose.mount.yml up -d app
```

## 第一次启动

在项目根目录执行：

```bash
cp .env.example .env

docker network create dnmp-infra || true

# 确保 dnmp PostgreSQL 中存在 ai2api 数据库；已存在时忽略错误。
docker exec PostgreSQL sh -lc 'createdb -U root ai2api 2>/dev/null || true'

docker compose -f docker-compose.mount.yml build app

docker compose -f docker-compose.mount.yml run --rm web-build

docker compose -f docker-compose.mount.yml up -d app
```

验证：

```bash
curl ${AI2API_BASE_URL:-http://127.0.0.1:18000}/version
```

默认密钥来自 `.env` 的 `CHATGPT2API_AUTH_KEY`，示例值为：

```text
chatgpt2api
```

登录验证：

```bash
curl -X POST ${AI2API_BASE_URL:-http://127.0.0.1:18000}/auth/login \
  -H 'Authorization: Bearer chatgpt2api'
```

## 前端构建命令说明

推荐命令：

```bash
docker compose -f docker-compose.mount.yml run --rm web-build
```

用途：在 Compose 定义的临时 Bun 工具容器中构建前端静态文件。

含义：

- `run --rm web-build`：启动一次 `web-build` 工具容器，执行完自动删除。
- `web-build` 使用固定镜像 `oven/bun:1.3.13`。
- `web-build` 把当前项目目录挂到容器 `/src`。
- `web-build` 的工作目录是 `/src/web`。
- `bun install --frozen-lockfile`：按 `bun.lock` 安装前端依赖。
- `bun run build`：生成 Next.js 静态导出到 `web/out`。
- `bun-cache` volume 用于缓存 Bun 下载包，加快后续构建。

`docker-compose.mount.yml` 会把宿主机 `./web/out` 挂载到容器 `/app/web_dist`，后端由 FastAPI 托管这些静态文件。没有 `web/out` 时，API 可以启动，但页面可能返回 404。

如果宿主机已经安装 Bun，也可以直接执行：

```bash
cd web
bun install
bun run build
```

## 日常更新

只改后端 Python 代码：

```bash
git pull
docker compose -f docker-compose.mount.yml restart app
```

改了前端代码：

```bash
git pull
docker compose -f docker-compose.mount.yml run --rm web-build
docker compose -f docker-compose.mount.yml restart app
```

改了 Python 依赖：

```bash
git pull
docker compose -f docker-compose.mount.yml build app
docker compose -f docker-compose.mount.yml up -d app
```

## 本地 `.venv`

如果主要使用 Docker 运行，本地 `.venv/` 不需要保留。

原因：

- 容器内会有自己的 `/app/.venv`。
- `.dockerignore` 已忽略宿主机 `.venv`。
- `docker-compose.mount.yml` 不会挂载宿主机 `.venv`。

只有需要宿主机直接运行 `uv run main.py` 时，才需要本地 `.venv`。

## Agent 注意事项

- 查看运行端口时使用：

  ```bash
  docker ps --format 'table {{.Names}}\t{{.Ports}}'
  ss -ltnp
  ```

- 默认不要建议推 TCR；本项目当前小规模部署优先使用本机构建 + volume 挂载。
- 注册任务在 `platform authorize` 前会用同一个请求 session 打印 `platform authorize 出口IP`，用于确认当次任务实际代理出口。
- 不要把 `web/node_modules`、`web/out`、`.venv` 作为必须提交内容。
- 修改 Docker/compose 后，至少运行：

  ```bash
  docker compose -f docker-compose.mount.yml config
  docker compose -f docker-compose.local.yml config
  ```

- 如果要证明完整镜像可用，再执行实际 build/up；但全量构建较慢，执行前先确认用户同意。
