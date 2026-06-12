# syntax=docker/dockerfile:1

FROM oven/bun:1.3.13 AS web-build

WORKDIR /app/web

COPY web/package.json web/bun.lock ./
RUN --mount=type=cache,target=/root/.bun/install/cache \
    bun install --frozen-lockfile --cache-dir=/root/.bun/install/cache

COPY VERSION /app/VERSION
COPY CHANGELOG.md /app/CHANGELOG.md
COPY web ./
RUN NEXT_PUBLIC_APP_VERSION="$(cat /app/VERSION)" bun run build


FROM python:3.13-slim AS runtime-deps

ARG DEBIAN_MIRROR=http://mirrors.tuna.tsinghua.edu.cn/debian
ARG DEBIAN_SECURITY_MIRROR=http://mirrors.tuna.tsinghua.edu.cn/debian-security
ARG PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_LINK_MODE=copy

WORKDIR /app

# 安装系统依赖
# - git: Git 存储后端需要
# - libpq-dev: PostgreSQL 客户端库
# - gcc: 编译 psycopg2-binary 需要
RUN if [ -n "$DEBIAN_SECURITY_MIRROR" ]; then \
      sed -i "s|http://deb.debian.org/debian-security|$DEBIAN_SECURITY_MIRROR|g; s|https://deb.debian.org/debian-security|$DEBIAN_SECURITY_MIRROR|g" \
        /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null || true; \
    fi && \
    if [ -n "$DEBIAN_MIRROR" ]; then \
      sed -i "s|http://deb.debian.org/debian|$DEBIAN_MIRROR|g; s|https://deb.debian.org/debian|$DEBIAN_MIRROR|g" \
        /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null || true; \
    fi && \
    apt-get update && apt-get install -y --no-install-recommends \
    git \
    libpq-dev \
    gcc \
    openssl \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir -i "$PIP_INDEX_URL" uv

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

EXPOSE 80

CMD ["uv", "run", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "80", "--access-log"]


FROM runtime-deps AS app

COPY main.py ./
COPY config.json ./
COPY VERSION ./
COPY api ./api
COPY services ./services
COPY utils ./utils
COPY scripts ./scripts
COPY --from=web-build /app/web/out ./web_dist
