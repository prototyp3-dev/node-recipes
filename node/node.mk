
ENVFILE := .env
DIR := $(shell basename ${PWD})
IMAGE_PATH ?= '.cartesi/path'

SHELL := /bin/bash

.ONESHELL:

run-devnet-%: ${ENVFILE}.%
	@docker compose --env-file $< -f node-compose.yml up -d devnet

run-database-%: ${ENVFILE}.%
	@docker compose --env-file $< -f node-compose.yml up -d database

run-node-%: ${ENVFILE}.%
	@docker compose --env-file $< -f node-compose.yml up -d node

create-db-%: ${ENVFILE}.%
	@docker compose --env-file $< -f node-compose.yml exec database \
	 /bin/bash -c 'PGPASSWORD=$${POSTGRES_PASSWORD} psql -U $${POSTGRES_USER} -c \
	 "create database $${GRAPHQL_DB};"'

run-graphql-%: ${ENVFILE}.%
	@docker compose --env-file $< -f node-compose.yml up -d graphql

stop-%: ${ENVFILE}.%
	@docker compose --env-file $< -f node-compose.yml down --remove-orphans -v

compose-%: ${ENVFILE}.%
	@docker compose --env-file $< -f node-compose.yml ${ARGS}

hash = $(eval hash := $(shell hexdump -e '1/1 "%.2x"' ${IMAGE_PATH}/hash))$(value hash)

deploy-%: ${ENVFILE}.% --check-envs
	@docker compose --env-file $< -f node-compose.yml cp ${IMAGE_PATH} node:/mnt/snapshots/${hash}
	docker compose --env-file $< -f node-compose.yml exec node bash -c "/deploy.sh /mnt/snapshots/${hash}"

${ENVFILE}.localhost:
	@test ! -f $@ && echo "$@ not found. Creating with default values"
	echo CARTESI_LOG_LEVEL=info >> $@
	echo CARTESI_BLOCKCHAIN_HTTP_ENDPOINT="http://devnet:8545" >> $@
	echo CARTESI_BLOCKCHAIN_WS_ENDPOINT="ws://devnet:8545" >> $@
	echo CARTESI_BLOCKCHAIN_ID=31337 >> $@
	echo CARTESI_CONTRACTS_INPUT_BOX_ADDRESS="0x593E5BCf894D6829Dd26D0810DA7F064406aebB6" >> $@
	echo CARTESI_CONTRACTS_INPUT_BOX_DEPLOYMENT_BLOCK_NUMBER=10 >> $@
	echo 'CARTESI_AUTH_MNEMONIC="test test test test test test test test test test test junk"' >> $@
	echo MAIN_SEQUENCER="ethereum" >> $@
	echo AUTHORITY_ADDRESS= >> $@

${ENVFILE}.%:
	test ! -f $@ && $(error "file $@ doesn't exist")


--check-envs:
	@set -e
	@test ! -z '${IMAGE_PATH}' || (echo "Must define IMAGE_PATH" && exit 1)