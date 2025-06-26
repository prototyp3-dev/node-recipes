# (c) Cartesi and individual authors (see AUTHORS)
# SPDX-License-Identifier: Apache-2.0 (see LICENSE)

# syntax=docker.io/docker/dockerfile:1

ARG FOUNDRY_DIR=/foundry
ARG FOUNDRY_VERSION=1.2.1
ARG CARTESI_ROLLUPS_DIR=/opt/cartesi/rollups-contracts
# ARG CARTESI_ROLLUPS_BRANCH=v2.0.0-rc.18
ARG CARTESI_ROLLUPS_VERSION=2.0.0
ARG CARTESI_PRT_VERSION=1.0.0
ARG MACHINE_STEP_VERSION=0.13.0
ARG CANNON_DIRECTORY=/cannon
ARG STATE_FILE=/usr/share/devnet/anvil_state.json
ARG ESPRESSO_DEPLOYMENT_FILE=/usr/share/devnet/espresso-deployment.txt
ARG ESPRESSO_DEV_NODE_TAG=20250623

FROM ghcr.io/espressosystems/espresso-sequencer/espresso-dev-node:${ESPRESSO_DEV_NODE_TAG} AS espresso-dev-node

RUN <<EOF
apt update
apt install -y --no-install-recommends \
    git
EOF

ARG FOUNDRY_VERSION
ARG FOUNDRY_DIR
ENV FOUNDRY_DIR=${FOUNDRY_DIR}
RUN mkdir -p ${FOUNDRY_DIR}
RUN curl -L https://foundry.paradigm.xyz | bash
RUN ${FOUNDRY_DIR}/bin/foundryup -i ${FOUNDRY_VERSION}

ARG STATE_FILE
ARG ESPRESSO_DEPLOYMENT_FILE

RUN mkdir -p $(dirname ${STATE_FILE}) && \
    mkdir -p $(dirname ${ESPRESSO_DEPLOYMENT_FILE})
COPY --chmod=755 <<EOF /dump-devnet-state.sh
#!/bin/bash
set -e
${FOUNDRY_DIR}/bin/anvil --dump-state ${STATE_FILE} --preserve-historical-states > /tmp/anvil.log 2>&1 & anvil_pid=\$!
timeout 22 bash -c 'until curl -s -X POST http://localhost:8545 -H "Content-Type: application/json" --data '"'"'{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":83}'"'"' >> /dev/null ; do sleep 1 && echo "wait"; done'
RUST_LOG=info espresso-dev-node --rpc-url http://127.0.0.1:8545 --l1-deployment dump --sequencer-api-port 8770 2>&1 | grep deployed | awk '{printf "%s: %s\\n",\$6,\$8 }' > ${ESPRESSO_DEPLOYMENT_FILE}
kill \$anvil_pid
wait \$anvil_pid
EOF

RUN bash /dump-devnet-state.sh

FROM node:22-slim AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable

ARG DEBIAN_FRONTEND=noninteractive
RUN <<EOF
    set -e
    apt-get update
    apt-get install -y --no-install-recommends \
        ca-certificates curl
    rm -rf /var/lib/apt/lists/* /var/log/* /var/cache/*
EOF

# RUN yarn global add --non-interactive @usecannon/cli@2.21.5
RUN corepack pnpm add -g @usecannon/cli

FROM base AS install

ARG DEBIAN_FRONTEND=noninteractive
RUN apt update && apt install -y --no-install-recommends git

ARG FOUNDRY_VERSION
ARG FOUNDRY_DIR
ENV FOUNDRY_DIR=${FOUNDRY_DIR}
RUN mkdir -p ${FOUNDRY_DIR}
RUN curl -L https://foundry.paradigm.xyz | bash
RUN ${FOUNDRY_DIR}/bin/foundryup -i ${FOUNDRY_VERSION}

ARG CARTESI_ROLLUPS_DIR
# ARG CARTESI_ROLLUPS_BRANCH
ARG CARTESI_ROLLUPS_VERSION
ARG CARTESI_PRT_VERSION
ARG MACHINE_STEP_VERSION

RUN mkdir -p ${CARTESI_ROLLUPS_DIR}/dave

RUN curl -s -L https://github.com/cartesi/dave/archive/refs/tags/v${CARTESI_PRT_VERSION}.tar.gz | \
    tar -C ${CARTESI_ROLLUPS_DIR}/dave -zxf - --strip-components 1 dave-${CARTESI_PRT_VERSION}

RUN curl -s -L https://github.com/cartesi/machine-solidity-step/archive/refs/tags/v${MACHINE_STEP_VERSION}.tar.gz | \
    tar -C ${CARTESI_ROLLUPS_DIR}/dave/machine/step -zxf - --strip-components 1 machine-solidity-step-${MACHINE_STEP_VERSION}


# RUN git clone --single-branch --branch ${CARTESI_ROLLUPS_BRANCH} \
#     https://github.com/cartesi/rollups-contracts.git ${CARTESI_ROLLUPS_DIR}

# RUN curl -s -L https://github.com/cartesi/rollups-contracts/archive/refs/tags/v${CARTESI_ROLLUPS_VERSION}.tar.gz | \
#     tar -C ${CARTESI_ROLLUPS_DIR} -zxf - rollups-contracts-${CARTESI_ROLLUPS_VERSION}/ --strip-components 1

# install npm dependencies    
# RUN cd ${CARTESI_ROLLUPS_DIR} && pnpm install
RUN cd ${CARTESI_ROLLUPS_DIR}/dave/cartesi-rollups/contracts && pnpm install

# install forge dependencies
# RUN cd ${CARTESI_ROLLUPS_DIR} && ${FOUNDRY_DIR}/bin/forge soldeer install
RUN cd ${CARTESI_ROLLUPS_DIR}/dave/cartesi-rollups/contracts && ${FOUNDRY_DIR}/bin/forge soldeer install

ARG CANNON_DIRECTORY
ENV CANNON_DIRECTORY=${CANNON_DIRECTORY}
RUN mkdir -p ${CANNON_DIRECTORY}
ENV PATH="$PATH:/$FOUNDRY_DIR/bin"

WORKDIR ${CARTESI_ROLLUPS_DIR}

COPY <<EOF ${CARTESI_ROLLUPS_DIR}/dave/cartesi-rollups/contracts/cannonfile-deploy.toml
name = 'devnet'
version = '0.0.1'

[clone.cartesiRollups]
source = "cartesi-rollups:${CARTESI_ROLLUPS_VERSION}@main"
chainId = 1

[clone.prtContracts]
source = "cartesi-prt-multilevel:${CARTESI_PRT_VERSION}@main"
#target = "cartesi-prt-multilevel:0.0.1@test"
chainId = 1

[deploy.DaveConsensusFactory]
artifact = "DaveConsensusFactory"
args = [
  "<%= cartesiRollups.InputBox.address %>",
  "<%= prtContracts.MultiLevelTournamentFactory.address %>",
]
create2 = true
salt = "<%= zeroHash %>"
ifExists = "continue"
depends = ['clone.prtContracts','clone.cartesiRollups']

EOF

COPY --chmod=755 <<EOF ${CARTESI_ROLLUPS_DIR}/devnet.sh
#!/bin/bash
set -e
anvil_params="--host 0.0.0.0 --block-time 2 --slots-in-an-epoch 1"
cannon_params="${CARTESI_ROLLUPS_DIR}/dave/cartesi-rollups/contracts/cannonfile-deploy.toml --skip-compile --wipe"
kill_anvil=
keep_alive=true
state_file=

trap stop_anvil 1 2 3 6

stop_anvil() {
    if [ ! -z \$anvil_pid ]; then
        kill \$anvil_pid
        wait \$anvil_pid
    fi
    exit 0
}

while getopts "kxra:c:s:" flag; do
    case \$flag in
        a)
        anvil_params=\$OPTARG
        ;;
        c)
        cannon_params=$\OPTARG
        ;;
        s)
        state_file=$\OPTARG
        ;;
        x)
        kill_anvil=true
        ;;
        k)
        keep_alive=false
        ;;
        r)
        cannon cartesi-rollups:${CARTESI_ROLLUPS_VERSION} $\ARGS
        exit 0
        ;;
        \?)
        echo Invalid option: \$flag
        exit 1
        ;;
    esac
done
if [ ! -z \$state_file ]; then
    anvil --load-state \$state_file \$anvil_params > /tmp/anvil.log 2>&1 & anvil_pid=\$!
    timeout 22 bash -c 'until curl -s -X POST http://localhost:8545 -H "Content-Type: application/json" --data '"'"'{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":83}'"'"' >> /dev/null ; do sleep 1 && echo "wait"; done'
else
    anvil \$anvil_params > /tmp/anvil.log 2>&1 & anvil_pid=\$!
    timeout 22 bash -c 'until curl -s -X POST http://localhost:8545 -H "Content-Type: application/json" --data '"'"'{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":83}'"'"' >> /dev/null ; do sleep 1 && echo "wait"; done'
    # curl -H "Content-Type: application/json" -X POST http://127.0.0.1:8545 --data '{"jsonrpc":"2.0","method":"anvil_setCode","params":["0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7","0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3"],"id":67}'
    cannon build --chain-id 31337 --rpc-url http://127.0.0.1:8545 --private-key ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \$cannon_params
fi
if [ ! -z \$kill_anvil ]; then
    stop_anvil
else
    if [[ \$keep_alive = 'true' ]]; then
        tail -f /tmp/anvil.log
    fi
fi
EOF

ARG STATE_FILE
COPY --from=espresso-dev-node ${STATE_FILE} ${STATE_FILE}.bkp

# RUN bash ${CARTESI_ROLLUPS_DIR}/devnet.sh -x -a "" -c "--dry-run -w  deployments/localhost --impersonate 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
RUN bash ${CARTESI_ROLLUPS_DIR}/devnet.sh -x \
    -a "--load-state ${STATE_FILE}.bkp --dump-state ${STATE_FILE} --preserve-historical-states" \
    -c "${CARTESI_ROLLUPS_DIR}/dave/cartesi-rollups/contracts/cannonfile-deploy.toml -w deployments/localhost"

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

ARG STATE_FILE
ARG ESPRESSO_DEPLOYMENT_FILE
COPY --from=install ${STATE_FILE} ${STATE_FILE}
COPY --from=espresso-dev-node ${STATE_FILE} ${STATE_FILE}.bkp
COPY --from=espresso-dev-node ${ESPRESSO_DEPLOYMENT_FILE} ${ESPRESSO_DEPLOYMENT_FILE}

RUN ln -s ${CARTESI_ROLLUPS_DIR}/devnet.sh /usr/local/bin/devnet.sh

WORKDIR ${CARTESI_ROLLUPS_DIR}

ENV STATE_FILE=${STATE_FILE}

CMD devnet.sh -s ${STATE_FILE}
