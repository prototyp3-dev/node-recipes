# (c) Cartesi and individual authors (see AUTHORS)
# SPDX-License-Identifier: Apache-2.0 (see LICENSE)

# syntax=docker.io/docker/dockerfile:1

ARG EMULATOR_VERSION=0.18.1
ARG S6_OVERLAY_VERSION=3.2.0.2
ARG TELEGRAF_VERSION=1.32.1
ARG NONODO_VERSION=2.11.3-beta

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

# Env variables
ENV CARTESI_HTTP_PORT=10000
ENV HEALTHZ_PORT=10001

# configure telegraf
RUN <<EOF
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
mkdir -p /etc/s6-overlay/s6-rc.d/migrate
echo "oneshot" > /etc/s6-overlay/s6-rc.d/migrate/type
echo "#!/command/with-contenv sh
cartesi-rollups-cli db upgrade -p \${CARTESI_POSTGRES_ENDPOINT}
" > /etc/s6-overlay/s6-rc.d/migrate/run.sh
chmod +x /etc/s6-overlay/s6-rc.d/migrate/run.sh
echo "/etc/s6-overlay/s6-rc.d/migrate/run.sh" \
> /etc/s6-overlay/s6-rc.d/migrate/up
mkdir -p /etc/s6-overlay/s6-rc.d/deploy-app/dependencies.d
touch /etc/s6-overlay/s6-rc.d/deploy-app/dependencies.d/migrate
echo "oneshot" > /etc/s6-overlay/s6-rc.d/deploy-app/type
echo "#!/command/with-contenv sh
if [ ! -z \${AUTHORITY_ADDRESS} ]; then
    cartesi-rollups-cli app deploy \
     -t /mnt/snapshot/0 \
     --mnemonic \"\${CARTESI_AUTH_MNEMONIC}\" \
     --rpc-url \${CARTESI_BLOCKCHAIN_HTTP_ENDPOINT} \
     -p \${CARTESI_POSTGRES_ENDPOINT} \
     -i \${AUTHORITY_ADDRESS} || echo 'Not deployed'
else
    cartesi-rollups-cli app deploy \
     -t /mnt/snapshot/0 \
     --mnemonic \"\${CARTESI_AUTH_MNEMONIC}\" \
     --rpc-url \${CARTESI_BLOCKCHAIN_HTTP_ENDPOINT} \
     -p \${CARTESI_POSTGRES_ENDPOINT} || echo 'Not deployed'
fi
" > /etc/s6-overlay/s6-rc.d/deploy-app/run.sh
chmod +x /etc/s6-overlay/s6-rc.d/deploy-app/run.sh
echo "/etc/s6-overlay/s6-rc.d/deploy-app/run.sh" \
> /etc/s6-overlay/s6-rc.d/deploy-app/up
chmod +x /etc/s6-overlay/s6-rc.d/deploy-app/run.sh
mkdir -p /etc/s6-overlay/s6-rc.d/node/dependencies.d
touch /etc/s6-overlay/s6-rc.d/advance/node/migrate
touch /etc/s6-overlay/s6-rc.d/advance/node/deploy-app
echo "longrun" > /etc/s6-overlay/s6-rc.d/node/type
echo "#!/command/with-contenv sh
cartesi-rollups-node
" > /etc/s6-overlay/s6-rc.d/node/run
mkdir -p /etc/s6-overlay/s6-rc.d/user/contents.d
touch /etc/s6-overlay/s6-rc.d/user/contents.d/migrate \
    /etc/s6-overlay/s6-rc.d/user/contents.d/deploy-app \
    /etc/s6-overlay/s6-rc.d/user/contents.d/node \
    /etc/s6-overlay/s6-rc.d/user/contents.d/telegraf
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


COPY --from=base-rollups-node-we /etc/telegraf/telegraf.conf /etc/telegraf/telegraf.conf
COPY --from=base-rollups-node-we /etc/s6-overlay/s6-rc.d/telegraf /etc/s6-overlay/s6-rc.d/telegraf


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
    CMD curl -G -f -H 'Content-Type: application/json' http://127.0.0.1:${HEALTHZ_PORT}/healthz

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
    CMD curl -G -f -H 'Content-Type: application/json' http://127.0.0.1:${HEALTHZ_PORT}/healthz

# Set the Go supervisor as the command.
CMD [ "/init" ]


