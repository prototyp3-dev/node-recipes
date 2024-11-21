# (c) Cartesi and individual authors (see AUTHORS)
# SPDX-License-Identifier: Apache-2.0 (see LICENSE)

# syntax=docker.io/docker/dockerfile:1

ARG EMULATOR_VERSION=0.18.1
ARG S6_OVERLAY_VERSION=3.2.0.2
ARG TELEGRAF_VERSION=1.32.1
ARG HLGRAPHQL_VERSION=2.0.0
ARG TRAEFIK_VERSION=3.2.0
ARG GO_BUILD_PATH=/build/cartesi/go

# =============================================================================
# STAGE: node builder
#
# =============================================================================

FROM recipe-stage/builder AS go-builder

ARG GO_BUILD_PATH

# Remove postgraphile migration
RUN rm ${GO_BUILD_PATH}/rollups-node/internal/repository/schema/migrations/000002_create_postgraphile_view*
RUN sed -i -e 's/const ExpectedVersion uint = 2/const ExpectedVersion uint = 1/' ${GO_BUILD_PATH}/rollups-node/internal/repository/schema/schema.go

RUN cd ${GO_BUILD_PATH}/rollups-node && make build-go

# =============================================================================
# STAGE: base-rollups-node-we
#
# =============================================================================

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
COPY --from=go-builder ${GO_BUILD_PATH}/rollups-node/cartesi-rollups-* /usr/bin

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

# install cartesi-rollups-hl-graphql
ARG HLGRAPHQL_VERSION
RUN curl -s -L https://github.com/Calindra/cartesi-rollups-hl-graphql/releases/download/v${HLGRAPHQL_VERSION}/cartesi-rollups-hl-graphql-v${HLGRAPHQL_VERSION}-linux-$(dpkg --print-architecture).tar.gz | \
    tar xzf - -C /usr/local/bin cartesi-rollups-hl-graphql

RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/user/contents.d
chown -R cartesi:cartesi /etc/s6-overlay/s6-rc.d/user/contents.d
EOF

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
    process_names = ['cartesi-rollups-*', 'jsonrpc-remote-cartesi-*', '*cartesi*', 'telegraf', 'cartesi-rollups-hl-graphql', 'nonodo', 'nginx']

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

    log_format  main  '$remote_addr - $upstream_cache_status rt=$request_time [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for" '
                      'uct="$upstream_connect_time" uht="$upstream_header_time" urt="$upstream_response_time"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    keepalive_timeout  65;

    #gzip  on;

    map $request_method $purge_method {
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
ARG CARTESI_HTTP_PORT=10000
ENV CARTESI_HTTP_PORT=${CARTESI_HTTP_PORT}
ARG ESPRESSO_SERVICE_PORT=10030
ENV ESPRESSO_SERVICE_PORT=${ESPRESSO_SERVICE_PORT}
ARG ESPRESSO_SERVICE_ENDPOINT=localhost:${ESPRESSO_SERVICE_PORT}
ENV ESPRESSO_SERVICE_ENDPOINT=${ESPRESSO_SERVICE_ENDPOINT}
ARG GRAPHQL_PORT=10004
ENV GRAPHQL_PORT=${GRAPHQL_PORT}
ENV CARTESI_SNAPSHOT_DIR=${NODE_PATH}/snapshots

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
cartesi-rollups-cli db upgrade -p ${CARTESI_POSTGRES_ENDPOINT}
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/migrate/up
/etc/s6-overlay/s6-rc.d/migrate/run.sh
EOF

################################################################################
# Configure s6 create db
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/createhlgdb/dependencies.d
touch /etc/s6-overlay/s6-rc.d/createhlgdb/dependencies.d/migrate
touch /etc/s6-overlay/s6-rc.d/user/contents.d/createhlgdb
echo "oneshot"/etc/s6-overlay/s6-rc.d/createhlgdb/type
EOF

COPY --chmod=755 <<EOF /etc/s6-overlay/s6-rc.d/createhlgdb/run.sh
#!/command/with-contenv sh
PGPASSWORD=${POSTGRES_PASSWORD} psql -U ${POSTGRES_USER} -h ${POSTGRES_HOST} \
    -c "create database ${GRAPHQL_DB};" || echo "HLGraphql database alredy created"
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/createhlgdb/up
/etc/s6-overlay/s6-rc.d/createhlgdb/run.sh
EOF

################################################################################
# Configure s6 reader
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/reader/dependencies.d
touch /etc/s6-overlay/s6-rc.d/reader/dependencies.d/{prepare-dirs, migrate}
touch /etc/s6-overlay/s6-rc.d/user/contents.d/reader
echo "longrun" > /etc/s6-overlay/s6-rc.d/reader/type
EOF

COPY --chmod=755 <<EOF /etc/s6-overlay/s6-rc.d/reader/start.sh
#!/command/with-contenv sh
READER_CMD=cartesi-rollups-evm-reader
if [ ${MAIN_SEQUENCER} = espresso ]; then
    READER_CMD=cartesi-rollups-espresso-reader
fi
${READER_CMD}
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/reader/run
#!/command/execlineb -P
with-contenv
pipeline -w { sed --unbuffered "s/^/reader: /" }
fdmove -c 2 1
/bin/sh /etc/s6-overlay/s6-rc.d/reader/start.sh
EOF

################################################################################
# Configure s6 advancer
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/advancer/dependencies.d
touch /etc/s6-overlay/s6-rc.d/advancer/dependencies.d/{prepare-dirs, migrate}
touch /etc/s6-overlay/s6-rc.d/user/contents.d/advancer
echo "longrun" > /etc/s6-overlay/s6-rc.d/advancer/type
EOF

COPY --chmod=755 <<EOF /etc/s6-overlay/s6-rc.d/advancer/start.sh
#!/command/with-contenv sh
cartesi-rollups-advancer
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/advancer/run
#!/command/execlineb -P
with-contenv
pipeline -w { sed --unbuffered "s/^/advancer: /" }
fdmove -c 2 1
/bin/sh /etc/s6-overlay/s6-rc.d/advancer/start.sh
EOF

################################################################################
# Configure s6 validator
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/validator/dependencies.d
touch /etc/s6-overlay/s6-rc.d/validator/dependencies.d/{prepare-dirs, migrate}
touch /etc/s6-overlay/s6-rc.d/user/contents.d/validator
echo "longrun" > /etc/s6-overlay/s6-rc.d/validator/type
EOF

COPY --chmod=755 <<EOF /etc/s6-overlay/s6-rc.d/validator/start.sh
#!/command/with-contenv sh
cartesi-rollups-validator
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/validator/run
#!/command/execlineb -P
with-contenv
pipeline -w { sed --unbuffered "s/^/validator: /" }
fdmove -c 2 1
/bin/sh /etc/s6-overlay/s6-rc.d/validator/start.sh
EOF

################################################################################
# Configure s6 claimer
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/claimer/dependencies.d
touch /etc/s6-overlay/s6-rc.d/claimer/dependencies.d/{prepare-dirs, migrate}
echo "longrun" > /etc/s6-overlay/s6-rc.d/claimer/type
EOF

COPY --chmod=755 <<EOF /etc/s6-overlay/s6-rc.d/claimer/start.sh
#!/command/with-contenv sh
cartesi-rollups-claimer
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/claimer/run
#!/command/execlineb -P
with-contenv
pipeline -w { sed --unbuffered "s/^/claimer: /" }
fdmove -c 2 1
/bin/sh /etc/s6-overlay/s6-rc.d/claimer/start.sh
EOF

################################################################################
# Configure s6 stage 2 hook
RUN mkdir -p /etc/s6-overlay/scripts

ENV S6_STAGE2_HOOK=/etc/s6-overlay/scripts/stage2-hook.sh
COPY --chmod=755 <<EOF /etc/s6-overlay/scripts/stage2-hook.sh
#!/command/with-contenv bash
if [[ ${CARTESI_FEATURE_CLAIMER_ENABLED} = false ]] || \
        [[ ${CARTESI_FEATURE_CLAIMER_ENABLED} = f ]] || \
        [[ ${CARTESI_FEATURE_CLAIMER_ENABLED} = no ]] || \
        [[ ${CARTESI_FEATURE_CLAIMER_ENABLED} = n ]] || \
        [[ ${CARTESI_FEATURE_CLAIMER_ENABLED} = 0 ]]; then
    echo 'Claimer disabled'
else
    echo 'Claimer enabled'
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/claimer
fi
EOF

################################################################################
# Configure s6 hlgraphql
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/hlgraphql/dependencies.d
touch /etc/s6-overlay/s6-rc.d/hlgraphql/dependencies.d/createhlgdb
touch /etc/s6-overlay/s6-rc.d/user/contents.d/hlgraphql
echo "longrun" > /etc/s6-overlay/s6-rc.d/hlgraphql/type
EOF

COPY --chmod=755 <<EOF /etc/s6-overlay/s6-rc.d/hlgraphql/start.sh
#!/command/with-contenv sh
POSTGRES_DB=${GRAPHQL_DB} cartesi-rollups-hl-graphql \
    --disable-devnet \
    --disable-advance \
    --disable-inspect \
    --http-port=${GRAPHQL_PORT} \
    --raw-enabled \
    --high-level-graphql \
    --graphile-disable-sync \
    --db-implementation=postgres \
    --db-raw-url=${CARTESI_POSTGRES_ENDPOINT}
EOF

COPY <<EOF /etc/s6-overlay/s6-rc.d/hlgraphql/run
#!/command/execlineb -P
with-contenv
pipeline -w { sed --unbuffered "s/^/hlgraphql: /" }
fdmove -c 2 1
/bin/sh /etc/s6-overlay/s6-rc.d/hlgraphql/start.sh
EOF

# deploy script
RUN <<EOF
mkdir -p /mnt/snapshots
chown -R cartesi:cartesi /mnt
EOF

COPY --chmod=755 <<EOF /deploy.sh
#!/bin/bash
if [ ! -z ${OWNER} ]; then
    owner_args="-o ${OWNER} -O ${OWNER}"
fi
if [ ! -z ${AUTHORITY_ADDRESS} ]; then
    authority_arg="-i ${AUTHORITY_ADDRESS}"
fi
if [ ! -z ${EPOCH_LENGTH} ]; then
    epoch_arg="-e ${EPOCH_LENGTH}"
fi
if [ ! -z ${SALT} ]; then
    salt_arg="--salt ${SALT}"
fi
cartesi-rollups-cli app deploy \
    -t $1 \
    --private-key ${CARTESI_AUTH_PRIVATE_KEY} \
    --rpc-url ${CARTESI_BLOCKCHAIN_HTTP_ENDPOINT} \
    -p ${CARTESI_POSTGRES_ENDPOINT} \
    ${owner_args} \
    ${authority_arg} \
    ${epoch_arg} \
    ${salt_arg} \
    ${EXTRA_ARGS} \
    || echo 'Not deployed'
EOF


COPY --chmod=755 <<EOF /register.sh
#!/bin/bash
cartesi-rollups-cli app register \
    -t $1 \
    -p ${CARTESI_POSTGRES_ENDPOINT} \
    -a ${APPLICATION_ADDRESS} \
    -i ${AUTHORITY_ADDRESS} \
    ${EXTRA_ARGS} \
    || echo 'Not deployed'
EOF

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
if [ "$$" -eq 1 ]; then
    # we already have PID 1
    exec /init "$@"
else
    # create a new PID namespace
    exec unshare --pid sh -c '
        # set up /proc and start the real init in the background
        unshare --mount-proc /init "$@" &
        child="$!"
        # forward signals to the real init
        trap "kill -INT \$child" INT
        trap "kill -TERM \$child" TERM
        # wait until the real init exits
        # ("wait" returns early on signals; "kill -0" checks if the process exists)
        until wait "$child" || ! kill -0 "$child" 2>/dev/null; do :; done
    ' sh "$@"
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
