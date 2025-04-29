
ENVFILE := .env
DIR := $(shell basename ${PWD})
IMAGE_PATH ?= '.cartesi/image'
APP_NAME ?= ${DIR}

SHELL := /bin/bash

.ONESHELL:

-%:
	$(eval ENV = $@)

run-devnet-%: ${ENVFILE}.% -%
	@ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml up -d devnet

run-database-%: ${ENVFILE}.% -%
	@ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml up -d database

run-espresso-%: ${ENVFILE}.% -%
	@ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml up -d espresso

run-node-%: ${ENVFILE}.% -%
	@ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml up -d node

stop-%: ${ENVFILE}.% -%
	@ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml down --remove-orphans -v

compose-%: ${ENVFILE}.% -%
	@ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml ${ARGS}

deploy-%: ${ENVFILE}.% --check-envs -%
	@ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml cp ${IMAGE_PATH}/. node:/mnt/apps/${APP_NAME}
	ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml exec -u root node bash -c "chown -R cartesi:cartesi /mnt/apps/${APP_NAME}"
	ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml exec node bash -c \
	 "APP_NAME=${APP_NAME} OWNER=${OWNER} CONSENSUS_ADDRESS=${CONSENSUS_ADDRESS} EPOCH_LENGTH=${EPOCH_LENGTH} SALT=${SALT} EXTRA_ARGS=${EXTRA_ARGS} \
	 /deploy.sh /mnt/apps/${APP_NAME}"

register-%: ${ENVFILE}.% --check-envs -%
	@ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml cp ${IMAGE_PATH}/. node:/mnt/apps/${APP_NAME}
	ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml exec -u root node bash -c "chown -R cartesi:cartesi /mnt/apps/${APP_NAME}"
	ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml exec node bash -c \
	 "APP_NAME=${APP_NAME} APPLICATION_ADDRESS=${APPLICATION_ADDRESS} CONSENSUS_ADDRESS=${CONSENSUS_ADDRESS} EXTRA_ARGS=${EXTRA_ARGS} \
	 /register.sh /mnt/apps/${APP_NAME}"

${ENVFILE}.localhost:
	@test ! -f $@ && echo "$@ not found. Creating with default values"
	echo CARTESI_LOG_LEVEL=info >> $@
	echo CARTESI_BLOCKCHAIN_HTTP_ENDPOINT="http://devnet:8545" >> $@
	echo CARTESI_BLOCKCHAIN_WS_ENDPOINT="ws://devnet:8545" >> $@
	echo CARTESI_BLOCKCHAIN_ID=31337 >> $@
	echo CARTESI_AUTH_PRIVATE_KEY=ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 >> $@
	echo CARTESI_CONTRACTS_INPUT_BOX_ADDRESS="0xB6b39Fb3dD926A9e3FBc7A129540eEbeA3016a6c" >> $@
	echo CARTESI_CONTRACTS_AUTHORITY_FACTORY_ADDRESS="0x451f57Ca716046D114Ab9ff23269a2F9F4a1bdaF" >> $@
	echo CARTESI_CONTRACTS_APPLICATION_FACTORY_ADDRESS="0x2210ad1d9B0bD2D470c2bfA4814ab6253BC421A0" >> $@
	echo CARTESI_CONTRACTS_SELF_HOSTED_APPLICATION_FACTORY_ADDRESS="0x4a409e1CaB9229711C4e1f68625DdbC75809e721" >> $@
	echo MAIN_SEQUENCER="ethereum" >> $@

${ENVFILE}.%:
	test ! -f $@ && $(error "file $@ doesn't exist")


--check-envs:
	@set -e
	@test ! -z '${IMAGE_PATH}' || (echo "Must define IMAGE_PATH" && exit 1)
