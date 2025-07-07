#!/bin/bash

# Cartesi Node Recipes - Unified Developer Script
# Simplifies all node operations into easy commands

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME=${APP_NAME:-$(basename "$PWD")}
IMAGE_PATH=${IMAGE_PATH:-".cartesi/image"}
ENVFILE=".env"
REPO_URL="https://github.com/prototyp3-dev/node-recipes"
BRANCH="main"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# Check dependencies
check_deps() {
    if ! command -v docker &> /dev/null; then
        error "Docker not found. Please install Docker Desktop from https://docker.com"
        exit 1
    fi
    
    if ! command -v docker compose &> /dev/null && ! command -v docker-compose &> /dev/null; then
        error "Docker Compose not found. Please install Docker Compose"
        exit 1
    fi
}

# Check send dependencies
check_send_deps() {
    command -v curl >/dev/null && command -v jq >/dev/null && command -v cast >/dev/null || { 
        error "Missing dependencies for send: install curl, jq, and cast (foundry)"
        echo "Install with: brew install curl jq && curl -L https://foundry.paradigm.xyz | bash && foundryup"
        exit 1
    }
}

# Check fly.io deployment dependencies
check_fly_deps() {
    command -v fly >/dev/null || { 
        error "Missing dependency for fly.io deployment: install fly CLI"
        echo "Install with: curl -L https://fly.io/install.sh | sh"
        exit 1
    }
}

# Check setup dependencies (for initial setup)
check_setup_deps() {
    local missing=()
    
    if ! command -v docker &> /dev/null; then
        missing+=("Docker")
    fi
    
    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        missing+=("curl or wget")
    fi
    
    if ! command -v unzip &> /dev/null; then
        missing+=("unzip")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing[*]}"
        echo
        echo "Please install the missing dependencies:"
        echo "  - Docker: https://docker.com"
        echo "  - curl/wget: usually pre-installed"
        echo "  - unzip: usually pre-installed"
        exit 1
    fi
}

# Check if node environment is set up
check_node_setup() {
    if [[ ! -f "node-compose.yml" || ! -f "node.mk" ]]; then
        error "Node environment not set up. Please run setup first:"
        echo "  curl -fsSL https://raw.githubusercontent.com/prototyp3-dev/node-recipes/main/dev.sh -o dev.sh && chmod +x dev.sh && ./dev.sh setup"
        exit 1
    fi
}

# Setup node development environment (local files)
setup_local() {
    log "Setting up Cartesi node development environment..."
    setup_node
    log "Setup complete! Run './dev.sh start' to begin development"
}

# Download node files from repository
download_files() {
    log "Downloading Cartesi Node Recipes files..."
    
    # Create temporary directory
    local temp_dir=$(mktemp -d)
    local zip_file="$temp_dir/node-recipes.zip"
    
    # Download repository
    if command -v curl &> /dev/null; then
        curl -fsSL "$REPO_URL/archive/refs/heads/$BRANCH.zip" -o "$zip_file"
    else
        wget -q "$REPO_URL/archive/refs/heads/$BRANCH.zip" -O "$zip_file"
    fi
    
    # Extract files
    unzip -q "$zip_file" -d "$temp_dir"
    local branch_folder=$(echo "$BRANCH" | tr '/' '-')
    local repo_dir="$temp_dir/node-recipes-$branch_folder"
    
    # Copy node files (don't overwrite this script)
    cp "$repo_dir/node/node-compose.yml" ./
    cp "$repo_dir/node/node.mk" ./
    
    # Cleanup
    rm -rf "$temp_dir"
    
    log "Files downloaded successfully!"
}

# Setup node development environment (with download)
setup() {
    check_setup_deps
    
    log "Setting up Cartesi node development environment..."
    
    # Download required files
    download_files
    
    # Setup environment
    setup_node
    
    # Create environment file
    create_default_env "localhost"
    
    # Show completion message
    echo
    log "🎉 Cartesi with Espresso sequencer setup complete!"
    echo
    info "Next steps:"
    echo
    echo "  1. Start development environment (with Espresso sequencer):"
    echo "     ./dev.sh start"
    echo
    echo "  2. Deploy your application:"
    echo "     ./dev.sh deploy"
    echo
    echo "  3. Send transactions to Espresso:"
    echo "     ./dev.sh send -a APP_ADDRESS -d DATA -k PRIVATE_KEY"
    echo
    echo "  4. Stop the development environment:"
    echo "     ./dev.sh stop"
    echo
    echo "For help: ./dev.sh help"
    echo
}

