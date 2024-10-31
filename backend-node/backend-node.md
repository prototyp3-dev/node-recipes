# Test Node images

Create versions of the node and graphql

## Build Images

Copy the file in this directory to the path where you have the rollups node source. Then build the images

```shell
make -f backend-node.mk node-image NODE_REPO_PATH=/path/to/rollups-node
```

and

```shell
make -f backend-node.mk hlgraphql-image NODE_REPO_PATH=/path/to/rollups-node
```

and

```shell
make -f backend-node.mk devnet-image NODE_REPO_PATH=/path/to/rollups-node
```
