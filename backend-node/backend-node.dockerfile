# (c) Cartesi and individual authors (see AUTHORS)
# SPDX-License-Identifier: Apache-2.0 (see LICENSE)

# syntax=docker.io/docker/dockerfile:1

ARG EMULATOR_VERSION=0.19.0
ARG S6_OVERLAY_VERSION=3.2.0.2
ARG TELEGRAF_VERSION=1.32.1
ARG HLGRAPHQL_VERSION=2.3.13
ARG TRAEFIK_VERSION=3.2.0
ARG GOVERSION=1.24.4
ARG GO_BUILD_PATH=/build/cartesi/go
ARG ROLLUPSNODE_VERSION=2.0.0-alpha.6
ARG ROLLUPSNODE_BRANCH=fix/handle-http-on-chunked-filter-logs
ARG ROLLUPSNODE_DIR=rollups-node
ARG ROLLUPSNODE_ACCEPT_DAVE_PATCH=https://gist.githubusercontent.com/lynoferraz/122bf63fdc23737a6bf00a1667799f1d/raw/6632b721934eec8902f9bcd53e9686f4c96b836b/node_accept_dave_consensus-v2.0.0-alpha.6.patch
ARG ESPRESSOREADER_VERSION=0.4.0-1
ARG ESPRESSOREADER_BRANCH=feature/adapt-node-alpha6
ARG ESPRESSOREADER_DIR=rollups-espresso-reader
# ARG ESPRESSO_DEV_NODE_TAG=20250428-dev-node-decaf-pos
ARG ESPRESSO_DEV_NODE_TAG=20250623
ARG GRAPHQL_BRANCH=bugfix/output-constraint-error
ARG GRAPHQL_DIR=rollups-graphql
ARG GRAPHQL_VERSION=2.3.14
ARG PRT_NODE_VERSION=1.0.0
ARG FOUNDRY_DIR=/foundry
ARG FOUNDRY_VERSION=1.2.1

# =============================================================================
# STAGE: node builder
#
# =============================================================================

FROM cartesi/machine-emulator:${EMULATOR_VERSION} AS common-env

USER root

RUN <<EOF
apt update
apt install -y --no-install-recommends \
    build-essential \
    wget ca-certificates \
    git
EOF

USER cartesi

# =============================================================================
# STAGE: foundry-installer
#
# =============================================================================

FROM common-env AS foundry-installer

USER root

RUN <<EOF
apt update
apt install -y --no-install-recommends \
    curl
EOF

# install foundry
ARG FOUNDRY_VERSION
ARG FOUNDRY_DIR
ENV FOUNDRY_DIR=${FOUNDRY_DIR}
RUN mkdir -p ${FOUNDRY_DIR}
RUN curl -L https://foundry.paradigm.xyz | bash
RUN ${FOUNDRY_DIR}/bin/foundryup -i ${FOUNDRY_VERSION}

# =============================================================================
# STAGE: go-installer and projects builder
#
# =============================================================================

FROM common-env AS go-installer

USER root

ARG GOVERSION
ARG TARGETARCH

RUN wget https://go.dev/dl/go${GOVERSION}.linux-${TARGETARCH}.tar.gz && \
    tar -C /usr/local -xzf go${GOVERSION}.linux-${TARGETARCH}.tar.gz

ENV PATH=/usr/local/go/bin:${PATH}

ARG GO_BUILD_PATH
RUN mkdir -p ${GO_BUILD_PATH} && chown -R cartesi:cartesi ${GO_BUILD_PATH}

USER cartesi

FROM go-installer AS go-builder

ARG GO_BUILD_PATH

WORKDIR ${GO_BUILD_PATH}

ENV GOCACHE=${GO_BUILD_PATH}/.cache
ENV GOENV=${GO_BUILD_PATH}/.config/go/env
ENV GOPATH=${GO_BUILD_PATH}/.go

ARG ROLLUPSNODE_VERSION
# ARG ROLLUPSNODE_BRANCH
ARG ROLLUPSNODE_DIR

RUN mkdir ${GO_BUILD_PATH}/${ROLLUPSNODE_DIR}
RUN wget -qO- https://github.com/cartesi/rollups-node/archive/refs/tags/v${ROLLUPSNODE_VERSION}.tar.gz | \
    tar -C ${GO_BUILD_PATH}/${ROLLUPSNODE_DIR} -zxf - --strip-components 1 rollups-node-${ROLLUPSNODE_VERSION}

# Pacth to accept dave consensus events
ARG ROLLUPSNODE_ACCEPT_DAVE_PATCH
ADD --chown=cartesi:cartesi ${ROLLUPSNODE_ACCEPT_DAVE_PATCH} ${GO_BUILD_PATH}/${ROLLUPSNODE_DIR}/accept_dave_events.patch
RUN cd ${GO_BUILD_PATH}/${ROLLUPSNODE_DIR} && \
    patch -p1 < accept_dave_events.patch

# RUN git clone --single-branch --branch ${ROLLUPSNODE_BRANCH} \
#     https://github.com/cartesi/rollups-node.git ${GO_BUILD_PATH}/${ROLLUPSNODE_DIR}

RUN cd ${GO_BUILD_PATH}/${ROLLUPSNODE_DIR} && go mod download
RUN cd ${GO_BUILD_PATH}/${ROLLUPSNODE_DIR} && make build-go

# ARG ESPRESSOREADER_VERSION
# ARG ESPRESSOREADER_DIR
# ARG ESPRESSOREADER_BRANCH

# RUN mkdir ${GO_BUILD_PATH}/${ESPRESSOREADER_DIR}
# RUN wget -qO- https://github.com/cartesi/rollups-espresso-reader/archive/refs/tags/v${ESPRESSOREADER_VERSION}.tar.gz | \
#     tar -C ${GO_BUILD_PATH}/${ESPRESSOREADER_DIR} -zxf - --strip-components 1 rollups-espresso-reader-${ESPRESSOREADER_VERSION}

# RUN wget -q https://github.com/cartesi/rollups-espresso-reader/releases/download/v${ESPRESSOREADER_VERSION}/cartesi-rollups-espresso-reader \
#     -O ${GO_BUILD_PATH}/${ESPRESSOREADER_DIR}/cartesi-rollups-espresso-reader

# RUN git clone --single-branch --branch ${ESPRESSOREADER_BRANCH} \
#     https://github.com/cartesi/rollups-espresso-reader.git ${GO_BUILD_PATH}/${ESPRESSOREADER_DIR}

