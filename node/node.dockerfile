# (c) Cartesi and individual authors (see AUTHORS)
# SPDX-License-Identifier: Apache-2.0 (see LICENSE)

# syntax=docker.io/docker/dockerfile:1

ARG TEST_NODE_VERSION=latest

FROM ghcr.io/prototyp3-dev/test-node:${TEST_NODE_VERSION}

ARG IMAGE_PATH .cartesi/image
COPY --chown=cartesi:cartesi ${IMAGE_PATH} /mnt/snapshot/0
