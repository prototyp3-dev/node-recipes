
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

deploy-dave-%: ${ENVFILE}.% --check-envs -%
	@ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml cp ${IMAGE_PATH}/. node:/mnt/apps/${APP_NAME}
	ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml exec -u root node bash -c "chown -R cartesi:cartesi /mnt/apps/${APP_NAME}"
	ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml exec node bash -c \
	 "APP_NAME=${APP_NAME} OWNER=${OWNER} EPOCH_LENGTH=${EPOCH_LENGTH} SALT=${SALT} EXTRA_ARGS=${EXTRA_ARGS} \
	 /deploy-dave.sh /mnt/apps/${APP_NAME}"

register-dave-%: ${ENVFILE}.% --check-envs -%
	@ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml cp ${IMAGE_PATH}/. node:/mnt/apps/${APP_NAME}
	ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml exec -u root node bash -c "chown -R cartesi:cartesi /mnt/apps/${APP_NAME}"
	ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml exec node bash -c \
	 "APP_NAME=${APP_NAME} EPOCH_LENGTH=${EPOCH_LENGTH} APPLICATION_ADDRESS=${APPLICATION_ADDRESS} CONSENSUS_ADDRESS=${CONSENSUS_ADDRESS} EXTRA_ARGS=${EXTRA_ARGS} \
	 /register-dave.sh /mnt/apps/${APP_NAME}"

${ENVFILE}.localhost:
	@test ! -f $@ && echo "$@ not found. Creating with default values"
	echo CARTESI_LOG_LEVEL=info >> $@
	echo CARTESI_BLOCKCHAIN_HTTP_ENDPOINT="http://devnet:8545" >> $@
	echo CARTESI_BLOCKCHAIN_WS_ENDPOINT="ws://devnet:8545" >> $@
	echo CARTESI_BLOCKCHAIN_ID=31337 >> $@
	echo CARTESI_AUTH_PRIVATE_KEY=ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 >> $@
	echo CARTESI_CONTRACTS_INPUT_BOX_ADDRESS="0xc70074BDD26d8cF983Ca6A5b89b8db52D5850051" >> $@
	echo CARTESI_CONTRACTS_AUTHORITY_FACTORY_ADDRESS="0xC7003566dD09Aa0fC0Ce201aC2769aFAe3BF0051" >> $@
	echo CARTESI_CONTRACTS_APPLICATION_FACTORY_ADDRESS="0xc7006f70875BaDe89032001262A846D3Ee160051" >> $@
	echo CARTESI_CONTRACTS_SELF_HOSTED_APPLICATION_FACTORY_ADDRESS="0xc700285Ab555eeB5201BC00CFD4b2CC8DED90051" >> $@
	echo CARTESI_CONTRACTS_DAVE_CONSENSUS_FACTORY_ADDRESS="0x6e362c9458fE812D4aA796651C64D02C87AbD1cB" >> $@
	echo MAIN_SEQUENCER="ethereum" >> $@
	echo CARTESI_FEATURE_GRAPHQL_ENABLED=true >> $@
	echo CARTESI_FEATURE_RPC_ENABLED=true >> $@

${ENVFILE}.%:
	test ! -f $@ && $(error "file $@ doesn't exist")


--check-envs:
	@set -e
	@test ! -z '${IMAGE_PATH}' || (echo "Must define IMAGE_PATH" && exit 1)