# RUN cd ${GO_BUILD_PATH}/${ESPRESSOREADER_DIR} && go mod download
# RUN cd ${GO_BUILD_PATH}/${ESPRESSOREADER_DIR} && \
#     go build -o cartesi-rollups-espresso-reader && \
#     go build -o cartesi-rollups-espresso-reader-db-migration dev/migrate/main.go


# ARG GRAPHQL_VERSION
# ARG GRAPHQL_BRANCH
# ARG GRAPHQL_DIR

# RUN mkdir ${GO_BUILD_PATH}/${GRAPHQL_DIR}
# RUN wget -qO- https://github.com/cartesi/rollups-graphql/releases/download/v${GRAPHQL_VERSION}/cartesi-rollups-graphql-v${GRAPHQL_VERSION}-linux-${TARGETARCH}.tar.gz | \
#     tar -C ${GO_BUILD_PATH}/${GRAPHQL_DIR} -zxf - cartesi-rollups-graphql

# RUN git clone --single-branch --branch ${GRAPHQL_BRANCH} \
#     https://github.com/cartesi/rollups-graphql.git ${GO_BUILD_PATH}/${GRAPHQL_DIR}

# RUN cd ${GO_BUILD_PATH}/${GRAPHQL_DIR} && go mod download
# RUN cd ${GO_BUILD_PATH}/${GRAPHQL_DIR} && \
#     go build -o cartesi-rollups-graphql


# =============================================================================
# STAGE: base-rollups-node-we
#
# =============================================================================

# https://github.com/EspressoSystems/espresso-sequencer/pkgs/container/espresso-sequencer%2Fespresso-dev-node
FROM ghcr.io/espressosystems/espresso-sequencer/espresso-dev-node:${ESPRESSO_DEV_NODE_TAG} AS espresso-dev-node

# FROM docker.io/library/debian:bookworm-20250428-slim@sha256:4b50eb66f977b4062683ff434ef18ac191da862dbe966961bc11990cf5791a8d AS base-rollups-node-we
# FROM ghcr.io/espressosystems/ubuntu-base:main AS base-rollups-node-we
# FROM postgres:17-bookworm AS base-rollups-node-we
# FROM cartesi/machine-emulator:${EMULATOR_VERSION} AS base-rollups-node-we
FROM ubuntu:24.04 AS base-rollups-node-we

ARG BASE_PATH=/mnt
ENV BASE_PATH=${BASE_PATH}

ENV SNAPSHOTS_APPS_PATH=${BASE_PATH}/apps
ENV NODE_PATH=${BASE_PATH}/node
ENV ESPRESSO_PATH=${BASE_PATH}/espresso
ENV DAVE_PATH=${BASE_PATH}/dave

RUN useradd --user-group cartesi

