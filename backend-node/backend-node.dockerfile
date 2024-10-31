# (c) Cartesi and individual authors (see AUTHORS)
# SPDX-License-Identifier: Apache-2.0 (see LICENSE)

# syntax=docker.io/docker/dockerfile:1

ARG EMULATOR_VERSION=0.18.1
ARG RUST_VERSION=1.78.0
ARG S6_OVERLAY_VERSION=3.2.0.2
ARG TELEGRAF_VERSION=1.32.1
ARG NONODO_VERSION=2.11.3-beta

# Build directories.
ARG RUST_BUILD_PATH=/build/cartesi/rust
ARG GO_BUILD_PATH=/build/cartesi/go
ARG EMULATOR_VERSION=0.18.1
ARG FOUNDRY_NIGHTLY_VERSION=9dbfb2f1115466b28f2697e158131f90df6b2590

FROM  cartesi/machine-emulator:${EMULATOR_VERSION} AS devnet-base

USER root

# Install ca-certificates, curl, and git (setup).
ENV DEBIAN_FRONTEND=noninteractive
RUN <<EOF
    set -e
    apt-get update
    apt-get install -y --no-install-recommends ca-certificates curl git
    rm -rf /var/lib/apt/lists/* /var/log/* /var/cache/*
EOF

# Install Foundry from downloaded pre-compiled binaries.
ARG FOUNDRY_NIGHTLY_VERSION
RUN <<EOF
    set -ex
    URL=https://github.com/foundry-rs/foundry/releases/download
    VERSION=nightly-${FOUNDRY_NIGHTLY_VERSION}
    ARCH=$(dpkg --print-architecture)
    ARTIFACT=foundry_nightly_linux_${ARCH}.tar.gz
    curl -sSL ${URL}/${VERSION}/${ARTIFACT} | tar -zx -C /usr/local/bin
EOF

# =============================================================================
# STAGE: devnet-deployer
#
# This stage builds the devnet state that will be loaded in Anvil.
# =============================================================================

FROM devnet-base AS devnet-deployer

# Install nodejs & pnpm.
ENV DEBIAN_FRONTEND=noninteractive
RUN <<EOF
    set -e
    apt-get install -y --no-install-recommends gnupg jq
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y --no-install-recommends nodejs
    npm install -g @pnpm/exe
EOF

COPY rollups-contracts /opt/cartesi/rollups-contracts

RUN <<EOF
    set -e
    cd /opt/cartesi/rollups-contracts
    anvil --preserve-historical-states --dump-state=anvil_state.json > anvil.log 2>&1 &
    ANVIL_PID=$!
    pnpm install
    if ! pnpm run deploy:development; then
        echo "Failed to deploy contracts"
        cat anvil.log
        exit 1
    fi
    cd deployments/localhost
    jq -c -n --argjson chainId $(cat .chainId) '[inputs | { (input_filename | gsub(".*/|[.]json$"; "")) : .address }] | add | .ChainId = $chainId' *.json > ../../deployment.json
    kill -15 ${ANVIL_PID}
    elapsed=0
    TIMEOUT=30
    while kill -0 ${ANVIL_PID} 2>/dev/null; do
	if [ $elapsed -ge $TIMEOUT ]; then
	    echo "Error:  Anvil state dump timed out after ${TIMEOUT} seconds" >&2
	    exit 1
	fi
	sleep 1
	elapsed=$((elapsed + 1))
    done
EOF

# =============================================================================
# STAGE: rollups-node-devnet
#
# This stage contains the Ethereum node that the rollups node uses for testing.
# It copies the anvil state from the builder stage and starts the local anvil
# instance.
#
# It also requires the machine-snapshot built in the snapshot-builder stage.
# =============================================================================

FROM devnet-base AS rollups-node-devnet

# Copy anvil state file and devnet deployment info.
ARG DEVNET_BUILD_PATH=/opt/cartesi/rollups-contracts
COPY --from=devnet-deployer ${DEVNET_BUILD_PATH}/anvil_state.json /usr/share/devnet/anvil_state.json
COPY --from=devnet-deployer ${DEVNET_BUILD_PATH}/deployment.json /usr/share/devnet/deployment.json

HEALTHCHECK --interval=1s --timeout=1s --retries=5 \
	CMD curl \
	-X \
	POST \
	-s \
	-H 'Content-Type: application/json' \
	-d '{"jsonrpc":"2.0","id":"1","method":"net_listening","params":[]}' \
	http://127.0.0.1:8545

CMD ["anvil", "--block-time", "1", "--host", "0.0.0.0", "--load-state", "/usr/share/devnet/anvil_state.json"]

FROM cartesi/machine-emulator:${EMULATOR_VERSION} AS common-env

USER root