# Setup node environment using makefile
setup_node() {
    log "Setting up Cartesi node environment..."
    
    # Pull required images
    docker pull ghcr.io/prototyp3-dev/test-node:2.0.0-alpha
    docker pull ghcr.io/prototyp3-dev/test-devnet:2.0.0
}

# Create environment file using makefile and add espresso config
create_default_env() {
    local env_suffix=${1:-"localhost"}
    local env_file=".env.$env_suffix"
    
    log "Creating environment file with Espresso defaults..."
    # Let makefile handle base environment file creation
    make -f node.mk "$env_file"
    
    # Override the default sequencer to espresso and add espresso-specific config
    if [[ -f "$env_file" ]]; then
        log "Configuring for Espresso sequencer by default..."
        
        # Update MAIN_SEQUENCER from ethereum to espresso
        if grep -q "MAIN_SEQUENCER=" "$env_file"; then
            sed -i.bak 's/MAIN_SEQUENCER="ethereum"/MAIN_SEQUENCER="espresso"/' "$env_file"
        else
            echo "MAIN_SEQUENCER=\"espresso\"" >> "$env_file"
        fi
        
        # Add espresso-specific configuration if not already present
        if ! grep -q "ESPRESSO_BASE_URL" "$env_file" 2>/dev/null; then
            echo "" >> "$env_file"
            echo "# Espresso Configuration" >> "$env_file"
            echo "ESPRESSO_BASE_URL=http://espresso:10040" >> "$env_file"
            echo "ESPRESSO_NAMESPACE=55555" >> "$env_file"
        fi
        
        log "Environment configured for Espresso sequencer by default"
    fi
}

# Start development environment
start() {
    check_deps
    check_node_setup
    
    local sequencer="espresso"  # Default to Espresso
    local port=8080
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            ethereum)
                sequencer="ethereum"
                shift
                ;;
            espresso)
                sequencer="espresso"
                shift
                ;;
            --port)
                port="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    log "Starting Cartesi node environment with $sequencer sequencer..."
    start_node "$sequencer" "$port"
}

# Start node environment using makefile with environment overrides
start_node() {
    local sequencer=${1:-"espresso"}
    local port=${2:-8080}
    
    # Use makefile targets with environment variable overrides
    export ENVFILENAME=".env.localhost"
    
    log "Configuring for $sequencer sequencer..."
    
    # Update sequencer in env file only if different
    if [[ -f ".env.localhost" ]]; then
        local current_sequencer=$(grep "MAIN_SEQUENCER=" .env.localhost 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        
        if [[ "$current_sequencer" != "$sequencer" ]]; then
            if grep -q "MAIN_SEQUENCER=" .env.localhost; then
                sed -i.bak "s/MAIN_SEQUENCER=.*/MAIN_SEQUENCER=\"$sequencer\"/" .env.localhost
                log "Updated MAIN_SEQUENCER from $current_sequencer to $sequencer in .env.localhost"
            else
                echo "MAIN_SEQUENCER=\"$sequencer\"" >> .env.localhost
                log "Added MAIN_SEQUENCER=$sequencer to .env.localhost"
            fi
        else
            log "MAIN_SEQUENCER already set to $sequencer"
        fi
    fi
    
    # Start services using makefile targets
    log "Starting database and devnet..."
    make -f node.mk run-database-localhost
    make -f node.mk run-devnet-localhost
    
    if [[ "$sequencer" == "espresso" ]]; then
        log "Starting Espresso sequencer..."
        make -f node.mk run-espresso-localhost
    fi
    
    log "Starting Cartesi node..."
    make -f node.mk run-node-localhost
    
    log "Node environment started with $sequencer sequencer!"
    log "GraphQL available at http://localhost:$port/graphql"
}

# Deploy application
deploy() {
    check_node_setup
    
    local app_name=${APP_NAME}
    local image_path=${IMAGE_PATH}
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --app-name)
                app_name="$2"
                shift 2
                ;;
            --image-path)
                image_path="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    log "Deploying application: $app_name"
    
    if [[ ! -d "$image_path" ]]; then
        error "Snapshot not found at $image_path. Please create your application snapshot first."
        exit 1
    fi
    
    deploy_to_node "$app_name" "$image_path"
}

