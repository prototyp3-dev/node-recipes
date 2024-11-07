# Test Node images

Create versions of the node and graphql

## Build Images

You'll ne the node repo accesible to set `NODE_REPO_PATH` variable. Then, to build node v2 images run:

```shell
make node-image NODE_REPO_PATH=/path/to/rollups-node
```

and

```shell
make hlgraphql-image
```

and

```shell
make devnet-image NODE_REPO_PATH=/path/to/rollups-node
```

To build nonode image run:

```shell
make nonode-image
```

Note: you may set `RELEASE_VERSION=latest` to generate the latest image tag, otherwise it uses a tag based on the time and git commit hash.