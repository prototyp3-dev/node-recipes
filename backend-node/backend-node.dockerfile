# (c) Cartesi and individual authors (see AUTHORS)
# SPDX-License-Identifier: Apache-2.0 (see LICENSE)

# syntax=docker.io/docker/dockerfile:1

ARG EMULATOR_VERSION=0.18.1
ARG S6_OVERLAY_VERSION=3.2.0.2
ARG TELEGRAF_VERSION=1.32.1
ARG NONODO_VERSION=2.14.0-beta

# =============================================================================
# STAGE: telegraf conf
#
# =============================================================================

FROM cartesi/machine-emulator:${EMULATOR_VERSION} AS telegraf-conf

USER root

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
    process_names = ['cartesi-rollups-*', 'jsonrpc-remote-cartesi-*', '*cartesi*', 'telegraf']

[[outputs.prometheus_client]]
    listen = ':9000'
    collectors_exclude = ['gocollector', 'process']
" > /etc/telegraf/telegraf.conf
EOF

# set Services
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

# =============================================================================
# STAGE: base-rollups-node-we
#
# =============================================================================

FROM recipe-stage/rollups-node AS base-rollups-node-we

USER root

# Download system dependencies required at runtime.
ARG DEBIAN_FRONTEND=noninteractive
RUN <<EOF
    set -e
    apt-get update
    apt-get install -y --no-install-recommends \
        xz-utils
    rm -rf /var/lib/apt/lists/* /var/log/* /var/cache/*
EOF

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

COPY --from=telegraf-conf /etc/telegraf/telegraf.conf /etc/telegraf/telegraf.conf
COPY --from=telegraf-conf /etc/s6-overlay/s6-rc.d/telegraf /etc/s6-overlay/s6-rc.d/telegraf
    
# Env variables
ENV CARTESI_HTTP_PORT=10000
ENV ESPRESSO_SERVICE_ENDPOINT=0.0.0.0:10030

# set Services
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/migrate
echo "oneshot" > /etc/s6-overlay/s6-rc.d/migrate/type
echo "#!/command/with-contenv sh
cartesi-rollups-cli db upgrade -p \${CARTESI_POSTGRES_ENDPOINT}
" > /etc/s6-overlay/s6-rc.d/migrate/run.sh
chmod +x /etc/s6-overlay/s6-rc.d/migrate/run.sh
echo "/etc/s6-overlay/s6-rc.d/migrate/run.sh" \
> /etc/s6-overlay/s6-rc.d/migrate/up
mkdir -p /etc/s6-overlay/s6-rc.d/node/dependencies.d
touch /etc/s6-overlay/s6-rc.d/advance/node/migrate
echo "longrun" > /etc/s6-overlay/s6-rc.d/node/type
echo "#!/command/with-contenv sh
cartesi-rollups-node
" > /etc/s6-overlay/s6-rc.d/node/run
mkdir -p /etc/s6-overlay/s6-rc.d/user/contents.d
touch /etc/s6-overlay/s6-rc.d/user/contents.d/migrate \
    /etc/s6-overlay/s6-rc.d/user/contents.d/node \
    /etc/s6-overlay/s6-rc.d/user/contents.d/telegraf
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
# STAGE: hlgraphql
#
# =============================================================================

FROM cartesi/machine-emulator:${EMULATOR_VERSION} AS hlgraphql

USER root

ARG DEBIAN_FRONTEND=noninteractive
RUN <<EOF
    set -e
    apt-get update
    apt-get install -y --no-install-recommends wget ca-certificates xz-utils
    rm -rf /var/lib/apt/lists/* /var/log/* /var/cache/*
EOF

ARG NONODO_VERSION
RUN wget -qO- https://github.com/Calindra/nonodo/releases/download/v${NONODO_VERSION}/nonodo-v${NONODO_VERSION}-linux-$(dpkg --print-architecture).tar.gz | \
    tar xzf - -C /usr/local/bin nonodo

# install s6 overlay
ARG S6_OVERLAY_VERSION
RUN wget -qO- https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz | \
    tar xJf - -C / 
RUN wget -qO- https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-$(uname -m).tar.xz | \
    tar xJf - -C / 

# install telegraf
ARG TELEGRAF_VERSION
RUN wget -qO- wget https://dl.influxdata.com/telegraf/releases/telegraf-${TELEGRAF_VERSION}_linux_$(dpkg --print-architecture).tar.gz | \
    tar xzf - --strip-components 2 -C / ./telegraf-${TELEGRAF_VERSION}

COPY --from=telegraf-conf /etc/telegraf/telegraf.conf /etc/telegraf/telegraf.conf
COPY --from=telegraf-conf /etc/s6-overlay/s6-rc.d/telegraf /etc/s6-overlay/s6-rc.d/telegraf

# set Services
RUN <<EOF
mkdir -p /etc/s6-overlay/s6-rc.d/nonodo
echo "longrun" > /etc/s6-overlay/s6-rc.d/nonodo/type
echo "#!/command/with-contenv sh
nonodo \
    --disable-devnet \
    --disable-advance \
    --disable-inspect \
    --http-address=0.0.0.0 \
    --http-port=\${GRAPHQL_PORT} \
    --raw-enabled \
    --high-level-graphql \
    --graphile-disable-sync \
    --db-implementation=postgres \
    --db-raw-url=\${CARTESI_POSTGRES_ENDPOINT}
" > /etc/s6-overlay/s6-rc.d/nonodo/run
mkdir -p /etc/s6-overlay/s6-rc.d/user/contents.d
touch /etc/s6-overlay/s6-rc.d/user/contents.d/telegraf \
    /etc/s6-overlay/s6-rc.d/user/contents.d/nonodo
EOF

HEALTHCHECK --interval=1s --timeout=1s --retries=5 \
    CMD curl -G -f -H 'Content-Type: application/json' http://127.0.0.1:${CARTESI_HTTP_PORT}/healthz

# Set user to low-privilege.
USER cartesi

# Set the Go supervisor as the command.
CMD [ "/init" ]

# =============================================================================
# STAGE: rollups-node-we
#
# =============================================================================

FROM base-rollups-node-we AS rollups-node-we

# Set user to low-privilege.
USER cartesi

HEALTHCHECK --interval=1s --timeout=1s --retries=5 \
    CMD wget -qO /dev/null --header='Content-Type: application/json' \
    --post-data='{"query":"{ inputs(last:1) { edges { node { id } } } }"}' \
    'http://127.0.0.1:10004/graphql'

# Set the Go supervisor as the command.
CMD [ "/init" ]