# Deploy to full node
deploy_to_node() {
    local app_name=$1
    local image_path=$2
    
    log "Deploying to full node..."
    
    # Wait for devnet to be ready
    log "Waiting for devnet to be ready..."
    local retries=0
    local max_retries=30
    while [[ $retries -lt $max_retries ]]; do
        if curl -s -X POST -H "Content-Type: application/json" \
           --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
           http://localhost:8545 > /dev/null 2>&1; then
            break
        fi
        sleep 2
        ((retries++))
        echo -n "."
    done
    echo
    
    if [[ $retries -eq $max_retries ]]; then
        error "Devnet not responding after $((max_retries * 2)) seconds. Please check if services are running properly."
        exit 1
    fi
    
    log "Devnet is ready. Starting deployment..."
    log "Note: This may take a few seconds to deploy the contracts..."
    
    # Run the actual deployment with error handling
    if ! ENVFILENAME=".env.localhost" APP_NAME="$app_name" IMAGE_PATH="$image_path" make -f node.mk deploy-localhost OWNER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; then
        error "Deployment failed. This might be due to:"
        echo "  1. Contracts not yet deployed (wait and try again)"
        echo "  2. Invalid snapshot at $image_path"
        echo "  3. Network connectivity issues"
        echo
        echo "Try running: ./dev.sh deploy again in a few seconds"
        exit 1
    fi
    
    log "Application deployed successfully!"
}

# Stop environment
stop() {
    log "Stopping Cartesi development environment..."
    
    # Stop Docker containers
    docker stop $(docker ps -q --filter "name=cartesi-") 2>/dev/null || true
    
    # Stop compose services if they exist
    if [[ -f "node-compose.yml" ]] || [[ -f "node.mk" ]]; then
        ENVFILENAME=".env.localhost" make -f node.mk stop-localhost 2>/dev/null || ENVFILENAME=".env.localhost" docker compose -f node-compose.yml --env-file .env.localhost down 2>/dev/null || true
    fi
    
    log "Environment stopped"
}

# Espresso transaction functions
get_nonce() {
    local response=$(curl -s -X POST -H "Content-Type: application/json" -d "{\"app_contract\":\"$1\",\"msg_sender\":\"$2\"}" "$3/nonce")
    echo "$response" | jq -r '.nonce' || { error "Failed to get nonce"; return 1; }
}

create_typed_data() {
    cat << EOF
{
  "domain": {
    "name": "Cartesi",
    "version": "0.1.0",
    "chainId": $3,
    "verifyingContract": "0x0000000000000000000000000000000000000000"
  },
  "types": {
    "EIP712Domain": [
      {"name": "name", "type": "string"},
      {"name": "version", "type": "string"},
      {"name": "chainId", "type": "uint256"},
      {"name": "verifyingContract", "type": "address"}
    ],
    "CartesiMessage": [
      {"name": "app", "type": "address"},
      {"name": "nonce", "type": "uint64"},
      {"name": "max_gas_price", "type": "uint128"},
      {"name": "data", "type": "bytes"}
    ]
  },
  "primaryType": "CartesiMessage",
  "message": {
    "app": "$1",
    "nonce": $2,
    "max_gas_price": "0",
    "data": "$4"
  }
}
EOF
}

sign_typed_data() {
    local temp_file=$(mktemp)
    echo "$1" > "$temp_file"
    local signature=$(cast wallet sign --private-key "$2" --data --from-file "$temp_file" 2>/dev/null)
    rm -f "$temp_file"
    echo "$signature" || { error "Failed to sign"; return 1; }
}

get_account_from_key() {
    cast wallet address --private-key "$1" || { error "Invalid private key"; return 1; }
}

submit_transaction() {
    local payload=$(jq -n --argjson typedData "$1" --arg signature "$2" --arg account "$3" '{typedData: $typedData, signature: $signature, account: $account}')
    local response=$(curl -s -X POST -H "Content-Type: application/json" -d "$payload" "$4/submit")
    echo "$response" | jq -r '.id' || { error "Failed to submit"; return 1; }
}

# Default values for send command
SEND_CHAIN_ID="31337"
SEND_NODE_URL="http://localhost:8080"

