# Test Node with Nonodo

Instructions to run a cartesi rollups node with nonodo

Check [Setup](#setup) for some initial instructions, [Localhost](#localhost) to start a local node with a devnet, [Testnet](#testnet) to start local node using a testnet, [Fly](#fly) for instructions to deploy a node on [Fly](https://fly.io/docs).

## Setup

To run the application inside the image, it requires a `entrypoint.sh` file. So make sure you generate it so it can run your application. Example `entrypoint.sh` file (considering the project is a single `app` binary):

```shell
#!/bin/bash
./app
```

You should also generate a valid rootfs to use as the root file system of the cartesi machine (you can follow [these instructions](/node/node.md#prepare-the-snapshot))

Also, make sure you have the updated base nonode image:

```shell
docker pull ghcr.io/prototyp3-dev/test-nonode:latest
```

## Localhost

Go to the directory containing your project (you should have a `entrypoint.sh` file). To run you can use the following command (we'll assume you have a rootfs in  `$PWD/.cartesi/root.ext2`):

```shell
docker run --rm -p8080:80 -p8545:8545 \
    -v $PWD:/opt/cartesi/app \
    -v $PWD/.cartesi/root.ext2:/opt/cartesi/image/root.ext2 \
    ghcr.io/prototyp3-dev/test-nonode:latest
```

## Testnet

Go to the directory containing your project. You should create a .env.<testnet> file with:

```shell
FROM_BLOCK=
RPC_URL=
APP_ADDRESS=
ESPRESSO_STARTING_BLOCK=
ESPRESSO_NAMESPACE=51025
ESPRESSO_BASE_URL=https://query.decaf.testnet.espresso.network
CARTESI_CONTRACTS_INPUT_BOX_ADDRESS=0x593E5BCf894D6829Dd26D0810DA7F064406aebB6
CARTESI_CONTRACTS_INPUT_BOX_DEPLOYMENT_BLOCK_NUMBER=6994348
```

To run you can use the following command (we'll assume you have a rootfs in `$PWD/.cartesi/root.ext2`):

```shell
docker run --rm -p8080:80 \
    --env-file=.env.<testnet> \
    -v $PWD:/opt/cartesi/app \
    -v $PWD/.cartesi/root.ext2:/opt/cartesi/image/root.ext2 \
    ghcr.io/prototyp3-dev/test-nonode:latest
```

Add `-v $PWD/db:/opt/cartesi/db` argument if you want to store the state and rerun using the db.

## Fly

Go to the directory containing your project. You should create a .env.<testnet> file with:

```shell
FROM_BLOCK=
RPC_URL=
APP_ADDRESS=
ESPRESSO_STARTING_BLOCK=
ESPRESSO_NAMESPACE=51025
ESPRESSO_BASE_URL=https://query.decaf.testnet.espresso.network
CARTESI_CONTRACTS_INPUT_BOX_ADDRESS=0x593E5BCf894D6829Dd26D0810DA7F064406aebB6
CARTESI_CONTRACTS_INPUT_BOX_DEPLOYMENT_BLOCK_NUMBER=6994348
```

Also create a `app-nonode.dockerfile` that creates an image containing your project (we'll assume you have a rootfs in `$PWD/.cartesi/root.ext2`)

```Dockerfile
FROM ghcr.io/prototyp3-dev/test-nonode-cloud:latest
COPY . /opt/cartesi/app
COPY .cartesi/root.ext2 /opt/cartesi/image/root.ext2
```

Then follow these steps to deploy on fly

**Step 1**: Create a directory for the fly app and cd into it

```shell
mkdir -p .fly/nonode
```

**Step 2**: Create the base fly configuration for the node. This is important to control the auto-stop behavior and minimum machines running. Create a `.fly/nonode/fly.toml` in this directory with the following content:

```toml
[build]
  dockerfile = '../../app-nonode.dockerfile'

[http_service]
  internal_port = 80
  force_https = true
  auto_stop_machines = 'off'
  auto_start_machines = false
  min_machines_running = 1
  processes = ['app']
 
[[vm]]
  size = 'shared-cpu-1x'
  memory = '1gb'
  cpu_kind = 'shared'
  cpus = 1
```

We suggest creating a .dockerignore file to avoid unnecessary files on the image and defining `ignorefile = "../../.dockerignore"` on the `[build]` section.

**Step 3**: Create the Fly app without deploying yet

```shell
fly launch --name app-nonode --copy-config --no-deploy -c .fly/nonode/fly.toml
```

**Step 4**: Import the secrets from the .env file

```shell
fly secrets import -c .fly/nonode/fly.toml < .env.<testnet>
```

**Step 5**: Deploy the app

```shell
fly deploy --ha=false -c .fly/nonode/fly.toml
```

Now you have a rollups node with nonodo running on the provided url.
