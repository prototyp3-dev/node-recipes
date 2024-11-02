# Test Node

Instructions to run a cartesi rollups node

Check [Setup](#setup) for some initial instructions, [Localhost](#localhost) to start a local node with a devnet, [Testnet](#testnet) to start local node using a testnet, [Fly](#fly) for instructions to deploy a node on [Fly](https://fly.io/docs), and [Prepare the Snapshot](#prepare-the-snapshot) for instructions to build the app snapshot.

## Setup

Go to the application directory (which contains your snapshot image) and copy the dockerfile, the docker compose file, and the node.mk.

```shell
wget -q https://github.com/prototyp3-dev/node-recipes/archive/refs/heads/main.zip -O recipes.zip
unzip -q recipes.zip "node-recipes-main/node/*" -d . && mv node-recipes-main/node/* . && rmdir -p node-recipes-main/node
rm recipes.zip
```

Also, make sure you have the updated test node images:

```shell
docker pull ghcr.io/prototyp3-dev/test-node:latest
docker pull ghcr.io/prototyp3-dev/test-graphql:latest
```

And if you will run a local devnet:

```shell
docker pull ghcr.io/prototyp3-dev/test-devnet:latest
```

## Localhost

You can start running devnet and database

```shell
make -f node.mk run-devnet-localhost
make -f node.mk run-database-localhost
```

Start the node

```shell
make -f node.mk run-node-localhost
```

Create the graphql database 

```shell
make -f node.mk create-db-localhost
```

And finally, run the graphql server

```shell
make -f node.mk run-graphql-localhost
```

With the infrastructure running, you can deploy the application with

```shell
make -f node.mk deploy-localhost 
```

Note: you can set `IMAGE_PATH` for an image path different than the default `.cartesi/image`.

To stop the environment just run:

```shell
make -f node.mk stop-localhost
```

## Testnet

Create an .env.<testnet> file with:

```shell
CARTESI_LOG_LEVEL=
CARTESI_BLOCKCHAIN_HTTP_ENDPOINT=
CARTESI_BLOCKCHAIN_WS_ENDPOINT=
CARTESI_BLOCKCHAIN_ID=
CARTESI_CONTRACTS_INPUT_BOX_ADDRESS=
CARTESI_CONTRACTS_INPUT_BOX_DEPLOYMENT_BLOCK_NUMBER=
CARTESI_AUTH_PRIVATE_KEY=
MAIN_SEQUENCER=
ESPRESSO_BASE_URL=
ESPRESSO_STARTING_BLOCK=
ESPRESSO_NAMESPACE=
```

Then start the database:

```shell
make -f node.mk run-database-<testnet>
```

Start the node:

```shell
make -f node.mk run-node-<testnet>
```

Create the graphql database and the graphql service

```shell
make -f node.mk create-db-<testnet>
make -f node.mk run-graphql-<testnet>
```

And deploy the application with (optionally set `IMAGE_PATH`):

```shell
make -f node.mk deploy-<testnet> OWNER=<app and auth owner>
```

You should set `OWNER` to the same owner of the `CARTESI_AUTH_PRIVATE_KEY`.Set `AUTHORITY_ADDRESS` to deploy a new application with same authority already deployed. You can also set `EPOCH_LENGTH`, and `SALT`.

To stop the environment just run:

```shell
make -f node.mk stop-<testnet>
```

Note: If want to register an already deployed application to the node use (optionally set `IMAGE_PATH`):

```shell
make -f node.mk register-<testnet> APPLICATION_ADDRESS=<app address> AUTHORITY_ADDRESS=<auth address> 
```

## Deploy backend to fly.io


## Prepare the Snapshot

### Requirements

You could use [Cartesi cli](https://github.com/cartesi/cli) or you can generate an image direcly with cartesi machine [Cartesi Machine](https://github.com/cartesi/machine-emulator). In this guide we'll show to use cartesi machine directly. For instructions using cartesi cli refer to its docs.

### Create a Cartesi Rollups image

The following commands assumes you have cartesi machine on your system. Alternatively, you might want to use a docker container with all required packeges and run in interactive mode:

```shell
docker run -it --rm -v $PWD:/workdir -w /workdir ghcr.io/prototyp3-dev/test-node:latest bash
```

First, you should start off from a base rootfs, either the one installed with cartesi machine (`/share/cartesi-machine/images/rootfs.ext2`) or one generated with cartesi cli (`/path/to/app/.cartesi/image.ext2`). Copy the base image to a working dir so you can start making changes. 

```shell
cp /path/to/rootfs.ext2 rootfs.ext2
```

This rootfs.ext2` is your working image. Then, you should resize as you see necessary

```shell
resize2fs -f rootfs.ext2 128M
```

#### Start from a rootfs.ext2 and prepare image

Before you install you app in the image, you should prepare and install any dependencies. Start the cartesi machine in interactive mode with network and volumes virtio:

```shell
cartesi-machine --network --volume=.:/mnt --workdir=/mnt --flash-drive=label:root,filename:rootfs.ext2,shared -u=root -it -- bash
```

Now that you are inside the cartesi machine, install any packages required to run your application. Also, copy your projects files to its final dir (we'll consider it is a single `app` binary):

```shell
root@localhost:/mnt# mkdir -p /opt/cartesi/app     
root@localhost:/mnt# cp app /opt/cartesi/app/.
```

#### Run in rollups mode and generate the starting snapshot

With the rootfs in place, you can start the cartesi machine in rollups mode and generate the starting snapshot:

```shell
mkdir -p .cartesi/
cartesi-machine --env=ROLLUP_HTTP_SERVER_URL=http://127.0.0.1:5004 --flash-drive=label:root,filename:rootfs.ext2 --store=.cartesi/image --assert-rolling-template -- rollup-init /opt/cartesi/app/app
```

The starting snapshot was saved to `.cartesi/image` directory. This snapshot is copied to your the node to be able to run the application.

And finally, make sure the image directory has read permissions for all users

```shell
chmod a+xr .cartesi/image
```
