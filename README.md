# Node Recipes

Experimental recipes to test Cartesi Rollups SDK and Espresso integration.

## Two Ways to Run Node Recipes

### 🚀 **Run using the Script**
Use the `dev.sh` script for an abstracted, user-friendly experience. Commands include `setup`, `start`, `deploy` and `stop`. Recommended for testing Espresso integration.

### ⚙️ **Run manually(without the script)**
Use Docker Compose and Makefiles directly for full control. This README covers the simplified script approach. For running manually, see [node/node.md](node/node.md).

---

## Quick Start

### 1. Setup

```bash
# Download and setup the development environment
curl -fsSL https://raw.githubusercontent.com/prototyp3-dev/node-recipes/feature/v2-alpha/dev.sh -o dev.sh && chmod +x dev.sh && ./dev.sh setup
```

This will:
- Download required Docker images
- Create `.env.localhost` with Espresso sequencer as default
- Configure all necessary Espresso settings

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