
ENVFILE := .env
DIR := $(shell basename ${PWD})
IMAGE_PATH ?= '.cartesi/path'

SHELL := /bin/bash

.ONESHELL:

build-node:
	docker build -f node.dockerfile --build-arg IMAGE_PATH=${IMAGE_PATH} -t ${DIR}-node .

run-devnet-%: ${ENVFILE}.%
	@DIR=${DIR} docker compose --env-file $< -f node-compose.yml up -d devnet

run-database-%: ${ENVFILE}.%
	@DIR=${DIR} docker compose --env-file $< -f node-compose.yml up -d database

run-node-%: ${ENVFILE}.%
	@DIR=${DIR} docker compose --env-file $< -f node-compose.yml up -d node

create-db-%: ${ENVFILE}.%
	@DIR=${DIR} docker compose --env-file $< -f node-compose.yml exec database \
	 /bin/bash -c 'PGPASSWORD=$${POSTGRES_PASSWORD} psql -U $${POSTGRES_USER} -c \
	 "create database $${GRAPHQL_DB};"'

run-graphql-%: ${ENVFILE}.%
	@DIR=${DIR} docker compose --env-file $< -f node-compose.yml up -d graphql

stop-%: ${ENVFILE}.%
	@DIR=${DIR} docker compose --env-file $< -f node-compose.yml down --remove-orphans -v

compose-%: ${ENVFILE}.%
	@DIR=${DIR} docker compose --env-file $< -f node-compose.yml ${ARGS}

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
