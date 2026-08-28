# deploy/elixir/loadtest/Dockerfile
# 压测 Release 镜像（独立于 IM）。构建上下文：仓库根目录
# docker build -f deploy/elixir/loadtest/Dockerfile -t im-loadtest:local .

FROM elixir:1.19.5-otp-28 AS build

RUN apt-get update -y && apt-get install -y build-essential git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod

COPY apps/elixir/im_proto /app/apps/elixir/im_proto
COPY apps/elixir/im_client /app/apps/elixir/im_client
COPY apps/elixir/loadtest/mix.exs apps/elixir/loadtest/mix.lock* /app/apps/elixir/loadtest/

WORKDIR /app/apps/elixir/loadtest
RUN mix local.hex --force && mix local.rebar --force
RUN mix deps.get --only prod
RUN mix deps.compile

COPY apps/elixir/loadtest/config config
COPY apps/elixir/loadtest/lib lib
COPY apps/elixir/loadtest/rel rel

RUN mix compile
RUN mix release
RUN chmod +x /app/apps/elixir/loadtest/_build/prod/rel/loadtest/bin/run_loadtest || true

FROM debian:trixie-slim AS runtime

RUN apt-get update -y && apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN chown nobody:nogroup /app
USER nobody:nogroup

ENV HOME=/app
ENV LANG=C.UTF-8

COPY --from=build --chown=nobody:nogroup /app/apps/elixir/loadtest/_build/prod/rel/loadtest ./

ENTRYPOINT ["/app/bin/run_loadtest"]
