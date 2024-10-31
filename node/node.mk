

ENVFILE := .env
DIR := $(shell basename ${PWD})

SHELL := /bin/bash

.ONESHELL:

build:
	docker build -f node.dockerfile .

start: run-devnet run-database

stop:
	@docker compose -f node-compose.yml down

run-devnet: ${ENVFILE}
	@docker compose --env-file $< -f node-compose.yml up -d devnet

run-database: ${ENVFILE}
	@docker compose --env-file $< -f node-compose.yml up -d database

run-node: ${ENVFILE}
	@docker compose --env-file $< -f node-compose.yml up -d node

run-create-db: ${ENVFILE}
	@set -a && source $< && \
	 docker exec ${DIR}-database-1 \
	 /bin/bash -c 'PGPASSWORD=$${POSTGRES_PASSWORD} psql -U $${POSTGRES_USER} -c "create database $${GRAPHQL_DB};"'

run-graphql: ${ENVFILE}
	@docker compose --env-file $< -f node-compose.yml up -d graphql


${ENVFILE}:
	@test ! -f $@ && echo "$(ENVFILE) not found. Creating with default values"
	echo CARTESI_LOG_LEVEL=info >> $(ENVFILE)
	echo CARTESI_BLOCKCHAIN_HTTP_ENDPOINT="http://devnet:8545" >> $(ENVFILE)
	echo CARTESI_BLOCKCHAIN_WS_ENDPOINT="ws://devnet:8545" >> $(ENVFILE)
	echo CARTESI_BLOCKCHAIN_ID=31337 >> $(ENVFILE)
	echo CARTESI_CONTRACTS_INPUT_BOX_ADDRESS="0x593E5BCf894D6829Dd26D0810DA7F064406aebB6" >> $(ENVFILE)
	echo CARTESI_CONTRACTS_INPUT_BOX_DEPLOYMENT_BLOCK_NUMBER=10 >> $(ENVFILE)
	echo 'CARTESI_AUTH_MNEMONIC="test test test test test test test test test test test junk"' >> $(ENVFILE)
	echo MAIN_SEQUENCER="ethereum" >> $(ENVFILE)
	echo AUTHORITY_ADDRESS= >> $(ENVFILE)