# Re-declare ARGs so they can be used in the RUN block
ARG RUST_BUILD_PATH
ARG GO_BUILD_PATH

# Install ca-certificates and curl (setup).
RUN <<EOF
    set -e
    apt-get update
    apt-get install -y --no-install-recommends ca-certificates curl wget build-essential pkg-config libssl-dev
    mkdir -p /opt/rust/rustup /opt/go ${RUST_BUILD_PATH} ${GO_BUILD_PATH}/rollups-node
    chown -R cartesi:cartesi /opt/rust /opt/go ${RUST_BUILD_PATH} ${GO_BUILD_PATH}
EOF

USER cartesi

# =============================================================================
# STAGE: contracts-artifacts
#
# - Generate the contracts artifacts.
# =============================================================================

FROM node:20-slim AS contracts-artifacts

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable
COPY rollups-contracts /build/rollups-contracts
WORKDIR /build/rollups-contracts
RUN pnpm install --frozen-lockfile && pnpm export

# =============================================================================
# STAGE: rust-installer
#
# - Install rust and cargo-chef.
# =============================================================================

FROM common-env AS rust-installer

# Get Rust
ENV CARGO_HOME=/opt/rust/cargo
ENV RUSTUP_HOME=/opt/rust/rustup

RUN <<EOF
    set -e
    cd /tmp
    wget https://github.com/rust-lang/rustup/archive/refs/tags/1.27.0.tar.gz
    echo "3d331ab97d75b03a1cc2b36b2f26cd0a16d681b79677512603f2262991950ad1  1.27.0.tar.gz" | sha256sum --check
    tar xzf 1.27.0.tar.gz
    bash rustup-1.27.0/rustup-init.sh \
        -y \
        --no-modify-path \
        --default-toolchain 1.78 \
        --component rustfmt \
        --profile minimal
    rm -rf 1.27.0*
    $CARGO_HOME/bin/cargo install cargo-chef
EOF

ENV PATH="${CARGO_HOME}/bin:${PATH}"

ARG RUST_BUILD_PATH
WORKDIR ${RUST_BUILD_PATH}

# =============================================================================
# STAGE: rust-prepare
#
# This stage prepares the recipe with just the external dependencies.
# =============================================================================

FROM rust-installer AS rust-prepare
COPY ./cmd/authority-claimer/ .
RUN cargo chef prepare --recipe-path recipe.json

# =============================================================================
# STAGE: rust-builder
#
# This stage builds the Rust binaries. First it builds the external
# dependencies and then it builds the node binaries.
# =============================================================================

FROM rust-installer AS rust-builder

# Build external dependencies with cargo chef.
COPY --from=rust-prepare ${RUST_BUILD_PATH}/recipe.json .
RUN cargo chef cook --release --recipe-path recipe.json

COPY --chown=cartesi:cartesi ./cmd/authority-claimer/ .
COPY --from=contracts-artifacts /build/rollups-contracts/export/artifacts ${RUST_BUILD_PATH}/../../rollups-contracts/export/artifacts

# Build application.
RUN cargo build --release

# =============================================================================
# STAGE: go-installer
#
# This stage installs Go in the /opt directory.
# =============================================================================

FROM common-env AS go-installer
# Download and verify Go based on the target architecture
RUN <<EOF
    set -e
    ARCH=$(dpkg --print-architecture)
    wget -O /tmp/go.tar.gz "https://go.dev/dl/go1.22.7.linux-${ARCH}.tar.gz"
    sha256sum /tmp/go.tar.gz
    case "$ARCH" in
        amd64) echo "fc5d49b7a5035f1f1b265c17aa86e9819e6dc9af8260ad61430ee7fbe27881bb  /tmp/go.tar.gz" | sha256sum --check ;;
        arm64) echo "ed695684438facbd7e0f286c30b7bc2411cfc605516d8127dc25c62fe5b03885  /tmp/go.tar.gz" | sha256sum --check ;;
        *) echo "unsupported architecture: $ARCH"; exit 1 ;;
    esac
    tar -C /opt -xzf /tmp/go.tar.gz
    rm /tmp/go.tar.gz
EOF

# Set up Go environment variables
ENV PATH="/opt/go/bin:$PATH"

# =============================================================================
# STAGE: go-prepare
#
# This stage prepares the Go build environment. It downloads the external
# =============================================================================

FROM go-installer AS go-prepare

ARG GO_BUILD_PATH
WORKDIR ${GO_BUILD_PATH}

ENV GOCACHE=${GO_BUILD_PATH}/.cache
ENV GOENV=${GO_BUILD_PATH}/.config/go/env
ENV GOPATH=${GO_BUILD_PATH}/.go

# Download external dependencies.
COPY go.mod ${GO_BUILD_PATH}/rollups-node/
COPY go.sum ${GO_BUILD_PATH}/rollups-node/
RUN cd ${GO_BUILD_PATH}/rollups-node && go mod download

