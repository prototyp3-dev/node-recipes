
ENVFILE := .env
DIR := $(shell basename ${PWD})
IMAGE_PATH ?= '.cartesi/path'

SHELL := /bin/bash

.ONESHELL:

-%:
	$(eval ENV = $@)

run-devnet-%: ${ENVFILE}.% -%
	@ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml up -d devnet

run-database-%: ${ENVFILE}.% -%
	@ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml up -d database

run-node-%: ${ENVFILE}.% -%
	@ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml up -d node

create-db-%: ${ENVFILE}.% -%
	@ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml exec database \
	 /bin/bash -c 'PGPASSWORD=$${POSTGRES_PASSWORD} psql -U $${POSTGRES_USER} -c \
	 "create database $${GRAPHQL_DB};"'

run-graphql-%: ${ENVFILE}.% -%
	@ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml up -d graphql

stop-%: ${ENVFILE}.% -%
	@ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml down --remove-orphans -v

compose-%: ${ENVFILE}.% -%
	@ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml ${ARGS}

hash = $(eval hash := $(shell hexdump -e '1/1 "%.2x"' ${IMAGE_PATH}/hash))$(value hash)

deploy-%: ${ENVFILE}.% --check-envs -%
	@ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml cp ${IMAGE_PATH}/. node:/mnt/snapshots/${hash}
	ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml exec node bash -c \
	 "OWNER=${OWNER} AUTHORITY_ADDRESS=${AUTHORITY_ADDRESS} EPOCH_LENGTH=${EPOCH_LENGTH} SALT=${SALT} EXTRA_ARGS=${EXTRA_ARGS} \
	 /deploy.sh /mnt/snapshots/${hash}"

register-%: ${ENVFILE}.% --check-envs -%
	@ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml cp ${IMAGE_PATH}/. node:/mnt/snapshots/${hash}
	ENVFILENAME=$< docker compose -p ${DIR}${ENV} --env-file $< -f node-compose.yml exec node bash -c \
	 "APPLICATION_ADDRESS=${APPLICATION_ADDRESS} AUTHORITY_ADDRESS=${AUTHORITY_ADDRESS} EXTRA_ARGS=${EXTRA_ARGS} \
	 /register.sh /mnt/snapshots/${hash}"

${ENVFILE}.localhost:
	@test ! -f $@ && echo "$@ not found. Creating with default values"
	echo CARTESI_LOG_LEVEL=info >> $@
	echo CARTESI_BLOCKCHAIN_HTTP_ENDPOINT="http://devnet:8545" >> $@
	echo CARTESI_BLOCKCHAIN_WS_ENDPOINT="ws://devnet:8545" >> $@
	echo CARTESI_BLOCKCHAIN_ID=31337 >> $@
	echo CARTESI_CONTRACTS_INPUT_BOX_ADDRESS="0x593E5BCf894D6829Dd26D0810DA7F064406aebB6" >> $@
	echo CARTESI_CONTRACTS_INPUT_BOX_DEPLOYMENT_BLOCK_NUMBER=10 >> $@
	echo CARTESI_AUTH_PRIVATE_KEY=ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 >> $@
	echo MAIN_SEQUENCER="ethereum" >> $@

${ENVFILE}.%:
	test ! -f $@ && $(error "file $@ doesn't exist")


--check-envs:
	@set -e
	@test ! -z '${IMAGE_PATH}' || (echo "Must define IMAGE_PATH" && exit 1)