
RELEASE_SUFFIX ?= ''
RELEASE_VERSION ?= $$(git log -1 --format="%at" | xargs -I{} date -d @{} +%Y%m%d.%H%M).$$(git rev-parse --short HEAD)

.ONESHELL:

# needs rollups node path
node-image: --check-envs
	@IMAGE_VERSION=${RELEASE_VERSION}${RELEASE_SUFFIX}
	IMAGE_TAG=ghcr.io/prototyp3-dev/test-node:$$IMAGE_VERSION
	echo $$IMAGE_TAG > .node.tag
	docker build -t recipe-stage/builder --target go-builder ${NODE_REPO_PATH}
	docker build -f backend-node.dockerfile --target rollups-node-we ${ARGS} . \
		-t $$IMAGE_TAG \
		--label "org.opencontainers.image.title=prototyp3-dev-test-node" \
		--label "org.opencontainers.image.description=Test Node" \
		--label "org.opencontainers.image.source=https://github.com/prototyp3-dev/node-recipes" \
		--label "org.opencontainers.image.created=$$(date -Iseconds --utc)" \
		--label "org.opencontainers.image.licenses=Apache-2.0" \
		--label "org.opencontainers.image.url=https://github.com/prototyp3-dev/node-recipes" \
		--label "org.opencontainers.image.version=$$IMAGE_VERSION"

node-cloud-image: --check-envs
	@IMAGE_VERSION=${RELEASE_VERSION}${RELEASE_SUFFIX}
	IMAGE_TAG=ghcr.io/prototyp3-dev/test-node-cloud:$$IMAGE_VERSION
	echo $$IMAGE_TAG > .node-cloud.tag
	docker build -t recipe-stage/builder --target go-builder ${NODE_REPO_PATH}
	docker build -f backend-node.dockerfile --target rollups-node-we-cloud ${ARGS} . \
		-t $$IMAGE_TAG \
		--label "org.opencontainers.image.title=prototyp3-dev-test-node-cloud" \
		--label "org.opencontainers.image.description=Test Node Cloud" \
		--label "org.opencontainers.image.source=https://github.com/prototyp3-dev/node-recipes" \
		--label "org.opencontainers.image.created=$$(date -Iseconds --utc)" \
		--label "org.opencontainers.image.licenses=Apache-2.0" \
		--label "org.opencontainers.image.url=https://github.com/prototyp3-dev/node-recipes" \
		--label "org.opencontainers.image.version=$$IMAGE_VERSION"

devnet-image: --check-envs
	@IMAGE_VERSION=${RELEASE_VERSION}${RELEASE_SUFFIX}
	IMAGE_TAG=ghcr.io/prototyp3-dev/test-devnet:$$IMAGE_VERSION
	echo $$IMAGE_TAG > .devnet.tag
	docker build -f ${NODE_REPO_PATH}/test/devnet/Dockerfile --target rollups-node-devnet ${NODE_REPO_PATH} \
		-t $$IMAGE_TAG \
		--label "org.opencontainers.image.title=prototyp3-dev-test-devnet" \
		--label "org.opencontainers.image.description=Test Devnet" \
		--label "org.opencontainers.image.source=https://github.com/prototyp3-dev/node-recipes" \
		--label "org.opencontainers.image.created=$$(date -Iseconds --utc)" \
		--label "org.opencontainers.image.licenses=Apache-2.0" \
		--label "org.opencontainers.image.url=https://github.com/prototyp3-dev/node-recipes" \
		--label "org.opencontainers.image.version=$$IMAGE_VERSION"

--check-envs:
	@test ! -z '${NODE_REPO_PATH}' || (echo "Must define NODE_REPO_PATH" && exit 1)

