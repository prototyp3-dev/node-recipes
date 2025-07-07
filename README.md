# Node Recipes

Experimental recipes to test Cartesi Rollups SDK and Espresso integration.

## Two Ways to Run Node Recipes

### 🚀 **Run using the Script**
Use the `dev.sh` script for an abstracted, user-friendly experience. Commands include `setup`, `start`, `deploy` and `stop`. Recommended for testing Espresso integration.

### ⚙️ **Run manually(without the script)**
Use Docker Compose and Makefiles directly for full control. This README covers the simplified script approach. For running manually, see [node/node.md](node/node.md).

---

## Quick Start

The following commands are meant to be run in the root of the Cartesi application project.

### 1. Setup

```bash
# Download and setup the development environment
curl -fsSL https://raw.githubusercontent.com/prototyp3-dev/node-recipes/main/dev.sh -o dev.sh && chmod +x dev.sh && ./dev.sh setup
```

This will:
- Download required Docker images
- Create `.env.localhost`
- Configure Espresso setup

### 2. Start Development Environment

```bash
# Start with Espresso sequencer (default)
./dev.sh start

# Or start with Ethereum sequencer
./dev.sh start ethereum
```

### 3. Deploy Your Application

```bash
./dev.sh deploy
```
Alternatively, for customized deployment, use:

```bash
./dev.sh deploy --app-name my-app --image-path ./custom-path
```

### 4. Send Transactions(EIP-712) to Espresso

```bash
./dev.sh send -a APP_ADDRESS -d HEX_DATA -k PRIVATE_KEY
```

### 5. Stop Environment

```bash
./dev.sh stop
```

---

## Deploy in testnet environment

For testnet deployment, we'll use fly.io to host the node and Ethereum Sepolia with Espresso Decaf as sequencer. 

### Prerequisites

Install fly.io CLI:
```bash
curl -L https://fly.io/install.sh | sh
```

### 1. Create Environment File for Ethereum Sepolia and Espresso Decaf Testnet

Create `.env.sepolia` with the following configuration:

```bash
cat > .env.sepolia << 'EOF'
CARTESI_LOG_LEVEL=info
CARTESI_AUTH_KIND=private_key
CARTESI_CONTRACTS_INPUT_BOX_ADDRESS=0xc70074BDD26d8cF983Ca6A5b89b8db52D5850051
CARTESI_CONTRACTS_AUTHORITY_FACTORY_ADDRESS=0xC7003566dD09Aa0fC0Ce201aC2769aFAe3BF0051
CARTESI_CONTRACTS_APPLICATION_FACTORY_ADDRESS=0xc7006f70875BaDe89032001262A846D3Ee160051
CARTESI_CONTRACTS_SELF_HOSTED_APPLICATION_FACTORY_ADDRESS=0xc700285Ab555eeB5201BC00CFD4b2CC8DED90051
MAIN_SEQUENCER=espresso
CARTESI_FEATURE_GRAPHQL_ENABLED=true
CARTESI_FEATURE_RPC_ENABLED=true
ESPRESSO_BASE_URL=https://query.decaf.testnet.espresso.network
ESPRESSO_NAMESPACE=55555
CARTESI_BLOCKCHAIN_HTTP_ENDPOINT=
CARTESI_BLOCKCHAIN_WS_ENDPOINT=
CARTESI_BLOCKCHAIN_ID=11155111
CARTESI_AUTH_PRIVATE_KEY=
CARTESI_DATABASE_CONNECTION=
EOF
```

**Important**: Update the following variables before deployment:
- `CARTESI_BLOCKCHAIN_HTTP_ENDPOINT`: Your Sepolia RPC endpoint (e.g., Infura, Alchemy)
- `CARTESI_BLOCKCHAIN_WS_ENDPOINT`: Your Sepolia WebSocket endpoint  
- `CARTESI_AUTH_PRIVATE_KEY`: Private key for contract deployments
- `CARTESI_DATABASE_CONNECTION`: Will be added after database creation in step 2

### 2. Deploy Node Infrastructure

```bash
./dev.sh deploy-node --app-name my-cartesi-node --env-file .env.sepolia
```

This will:
- Create fly.toml configuration
- Launch fly.io app (interactive setup)
- Create Postgres database (interactive setup)
- **Pause for manual step**: Update database connection in your .env.sepolia file

### 3. Deploy Application and Contracts

For new contract deployment:
```bash
./dev.sh deploy-app --app-name my-cartesi-node --env-file .env.sepolia --owner 0xYourOwnerAddress
```

For existing contracts:
```bash
./dev.sh deploy-app --app-name my-cartesi-node --env-file .env.sepolia --application-address 0xExistingAppAddress --consensus-address 0xConsensusAddress
```

---

## Dependencies

- **Docker Desktop**: https://docker.com
- **For send command**: curl, jq, cast (foundry)

Install missing dependencies:
```bash
# macOS
brew install curl jq
curl -L https://foundry.paradigm.xyz | bash && foundryup

# Ubuntu/Debian
sudo apt install curl jq
curl -L https://foundry.paradigm.xyz | bash && foundryup
```