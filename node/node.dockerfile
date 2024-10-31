# (c) Cartesi and individual authors (see AUTHORS)
# SPDX-License-Identifier: Apache-2.0 (see LICENSE)

# syntax=docker.io/docker/dockerfile:1

ARG TEST_NODE_VERSION=devel

FROM ghcr.io/prototyp3-dev/test-node:${TEST_NODE_VERSION}

COPY --chown=cartesi:cartesi .cartesi/image /mnt/snapshot/0