# =============================================================================
# STAGE: go-builder
#
# This stage builds the node Go binaries. First it downloads the external
# dependencies and then it builds the binaries.
# =============================================================================

FROM go-prepare AS go-builder

ARG GO_BUILD_PATH

# Build application.
COPY --chown=cartesi:cartesi Makefile ${GO_BUILD_PATH}/rollups-node/Makefile
COPY --chown=cartesi:cartesi api ${GO_BUILD_PATH}/rollups-node/api
COPY --chown=cartesi:cartesi cmd ${GO_BUILD_PATH}/rollups-node/cmd
COPY --chown=cartesi:cartesi dev ${GO_BUILD_PATH}/rollups-node/dev
COPY --chown=cartesi:cartesi internal ${GO_BUILD_PATH}/rollups-node/internal
COPY --chown=cartesi:cartesi pkg ${GO_BUILD_PATH}/rollups-node/pkg
COPY --from=contracts-artifacts /build/rollups-contracts/export/artifacts ${GO_BUILD_PATH}/rollups-node/rollups-contracts/export/artifacts

RUN cd ${GO_BUILD_PATH}/rollups-node && make build-go

# =============================================================================
# STAGE: rollups-node
#
# This stage prepares the final Docker image that will be used in the production
# environment. It installs in /usr/bin all the binaries necessary to run the
# node.
#
# (This stage copies the binaries from previous stages.)
# =============================================================================

FROM cartesi/machine-emulator:${EMULATOR_VERSION} AS base-rollups-node-we

ARG NODE_RUNTIME_DIR=/var/lib/cartesi-rollups-node

USER root

# Download system dependencies required at runtime.
ARG DEBIAN_FRONTEND=noninteractive
RUN <<EOF
    set -e
    apt-get update
    apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
        procps \
        xz-utils
    rm -rf /var/lib/apt/lists/* /var/log/* /var/cache/*
    mkdir -p ${NODE_RUNTIME_DIR}/snapshots ${NODE_RUNTIME_DIR}/data
    chown -R cartesi:cartesi ${NODE_RUNTIME_DIR}
EOF

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

# Configure telegraf



# Copy Rust binaries.
# Explicitly copy each binary to avoid adding unnecessary files to the runtime
# image.
ARG RUST_BUILD_PATH
ARG RUST_TARGET=${RUST_BUILD_PATH}/target/release
COPY --from=rust-builder ${RUST_TARGET}/cartesi-rollups-authority-claimer /usr/bin

# Copy Go binary.
ARG GO_BUILD_PATH
COPY --from=go-builder ${GO_BUILD_PATH}/rollups-node/cartesi-rollups-* /usr/bin


# Env variables
ENV CARTESI_HTTP_PORT=8080
ENV HEALTHZ_PORT=8081


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
touch /etc/s6-overlay/s6-rc.d/advance/deploy-app/migrate
echo "oneshot" > /etc/s6-overlay/s6-rc.d/deploy-app/type
echo "#!/command/with-contenv sh
if [ ! -z \${AUTHORITY_ADDRESS} ]; then
    echo cartesi-rollups-cli app deploy -t /mnt/snapshot/0 -i \${AUTHORITY_ADDRESS}
else
    echo cartesi-rollups-cli app deploy -t /mnt/snapshot/0
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
    /etc/s6-overlay/s6-rc.d/user/contents.d/deploy-app
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
# POSTGRES_HOST=localhost POSTGRES_PORT=5432 POSTGRES_DB=hlgraphql POSTGRES_USER=postgres POSTGRES_PASSWORD=password  
# ./nonodo -d --raw-enabled --high-level-graphql --graphile-disable-sync --db-implementation=postgres --db-raw-url=postgres://postgres:password@localhost:5432/rollupsdb?sslmode=disable --disable-devnet --http-port=60000

# Set user to low-privilege.
USER cartesi

WORKDIR ${NODE_RUNTIME_DIR}

HEALTHCHECK --interval=1s --timeout=1s --retries=5 \
    CMD curl -G -f -H 'Content-Type: application/json' http://127.0.0.1:${HEALTHZ_PORT}/healthz

# Set the Go supervisor as the command.
CMD [ "/init" ]

# =============================================================================
# STAGE: rollups-node-we
#
# =============================================================================

FROM base-rollups-node-we AS rollups-node-we

# Set user to low-privilege.
USER cartesi

WORKDIR ${NODE_RUNTIME_DIR}

HEALTHCHECK --interval=1s --timeout=1s --retries=5 \
    CMD curl -G -f -H 'Content-Type: application/json' http://127.0.0.1:${HEALTHZ_PORT}/healthz

# Set the Go supervisor as the command.
CMD [ "/init" ]


