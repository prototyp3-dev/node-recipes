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

In order to run an application on the Cartesi Rollups Node, you need to provide a snapshot of your application's Cartesi Machine.
This guide illustrates two ways of generating that snapshot:
- Using the [Cartesi CLI](https://github.com/cartesi/cli) with a Dockerfile
- Using the [Cartesi Machine](https://github.com/cartesi/machine-emulator) itself and adding dependencies manually.

### Option 1: create a snapshot with the Cartesi CLI

#### Install Cartesi CLI for Rollups v2

Install Cartesi CLI version [2.0.0-alpha.2](https://www.npmjs.com/package/@cartesi/cli/v/2.0.0-alpha.2).
In this guide, we suggest you to install it locally in your application's directory:

```shell
cd <path/to/your/app>
npm i @cartesi/cli@2.0.0-alpha.2
```

If you do not have the `cartesi-machine` command on your system, you are good to go.

However, if you do have it, then you must check that it is a compatible version and that it is correctly set up.
Make sure that: 

- `cartesi-machine --version` prints version `0.18.1`
- `sha256sum /usr/share/cartesi-machine/images/linux.bin` prints `65dd100ff6204346ac2f50f772721358b5c1451450ceb39a154542ee27b4c947`

The appropriate Cartesi Machine binaties can be installed from the artifacts located [here](https://github.com/cartesi/machine-emulator/releases/tag/v0.18.1), while the appropriate `linux.bin` file can be downloaded from [here](https://github.com/cartesi/image-kernel/releases/download/v0.20.0/linux-6.5.13-ctsi-1-v0.20.0.bin).
Once again, bear in mind that this is _optional_: the CLI will work if you do not have the Cartesi Machine command installed locally.

#### Update app Dockerfile for Rollups v2

Your application's Dockerfile should be changed in order to be compatible with Rollups v2.
In this guide, we suggest you to copy the appropriate Dockerfile for your application's language from the [application-templates](https://github.com/cartesi/application-templates/tree/prerelease/sdk-12) repository:

- For Python: https://github.com/cartesi/application-templates/blob/prerelease/sdk-12/python/Dockerfile
- For Typescript: https://github.com/cartesi/application-templates/blob/prerelease/sdk-12/typescript/Dockerfile

Then, simply change the file to add your application's specific dependencies or configurations.

In comparison to a v1 Dockerfile, the changes for a v2 Dockerfile mainly amount to updating the version of `MACHINE_EMULATOR_TOOLS`, changing the order of some of the instructions, removing `LABEL` directives, and removing `--platform=linux/riscv64` from Cartesi images.

#### Build the snapshot

Simply run `cartesi build`. If installed locally (as suggested above), run:

```shell
npx cartesi build
```

After a successful execution, your snapshot will be located inside `./.cartesi/image/`.


### Option 2: create a snapshot with the Cartesi Machine

The following commands assumes you have the `cartesi-machine` command on your system. Alternatively, you might want to use a docker container with all required packeges and run in interactive mode:

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