# Send transaction to Espresso
send() {
    check_send_deps
    
    local app_address=""
    local data=""
    local private_key=""
    local chain_id="$SEND_CHAIN_ID"
    local node_url="$SEND_NODE_URL"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--app)
                app_address="$2"
                shift 2
                ;;
            -d|--data)
                data="$2"
                shift 2
                ;;
            -k|--private-key)
                private_key="$2"
                shift 2
                ;;
            -c|--chain-id)
                chain_id="$2"
                shift 2
                ;;
            -n|--node-url)
                node_url="$2"
                shift 2
                ;;
            -h|--help)
                cat << 'EOF'
Usage: ./dev.sh send -a APP_ADDRESS -d DATA -k PRIVATE_KEY [OPTIONS]

Send L2 transactions to Cartesi+Espresso

REQUIRED:
    -a, --app ADDRESS      App contract address
    -d, --data DATA        Transaction data in hex
    -k, --private-key KEY  Private key for signing

OPTIONAL:
    -c, --chain-id ID      Chain ID (default: 31337)
    -n, --node-url URL     Node URL (default: http://localhost:8080)
    -h, --help            Show this help

EXAMPLES:
    # Basic usage (uses defaults)
    ./dev.sh send -a 0x1234... -d 0x48656c6c6f -k your_private_key
    
    # With custom chain/node
    ./dev.sh send -a 0x1234... -d 0x48656c6c6f -k your_key -c 11155111 -n http://remote:8080
EOF
                return 0
                ;;
            *)
                error "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    # Validate required arguments
    if [[ -z "$app_address" ]] || [[ -z "$data" ]] || [[ -z "$private_key" ]]; then
        error "Missing required arguments"
        echo "Use: ./dev.sh send --help for usage"
        return 1
    fi
    
    # Add 0x prefix if missing
    [[ ! "$app_address" =~ ^0x ]] && app_address="0x$app_address"
    [[ ! "$data" =~ ^0x ]] && data="0x$data"
    [[ "$private_key" =~ ^0x ]] && private_key="${private_key#0x}"
    
    log "Sending transaction to Espresso..."
    
    # Get account address from private key
    local account
    if ! account=$(get_account_from_key "$private_key"); then
        error "Failed to get account from private key"
        return 1
    fi
    log "Account: $account"
    
    # Get nonce
    local nonce
    if ! nonce=$(get_nonce "$app_address" "$account" "$node_url"); then
        error "Failed to get transaction nonce"
        return 1
    fi
    log "Nonce: $nonce"
    
    # Create TypedData
    local typed_data
    if ! typed_data=$(create_typed_data "$app_address" "$nonce" "$chain_id" "$data"); then
        error "Failed to create typed data"
        return 1
    fi
    
    # Sign the TypedData
    local signature
    if ! signature=$(sign_typed_data "$typed_data" "$private_key"); then
        error "Failed to sign transaction"
        return 1
    fi
    log "Transaction signed"
    
    # Submit transaction
    local tx_id
    if ! tx_id=$(submit_transaction "$typed_data" "$signature" "$account" "$node_url"); then
        error "Failed to submit transaction"
        return 1
    fi
    log "🎉 Transaction submitted! Input ID: $tx_id"
}

# Show help
help() {
    cat << 'EOF'
Cartesi Node Recipes - Developer Script

USAGE:
    ./dev.sh <command> [options]

COMMANDS:
    setup                  Download and setup node development environment
    
    start [sequencer]      Start node environment
                          Default: espresso sequencer
                          Options: ethereum, espresso
        --port PORT        Use custom port (default: 8080)
    
    stop                   Stop all services
    
    deploy [options]       Deploy application on local node
        --app-name NAME    Application name
        --image-path PATH  Snapshot location
    
    send                   Send transaction to Espresso
        -a, --app ADDRESS  App contract address (required)
        -d, --data DATA    Transaction data in hex (required)
        -k, --private-key  Private key for signing (required)
        Optional: -c chain-id (31337), -n node-url (localhost:8080)
    
    deploy-node            Deploy node to fly.io
        --app-name NAME    Fly app name (required)
        --env-file FILE    Environment file (required)
        --volume NAME      Volume name for storage
    
    deploy-app             Deploy contracts and register app
        --app-name NAME    Fly app name (required)
        --env-file FILE    Environment file (required)
        --owner ADDRESS    Owner for new contracts
        --skip-contracts   Use existing contracts
        --application-address  Existing app contract address
    
    help                   Show this help

EXAMPLES:
    # First time setup
    curl -fsSL https://raw.githubusercontent.com/prototyp3-dev/node-recipes/main/dev.sh -o dev.sh && chmod +x dev.sh && ./dev.sh setup
    
    # Daily usage
    ./dev.sh start                     # Start with Espresso sequencer (default)
    ./dev.sh start ethereum            # Start with Ethereum sequencer
    ./dev.sh deploy                    # Deploy current application
    ./dev.sh send -a 0x1234... -d 0x48656c6c6f -k your_key  # Send transaction
    ./dev.sh stop                      # Stop everything

EOF
}

