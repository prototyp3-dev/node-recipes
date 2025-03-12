# (c) Cartesi and individual authors (see AUTHORS)
# SPDX-License-Identifier: Apache-2.0 (see LICENSE)

ARG FOUNDRY_DIR=/foundry
ARG CARTESI_ROLLUPS_DIR=/opt/cartesi/rollups-contracts
ARG CARTESI_ROLLUPS_BRANCH=v2.0.0-rc.12
ARG CARTESI_ROLLUPS_VERSION=2.0.0-rc.12
ARG CANNON_DIRECTORY=/cannon


# syntax=docker.io/docker/dockerfile:1
FROM node:22-slim AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable

ARG DEBIAN_FRONTEND=noninteractive
RUN <<EOF
    set -e
    apt-get update
    apt-get install -y --no-install-recommends \
        ca-certificates curl unzip
    rm -rf /var/lib/apt/lists/* /var/log/* /var/cache/*
EOF

# RUN yarn global add --non-interactive @usecannon/cli@2.21.5
RUN corepack pnpm add -g @usecannon/cli

FROM base AS install

ARG DEBIAN_FRONTEND=noninteractive
RUN apt update && apt install -y --no-install-recommends git

ARG FOUNDRY_DIR
ENV FOUNDRY_DIR=${FOUNDRY_DIR}
RUN mkdir -p ${FOUNDRY_DIR}
RUN curl -L https://foundry.paradigm.xyz | bash
RUN ${FOUNDRY_DIR}/bin/foundryup -i stable

ARG CARTESI_ROLLUPS_DIR
ARG CARTESI_ROLLUPS_BRANCH
ARG CARTESI_ROLLUPS_VERSION

RUN mkdir -p ${CARTESI_ROLLUPS_DIR}

# RUN git clone --single-branch --branch ${CARTESI_ROLLUPS_BRANCH} \
#     https://github.com/cartesi/rollups-contracts.git ${CARTESI_ROLLUPS_DIR}

RUN curl -s -L https://github.com/cartesi/rollups-contracts/archive/refs/tags/v${CARTESI_ROLLUPS_VERSION}.tar.gz | \
    tar -C ${CARTESI_ROLLUPS_DIR} -zxf - rollups-contracts-${CARTESI_ROLLUPS_VERSION}/ --strip-components 1

# RUN sed -i -e 's/"dependencies": {/"dependencies": {\n        "@cartesi\/util": "6.3.0",/' ${CARTESI_ROLLUPS_DIR}/package.json

# install npm dependencies    
RUN cd ${CARTESI_ROLLUPS_DIR} && pnpm i

# install forge dependencies
RUN cd ${CARTESI_ROLLUPS_DIR} && ${FOUNDRY_DIR}/bin/forge install --no-git foundry-rs/forge-std@bb4ceea

# make build generate the same artifact as hardhat
RUN <<EOF
set -e
sed -i -e 's/libs = .*/libs = ["@cartesi", "@openzeppelin", "forge-std"]/' ${CARTESI_ROLLUPS_DIR}/foundry.toml
sed -i -e 's/\[profile.default\]/[profile.default]\nevm_version = "paris"\noptimizer = true\nuse_literal_content = true\nauto_detect_remappings = false/' ${CARTESI_ROLLUPS_DIR}/foundry.toml
EOF

RUN rm ${CARTESI_ROLLUPS_DIR}/remappings.txt

RUN <<EOF
set -e
ln -s ${CARTESI_ROLLUPS_DIR}/node_modules/@cartesi ${CARTESI_ROLLUPS_DIR}/@cartesi
ln -s ${CARTESI_ROLLUPS_DIR}/node_modules/@openzeppelin ${CARTESI_ROLLUPS_DIR}/@openzeppelin
ln -s ${CARTESI_ROLLUPS_DIR}/lib/forge-std/src ${CARTESI_ROLLUPS_DIR}/forge-std
EOF

# cannon configuration
RUN <<EOF
set -e
curl -s -L https://github.com/cartesi/rollups-contracts/raw/refs/heads/main/cannonfile.toml \
    -o ${CARTESI_ROLLUPS_DIR}/cannonfile.toml
sed -i -e "s/version = \".*\"/version = \"${CARTESI_ROLLUPS_VERSION}\"/" ${CARTESI_ROLLUPS_DIR}/cannonfile.toml
sed -i -e 's/true/"0xE1CB04A0fA36DdD16a06ea828007E35e1a3cBC37"/g' ${CARTESI_ROLLUPS_DIR}/cannonfile.toml
EOF

ARG CANNON_DIRECTORY
ENV CANNON_DIRECTORY=${CANNON_DIRECTORY}
RUN mkdir -p ${CANNON_DIRECTORY}
ENV PATH="$PATH:/foundry/bin"

WORKDIR ${CARTESI_ROLLUPS_DIR}
COPY <<EOF ${CARTESI_ROLLUPS_DIR}/build-cannon.sh
anvil_params="--host 0.0.0.0 --block-time 2"
cannon_params="--skip-compile --wipe"
kill_anvil=
keep_alive=true

trap stop_anvil 1 2 3 6

stop_anvil() {
    if [ ! -z \$anvil_pid ]; then
        kill \$anvil_pid
    fi
    exit 0
}

while getopts "kxa:c:" flag; do
    case \$flag in
        a)
        anvil_params=\$OPTARG
        ;;
        c)
        cannon_params=$\OPTARG
        ;;
        x)
        kill_anvil=true
        ;;
        k)
        keep_alive=false
        ;;
        \?)
        echo Invalid option: \$flag
        exit 1
        ;;
    esac
done
anvil --hardfork paris \$anvil_params > /tmp/anvil.log 2>&1 & anvil_pid=\$!
timeout 22 bash -c 'until curl -s -X POST http://localhost:8545 -H "Content-Type: application/json" --data '"'"'{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":83}'"'"' >> /dev/null ; do sleep 1 && echo "wait"; done'
curl -H "Content-Type: application/json" -X POST http://127.0.0.1:8545 --data '{"jsonrpc":"2.0","method":"anvil_setCode","params":["0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7","0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3"],"id":67}'
cannon build --anvil.hardfork paris --chain-id 31337 --rpc-url http://127.0.0.1:8545 --private-key ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \$cannon_params
if [ ! -z \$kill_anvil ]; then
    stop_anvil
else
    if [[ \$keep_alive = 'true' ]]; then
        tail -f /tmp/anvil.log
    fi
fi
EOF

RUN bash ${CARTESI_ROLLUPS_DIR}/build-cannon.sh -x -a "" -c "--dry-run -w deployments/localhost"

FROM base

ARG CANNON_DIRECTORY
ENV CANNON_DIRECTORY=${CANNON_DIRECTORY}
ARG FOUNDRY_DIR
ARG CARTESI_ROLLUPS_VERSION
ENV CARTESI_ROLLUPS_VERSION=${CARTESI_ROLLUPS_VERSION}
ARG CARTESI_ROLLUPS_DIR

COPY --from=install ${FOUNDRY_DIR}/* /usr/local/bin/
COPY --from=install ${CANNON_DIRECTORY} ${CANNON_DIRECTORY}
COPY --from=install ${CARTESI_ROLLUPS_DIR} ${CARTESI_ROLLUPS_DIR}

WORKDIR ${CARTESI_ROLLUPS_DIR}

CMD ["bash","build-cannon.sh"]
