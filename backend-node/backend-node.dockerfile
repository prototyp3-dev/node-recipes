# (c) Cartesi and individual authors (see AUTHORS)
# SPDX-License-Identifier: Apache-2.0 (see LICENSE)

# syntax=docker.io/docker/dockerfile:1

ARG EMULATOR_VERSION=0.18.1
ARG S6_OVERLAY_VERSION=3.2.0.2
ARG TELEGRAF_VERSION=1.32.1
ARG NONODO_VERSION=2.14.1-beta
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

# install nonodo
ARG NONODO_VERSION
RUN curl -s -L https://github.com/Calindra/nonodo/releases/download/v${NONODO_VERSION}/nonodo-v${NONODO_VERSION}-linux-$(dpkg --print-architecture).tar.gz | \
    tar xzf - -C /usr/local/bin nonodo

# configure telegraf
RUN <<EOF
mkdir -p /etc/telegraf
echo "
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

[[inputs.procstat]]

[[outputs.health]]
    service_address = 'http://:9274'

[[inputs.procstat.filter]]
    name = 'rollups-node'
    process_names = ['cartesi-rollups-*', 'jsonrpc-remote-cartesi-*', '*cartesi*', 'telegraf', 'nonodo', 'traefik']

[[outputs.prometheus_client]]
    listen = ':9000'
    collectors_exclude = ['gocollector', 'process']
" > /etc/telegraf/telegraf.conf
EOF

