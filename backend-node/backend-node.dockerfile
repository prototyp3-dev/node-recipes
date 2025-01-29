# (c) Cartesi and individual authors (see AUTHORS)
# SPDX-License-Identifier: Apache-2.0 (see LICENSE)

# syntax=docker.io/docker/dockerfile:1

ARG EMULATOR_VERSION=0.18.1
ARG S6_OVERLAY_VERSION=3.2.0.2
ARG TELEGRAF_VERSION=1.32.1
ARG HLGRAPHQL_VERSION=2.3.4
ARG TRAEFIK_VERSION=3.2.0
ARG GOVERSION=1.23.5
ARG GO_BUILD_PATH=/build/cartesi/go
ARG ROLLUPSNODE_BRANCH=v2.0.0-dev-20250128 
ARG ROLLUPSNODE_DIR=rollups-node
ARG ESPRESSOREADER_VERSION=2.0.1-beta
ARG ESPRESSOREADER_BRANCH=feature/adapt-node-20250128
ARG ESPRESSOREADER_DIR=rollups-espresso-reader
ARG ESPRESSO_DEV_NODE_TAG=20241120-patch3
ARG GRAPHQL_BRANCH=feature/migration-db-v2-beta
ARG GRAPHQL_DIR=rollups-graphql

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

FROM common-env AS go-installer

USER root

ARG GOVERSION

RUN wget https://go.dev/dl/go${GOVERSION}.linux-$(dpkg --print-architecture).tar.gz && \
    tar -C /usr/local -xzf go${GOVERSION}.linux-$(dpkg --print-architecture).tar.gz

ENV PATH=/usr/local/go/bin:${PATH}

ARG GO_BUILD_PATH
RUN mkdir -p ${GO_BUILD_PATH} && chown -R cartesi:cartesi ${GO_BUILD_PATH}

USER cartesi

FROM go-installer AS go-builder

ARG GO_BUILD_PATH

ENV GOCACHE=${GO_BUILD_PATH}/.cache
ENV GOENV=${GO_BUILD_PATH}/.config/go/env
ENV GOPATH=${GO_BUILD_PATH}/.go

ARG ROLLUPSNODE_BRANCH
ARG ROLLUPSNODE_DIR

RUN git clone --single-branch --branch ${ROLLUPSNODE_BRANCH} \
    https://github.com/cartesi/rollups-node.git ${GO_BUILD_PATH}/${ROLLUPSNODE_DIR}

RUN cd ${GO_BUILD_PATH}/${ROLLUPSNODE_DIR} && go mod download
RUN cd ${GO_BUILD_PATH}/${ROLLUPSNODE_DIR} && make build-go

ARG ESPRESSOREADER_VERSION
ARG ESPRESSOREADER_DIR
ARG ESPRESSOREADER_BRANCH

RUN git clone --single-branch --branch ${ESPRESSOREADER_BRANCH} \
    https://github.com/cartesi/rollups-espresso-reader.git ${GO_BUILD_PATH}/${ESPRESSOREADER_DIR}

RUN cd ${GO_BUILD_PATH}/${ESPRESSOREADER_DIR} && go mod download
RUN cd ${GO_BUILD_PATH}/${ESPRESSOREADER_DIR} && \
    go build -o cartesi-rollups-espresso-reader && \
    go build -o cartesi-rollups-espresso-reader-db-migration dev/migrate/main.go


ARG GRAPHQL_BRANCH
ARG GRAPHQL_DIR

RUN git clone --single-branch --branch ${GRAPHQL_BRANCH} \
    https://github.com/cartesi/rollups-graphql.git ${GO_BUILD_PATH}/${GRAPHQL_DIR}

RUN cd ${GO_BUILD_PATH}/${GRAPHQL_DIR} && go mod download
RUN cd ${GO_BUILD_PATH}/${GRAPHQL_DIR} && \
    go build -o cartesi-rollups-graphql


# =============================================================================
# STAGE: base-rollups-node-we
#
# =============================================================================

# https://github.com/EspressoSystems/espresso-sequencer/pkgs/container/espresso-sequencer%2Fespresso-dev-node
FROM ghcr.io/espressosystems/espresso-sequencer/espresso-dev-node:${ESPRESSO_DEV_NODE_TAG} AS espresso-dev-node

FROM cartesi/machine-emulator:${EMULATOR_VERSION} AS base-rollups-node-we

USER root

ARG BASE_PATH=/mnt
ENV BASE_PATH=${BASE_PATH}

