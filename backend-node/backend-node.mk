
RELEASE_SUFFIX ?= ''
RELEASE_VERSION ?= $$(git log -1 --format="%at" | xargs -I{} date -d @{} +%Y%m%d.%H%M).$$(git rev-parse --short HEAD)

.ONESHELL:

# in rollups node path
node-image: --check-envs
	@IMAGE_VERSION=${RELEASE_VERSION}${RELEASE_SUFFIX}
	IMAGE_TAG=ghcr.io/prototyp3-dev/test-node:$$IMAGE_VERSION
	echo $$IMAGE_TAG > .node.tag
	docker build -t recipe-stage/rollups-node ${NODE_REPO_PATH}
	docker build -f backend-node.dockerfile --target rollups-node-we . \
		-t $$IMAGE_TAG \
		--label "org.opencontainers.image.title=prototyp3-dev-test-node" \
		--label "org.opencontainers.image.description=Test Node" \
		--label "org.opencontainers.image.source=https://github.com/prototyp3-dev/test-node" \
		--label "org.opencontainers.image.created=$$(date -Iseconds --utc)" \
		--label "org.opencontainers.image.licenses=Apache-2.0" \
		--label "org.opencontainers.image.url=https://github.com/prototyp3-dev/test-node" \
		--label "org.opencontainers.image.version=$$IMAGE_VERSION"


hlgraphql-image: --check-envs
	@IMAGE_VERSION=${RELEASE_VERSION}${RELEASE_SUFFIX}
	IMAGE_TAG=ghcr.io/prototyp3-dev/test-hlgraphql:$$IMAGE_VERSION
	echo $$IMAGE_TAG > .hlgraphql.tag
	docker build -f backend-node.dockerfile --target hlgraphql . \
		-t $$IMAGE_TAG \
		--label "org.opencontainers.image.title=prototyp3-dev-test-hlgraphql" \
		--label "org.opencontainers.image.description=Test High Level Graphql" \
		--label "org.opencontainers.image.source=https://github.com/prototyp3-dev/test-node" \
		--label "org.opencontainers.image.created=$$(date -Iseconds --utc)" \
		--label "org.opencontainers.image.licenses=Apache-2.0" \
		--label "org.opencontainers.image.url=https://github.com/prototyp3-dev/test-node" \
		--label "org.opencontainers.image.version=$$IMAGE_VERSION"

devnet-image: --check-envs
	@IMAGE_VERSION=${RELEASE_VERSION}${RELEASE_SUFFIX}
	IMAGE_TAG=ghcr.io/prototyp3-dev/test-devnet:$$IMAGE_VERSION
	echo $$IMAGE_TAG > .devnet.tag
	docker build -f ${NODE_REPO_PATH}/test/devnet/Dockerfile --target rollups-node-devnet ${NODE_REPO_PATH} \
		-t $$IMAGE_TAG \
		--label "org.opencontainers.image.title=prototyp3-dev-test-devnet" \
		--label "org.opencontainers.image.description=Test Devnet" \
		--label "org.opencontainers.image.source=https://github.com/prototyp3-dev/test-node" \
		--label "org.opencontainers.image.created=$$(date -Iseconds --utc)" \
		--label "org.opencontainers.image.licenses=Apache-2.0" \
		--label "org.opencontainers.image.url=https://github.com/prototyp3-dev/test-node" \
		--label "org.opencontainers.image.version=$$IMAGE_VERSION"

--check-envs:
	@test ! -z '${NODE_REPO_PATH}' || (echo "Must define NODE_REPO_PATH" && exit 1)