# Deploy node to fly.io
deploy_node() {
    check_fly_deps
    
    local app_name=""
    local env_file=""
    local volume_name=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --app-name)
                app_name="$2"
                shift 2
                ;;
            --env-file)
                env_file="$2"
                shift 2
                ;;
            --volume)
                volume_name="$2"
                shift 2
                ;;
            -h|--help)
                cat << 'EOF'
Usage: ./dev.sh deploy-node --app-name APP_NAME --env-file ENV_FILE [OPTIONS]

Deploy Cartesi node infrastructure to fly.io

REQUIRED:
    --app-name NAME        Fly app name
    --env-file FILE        Environment file (e.g., .env.testnet)

OPTIONAL:
    --volume NAME          Volume name for persistent storage
    -h, --help            Show this help

EXAMPLES:
    ./dev.sh deploy-node --app-name my-cartesi-node --env-file .env.testnet
    ./dev.sh deploy-node --app-name my-node --env-file .env.testnet --volume node-volume
EOF
                return 0
                ;;
            *)
                error "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    # Validate required arguments
    if [[ -z "$app_name" ]] || [[ -z "$env_file" ]]; then
        error "Missing required arguments"
        echo "Use: ./dev.sh deploy-node --help for usage"
        return 1
    fi
    
    if [[ ! -f "$env_file" ]]; then
        error "Environment file not found: $env_file"
        return 1
    fi
    
    log "Deploying Cartesi node to fly.io..."
    
    # Create fly directory structure
    mkdir -p .fly/node
    
    # Create fly.toml configuration
    log "Creating fly.toml configuration..."
    cat > .fly/node/fly.toml << EOF
[build]
  image = "ghcr.io/prototyp3-dev/test-node-cloud:latest"

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
EOF
    
    # Add volume mount if specified
    if [[ -n "$volume_name" ]]; then
        log "Adding volume mount: $volume_name"
        cat >> .fly/node/fly.toml << EOF

[[mounts]]
  source = '$volume_name'
  destination = '/mnt'
  initial_size = '5gb'
EOF
    fi
    
    # Create/launch the fly.io app without deploying
    log "Creating fly app: $app_name"
    if ! fly launch --name "$app_name" --copy-config --no-deploy -c .fly/node/fly.toml; then
        warn "App may already exist, continuing..."
    fi
    
    # Create database
    log "Creating Postgres database..."
    fly postgres create
    
    echo
    warn "IMPORTANT: Update your database connection string in $env_file"
    echo "  1. Copy the DATABASE_URL from the output above"
    echo "  2. Modify it to use 'postgres' database and add sslmode=disable:"
    echo "     Format: postgres://{username}:{password}@{hostname}:{port}/postgres?sslmode=disable"
    echo "  3. Add it to your $env_file as:"
    echo "     CARTESI_DATABASE_CONNECTION=\"postgres://user:pass@host:port/postgres?sslmode=disable\""
    echo "  4. Save the file"
    echo
    read -p "Press Enter after updating $env_file with the database connection..."
    
    # Verify the database connection was added
    if ! grep -q "CARTESI_DATABASE_CONNECTION" "$env_file"; then
        error "CARTESI_DATABASE_CONNECTION not found in $env_file"
        echo "Please add the database connection string and try again"
        return 1
    fi
    
    log "Database connection found in $env_file ✓"
    
    # Import environment secrets
    log "Importing environment secrets..."
    fly secrets import -c .fly/node/fly.toml < "$env_file"
    
    # Deploy the node
    log "Deploying node to fly.io..."
    fly deploy --ha=false -c .fly/node/fly.toml
    
    echo
    warn "Next steps:"
    echo "  Deploy app: ./dev.sh deploy-app --app-name $app_name --env-file $env_file --owner OWNER_ADDRESS"
}

