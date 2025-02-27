# Test Node

Instructions to run a cartesi rollups node

Check [Setup](#setup) for some initial instructions, [Localhost](#localhost) to start a local node with a devnet, [Testnet](#testnet) to start local node using a testnet, [Fly](#deploy-backend-to-flyio) for instructions to deploy a node on [Fly](https://fly.io/docs), and [Prepare the Snapshot](#prepare-the-snapshot) for instructions to build the app snapshot.

## Setup

Go to the application directory (which contains your snapshot image) and copy the dockerfile, the docker compose file, and the node.mk.

```shell
wget -q https://github.com/prototyp3-dev/node-recipes/archive/refs/heads/feature/use-20250128-build.zip -O recipes.zip
unzip -q recipes.zip "node-recipes-feature-use-20250128-build/node/*" -d . && mv node-recipes-feature-use-20250128-build/node/* . && rmdir -p node-recipes-feature-use-20250128-build/node
rm recipes.zip
```

Also, make sure you have the updated test node images:

```shell
docker pull ghcr.io/prototyp3-dev/test-node:test
```

And if you will run a local devnet:

```shell
docker pull ghcr.io/prototyp3-dev/test-devnet:test
```

## Localhost

You can start services

```shell
make -f node.mk run-devnet-localhost
make -f node.mk run-database-localhost
make -f node.mk run-node-localhost
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

To test with a local espresso development node, add the `MAIN_SEQUENCER` env and other espresso configurations to .env.localhost file:

```shell
MAIN_SEQUENCER=espresso
ESPRESSO_BASE_URL=http://espresso:10040
ESPRESSO_NAMESPACE=51025
ESPRESSO_STARTING_BLOCK=10
```

Then you can start the database, devnet, and espresso:

```shell
make -f node.mk run-devnet-localhost
make -f node.mk run-database-localhost
make -f node.mk run-espresso-localhost
```

Finally, start the node and deploy the application

```shell
make -f node.mk run-node-localhost
make -f node.mk deploy-localhost 
```

## Testnet

Create a .env.<testnet> file with:

```shell
CARTESI_LOG_LEVEL=info
CARTESI_AUTH_KIND=private_key
CARTESI_CONTRACTS_INPUT_BOX_ADDRESS=0x593E5BCf894D6829Dd26D0810DA7F064406aebB6
CARTESI_CONTRACTS_INPUT_BOX_DEPLOYMENT_BLOCK_NUMBER=6994348
MAIN_SEQUENCER=espresso
ESPRESSO_BASE_URL=https://query.decaf.testnet.espresso.network
ESPRESSO_NAMESPACE=51025
ESPRESSO_STARTING_BLOCK=
CARTESI_BLOCKCHAIN_HTTP_ENDPOINT=
CARTESI_BLOCKCHAIN_WS_ENDPOINT=
CARTESI_BLOCKCHAIN_ID=
CARTESI_AUTH_PRIVATE_KEY=
```

Then start the database and node:

```shell
make -f node.mk run-database-<testnet>
make -f node.mk run-node-<testnet>
```

And deploy the application with (optionally set `IMAGE_PATH`):

```shell
make -f node.mk deploy-<testnet> OWNER=<app and auth owner>
```

You should set `OWNER` to the same owner of the `CARTESI_AUTH_PRIVATE_KEY`. Set `CONSENSUS_ADDRESS` to deploy a new application with same consensus already deployed. You can also set `EPOCH_LENGTH`, and `SALT`.

To stop the environment just run:

```shell
make -f node.mk stop-<testnet>
```

Note: If want to register an already deployed application to the node use (optionally set `IMAGE_PATH`):

```shell
make -f node.mk register-<testnet> APPLICATION_ADDRESS=<app address> CONSENSUS_ADDRESS=<auth address> 
```

## Deploy backend to fly.io

Go to the directory containing your project. You should create a `.env.<testnet>` file with:

```shell
CARTESI_LOG_LEVEL=info
CARTESI_AUTH_KIND=private_key
CARTESI_CONTRACTS_INPUT_BOX_ADDRESS=0x593E5BCf894D6829Dd26D0810DA7F064406aebB6
CARTESI_CONTRACTS_INPUT_BOX_DEPLOYMENT_BLOCK_NUMBER=6994348
MAIN_SEQUENCER=espresso
ESPRESSO_BASE_URL=https://query.decaf.testnet.espresso.network/
ESPRESSO_NAMESPACE=51025
ESPRESSO_STARTING_BLOCK=
CARTESI_BLOCKCHAIN_HTTP_ENDPOINT=
CARTESI_BLOCKCHAIN_WS_ENDPOINT=
CARTESI_BLOCKCHAIN_ID=
CARTESI_AUTH_PRIVATE_KEY=
CARTESI_POSTGRES_ENDPOINT=
```

Note that the value of `CARTESI_POSTGRES_ENDPOINT` will be provided on the Step 3.

Then follow these steps to deploy on fly

**Step 1**: Create a directory for the fly app and cd into it

```shell
mkdir -p .fly/node
```

**Step 2**: Create the base fly configuration for the node. This is important to control the auto-stop behavior and minimum machines running. Create a `.fly/node/fly.toml` in this directory with the following content:

```toml
[build]
  image = "ghcr.io/prototyp3-dev/test-node-cloud:test"

[http_service]
  internal_port = 80
  force_https = true
  auto_stop_machines = 'off'
  auto_start_machines = false
  min_machines_running = 1
  processes = ['app']

[metrics]
  port = 9000
  path = "/metrics"

[[vm]]
  size = 'shared-cpu-1x'
  memory = '1gb'
  cpu_kind = 'shared'
  cpus = 1
```

We suggest creating a persistent volume to store the snapshots, so you wouldn't need to transfer the snapshots when restarting the virtual machine. Create the `<node-volume>` volume and add this section to the `.fly/node/fly.toml` file:

```toml
[[mounts]]
  source = '<nodevolume>'
  destination = '/mnt'
  initial_size = '5gb'
```

**Step 3**: Create the Postgres database

```shell
fly ext supabase create
```

Make sure to add the value of `CARTESI_POSTGRES_ENDPOINT` variable to your environment file.

You can also use the `fly postgres` to create the database:

```shell
fly postgres create
```

Similarly, make sure to set the value of `CARTESI_POSTGRES_ENDPOINT` variable to your environment file. You should use the provided `Connection string` to set these variables, and don't forget to add the database `postgres` and option `sslmode=disable` to the string (**`postgres?sslmode=disable`**):

```shell
postgres://{username}:{password}@{hostname}:{port}/postgres?sslmode=disable
```

**Step 4**: Create the Fly app without deploying yet

```shell
fly launch --name <app-name> --copy-config --no-deploy -c .fly/node/fly.toml
```

**Step 5**: Import the secrets from the .env file

```shell
fly secrets import -c .fly/node/fly.toml < .env.<testnet>
```

**Step 6**: Deploy the backend node

```shell
fly deploy --ha=false -c .fly/node/fly.toml
```

Now you have a rollups node with the node running on the provided url.

**Step 7**: Deploy the app to the node

You'll have to copy the snapshot using sftp shell (we are considering the application snapshot is at `.cartesi/image`). 

```shell
app_name=<app-name>
image_path=.cartesi/image

fly ssh console -c .fly/node/fly.toml -C "mkdir -p /mnt/apps/$app_name"
```

Then run this command to print all transfers:

```shell
for f in $(ls -d $image_path/*); do echo "put $f /mnt/apps/$app_name"/$(basename $f); done
```

Then run the sftp shell and paste the listed transfers:

```shell
fly sftp shell -c .fly/node/fly.toml
```

Finally, run the deployment on the node: 

```shell
fly ssh console -c .fly/node/fly.toml -C "bash -c 'OWNER={OWNER} /deploy.sh /mnt/apps/$app_name'"
```

You should set `OWNER` to the same owner of the `CARTESI_AUTH_PRIVATE_KEY`. Set `CONSENSUS_ADDRESS` to deploy a new application with same consensus already deployed. You can also set `EPOCH_LENGTH`, and `SALT`.

If you have already deployed the application, you can register it to add to the node (after transfering the image).

```shell
fly ssh console -c .fly/node/fly.toml -C "bash -c 'APPLICATION_ADDRESS=${APPLICATION_ADDRESS} CONSENSUS_ADDRESS=${CONSENSUS_ADDRESS} /register.sh /mnt/apps/$app_name'"
```

Your application is now deployed on the node. Also note that you can deploy multiple applications on the same node.

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
docker run -it --rm -v $PWD:/workdir -w /workdir ghcr.io/prototyp3-dev/test-node:test bash
```

First, you should start off from a base rootfs, either the one installed with cartesi machine (`/share/cartesi-machine/images/rootfs.ext2`) or one generated with cartesi cli (`/path/to/app/.cartesi/root.ext2`). Copy the base image to a working dir so you can start making changes. 

```shell
cp /path/to/rootfs.ext2 root.ext2
```

This root.ext2` is your working image. Then, you should resize as you see necessary

```shell
resize2fs -f root.ext2 128M
```

#### Start from a root.ext2 and prepare image

Before you install you app in the image, you should prepare and install any dependencies. Start the cartesi machine in interactive mode with network and volumes virtio:

```shell
cartesi-machine --network --volume=.:/mnt --workdir=/mnt --flash-drive=label:root,filename:root.ext2,shared -u=root -it -- bash
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
cartesi-machine --env=ROLLUP_HTTP_SERVER_URL=http://127.0.0.1:5004 --flash-drive=label:root,filename:root.ext2 --store=.cartesi/image --assert-rolling-template -- rollup-init /opt/cartesi/app/app
```

The starting snapshot was saved to `.cartesi/image` directory. This snapshot is copied to your the node to be able to run the application.

And finally, make sure the image directory has read permissions for all users

```shell
chmod a+xr .cartesi/image
```
