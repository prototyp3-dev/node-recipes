
RELEASE_SUFFIX ?= ''
RELEASE_VERSION ?= $$(git log -1 --format="%at" | xargs -I{} date -d @{} +%Y%m%d.%H%M).$$(git rev-parse --short HEAD)
# TARGETARCH ?= $$(dpkg --print-architecture)

.ONESHELL:

# RELEASE_VERSION=2.0.0-alpha ARGS="--platform=linux/arm64,linux/amd64 --push"

# needs rollups node path
node-image:
	@IMAGE_VERSION=${RELEASE_VERSION}${RELEASE_SUFFIX}
	IMAGE_TAG=ghcr.io/prototyp3-dev/test-node:$$IMAGE_VERSION
	echo $$IMAGE_TAG > .node.tag
	docker build --debug -f backend-node.dockerfile --target rollups-node-we ${ARGS} . \
		-t $$IMAGE_TAG \
		--label "org.opencontainers.image.title=prototyp3-dev-test-node" \
		--label "org.opencontainers.image.description=Test Node" \
		--label "org.opencontainers.image.source=https://github.com/prototyp3-dev/node-recipes" \
		--label "org.opencontainers.image.created=$$(date -Iseconds --utc)" \
		--label "org.opencontainers.image.licenses=Apache-2.0" \
		--label "org.opencontainers.image.url=https://github.com/prototyp3-dev/node-recipes" \
		--label "org.opencontainers.image.version=$$IMAGE_VERSION"

node-cloud-image:
	@IMAGE_VERSION=${RELEASE_VERSION}${RELEASE_SUFFIX}
	IMAGE_TAG=ghcr.io/prototyp3-dev/test-node-cloud:$$IMAGE_VERSION
	echo $$IMAGE_TAG > .node-cloud.tag
	docker build -f backend-node.dockerfile --target rollups-node-we-cloud ${ARGS} . \
		-t $$IMAGE_TAG \
		--label "org.opencontainers.image.title=prototyp3-dev-test-node-cloud" \
		--label "org.opencontainers.image.description=Test Node Cloud" \
		--label "org.opencontainers.image.source=https://github.com/prototyp3-dev/node-recipes" \
		--label "org.opencontainers.image.created=$$(date -Iseconds --utc)" \
		--label "org.opencontainers.image.licenses=Apache-2.0" \
		--label "org.opencontainers.image.url=https://github.com/prototyp3-dev/node-recipes" \
		--label "org.opencontainers.image.version=$$IMAGE_VERSION"

# RELEASE_VERSION=2.0.0 ARGS="--platform=linux/arm64,linux/amd64 --push"
devnet-image:
	@IMAGE_VERSION=${RELEASE_VERSION}${RELEASE_SUFFIX}
	IMAGE_TAG=ghcr.io/prototyp3-dev/test-devnet:$$IMAGE_VERSION
	echo $$IMAGE_TAG > .devnet.tag
	docker build -f devnet.dockerfile ${ARGS} . \
		-t $$IMAGE_TAG \
		--label "org.opencontainers.image.title=prototyp3-dev-test-devnet" \
		--label "org.opencontainers.image.description=Test Devnet" \
		--label "org.opencontainers.image.source=https://github.com/prototyp3-dev/node-recipes" \
		--label "org.opencontainers.image.created=$$(date -Iseconds --utc)" \
		--label "org.opencontainers.image.licenses=Apache-2.0" \
		--label "org.opencontainers.image.url=https://github.com/prototyp3-dev/node-recipes" \
		--label "org.opencontainers.image.version=$$IMAGE_VERSION"
	docker run -it --rm $$IMAGE_TAG cat /usr/share/devnet/espresso-deployment.txt > .devnet_espresso_deployment.txt
	echo "Espresso deployment:"
	cat .devnet_espresso_deployment.txt

# setup-multi-platform-builder:
# 	@echo "Setting up multi-platform builder..."
# 	docker buildx create --name multiarch_builder --use --platform=linux/arm64,linux/amd64 || true
# 	docker buildx inspect --bootstrap

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