# Configure s6 Telegraf
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/telegraf
echo "longrun" > /etc/s6-overlay/s6-rc.d/telegraf/type
mkdir -p /etc/s6-overlay/s6-rc.d/telegraf/data
echo "#!/command/execlineb -P
wget -qO /dev/null 127.0.0.1:9274/
" > /etc/s6-overlay/s6-rc.d/telegraf/data/check
echo "#!/command/execlineb -P
pipeline -w { sed --unbuffered \"s/^/telegraf: /\" }
fdmove -c 2 1
/usr/bin/telegraf
" > /etc/s6-overlay/s6-rc.d/telegraf/run
EOF

# Configure nginx
RUN <<EOF
mkdir -p /var/log/nginx/
chown -R cartesi:cartesi /var/log/nginx/
mkdir -p /var/cache
chown -R cartesi:cartesi /var/cache
chown -R cartesi:cartesi /var/lib/nginx
echo "
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

    log_format  main  '$remote_addr - $upstream_cache_status rt=$request_time [$time_local] \"$request\" '
                      '$status $body_bytes_sent \"$http_referer\" '
                      '\"$http_user_agent\" \"$http_x_forwarded_for\" '
                      'uct=\"$upstream_connect_time\" uht=\"$upstream_header_time\" urt=\"$upstream_response_time\"';

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
" > /etc/nginx/nginx.conf
rm /etc/nginx/sites-enabled/*
EOF

# Configure s6 nginx
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/nginx
echo "longrun" > /etc/s6-overlay/s6-rc.d/nginx/type
echo "#!/command/execlineb -P
pipeline -w { sed --unbuffered \"s/^/nginx: /\" }
fdmove -c 2 1
/usr/sbin/nginx -g \"daemon off;\"
" > /etc/s6-overlay/s6-rc.d/nginx/run
touch /etc/s6-overlay/s6-rc.d/user/contents.d/nginx
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

# Configure s6 create dir
RUN <<EOF
mkdir -p ${BASE_PATH}
chown -R cartesi:cartesi ${BASE_PATH}
mkdir -p /etc/s6-overlay/s6-rc.d/prepare-dirs
echo "oneshot" > /etc/s6-overlay/s6-rc.d/prepare-dirs/type
echo "#!/command/with-contenv sh
mkdir -p \${SNAPSHOTS_APPS_PATH}
mkdir -p \${NODE_PATH}/snapshots
mkdir -p \${NODE_PATH}/data
" > /etc/s6-overlay/s6-rc.d/prepare-dirs/run.sh
chmod +x /etc/s6-overlay/s6-rc.d/prepare-dirs/run.sh
echo "/etc/s6-overlay/s6-rc.d/prepare-dirs/run.sh" \
> /etc/s6-overlay/s6-rc.d/prepare-dirs/up
EOF

# Configure s6 migrate
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/migrate
echo "oneshot" > /etc/s6-overlay/s6-rc.d/migrate/type
echo "#!/command/with-contenv sh
cartesi-rollups-cli db upgrade -p \${CARTESI_POSTGRES_ENDPOINT}
" > /etc/s6-overlay/s6-rc.d/migrate/run.sh
chmod +x /etc/s6-overlay/s6-rc.d/migrate/run.sh
echo "/etc/s6-overlay/s6-rc.d/migrate/run.sh" \
> /etc/s6-overlay/s6-rc.d/migrate/up
touch /etc/s6-overlay/s6-rc.d/user/contents.d/migrate
EOF

# Configure s6 migrate
RUN <<EOF
touch /etc/s6-overlay/s6-rc.d/createhlgdb/dependencies.d/migrate
mkdir -p /etc/s6-overlay/s6-rc.d/createhlgdb
echo "oneshot" > /etc/s6-overlay/s6-rc.d/createhlgdb/type
echo "#!/command/with-contenv sh
PGPASSWORD=\${POSTGRES_PASSWORD} psql -U \${POSTGRES_USER} -h \${POSTGRES_HOST} \
    -c \"create database \${GRAPHQL_DB};\" || echo \"HLGraphql database alredy created\"
" > /etc/s6-overlay/s6-rc.d/createhlgdb/run.sh
chmod +x /etc/s6-overlay/s6-rc.d/createhlgdb/run.sh
echo "/etc/s6-overlay/s6-rc.d/createhlgdb/run.sh" \
> /etc/s6-overlay/s6-rc.d/createhlgdb/up
touch /etc/s6-overlay/s6-rc.d/user/contents.d/createhlgdb
EOF

# Configure s6 node
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/node/dependencies.d
touch /etc/s6-overlay/s6-rc.d/node/dependencies.d/prepare-dirs \
    /etc/s6-overlay/s6-rc.d/node/dependencies.d/migrate
echo "longrun" > /etc/s6-overlay/s6-rc.d/node/type
echo "#!/command/with-contenv sh
cartesi-rollups-node
" > /etc/s6-overlay/s6-rc.d/node/start.sh
echo "#!/command/execlineb -P
with-contenv
pipeline -w { sed --unbuffered \"s/^/node: /\" }
fdmove -c 2 1
/bin/sh /etc/s6-overlay/s6-rc.d/node/start.sh
" > /etc/s6-overlay/s6-rc.d/node/run
mkdir -p /etc/s6-overlay/s6-rc.d/user/contents.d
touch /etc/s6-overlay/s6-rc.d/user/contents.d/node
EOF

# Configure s6 hlgraphql
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/hlgraphql/dependencies.d
touch /etc/s6-overlay/s6-rc.d/hlgraphql/dependencies.d/createhlgdb
echo "longrun" > /etc/s6-overlay/s6-rc.d/hlgraphql/type
echo "#!/command/with-contenv sh
POSTGRES_DB=\${GRAPHQL_DB} nonodo \
    --disable-devnet \
    --disable-advance \
    --disable-inspect \
    --http-port=\${GRAPHQL_PORT} \
    --raw-enabled \
    --high-level-graphql \
    --graphile-disable-sync \
    --db-implementation=postgres \
    --db-raw-url=\${CARTESI_POSTGRES_ENDPOINT}
" > /etc/s6-overlay/s6-rc.d/hlgraphql/start.sh
echo "#!/command/execlineb -P
with-contenv
pipeline -w { sed --unbuffered \"s/^/hlgraphql: /\" }
fdmove -c 2 1
/bin/sh /etc/s6-overlay/s6-rc.d/hlgraphql/start.sh
" > /etc/s6-overlay/s6-rc.d/hlgraphql/run
mkdir -p /etc/s6-overlay/s6-rc.d/user/contents.d
touch /etc/s6-overlay/s6-rc.d/user/contents.d/hlgraphql
EOF

# deploy script
RUN <<EOF
mkdir -p /mnt/snapshots
chown -R cartesi:cartesi /mnt
echo "#!/bin/bash
if [ ! -z \${OWNER} ]; then
    owner_args=\"-o \${OWNER} -O \${OWNER}\"
fi
if [ ! -z \${AUTHORITY_ADDRESS} ]; then
    authority_arg=\"-i \${AUTHORITY_ADDRESS}\"
fi
if [ ! -z \${EPOCH_LENGTH} ]; then
    epoch_arg=\"-e \${EPOCH_LENGTH}\"
fi
if [ ! -z \${SALT} ]; then
    salt_arg=\"--salt \${SALT}\"
fi
cartesi-rollups-cli app deploy \
    -t \$1 \
    --private-key \${CARTESI_AUTH_PRIVATE_KEY} \
    --rpc-url \${CARTESI_BLOCKCHAIN_HTTP_ENDPOINT} \
    -p \${CARTESI_POSTGRES_ENDPOINT} \
    \${owner_args} \
    \${authority_arg} \
    \${epoch_arg} \
    \${salt_arg} \
    \${EXTRA_ARGS} \
    || echo 'Not deployed'
" > /deploy.sh
chmod +x /deploy.sh
echo "#!/bin/bash
cartesi-rollups-cli app register \
    -t \$1 \
    -p \${CARTESI_POSTGRES_ENDPOINT} \
    -a \${APPLICATION_ADDRESS} \
    -i \${AUTHORITY_ADDRESS} \
    \${EXTRA_ARGS} \
    || echo 'Not deployed'
" > /register.sh
chmod +x /register.sh
EOF

# =============================================================================
# STAGE: rollups-node-we
#
# =============================================================================

FROM base-rollups-node-we AS rollups-node-we-cloud

RUN touch /etc/s6-overlay/s6-rc.d/user/contents.d/telegraf

# Configure nginx server with cache
RUN <<EOF
echo "
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
" > /etc/nginx/sites-available/cloud.conf
ln -sr /etc/nginx/sites-available/cloud.conf /etc/nginx/sites-enabled/cloud.conf
EOF

# Create init wrapper
RUN <<EOF
echo '#!/bin/sh
# run /init with PID 1, creating a new PID namespace if necessary
if [ "$$" -eq 1 ]; then
    # we already have PID 1
    exec /init "$@"
else
    # create a new PID namespace
    exec unshare --pid sh -c '"'"'
        # set up /proc and start the real init in the background
        unshare --mount-proc /init "$@" &
        child="$!"
        # forward signals to the real init
        trap "kill -INT \$child" INT
        trap "kill -TERM \$child" TERM
        # wait until the real init exits
        # ("wait" returns early on signals; "kill -0" checks if the process exists)
        until wait "$child" || ! kill -0 "$child" 2>/dev/null; do :; done
    '"'"' sh "$@"
fi
' > /init-wrapper
chmod +x /init-wrapper
EOF

CMD ["/init-wrapper"]


FROM base-rollups-node-we AS rollups-node-we

RUN chown -R cartesi:cartesi /run

# Configure nginx server with cache
RUN <<EOF
echo "
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
" > /etc/nginx/sites-available/node.conf
ln -sr /etc/nginx/sites-available/node.conf /etc/nginx/sites-enabled/node.conf
EOF

# Set user to low-privilege.
USER cartesi

# Set the Go supervisor as the command.
CMD [ "/init" ]