# Deploy contracts and register app
deploy_app() {
    check_fly_deps
    
    local app_name=""
    local env_file=""
    local owner=""
    local image_path=${IMAGE_PATH}
    local cartesi_app_name=${APP_NAME}
    local skip_contracts=false
    local application_address=""
    local consensus_address=""
    local epoch_length=""
    local salt=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --app-name)
                app_name="$2"
                shift 2
                ;;
            --env-file)
                env_file="$2"
                shift 2
                ;;
            --owner)
                owner="$2"
                shift 2
                ;;
            --image-path)
                image_path="$2"
                shift 2
                ;;
            --cartesi-app-name)
                cartesi_app_name="$2"
                shift 2
                ;;
            --skip-contracts)
                skip_contracts=true
                shift
                ;;
            --application-address)
                application_address="$2"
                skip_contracts=true
                shift 2
                ;;
            --consensus-address)
                consensus_address="$2"
                shift 2
                ;;
            --epoch-length)
                epoch_length="$2"
                shift 2
                ;;
            --salt)
                salt="$2"
                shift 2
                ;;
            -h|--help)
                cat << 'EOF'
Usage: ./dev.sh deploy-app --app-name FLY_APP_NAME --env-file ENV_FILE [OPTIONS]

Deploy contracts and register app with fly.io node

REQUIRED:
    --app-name NAME        Fly app name
    --env-file FILE        Environment file (e.g., .env.testnet)

REQUIRED (if not skipping contracts):
    --owner ADDRESS        Owner address (same as CARTESI_AUTH_PRIVATE_KEY owner)

REQUIRED (if skipping contracts):
    --application-address  Existing application contract address

OPTIONAL:
    --image-path PATH      App snapshot path (default: .cartesi/image)
    --cartesi-app-name     Cartesi app name (default: directory name)
    --skip-contracts       Skip contract deployment, use existing addresses
    --consensus-address    Consensus address (for existing or new deployment)
    --epoch-length         Epoch length for new deployment
    --salt                 Salt for new deployment
    -h, --help            Show this help

EXAMPLES:
    # Deploy new contracts and register app
    ./dev.sh deploy-app --app-name my-node --env-file .env.testnet --owner 0x1234...
    
    # Use existing contracts and register app
    ./dev.sh deploy-app --app-name my-node --env-file .env.testnet --application-address 0x5678... --consensus-address 0x9abc...
    
    # Skip contracts entirely
    ./dev.sh deploy-app --app-name my-node --env-file .env.testnet --skip-contracts