nonode-image:
	@IMAGE_VERSION=${RELEASE_VERSION}${RELEASE_SUFFIX}
	IMAGE_TAG=ghcr.io/prototyp3-dev/test-nonode:$$IMAGE_VERSION
	echo $$IMAGE_TAG > .nonode.tag
	docker build -f nonode.dockerfile --target nonode ${ARGS} . \
		-t $$IMAGE_TAG \
		--label "org.opencontainers.image.title=prototyp3-dev-test-nonode" \
		--label "org.opencontainers.image.description=Test Nonode" \
		--label "org.opencontainers.image.source=https://github.com/prototyp3-dev/node-recipes" \
		--label "org.opencontainers.image.created=$$(date -Iseconds --utc)" \
		--label "org.opencontainers.image.licenses=Apache-2.0" \
		--label "org.opencontainers.image.url=https://github.com/prototyp3-dev/node-recipes" \
		--label "org.opencontainers.image.version=$$IMAGE_VERSION"

nonode-cloud-image:
	@IMAGE_VERSION=${RELEASE_VERSION}${RELEASE_SUFFIX}
	IMAGE_TAG=ghcr.io/prototyp3-dev/test-nonode-cloud:$$IMAGE_VERSION
	echo $$IMAGE_TAG > .nonode-cloud.tag
	docker build -f nonode.dockerfile --target nonode-cloud ${ARGS} . \
		-t $$IMAGE_TAG \
		--label "org.opencontainers.image.title=prototyp3-dev-test-nonode-cloud" \
		--label "org.opencontainers.image.description=Test Nonode Cloud" \
		--label "org.opencontainers.image.source=https://github.com/prototyp3-dev/node-recipes" \
		--label "org.opencontainers.image.created=$$(date -Iseconds --utc)" \
		--label "org.opencontainers.image.licenses=Apache-2.0" \
		--label "org.opencontainers.image.url=https://github.com/prototyp3-dev/node-recipes" \
		--label "org.opencontainers.image.version=$$IMAGE_VERSION"

nonode-snapshot-image:
	@IMAGE_VERSION=${RELEASE_VERSION}${RELEASE_SUFFIX}
	IMAGE_TAG=ghcr.io/prototyp3-dev/test-nonode-snapshot:$$IMAGE_VERSION
	echo $$IMAGE_TAG > .nonode-snapshot.tag
	docker build -f nonode.dockerfile --target nonode-snapshot ${ARGS} . \
		-t $$IMAGE_TAG \
		--label "org.opencontainers.image.title=prototyp3-dev-test-nonode-snapshot" \
		--label "org.opencontainers.image.description=Test Nonode Snapshot" \
		--label "org.opencontainers.image.source=https://github.com/prototyp3-dev/node-recipes" \
		--label "org.opencontainers.image.created=$$(date -Iseconds --utc)" \
		--label "org.opencontainers.image.licenses=Apache-2.0" \
		--label "org.opencontainers.image.url=https://github.com/prototyp3-dev/node-recipes" \
		--label "org.opencontainers.image.version=$$IMAGE_VERSION"

nonode-snapshot-cloud-image:
	@IMAGE_VERSION=${RELEASE_VERSION}${RELEASE_SUFFIX}
	IMAGE_TAG=ghcr.io/prototyp3-dev/test-nonode-snapshot-cloud:$$IMAGE_VERSION
	echo $$IMAGE_TAG > .nonode-snapshot-cloud.tag
	docker build -f nonode.dockerfile --target nonode-snapshot-cloud ${ARGS} . \
		-t $$IMAGE_TAG \
		--label "org.opencontainers.image.title=prototyp3-dev-test-nonode-snapshot-cloud" \
		--label "org.opencontainers.image.description=Test Nonode Snapshot Cloud" \
		--label "org.opencontainers.image.source=https://github.com/prototyp3-dev/node-recipes" \
		--label "org.opencontainers.image.created=$$(date -Iseconds --utc)" \
		--label "org.opencontainers.image.licenses=Apache-2.0" \
		--label "org.opencontainers.image.url=https://github.com/prototyp3-dev/node-recipes" \
		--label "org.opencontainers.image.version=$$IMAGE_VERSION"