# Download system dependencies required at runtime.
ARG DEBIAN_FRONTEND=noninteractive
RUN <<EOF
    set -e
    apt-get update
    apt-get install -y --no-install-recommends \
        ca-certificates curl procps \
        xz-utils nginx postgresql-client \
        lua5.4 libslirp0 libglib2.0-0 libc6 \
        postgresql-client jq xxd
    rm -rf /var/lib/apt/lists/* /var/log/* /var/cache/*
    mkdir -p ${NODE_PATH}/snapshots ${NODE_PATH}/data ${ESPRESSO_PATH}
    chown -R cartesi:cartesi ${NODE_PATH}
EOF

ARG TARGETARCH

# install s6 overlay
ARG S6_OVERLAY_VERSION
RUN curl -s -L https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz | \
    tar xJf - -C /
RUN curl -s -L https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-$(uname -m).tar.xz | \
    tar xJf - -C /

# install telegraf
ARG TELEGRAF_VERSION
RUN curl -s -L https://dl.influxdata.com/telegraf/releases/telegraf-${TELEGRAF_VERSION}_linux_${TARGETARCH}.tar.gz | \
    tar xzf - --strip-components 2 -C / ./telegraf-${TELEGRAF_VERSION}

# curl -s -L -o /tmp/cartesi-machine.deb https://github.com/cartesi/machine-emulator/releases/download/v${EMULATOR_VERSION}${EMULATOR_VERSION_SUFFIX}/cartesi-machine-v${EMULATOR_VERSION}_${TARGETARCH}.deb
ARG EMULATOR_VERSION
RUN <<EOF
set -e
curl -s -L -o /tmp/cartesi-machine.deb https://github.com/cartesi/machine-emulator/releases/download/v${EMULATOR_VERSION}/machine-emulator_${TARGETARCH}.deb
dpkg -i /tmp/cartesi-machine.deb
rm /tmp/cartesi-machine.deb
EOF

# install cartesi-rollups
# ARG ROLLUPSNODE_VERSION
# RUN <<EOF
# set -e
# curl -s -L -o /tmp/cartesi-rollups-node.deb https://github.com/cartesi/rollups-node/releases/download/v${ROLLUPSNODE_VERSION}/cartesi-rollups-node-v${ROLLUPSNODE_VERSION}_${TARGETARCH}.deb
# dpkg -i /tmp/cartesi-rollups-node.deb
# rm /tmp/cartesi-rollups-node.deb
# EOF

# install cartesi-rollups-graphql
ARG ESPRESSOREADER_VERSION
RUN curl -s -L https://github.com/cartesi/rollups-espresso-reader/releases/download/v${ESPRESSOREADER_VERSION}/cartesi-rollups-espresso-reader-v${ESPRESSOREADER_VERSION}-linux-${TARGETARCH}.tar.gz | \
    tar xzf - -C /usr/local/bin cartesi-rollups-espresso-reader
RUN curl -s -L https://github.com/cartesi/rollups-espresso-reader/releases/download/v${ESPRESSOREADER_VERSION}/cartesi-rollups-espresso-reader-db-migration-v${ESPRESSOREADER_VERSION}-linux-${TARGETARCH}.tar.gz | \
    tar xzf - -C /usr/local/bin cartesi-rollups-espresso-reader-db-migration

# install cartesi-rollups-graphql
ARG GRAPHQL_VERSION
RUN curl -s -L https://github.com/cartesi/rollups-graphql/releases/download/v${GRAPHQL_VERSION}/cartesi-rollups-graphql-v${GRAPHQL_VERSION}-linux-${TARGETARCH}.tar.gz | \
    tar xzf - -C /usr/local/bin cartesi-rollups-graphql

# install cartesi-rollups-prt-node
ARG PRT_NODE_VERSION
RUN curl -s -L https://github.com/cartesi/dave/releases/download/v${PRT_NODE_VERSION}/cartesi-rollups-prt-node-Linux-gnu-$(x=$TARGETARCH; [ $TARGETARCH = amd64 ] && x=x86_64; echo $x).tar.gz | \
    tar xzf - -C /usr/local/bin cartesi-rollups-prt-node

# # Copy Go binary.
ARG GO_BUILD_PATH
ARG ROLLUPSNODE_DIR
# ARG ESPRESSOREADER_DIR
# ARG GRAPHQL_DIR
COPY --from=go-builder ${GO_BUILD_PATH}/${ROLLUPSNODE_DIR}/cartesi-rollups-* /usr/bin
# COPY --from=go-builder ${GO_BUILD_PATH}/${ESPRESSOREADER_DIR}/cartesi-rollups-* /usr/bin
# COPY --from=go-builder ${GO_BUILD_PATH}/${cartesi-rollups-graphql}/cartesi-rollups-* /usr/bin

# Install espresso
COPY --from=espresso-dev-node /usr/bin/espresso-dev-node /usr/local/bin/

# install foundry
ARG FOUNDRY_DIR
COPY --from=foundry-installer ${FOUNDRY_DIR}/bin/* /usr/local/bin/

RUN mkdir -p /etc/s6-overlay/s6-rc.d/user/contents.d

################################################################################
# Env variables
ARG CARTESI_INSPECT_PORT=10012
ENV CARTESI_INSPECT_PORT=${CARTESI_INSPECT_PORT}
ENV CARTESI_INSPECT_ADDRESS=localhost:${CARTESI_INSPECT_PORT}
ARG CARTESI_JSONRPC_API_PORT=10011
ENV CARTESI_JSONRPC_API_PORT=${CARTESI_JSONRPC_API_PORT}
ENV CARTESI_JSONRPC_API_ADDRESS=localhost:${CARTESI_JSONRPC_API_PORT}
ARG ESPRESSO_SERVICE_PORT=10030
ENV ESPRESSO_SERVICE_PORT=${ESPRESSO_SERVICE_PORT}
ARG ESPRESSO_SERVICE_ENDPOINT=localhost:${ESPRESSO_SERVICE_PORT}
ENV ESPRESSO_SERVICE_ENDPOINT=${ESPRESSO_SERVICE_ENDPOINT}
ARG GRAPHQL_PORT=10020
ENV GRAPHQL_PORT=${GRAPHQL_PORT}
ENV CARTESI_SNAPSHOTS_DIR=${NODE_PATH}/snapshots

ENV NODE_DB=rollupsdb
ENV GRAPHQL_DB=hlgraphql
ENV ESPRESSONODE_DB=sequencer
ENV ACTIVATE_CARTESI_NODE=true
ENV ACTIVATE_ESPRESSO_DEV_NODE=false

ENV AZTEC_SRS_PATH=/kzg10-aztec20-srs-1048584.bin

################################################################################
# configure telegraf
RUN mkdir -p /etc/telegraf
COPY <<EOF /etc/telegraf/telegraf.conf
[agent]
    interval = '60s'
    round_interval = true
    metric_batch_size = 1000
    metric_buffer_limit = 10000
    collection_jitter = '0s'
    flush_interval = '60s'
    flush_jitter = '0s'
    precision = '1ms'
    omit_hostname = true

[[inputs.processes]]

[[inputs.procstat]]

[[outputs.health]]
    service_address = 'http://:9274'

[[inputs.procstat.filter]]
    name = 'rollups-node'
    process_names = ['cartesi-rollups-*', 'jsonrpc-remote-cartesi-*', '*cartesi*', 'telegraf', 'cartesi-rollups-graphql', 'nginx']

[[inputs.prometheus]]
    urls = ["http://localhost:10001","http://localhost:10002","http://localhost:10003","http://localhost:10004"]

[[outputs.prometheus_client]]
    listen = ':9000'
    collectors_exclude = ['process']
EOF

# Configure s6 Telegraf
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/telegraf/data
echo "longrun" > /etc/s6-overlay/s6-rc.d/telegraf/type
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/telegraf/data/check
#!/command/execlineb -P
wget -qO /dev/null 127.0.0.1:9274/
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/telegraf/run
#!/command/execlineb -P
pipeline -w { sed --unbuffered "s/^/telegraf: /" }
fdmove -c 2 1
/usr/bin/telegraf
EOF

################################################################################
# Configure nginx
RUN <<EOF
mkdir -p /var/log/nginx/
chown -R cartesi:cartesi /var/log/nginx/
mkdir -p /var/cache
chown -R cartesi:cartesi /var/cache
chown -R cartesi:cartesi /var/lib/nginx
EOF

COPY <<EOF /etc/nginx/nginx.conf
user cartesi;
worker_processes  auto;

error_log  /var/log/nginx/error.log notice;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '\$remote_addr - \$upstream_cache_status rt=\$request_time [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for" '
                      'uct="\$upstream_connect_time" uht="\$upstream_header_time" urt="\$upstream_response_time"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    keepalive_timeout  65;

    #gzip  on;

    map \$request_method \$purge_method {
        PURGE 1;
        default 0;
    }

    proxy_cache_path /var/cache keys_zone=mycache:200m;

    include /etc/nginx/sites-enabled/*;
}
EOF

# Configure nginx server with cache
COPY --chmod=755 <<EOF /etc/nginx/sites-available/cloud.conf
server {
    listen       80;
    listen  [::]:80;

    proxy_cache mycache;

    location /graphql {
        proxy_pass   http://localhost:${GRAPHQL_PORT}/graphql;
    }

    location /nonce {
        proxy_pass   http://localhost:${ESPRESSO_SERVICE_PORT}/nonce;
    }

    location /submit {
        proxy_pass   http://localhost:${ESPRESSO_SERVICE_PORT}/submit;
    }

    location /inspect {
        proxy_pass   http://localhost:${CARTESI_INSPECT_PORT}/inspect;
        proxy_cache_valid 200 5s;
        proxy_cache_background_update on;
        proxy_cache_use_stale error timeout updating http_500 http_502
                              http_503 http_504;
        proxy_cache_lock on;

        proxy_read_timeout 300s;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
    }

    location /rpc {
        proxy_pass   http://localhost:${CARTESI_JSONRPC_API_ADDRESS}/rpc;
        proxy_cache_valid 200 1s;
        proxy_cache_background_update on;
        proxy_cache_use_stale error timeout updating http_500 http_502
                              http_503 http_504;
        proxy_cache_lock on;

        proxy_read_timeout 300s;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
    }

    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }
}
EOF

# Configure nginx server without cache
COPY --chmod=755 <<EOF /etc/nginx/sites-available/node.conf
server {
    listen       80;
    listen  [::]:80;

    location /graphql {
        proxy_pass   http://localhost:${GRAPHQL_PORT}/graphql;
    }

    location /nonce {
        proxy_pass   http://localhost:${ESPRESSO_SERVICE_PORT}/nonce;
    }

    location /submit {
        proxy_pass   http://localhost:${ESPRESSO_SERVICE_PORT}/submit;
    }

    location /inspect {
        proxy_pass   http://localhost:${CARTESI_INSPECT_PORT}/inspect;
    }

    location /rpc {
        proxy_pass   http://localhost:${CARTESI_JSONRPC_API_PORT}/rpc;
    }

    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }
}
EOF

RUN rm /etc/nginx/sites-enabled/*
RUN chown -R cartesi:cartesi /etc/nginx/sites-enabled

# Configure s6 nginx
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/nginx
echo "longrun" > /etc/s6-overlay/s6-rc.d/nginx/type
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/nginx/run
#!/command/execlineb -P
pipeline -w { sed --unbuffered "s/^/nginx: /" }
fdmove -c 2 1
/usr/sbin/nginx -g "daemon off;"
EOF

################################################################################
# Configure s6 create dir
RUN <<EOF
mkdir -p ${BASE_PATH}
chown -R cartesi:cartesi ${BASE_PATH}
mkdir -p /etc/s6-overlay/s6-rc.d/prepare-dirs
echo "oneshot" > /etc/s6-overlay/s6-rc.d/prepare-dirs/type
EOF

COPY --chmod=755 <<EOF /etc/s6-overlay/s6-rc.d/prepare-dirs/run.sh
#!/command/with-contenv sh
mkdir -p "${SNAPSHOTS_APPS_PATH}"
mkdir -p "${NODE_PATH}"/snapshots
mkdir -p "${NODE_PATH}"/data
mkdir -p "${ESPRESSO_PATH}"
mkdir -p "${DAVE_PATH}"/snapshots
mkdir -p "${DAVE_PATH}"/states
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/prepare-dirs/up
/etc/s6-overlay/s6-rc.d/prepare-dirs/run.sh
EOF

################################################################################
# Configure s6 migrate
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/migrate
echo "oneshot" > /etc/s6-overlay/s6-rc.d/migrate/type
EOF

COPY --chmod=755 <<EOF /etc/s6-overlay/s6-rc.d/migrate/run.sh
#!/command/with-contenv sh
cartesi-rollups-cli db init
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/migrate/up
/etc/s6-overlay/s6-rc.d/migrate/run.sh
EOF

################################################################################
# Configure s6 create hl db
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/createhlgdb/dependencies.d
touch /etc/s6-overlay/s6-rc.d/createhlgdb/dependencies.d/migrate
echo "oneshot" > /etc/s6-overlay/s6-rc.d/createhlgdb/type
EOF

COPY --chmod=755 <<EOF /etc/s6-overlay/s6-rc.d/createhlgdb/run.sh
#!/command/with-contenv bash
psql \${CARTESI_DATABASE_CONNECTION} -c "create database \${GRAPHQL_DB};" && echo "HLGraphql database created!" || echo "HLGraphql database alredy created"
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/createhlgdb/up
/etc/s6-overlay/s6-rc.d/createhlgdb/run.sh
EOF

################################################################################
# Configure s6 evm-reader
ENV EVMREADER_ENVFILE=${NODE_PATH}/evmreader-envs

RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/define-evmreader-envs/dependencies.d
touch /etc/s6-overlay/s6-rc.d/define-evmreader-envs/dependencies.d/prepare-dirs
echo "oneshot" > /etc/s6-overlay/s6-rc.d/define-evmreader-envs/type
EOF

COPY --chmod=755 <<EOF /etc/s6-overlay/s6-rc.d/define-evmreader-envs/run.sh
#!/command/with-contenv sh
if [ \${MAIN_SEQUENCER} = espresso ]; then
    echo "CARTESI_FEATURE_INPUT_READER_ENABLED=false" > \${EVMREADER_ENVFILE}
else
    echo "CARTESI_FEATURE_INPUT_READER_ENABLED=true" > \${EVMREADER_ENVFILE}
fi
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/define-evmreader-envs/up
/etc/s6-overlay/s6-rc.d/define-evmreader-envs/run.sh
EOF


RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/evm-reader/dependencies.d
touch /etc/s6-overlay/s6-rc.d/evm-reader/dependencies.d/prepare-dirs \
    /etc/s6-overlay/s6-rc.d/evm-reader/dependencies.d/migrate \
    /etc/s6-overlay/s6-rc.d/evm-reader/dependencies.d/define-evmreader-envs
echo "longrun" > /etc/s6-overlay/s6-rc.d/evm-reader/type
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/evm-reader/run
#!/command/execlineb -P
with-contenv
pipeline -w { sed --unbuffered "s/^/evm-reader: /" }
fdmove -c 2 1
importas -S EVMREADER_ENVFILE
envfile \${EVMREADER_ENVFILE}
cartesi-rollups-evm-reader
EOF

################################################################################
# Configure s6 create espresso db
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/createespressonodedb
echo "oneshot" > /etc/s6-overlay/s6-rc.d/createespressonodedb/type
EOF

COPY --chmod=755 <<EOF /etc/s6-overlay/s6-rc.d/createespressonodedb/run.sh
#!/command/with-contenv bash
psql \${CARTESI_DATABASE_CONNECTION} -c "create database \${ESPRESSONODE_DB};" && echo "Espresso node database created!" || echo "Espresso node database alredy created"
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/createespressonodedb/up
/etc/s6-overlay/s6-rc.d/createespressonodedb/run.sh
EOF

################################################################################
# Configure s6 espresso dev node

ENV ESPRESSO_ENVFILE=${NODE_PATH}/espresso-envs

RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/define-espresso-envs/dependencies.d
touch /etc/s6-overlay/s6-rc.d/define-espresso-envs/dependencies.d/prepare-dirs
echo "oneshot" > /etc/s6-overlay/s6-rc.d/define-espresso-envs/type
EOF

COPY --chmod=755 <<EOF /etc/s6-overlay/s6-rc.d/define-espresso-envs/run.sh
#!/command/with-contenv sh
# echo "POSTGRES_ESPRESSO_DB_URL=\${CARTESI_DATABASE_CONNECTION}" > \${ESPRESSO_ENVFILE}
# sed -i -e "s/\${NODE_DB}/\${ESPRESSONODE_DB}/" \${ESPRESSO_ENVFILE}
# sed -i -e "s/?sslmode=disable//" \${ESPRESSO_ENVFILE}
echo "ESPRESSONODE_RUST_LOG=\${CARTESI_LOG_LEVEL}" >> \${ESPRESSO_ENVFILE}
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/define-espresso-envs/up
/etc/s6-overlay/s6-rc.d/define-espresso-envs/run.sh
EOF


RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/espresso-node/dependencies.d
touch /etc/s6-overlay/s6-rc.d/espresso-node/dependencies.d/createespressonodedb \
    /etc/s6-overlay/s6-rc.d/espresso-node/dependencies.d/define-espresso-envs
echo "longrun" > /etc/s6-overlay/s6-rc.d/espresso-node/type
mkdir -p /etc/s6-overlay/s6-rc.d/espresso-node/data
EOF

RUN curl -sLO https://github.com/EspressoSystems/ark-srs/releases/download/v0.2.0/$AZTEC_SRS_PATH

COPY <<EOF /etc/s6-overlay/s6-rc.d/espresso-node/run
#!/command/execlineb -P
with-contenv
pipeline -w { sed --unbuffered "s/^/espresso-node: /" }
fdmove -c 2 1
importas -S ESPRESSO_ENVFILE
envfile \${ESPRESSO_ENVFILE}
multisubstitute {
    # importas -S POSTGRES_ESPRESSO_DB_URL
    importas -S ESPRESSONODE_RUST_LOG
}
# foreground {
#     echo 'RUST_LOG=\${ESPRESSONODE_RUST_LOG} espresso-dev-node \${POSTGRES_ESPRESSO_DB_URL} \${ESPRESSONODE_EXTRA_FLAGS}'
# }
export RUST_LOG \${ESPRESSONODE_RUST_LOG}
s6-notifyoncheck -s 2000 -w 1000 -t 500 -n 10
espresso-dev-node
EOF
# espresso-dev-node \${POSTGRES_ESPRESSO_DB_URL}

COPY --chmod=755 <<EOF /etc/s6-overlay/s6-rc.d/espresso-node/data/check
#!/command/execlineb -P
with-contenv
multisubstitute {
    importas -S ESPRESSO_SEQUENCER_API_PORT
}
foreground {
    echo "Check espresso node at http://localhost:\${ESPRESSO_SEQUENCER_API_PORT}/v0/status/block-height"
}
curl --silent --fail http://localhost:\${ESPRESSO_SEQUENCER_API_PORT}/v0/status/block-height 
EOF

COPY --chmod=644 <<EOF /etc/s6-overlay/s6-rc.d/espresso-node/notification-fd
3
EOF

################################################################################
# Configure s6 migrate espresso
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/migrate-espresso/dependencies.d
touch /etc/s6-overlay/s6-rc.d/migrate-espresso/dependencies.d/migrate
echo "oneshot" > /etc/s6-overlay/s6-rc.d/migrate-espresso/type
EOF

COPY --chmod=755 <<EOF /etc/s6-overlay/s6-rc.d/migrate-espresso/run.sh
#!/command/with-contenv sh
cartesi-rollups-espresso-reader-db-migration && echo "Espresso database migrated!" || echo "Espresso database not migrated"
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/migrate-espresso/up
/etc/s6-overlay/s6-rc.d/migrate-espresso/run.sh
EOF

################################################################################
# Configure s6 espresso-reader

RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/test-espresso
echo "oneshot" > /etc/s6-overlay/s6-rc.d/test-espresso/type
EOF

COPY --chmod=755 <<EOF /etc/s6-overlay/s6-rc.d/test-espresso/test.sh
#!/bin/sh
set -e
ESPRESSO_STARTING_BLOCK=\${ESPRESSO_STARTING_BLOCK:-1}
sleep 1
echo "Testing Espresso Dev Node at '\${ESPRESSO_BASE_URL}/v0/status/block-height'"
block_height=$(curl -s -f \${ESPRESSO_BASE_URL}/v0/status/block-height)
echo "  Waiting block height \${ESPRESSO_STARTING_BLOCK} (current \${block_height})"
[ "\${block_height}" -ge "\${ESPRESSO_STARTING_BLOCK}" ]
EOF

COPY --chmod=755 <<EOF /etc/s6-overlay/s6-rc.d/test-espresso/run.sh
#!/command/execlineb -P
with-contenv
pipeline -w { sed --unbuffered "s/^/test-espresso: /" }
fdmove -c 2 1
loopwhilex -x 0 sh /etc/s6-overlay/s6-rc.d/test-espresso/test.sh
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/test-espresso/up
/etc/s6-overlay/s6-rc.d/test-espresso/run.sh
EOF

RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/espresso-reader/dependencies.d
touch /etc/s6-overlay/s6-rc.d/espresso-reader/dependencies.d/prepare-dirs \
    /etc/s6-overlay/s6-rc.d/espresso-reader/dependencies.d/migrate \
    /etc/s6-overlay/s6-rc.d/espresso-reader/dependencies.d/migrate-espresso \
    /etc/s6-overlay/s6-rc.d/espresso-reader/dependencies.d/test-espresso
echo "longrun" > /etc/s6-overlay/s6-rc.d/espresso-reader/type
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/espresso-reader/run
#!/command/execlineb -P
with-contenv
pipeline -w { sed --unbuffered "s/^/espresso-reader: /" }
fdmove -c 2 1
cartesi-rollups-espresso-reader
EOF

################################################################################
# Configure s6 advancer
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/advancer/dependencies.d
touch /etc/s6-overlay/s6-rc.d/advancer/dependencies.d/prepare-dirs \
    /etc/s6-overlay/s6-rc.d/advancer/dependencies.d/migrate
echo "longrun" > /etc/s6-overlay/s6-rc.d/advancer/type
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/advancer/run
#!/command/execlineb -P
with-contenv
pipeline -w { sed --unbuffered "s/^/advancer: /" }
fdmove -c 2 1
cartesi-rollups-advancer
EOF

################################################################################
# Configure s6 validator
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/validator/dependencies.d
touch /etc/s6-overlay/s6-rc.d/validator/dependencies.d/prepare-dirs \
    /etc/s6-overlay/s6-rc.d/validator/dependencies.d/migrate
echo "longrun" > /etc/s6-overlay/s6-rc.d/validator/type
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/validator/run
#!/command/execlineb -P
with-contenv
pipeline -w { sed --unbuffered "s/^/validator: /" }
fdmove -c 2 1
cartesi-rollups-validator
EOF

################################################################################
# Configure s6 claimer
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/claimer/dependencies.d
touch /etc/s6-overlay/s6-rc.d/claimer/dependencies.d/prepare-dirs \
    /etc/s6-overlay/s6-rc.d/claimer/dependencies.d/migrate
echo "longrun" > /etc/s6-overlay/s6-rc.d/claimer/type
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/claimer/run
#!/command/execlineb -P
with-contenv
pipeline -w { sed --unbuffered "s/^/claimer: /" }
fdmove -c 2 1
cartesi-rollups-claimer
EOF

################################################################################
# Configure s6 jsonrpc api
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/jsonrpc-api/dependencies.d
touch /etc/s6-overlay/s6-rc.d/jsonrpc-api/dependencies.d/prepare-dirs \
    /etc/s6-overlay/s6-rc.d/jsonrpc-api/dependencies.d/migrate
echo "longrun" > /etc/s6-overlay/s6-rc.d/jsonrpc-api/type
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/jsonrpc-api/run
#!/command/execlineb -P
with-contenv
pipeline -w { sed --unbuffered "s/^/jsonrpc-api: /" }
fdmove -c 2 1
cartesi-rollups-jsonrpc-api
EOF

################################################################################
# Configure s6 stage 2 hook
RUN mkdir -p /etc/s6-overlay/scripts

ENV S6_STAGE2_HOOK=/etc/s6-overlay/scripts/stage2-hook.sh
COPY --chmod=755 <<EOF /etc/s6-overlay/scripts/stage2-hook.sh
#!/command/with-contenv bash
# decide nginx conf
if [[ \${CLOUD} = true ]]; then
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/telegraf
    ln -sr /etc/nginx/sites-available/cloud.conf /etc/nginx/sites-enabled/cloud.conf
else
    ln -sr /etc/nginx/sites-available/node.conf /etc/nginx/sites-enabled/node.conf
fi
if [[ \${ACTIVATE_CARTESI_NODE} = true ]]; then
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/nginx
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/migrate
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/advancer
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/claimer
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/validator
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/define-evmreader-envs
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/evm-reader
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/define-dave-envs
    # decide reader to start espresso reader
    if [[ \${MAIN_SEQUENCER} = espresso ]]; then
        # if [[ \${CARTESI_BLOCKCHAIN_HTTP_ENDPOINT} = "http://devnet:8545" ]]; then
        #     touch /etc/s6-overlay/s6-rc.d/espresso-reader/dependencies.d/espresso-node
        #     touch /etc/s6-overlay/s6-rc.d/user/contents.d/createespressonodedb
        #     touch /etc/s6-overlay/s6-rc.d/user/contents.d/define-espresso-envs
        #     touch /etc/s6-overlay/s6-rc.d/user/contents.d/espresso-node
        # fi
        touch /etc/s6-overlay/s6-rc.d/user/contents.d/test-espresso
        touch /etc/s6-overlay/s6-rc.d/user/contents.d/migrate-espresso
        touch /etc/s6-overlay/s6-rc.d/user/contents.d/espresso-reader
    fi
    if [ \${CARTESI_FEATURE_GRAPHQL_ENABLED} = true ]; then
        touch /etc/s6-overlay/s6-rc.d/user/contents.d/hlgraphql
        touch /etc/s6-overlay/s6-rc.d/user/contents.d/define-hlg-envs
        touch /etc/s6-overlay/s6-rc.d/user/contents.d/createhlgdb
    fi
    if [ \${CARTESI_FEATURE_RPC_ENABLED} = true ]; then
        touch /etc/s6-overlay/s6-rc.d/user/contents.d/jsonrpc-api
    fi
fi
if [[ \${ACTIVATE_ESPRESSO_DEV_NODE} = true ]]; then
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/define-espresso-envs
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/espresso-node
fi
EOF

################################################################################
# Configure s6 hlgraphql
ENV HLGRAPHQL_ENVFILE=${NODE_PATH}/hlgraphql-envs

RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/define-hlg-envs/dependencies.d
touch /etc/s6-overlay/s6-rc.d/define-hlg-envs/dependencies.d/prepare-dirs
echo "oneshot" > /etc/s6-overlay/s6-rc.d/define-hlg-envs/type
EOF

COPY --chmod=755 <<EOF /etc/s6-overlay/s6-rc.d/define-hlg-envs/run.sh
#!/command/with-contenv sh
echo "CARTESI_GRAPHQL_DATABASE_CONNECTION=\${CARTESI_DATABASE_CONNECTION}" > \${HLGRAPHQL_ENVFILE}
sed -i -e "s/\${NODE_DB}/\${GRAPHQL_DB}/" \${HLGRAPHQL_ENVFILE}
if [ \${CARTESI_LOG_LEVEL} = debug ]; then
    echo "GRAPHQL_EXTRA_FLAGS=\" -d\"" >> \${HLGRAPHQL_ENVFILE}
else
    echo "GRAPHQL_EXTRA_FLAGS=" >> \${HLGRAPHQL_ENVFILE}
fi
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/define-hlg-envs/up
/etc/s6-overlay/s6-rc.d/define-hlg-envs/run.sh
EOF

RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/hlgraphql/dependencies.d
touch /etc/s6-overlay/s6-rc.d/hlgraphql/dependencies.d/createhlgdb \
    /etc/s6-overlay/s6-rc.d/hlgraphql/dependencies.d/define-hlg-envs
echo "longrun" > /etc/s6-overlay/s6-rc.d/hlgraphql/type
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/hlgraphql/run
#!/command/execlineb -P
with-contenv
pipeline -w { sed --unbuffered "s/^/hlgraphql: /" }
fdmove -c 2 1
importas -S HLGRAPHQL_ENVFILE
envfile \${HLGRAPHQL_ENVFILE}
multisubstitute {
    importas -S CARTESI_GRAPHQL_DATABASE_CONNECTION
    importas -S GRAPHQL_EXTRA_FLAGS
    importas POSTGRES_NODE_DB_URL CARTESI_DATABASE_CONNECTION
    importas -S GRAPHQL_PORT
    importas -S CARTESI_BLOCKCHAIN_WS_ENDPOINT
    importas -S CARTESI_CONTRACTS_INPUT_BOX_DEPLOYMENT_BLOCK_NUMBER
}
export CARTESI_GRAPHQL_DATABASE_CONNECTION \${CARTESI_GRAPHQL_DATABASE_CONNECTION}
export POSTGRES_NODE_DB_URL \${POSTGRES_NODE_DB_URL}
export HTTP_PORT \${GRAPHQL_PORT}
cartesi-rollups-graphql \${GRAPHQL_EXTRA_FLAGS}
EOF

################################################################################
# Configure s6 dave node template
ENV DAVE_ENVFILE=${DAVE_PATH}/dave-envs

RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/define-dave-envs/dependencies.d
touch /etc/s6-overlay/s6-rc.d/define-dave-envs/dependencies.d/prepare-dirs
echo "oneshot" > /etc/s6-overlay/s6-rc.d/define-dave-envs/type
EOF

COPY --chmod=755 <<EOF /etc/s6-overlay/s6-rc.d/define-dave-envs/run.sh
#!/command/with-contenv sh
echo "DAVE_RUST_LOG=\${CARTESI_LOG_LEVEL}" >> \${DAVE_ENVFILE}
if [ \${CARTESI_LOG_LEVEL} = "debug" ]; then
    backtrace"full"
fi
echo "DAVE_RUST_BACKTRACE=\$backtrace" >> \${DAVE_ENVFILE}
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/define-dave-envs/up
/etc/s6-overlay/s6-rc.d/define-dave-envs/run.sh
EOF

RUN <<EOF
mkdir -p /etc/s6-overlay/templates/dave-node/dependencies.d
touch /etc/s6-overlay/templates/dave-node/dependencies.d/define-dave-envs
echo "longrun" > /etc/s6-overlay/templates/dave-node/type
EOF

COPY --chmod=755 <<EOF /etc/s6-overlay/templates/dave-node/run
#!/command/execlineb -s1
with-contenv
pipeline -w { sed --unbuffered "s/^/dave-\${1}: /" }
fdmove -c 2 1
importas -S DAVE_ENVFILE
envfile \${DAVE_ENVFILE}

multisubstitute {
    importas -S DAVE_PATH
    importas -S DAVE_RUST_LOG
    importas -S DAVE_RUST_BACKTRACE
    importas -S CARTESI_AUTH_PRIVATE_KEY
    importas -S CARTESI_BLOCKCHAIN_HTTP_ENDPOINT
    importas -S CARTESI_BLOCKCHAIN_ID
}
foreground {
    echo "cartesi-rollups-prt-node --web3-rpc-url=\${CARTESI_BLOCKCHAIN_HTTP_ENDPOINT} --web3-chain-id=\${CARTESI_BLOCKCHAIN_ID} --app-address=\${1} --machine-path=\${DAVE_PATH}/snapshots/\${1} --state-dir=\${DAVE_PATH}/states/\${1} pk --web3-private-key=\${CARTESI_AUTH_PRIVATE_KEY}"
}
export RUST_LOG \${DAVE_RUST_LOG}
export RUST_BACKTRACE \${DAVE_RUST_BACKTRACE}

cartesi-rollups-prt-node 
    --web3-rpc-url=\${CARTESI_BLOCKCHAIN_HTTP_ENDPOINT}
    --web3-chain-id=\${CARTESI_BLOCKCHAIN_ID}
    --app-address=\${1}
    --machine-path=\${DAVE_PATH}/snapshots/\${1}
    --state-dir=\${DAVE_PATH}/states/\${1}
    pk
    --web3-private-key=\${CARTESI_AUTH_PRIVATE_KEY}
EOF

################################################################################
# deploy and register scripts

COPY --chmod=755 <<EOF /deploy.sh
#!/bin/bash
if [ ! -z \${OWNER} ]; then
    owner_args="--owner \${OWNER} --authority-owner \${OWNER}"
fi
if [ ! -z \${CONSENSUS_ADDRESS} ]; then
    consensus_arg="--consensus \${CONSENSUS_ADDRESS}"
fi
if [ ! -z \${EPOCH_LENGTH} ]; then
    epoch_arg="--epoch-length \${EPOCH_LENGTH}"
fi
if [ ! -z \${SALT} ]; then
    salt_arg="--salt \${SALT}"
fi
if [ ! -z \${APPLICATION_FACTORY_ADDRESS} ]; then
    app_fac_arg="--app-factory \${APPLICATION_FACTORY_ADDRESS}"
fi
if [ ! -z \${AUTHORITY_FACTORY_ADDRESS} ]; then
    auth_fac_arg="--authority-factory \${AUTHORITY_FACTORY_ADDRESS}"
fi
if [[ \${MAIN_SEQUENCER} = espresso ]]; then
    da_arg="--data-availability \$(cast calldata 'InputBoxAndEspresso(address,uint256,uint32)' \$CARTESI_CONTRACTS_INPUT_BOX_ADDRESS \$(curl -s -f \${ESPRESSO_BASE_URL}/v0/status/block-height) \$ESPRESSO_NAMESPACE)"
fi
cartesi-rollups-cli deploy application \${APP_NAME} \$1 \${owner_args} \${consensus_arg} \${epoch_arg} \${salt_arg} \${app_fac_arg} \${auth_fac_arg} \${da_arg} \${EXTRA_ARGS} || echo 'Not deployed'
EOF

COPY --chmod=755 <<EOF /register.sh
#!/bin/bash
cartesi-rollups-cli app register -n \${APP_NAME} --blockchain-http-endpoint \${CARTESI_BLOCKCHAIN_HTTP_ENDPOINT} -a \${APPLICATION_ADDRESS} -c \${CONSENSUS_ADDRESS} \${EXTRA_ARGS} -t \$1 || echo 'Not registered'
EOF

COPY --chmod=755 <<EOF /deploy-dave.sh
#!/bin/bash
OWNER=\${OWNER:-0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266}
EPOCH_LENGTH=\${EPOCH_LENGTH:-303}
SALT=\${SALT:-0x0000000000000000000000000000000000000000000000000000000000000000}

da_arg="0x"
if [[ \${MAIN_SEQUENCER} = ethereum ]]; then
    da_arg="\$(cast calldata 'InputBox(address)' \$CARTESI_CONTRACTS_INPUT_BOX_ADDRESS)"
fi
if [[ \${MAIN_SEQUENCER} = espresso ]]; then
    echo "Espresso with dave consensus is not supported yet"
    exit 1
    # da_arg="\$(cast calldata 'InputBoxAndEspresso(address,uint256,uint32)' \$CARTESI_CONTRACTS_INPUT_BOX_ADDRESS \$(curl -s -f \${ESPRESSO_BASE_URL}/v0/status/block-height) \$ESPRESSO_NAMESPACE)"
fi
machine_hash=\$(xxd -p -c 32 \$1/hash)

res=\$(cast send --json --rpc-url \$CARTESI_BLOCKCHAIN_HTTP_ENDPOINT --private-key \$CARTESI_AUTH_PRIVATE_KEY \$CARTESI_CONTRACTS_APPLICATION_FACTORY_ADDRESS "newApplication(address,address,bytes32,bytes,bytes32)" 0x0000000000000000000000000000000000000000 \$OWNER \$machine_hash \$da_arg \$SALT)

if [ -z "\${res}" ]; then
    echo "Application deployment failed"
    exit 1
fi

application_address=\$(echo "\${res}" | jq -r '.logs[0].address')

echo "application: \$application_address"

res=\$(cast send --json --rpc-url \$CARTESI_BLOCKCHAIN_HTTP_ENDPOINT --private-key \$CARTESI_AUTH_PRIVATE_KEY \$CARTESI_CONTRACTS_DAVE_CONSENSUS_FACTORY_ADDRESS "newDaveConsensus(address,bytes32,bytes32)" \$application_address \$machine_hash \$SALT)

if [ -z "\${res}" ]; then
    echo "Dave Consensus deployment failed"
    exit 1
fi

dave_consensus_address=\$(echo "\${res}" | jq -r '.logs[0].address')

echo "dave consensus: \$dave_consensus_address"

res=\$(cast send --json --rpc-url \$CARTESI_BLOCKCHAIN_HTTP_ENDPOINT --private-key \$CARTESI_AUTH_PRIVATE_KEY \$application_address "migrateToOutputsMerkleRootValidator(address)" \$dave_consensus_address)

if [ -z "\${res}" ]; then
    echo "Migrate to dave Consensus failed"
    exit 1
fi

APP_NAME=\${APP_NAME} EPOCH_LENGTH=\${EPOCH_LENGTH} EXTRA_ARGS=\${EXTRA_ARGS} APPLICATION_ADDRESS=\$application_address CONSENSUS_ADDRESS=\$dave_consensus_address /register-dave.sh \$1 
EOF

COPY --chmod=755 <<EOF /initialize-dave-node.sh
#!/bin/bash

ln -sr \$1 \${DAVE_PATH}/snapshots/\${APPLICATION_ADDRESS}
mkdir -p \${DAVE_PATH}/states/\${APPLICATION_ADDRESS}

if [ ! -d /run/s6-rc/servicedirs/dave-nodes ]; then
    echo "Dave nodes instance not found, making it.."
    /command/s6-instance-maker /etc/s6-overlay/templates/dave-node /run/s6-rc/servicedirs/dave-nodes
fi

if [ ! -f /run/services/dave-nodes ]; then
    echo "Linking dave nodes service..."
    ln -s /run/s6-rc/servicedirs/dave-nodes /run/service/dave-nodes
else
    echo "Dave nodes service linked"
fi

if [[ \$(/command/s6-svstat -o up /run/service/dave-nodes 2>/dev/null) != true ]]; then
    echo "Dave nodes service not supervised. Initializing it..."
    /command/s6-svscanctl -a /run/service
    timeout 22 bash -c 'until /command/s6-svstat -o up /run/service/dave-nodes >> /dev/null ; do sleep 1 && echo "  waiting dave node supervisor.."; done'
else
    echo "Dave nodes service supervised"
fi

/command/s6-instance-create /run/service/dave-nodes \${APPLICATION_ADDRESS}
EOF

COPY --chmod=755 <<EOF /register-dave.sh
#!/bin/bash
EPOCH_LENGTH=\${EPOCH_LENGTH:-303}

if [[ \${CARTESI_FEATURE_DAVE_CONSENSUS_ENABLED} != false ]]; then
    APPLICATION_ADDRESS=\$APPLICATION_ADDRESS /initialize-dave-node.sh \$1 
fi
deployment_block_number=\$(cast call --rpc-url \${CARTESI_BLOCKCHAIN_HTTP_ENDPOINT} \${APPLICATION_ADDRESS} "getDeploymentBlockNumber()(uint256)")
cartesi-rollups-cli app register -n \${APP_NAME} --blockchain-http-endpoint \${CARTESI_BLOCKCHAIN_HTTP_ENDPOINT} -t \$1 -a \${APPLICATION_ADDRESS} -c \${CONSENSUS_ADDRESS} --epoch-length \$EPOCH_LENGTH --inputbox-block-number \${deployment_block_number} \${EXTRA_ARGS} || echo 'Not registered'
EOF

WORKDIR /opt/cartesi

RUN <<EOF
chown -R cartesi:cartesi /mnt
chown -R cartesi:cartesi /opt/cartesi
chown -R cartesi:cartesi /etc/s6-overlay
chown -R cartesi:cartesi /run
EOF

# =============================================================================
# STAGE: rollups-node-we-cloud
#
# =============================================================================

FROM base-rollups-node-we AS rollups-node-we-cloud

# Set root user
USER root

# Create init wrapper
COPY --chmod=755 <<EOF /init-wrapper
#!/bin/sh
# run /init with PID 1, creating a new PID namespace if necessary
if [ "\$$" -eq 1 ]; then
    echo # we already have PID 1
    exec /init "\$@"
else
    echo # create a new PID namespace
    exec unshare --pid sh -c '
        # set up /proc and start the real init in the background
        unshare --mount-proc /init "\$@" &
        child="\$!"
        # forward signals to the real init
        trap "kill -INT \$child" INT
        trap "kill -TERM \$child" TERM
        # wait until the real init exits
        # ("wait" returns early on signals; "kill -0" checks if the process exists)
        until wait "\$child" || ! kill -0 "\$child" 2>/dev/null; do :; done
    ' sh "\$@"
fi
EOF

ENV CLOUD=true

ENTRYPOINT ["/init-wrapper"]

# =============================================================================
# STAGE: rollups-node-we
#
# =============================================================================

FROM base-rollups-node-we AS rollups-node-we

# Set user to low-privilege.
USER cartesi

# ENTRYPOINT [ "/init" ]