ENV SNAPSHOTS_APPS_PATH=${BASE_PATH}/apps
ENV NODE_PATH=${BASE_PATH}/node

# Download system dependencies required at runtime.
ARG DEBIAN_FRONTEND=noninteractive
RUN <<EOF
    set -e
    apt-get update
    apt-get install -y --no-install-recommends \
        ca-certificates curl procps \
        xz-utils nginx postgresql-client
    rm -rf /var/lib/apt/lists/* /var/log/* /var/cache/*
    mkdir -p ${NODE_PATH}/snapshots ${NODE_PATH}/data
    chown -R cartesi:cartesi ${NODE_PATH}
EOF

# Copy Go binary.
ARG GO_BUILD_PATH
ARG ROLLUPSNODE_DIR
ARG ESPRESSOREADER_DIR
ARG GRAPHQL_DIR
COPY --from=go-builder ${GO_BUILD_PATH}/${ROLLUPSNODE_DIR}/cartesi-rollups-* /usr/bin
COPY --from=go-builder ${GO_BUILD_PATH}/${ESPRESSOREADER_DIR}/cartesi-rollups-* /usr/bin
COPY --from=go-builder ${GO_BUILD_PATH}/${cartesi-rollups-graphql}/cartesi-rollups-* /usr/bin

# install s6 overlay
ARG S6_OVERLAY_VERSION
RUN curl -s -L https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz | \
    tar xJf - -C /
RUN curl -s -L https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-$(uname -m).tar.xz | \
    tar xJf - -C /

# install telegraf
ARG TELEGRAF_VERSION
RUN curl -s -L https://dl.influxdata.com/telegraf/releases/telegraf-${TELEGRAF_VERSION}_linux_$(dpkg --print-architecture).tar.gz | \
    tar xzf - --strip-components 2 -C / ./telegraf-${TELEGRAF_VERSION}

# # install cartesi-rollups-graphql
# ARG HLGRAPHQL_VERSION
# RUN curl -s -L https://github.com/cartesi/rollups-graphql/releases/download/v${HLGRAPHQL_VERSION}/cartesi-rollups-graphql-v${HLGRAPHQL_VERSION}-linux-$(dpkg --print-architecture).tar.gz | \
#     tar xzf - -C /usr/local/bin cartesi-rollups-graphql

# Install espresso
COPY --from=espresso-dev-node /usr/bin/espresso-dev-node /usr/local/bin/

RUN mkdir -p /etc/s6-overlay/s6-rc.d/user/contents.d

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

RUN rm /etc/nginx/sites-enabled/*

# Configure s6 nginx
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/nginx
touch /etc/s6-overlay/s6-rc.d/user/contents.d/nginx
echo "longrun" > /etc/s6-overlay/s6-rc.d/nginx/type
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/nginx/run
#!/command/execlineb -P
pipeline -w { sed --unbuffered "s/^/nginx: /" }
fdmove -c 2 1
/usr/sbin/nginx -g "daemon off;"
EOF

# Env variables
ARG CARTESI_HTTP_PORT=10012
ENV CARTESI_HTTP_PORT=${CARTESI_HTTP_PORT}
ENV CARTESI_INSPECT_ADDRESS=localhost:${CARTESI_HTTP_PORT}
ARG ESPRESSO_SERVICE_PORT=10030
ENV ESPRESSO_SERVICE_PORT=${ESPRESSO_SERVICE_PORT}
ARG ESPRESSO_SERVICE_ENDPOINT=localhost:${ESPRESSO_SERVICE_PORT}
ENV ESPRESSO_SERVICE_ENDPOINT=${ESPRESSO_SERVICE_ENDPOINT}
ARG GRAPHQL_PORT=10020
ENV GRAPHQL_PORT=${GRAPHQL_PORT}
ENV CARTESI_SNAPSHOT_DIR=${NODE_PATH}/snapshots

ENV NODE_DB=rollupsdb
ENV GRAPHQL_DB=hlgraphql
ENV ESPRESSONODE_DB=sequencer

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
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/prepare-dirs/up
/etc/s6-overlay/s6-rc.d/prepare-dirs/run.sh
EOF

################################################################################
# Configure s6 migrate
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/migrate
touch /etc/s6-overlay/s6-rc.d/user/contents.d/migrate
echo "oneshot" > /etc/s6-overlay/s6-rc.d/migrate/type
EOF

COPY --chmod=755 <<EOF /etc/s6-overlay/s6-rc.d/migrate/run.sh
#!/command/with-contenv sh
cartesi-rollups-cli db upgrade -p \${CARTESI_POSTGRES_ENDPOINT}
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/migrate/up
/etc/s6-overlay/s6-rc.d/migrate/run.sh
EOF

################################################################################
# Configure s6 create hl db
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/createhlgdb/dependencies.d
touch /etc/s6-overlay/s6-rc.d/createhlgdb/dependencies.d/migrate
touch /etc/s6-overlay/s6-rc.d/user/contents.d/createhlgdb
echo "oneshot" > /etc/s6-overlay/s6-rc.d/createhlgdb/type
EOF

COPY --chmod=755 <<EOF /etc/s6-overlay/s6-rc.d/createhlgdb/run.sh
#!/command/with-contenv bash
psql \${CARTESI_POSTGRES_ENDPOINT} -c "create database \${GRAPHQL_DB};" && echo "HLGraphql database created!" || echo "HLGraphql database alredy created"
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
touch /etc/s6-overlay/s6-rc.d/user/contents.d/define-evmreader-envs
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
touch /etc/s6-overlay/s6-rc.d/user/contents.d/evm-reader
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
psql \${CARTESI_POSTGRES_ENDPOINT} -c "create database \${ESPRESSONODE_DB};" && echo "Espresso node database created!" || echo "Espresso node database alredy created"
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
echo "POSTGRES_ESPRESSO_DB_URL=\${CARTESI_POSTGRES_ENDPOINT}" > \${ESPRESSO_ENVFILE}
sed -i -e "s/\${NODE_DB}/\${ESPRESSONODE_DB}/" \${ESPRESSO_ENVFILE}
if [ \${CARTESI_LOG_LEVEL} = debug ]; then
    echo "ESPRESSONODE_RUST_LOG=\${CARTESI_LOG_LEVEL}" >> \${ESPRESSO_ENVFILE}
else
    echo "ESPRESSONODE_RUST_LOG=warn" >> \${ESPRESSO_ENVFILE}
fi
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

COPY <<EOF /etc/s6-overlay/s6-rc.d/espresso-node/run
#!/command/execlineb -P
with-contenv
pipeline -w { sed --unbuffered "s/^/espresso-node: /" }
fdmove -c 2 1
importas -S ESPRESSO_ENVFILE
envfile \${ESPRESSO_ENVFILE}
multisubstitute {
    importas -S POSTGRES_ESPRESSO_DB_URL
    importas -S ESPRESSONODE_RUST_LOG
}
# foreground {
#     echo 'RUST_LOG=\${ESPRESSONODE_RUST_LOG} espresso-dev-node \${POSTGRES_ESPRESSO_DB_URL} \${ESPRESSONODE_EXTRA_FLAGS}'
# }
export RUST_LOG \${ESPRESSONODE_RUST_LOG}
export ESPRESSO_BASE_URL \${ESPRESSO_BASE_URL}
s6-notifyoncheck -s 2000 -w 1000 -t 500 -n 10
espresso-dev-node \${POSTGRES_ESPRESSO_DB_URL}
EOF

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
cartesi-rollups-espresso-reader-db-migration
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
sleep 1
echo "Testing Espresso Dev Node at '\${ESPRESSO_BASE_URL}/v0/status/block-height'"
block_height=$(curl -s -f \${ESPRESSO_BASE_URL}/v0/status/block-height )
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
touch /etc/s6-overlay/s6-rc.d/user/contents.d/advancer
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
touch /etc/s6-overlay/s6-rc.d/user/contents.d/validator
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
touch /etc/s6-overlay/s6-rc.d/user/contents.d/claimer
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
# Configure s6 stage 2 hook
RUN mkdir -p /etc/s6-overlay/scripts

ENV S6_STAGE2_HOOK=/etc/s6-overlay/scripts/stage2-hook.sh
COPY --chmod=755 <<EOF /etc/s6-overlay/scripts/stage2-hook.sh
#!/command/with-contenv bash
# decide which reader to start
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
EOF

################################################################################
# Configure s6 hlgraphql
ENV HLGRAPHQL_ENVFILE=${NODE_PATH}/hlgraphql-envs

RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/define-hlg-envs/dependencies.d
touch /etc/s6-overlay/s6-rc.d/define-hlg-envs/dependencies.d/prepare-dirs
touch /etc/s6-overlay/s6-rc.d/user/contents.d/define-hlg-envs
echo "oneshot" > /etc/s6-overlay/s6-rc.d/define-hlg-envs/type
EOF

COPY --chmod=755 <<EOF /etc/s6-overlay/s6-rc.d/define-hlg-envs/run.sh
#!/command/with-contenv sh
echo "POSTGRES_GRAPHQL_DB_URL=\${CARTESI_POSTGRES_ENDPOINT}" > \${HLGRAPHQL_ENVFILE}
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
touch /etc/s6-overlay/s6-rc.d/user/contents.d/hlgraphql
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
    importas -S POSTGRES_GRAPHQL_DB_URL
    importas -S GRAPHQL_EXTRA_FLAGS
    importas POSTGRES_NODE_DB_URL CARTESI_POSTGRES_ENDPOINT
    importas -S GRAPHQL_PORT
    importas -S CARTESI_BLOCKCHAIN_WS_ENDPOINT
    importas -S CARTESI_CONTRACTS_INPUT_BOX_DEPLOYMENT_BLOCK_NUMBER
}
export POSTGRES_GRAPHQL_DB_URL \${POSTGRES_GRAPHQL_DB_URL}
export POSTGRES_NODE_DB_URL \${POSTGRES_NODE_DB_URL}
export HTTP_PORT \${GRAPHQL_PORT}
cartesi-rollups-graphql \
    \${GRAPHQL_EXTRA_FLAGS}
EOF

# deploy script
RUN <<EOF
chown -R cartesi:cartesi /mnt
EOF

COPY --chmod=755 <<EOF /deploy.sh
#!/bin/bash
if [ ! -z \${OWNER} ]; then
    owner_args="-o \${OWNER} -O \${OWNER}"
fi
if [ ! -z \${CONSENSUS_ADDRESS} ]; then
    consensus_arg="-c \${CONSENSUS_ADDRESS}"
fi
if [ ! -z \${EPOCH_LENGTH} ]; then
    epoch_arg="-e \${EPOCH_LENGTH}"
fi
if [ ! -z \${SALT} ]; then
    salt_arg="--salt \${SALT}"
fi
cartesi-rollups-cli app deploy -n \${APP_NAME} -t \$1 --private-key \${CARTESI_AUTH_PRIVATE_KEY} --rpc-url \${CARTESI_BLOCKCHAIN_HTTP_ENDPOINT} -p \${CARTESI_POSTGRES_ENDPOINT} \${owner_args} \${consensus_arg} \${epoch_arg} \${salt_arg} \${EXTRA_ARGS} || echo 'Not deployed'
EOF


COPY --chmod=755 <<EOF /register.sh
#!/bin/bash
cartesi-rollups-cli app register -n \${APP_NAME} -t \$1 -p \${CARTESI_POSTGRES_ENDPOINT} -a \${APPLICATION_ADDRESS} -c \${CONSENSUS_ADDRESS} \${EXTRA_ARGS} || echo 'Not registered'
EOF

RUN <<EOF
chown -R cartesi:cartesi /opt/cartesi
chown -R cartesi:cartesi /etc/s6-overlay/s6-rc.d
EOF

ENV HOME=/opt/cartesi

# =============================================================================
# STAGE: rollups-node-we
#
# =============================================================================

FROM base-rollups-node-we AS rollups-node-we-cloud

RUN touch /etc/s6-overlay/s6-rc.d/user/contents.d/telegraf

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
        proxy_pass   http://localhost:${CARTESI_HTTP_PORT}/inspect;
        proxy_cache_valid 200 5s;
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

RUN ln -sr /etc/nginx/sites-available/cloud.conf /etc/nginx/sites-enabled/cloud.conf

# Create init wrapper
COPY --chmod=755 <<EOF /init-wrapper
#!/bin/sh
# run /init with PID 1, creating a new PID namespace if necessary
if [ "\$$" -eq 1 ]; then
    # we already have PID 1
    exec /init "\$@"
else
    # create a new PID namespace
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

CMD ["/init-wrapper"]


FROM base-rollups-node-we AS rollups-node-we

RUN chown -R cartesi:cartesi /run

# Configure nginx server with cache
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
        proxy_pass   http://localhost:${CARTESI_HTTP_PORT}/inspect;
    }

    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }
}
EOF

RUN ln -sr /etc/nginx/sites-available/node.conf /etc/nginx/sites-enabled/node.conf

# Set user to low-privilege.
USER cartesi

# Set the Go supervisor as the command.
CMD [ "/init" ]