EOF
                return 0
                ;;
            *)
                error "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    # Validate required arguments
    if [[ -z "$app_name" ]] || [[ -z "$env_file" ]]; then
        error "Missing required arguments: --app-name and --env-file"
        echo "Use: ./dev.sh deploy-app --help for usage"
        return 1
    fi
    
    if [[ "$skip_contracts" == false ]] && [[ -z "$owner" ]] && [[ -z "$application_address" ]]; then
        error "Missing required argument: --owner (for new deployment) or --application-address (for existing)"
        echo "Use: ./dev.sh deploy-app --help for usage"
        return 1
    fi
    
    if [[ ! -f "$env_file" ]]; then
        error "Environment file not found: $env_file"
        return 1
    fi
    
    if [[ ! -d "$image_path" ]]; then
        error "Snapshot not found at $image_path. Please create your application snapshot first."
        return 1
    fi
    
    # Step 1: Transfer snapshot files to fly.io node
    log "Step 1: Transferring app snapshot files to fly.io node..."
    
    # Create app directory on fly
    log "Creating app directory on node..."
    if ! fly ssh console -c .fly/node/fly.toml -C "mkdir -p /mnt/apps/$cartesi_app_name"; then
        error "Failed to create app directory on fly.io node"
        return 1
    fi
    
    # Transfer snapshot files automatically using SFTP
    log "Transferring snapshot files automatically using SFTP..."
    
    # Generate SFTP commands file
    local sftp_commands="/tmp/fly_sftp_commands.txt"
    > "$sftp_commands"  # Clear the file
    
    # Count total files for progress tracking
    local total_files=$(ls -1 "$image_path"/* | wc -l)
    log "Preparing to transfer $total_files files..."
    
    # Generate put commands for all files
    for file_path in "$image_path"/*; do
        local filename=$(basename "$file_path")
        echo "put $file_path /mnt/apps/$cartesi_app_name/$filename" >> "$sftp_commands"
    done
    
    log "SFTP commands generated. Transferring files..."
    
    # Execute SFTP batch transfer
    if ! fly sftp shell -c .fly/node/fly.toml < "$sftp_commands"; then
        error "Failed to transfer files via SFTP"
        rm -f "$sftp_commands"
        return 1
    fi
    
    # Cleanup
    rm -f "$sftp_commands"
    
    log "✅ All snapshot files transferred successfully!"
    
    # Verify files were transferred correctly
    log "Verifying file transfer..."
    if ! fly ssh console -c .fly/node/fly.toml -C "ls -la /mnt/apps/$cartesi_app_name" > /tmp/remote_files.txt; then
        warn "Could not verify remote files, but transfer appeared successful"
    else
        log "Remote files:"
        cat /tmp/remote_files.txt
        rm -f /tmp/remote_files.txt
    fi
    
    # Step 2: Deploy contracts and register app (all on fly.io node)
    if [[ "$skip_contracts" == false ]]; then
        log "Step 2: Deploying contracts and registering app on fly.io node..."
        
        # Build deploy command to run on fly.io node
        local deploy_cmd="APP_NAME=$cartesi_app_name OWNER=$owner"
        
        if [[ -n "$consensus_address" ]]; then
            deploy_cmd="$deploy_cmd CONSENSUS_ADDRESS=$consensus_address"
        fi
        
        if [[ -n "$epoch_length" ]]; then
            deploy_cmd="$deploy_cmd EPOCH_LENGTH=$epoch_length"
        fi
        
        if [[ -n "$salt" ]]; then
            deploy_cmd="$deploy_cmd SALT=$salt"
        fi
        
        # Run deployment on fly.io node
        local deploy_output
        if ! deploy_output=$(fly ssh console -c .fly/node/fly.toml -C "bash -c '$deploy_cmd /deploy.sh /mnt/apps/$cartesi_app_name'" 2>&1); then
            error "Contract deployment command failed on fly.io node"
            echo "$deploy_output"
            return 1
        fi
        
        # Show deployment output and check for failure indicators
        echo "$deploy_output"
        if echo "$deploy_output" | grep -q -E "(Not deployed|failed|failure|error|Error)"; then
            return 1
        fi
    else
        log "Step 2: Registering existing app on fly.io node..."
        
        # Register existing app
        local register_cmd="APP_NAME=$cartesi_app_name"
        
        if [[ -n "$application_address" ]]; then
            register_cmd="$register_cmd APPLICATION_ADDRESS=$application_address"
        fi
        
        if [[ -n "$consensus_address" ]]; then
            register_cmd="$register_cmd CONSENSUS_ADDRESS=$consensus_address"
        fi
        
        # Run registration on fly.io node
        local register_output
        if ! register_output=$(fly ssh console -c .fly/node/fly.toml -C "bash -c '$register_cmd /register.sh /mnt/apps/$cartesi_app_name'" 2>&1); then
            error "App registration command failed on fly.io node"
            echo "$register_output"
            return 1
        fi
        
        # Show registration output and check for failure indicators
        echo "$register_output"
        if echo "$register_output" | grep -q -E "(Not registered|failed|failure|error|Error)"; then
            return 1
        fi
    fi
    
    # Cleanup
    rm -f /tmp/fly_transfers.txt
    
    echo
    info "Your application is now running on: https://$app_name.fly.dev"
}

# Main command dispatcher
main() {
    case ${1:-help} in
        setup)
            setup
            ;;
        start)
            shift
            start "$@"
            ;;
        stop)
            stop
            ;;
        deploy)
            shift
            deploy "$@"
            ;;
        send)
            shift
            send "$@"
            ;;
        deploy-node)
            shift
            deploy_node "$@"
            ;;
        deploy-app)
            shift
            deploy_app "$@"
            ;;
        help|--help|-h)
            help
            ;;
        *)
            error "Unknown command: $1"
            echo
            help
            exit 1
            ;;
    esac
}

# Run main function
main "$@" 