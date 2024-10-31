# Test Node

Instructions to run a cartesi rollups node

## Prepare the Snapshot

### Requirements

You could use [Cartesi cli](https://github.com/cartesi/cli) or you can generate an image direcly with cartesi machine [Cartesi Machine](https://github.com/cartesi/machine-emulator). In this guide we'll show to use cartesi machine directly. For instructions using cartesi cli refer to its docs.

### Create a Cartesi Rollups image

The following commands assumes you have cartesi machine on your system. Alternatively, you might want to use a docker container with all required packeges and run in interactive mode:

```shell
docker run -it --rm -v $PWD:/workdir -w /workdir ghcr.io/prototyp3-dev/test-node:devel bash
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

## Local

From a the location of the application snapshot `.cartesi/ìmage`

```shell
make -f node.mk start
```

Then you can start the node (it will also deploy the application)

```shell
make -f node.mk run-node
```

Create the graphql database 

```shell
make -f node.mk run-create-db
```

And finally, run the graphql server

```shell
make -f node.mk run-graphql
```

To stop the environment just run:

```shell
make -f node.mk stop
```

## Testnet

Define the following variables (tip: create a .env.<testnet> file and source it)

```shell
CARTESI_LOG_LEVEL=
CARTESI_BLOCKCHAIN_HTTP_ENDPOINT=
CARTESI_BLOCKCHAIN_WS_ENDPOINT=
CARTESI_BLOCKCHAIN_ID=
CARTESI_CONTRACTS_INPUT_BOX_ADDRESS=
CARTESI_CONTRACTS_INPUT_BOX_DEPLOYMENT_BLOCK_NUMBER=
CARTESI_AUTH_MNEMONIC=
MAIN_SEQUENCER=
AUTHORITY_ADDRESS=
```

You can leave `AUTHORITY_ADDRESS` if you don't deployed it yet



## Deploy backend to fly.io

