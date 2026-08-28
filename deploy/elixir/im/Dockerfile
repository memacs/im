# deploy/elixir/im/Dockerfile
# IM Release 镜像 — 与线上构建一致（elixir:1.19.5-otp-28 多阶段；OTP ≥ 28.1，见根目录 mise.toml）
# 构建上下文：仓库根目录
# 本地：docker build -f deploy/elixir/im/Dockerfile -t im:local .
# 部署：kubectl apply -k deploy/elixir/im/k8s/overlays/local/

# ---------- build：编译 Release ----------
FROM elixir:1.19.5-otp-28 AS build

RUN apt-get update -y && apt-get install -y build-essential git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /apps/elixir/im

ENV MIX_ENV=prod

# path 依赖 im_proto 须与 mix.exs 相对路径一致（../im_proto）
COPY apps/elixir/im_proto /apps/elixir/im_proto
COPY apps/elixir/im/mix.exs apps/elixir/im/mix.lock ./
RUN mix local.hex --force && mix local.rebar --force
RUN mix deps.get --only prod
RUN mix deps.compile

COPY apps/elixir/im/config config
# Pb 生成物在 im_proto；im/lib 仅手写业务代码
COPY apps/elixir/im/lib lib
COPY apps/elixir/im/priv priv
# rel/overlays 提供 bin/migrate（Release 内执行 Ecto 迁移）
COPY apps/elixir/im/rel rel

RUN mix compile
RUN mix release

# ---------- runtime：最小运行镜像 ----------
# 必须与 build 阶段同一 Debian 版本：elixir:1.19.5-otp-28 基于 trixie(glibc 2.41)，
# 打包进 Release 的 ERTS 需要 GLIBC_2.38，在 bookworm(glibc 2.36) 上会启动失败。
FROM debian:trixie-slim AS runtime

RUN apt-get update -y && apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN chown nobody:nogroup /app
USER nobody:nogroup

ENV HOME=/app
ENV LANG=C.UTF-8

COPY --from=build --chown=nobody:nogroup /apps/elixir/im/_build/prod/rel/im ./

EXPOSE 4000

CMD ["/app/bin/im", "start"]
