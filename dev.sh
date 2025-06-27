#!/bin/bash

# Cartesi Node Recipes - Unified Developer Script
# Simplifies all node operations into easy commands
# stashed changes

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME=${APP_NAME:-$(basename "$PWD")}
IMAGE_PATH=${IMAGE_PATH:-".cartesi/image"}
ENVFILE=".env"
REPO_URL="https://github.com/prototyp3-dev/node-recipes"
BRANCH="feature/v2-alpha"

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
        echo "  curl -fsSL https://raw.githubusercontent.com/prototyp3-dev/node-recipes/feature/v2-alpha/dev.sh -o dev.sh && chmod +x dev.sh && ./dev.sh setup"
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
    echo "For status: ./dev.sh status"
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
    # Now the env file has the correct sequencer
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
    
    # Check if services are running
    # TODO: Fix service detection - temporarily commented out
    # if ! ENVFILENAME=".env.localhost" docker compose -f node-compose.yml --env-file .env.localhost ps --services --filter "status=running" | grep -q "node"; then
    #     error "Node service is not running. Please start the environment first with: ./dev.sh start"
    #     exit 1
    # fi
    
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
    log "Note: This may take a few seconds to deploy all Cartesi rollups contracts..."
    
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

# Wait for services to be ready
wait_for_services() {
    local basic_only=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --basic)
                basic_only=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    if [[ "$basic_only" == "true" ]]; then
        log "Waiting for basic service connectivity..."
    else
        log "Waiting for services to be ready..."
    fi
    
    # Check if compose file exists
    if [[ ! -f "node-compose.yml" ]]; then
        error "node-compose.yml not found. Run setup first: ./dev.sh setup node"
        exit 1
    fi
    
    # Wait for devnet
    log "Checking devnet..."
    local retries=0
    local max_retries=30
    while [[ $retries -lt $max_retries ]]; do
        if curl -s -X POST -H "Content-Type: application/json" \
           --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
           http://localhost:8545 > /dev/null 2>&1; then
            log "✅ Devnet is ready"
            break
        fi
        sleep 2
        ((retries++))
        echo -n "."
    done
    echo
    
    if [[ $retries -eq $max_retries ]]; then
        error "Devnet not ready after $((max_retries * 2)) seconds"
        exit 1
    fi
    
    # Wait for node
    log "Checking node..."
    retries=0
    while [[ $retries -lt $max_retries ]]; do
        if [[ "$basic_only" == "true" ]]; then
            # Basic check - just see if something is listening on port 8080
            if curl -s http://localhost:8080/ > /dev/null 2>&1; then
                log "✅ Node is responding"
                break
            fi
        else
            # Try multiple endpoints that might be available
            if curl -s -f http://localhost:8080/healthz > /dev/null 2>&1 || \
               curl -s -f http://localhost:8080/health > /dev/null 2>&1 || \
               curl -s http://localhost:8080/ > /dev/null 2>&1; then
                log "✅ Node is ready"
                break
            fi
        fi
        sleep 2
        ((retries++))
        echo -n "."
    done
    echo
    
    if [[ $retries -eq $max_retries ]]; then
        error "Node not ready after $((max_retries * 2)) seconds"
        echo
        warn "Debug information:"
        echo "Trying to connect to node endpoints..."
        
        # Debug: Show what's actually responding
        if curl -s -I http://localhost:8080/ 2>/dev/null | head -1; then
            echo "✅ http://localhost:8080/ is responding"
        else
            echo "❌ http://localhost:8080/ is not responding"
        fi
        
        if curl -s -I http://localhost:8080/healthz 2>/dev/null | head -1; then
            echo "✅ http://localhost:8080/healthz is responding"
        else
            echo "❌ http://localhost:8080/healthz is not responding"
        fi
        
        if curl -s -I http://localhost:8080/health 2>/dev/null | head -1; then
            echo "✅ http://localhost:8080/health is responding"
        else
            echo "❌ http://localhost:8080/health is not responding"
        fi
        
        echo
        echo "You can check the node logs with: ./dev.sh logs node"
        exit 1
    fi
    
    log "🎉 All services are ready! You can now deploy your application."
}

# Show status
status() {
    log "Cartesi Node Environment Status"
    echo
    
    info "App Name: $APP_NAME"
    info "Image Path: $IMAGE_PATH"
    
    # Show sequencer configuration
    if [[ -f ".env.localhost" ]]; then
        local sequencer=$(grep "MAIN_SEQUENCER=" .env.localhost 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        info "Sequencer: ${sequencer:-unknown}"
    fi
    echo
    
    info "Running Containers:"
    docker ps --filter "name=cartesi-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || echo "None"
    echo
    
    if [[ -f "node-compose.yml" ]]; then
        info "Compose Services:"
        ENVFILENAME=".env.localhost" docker compose -f node-compose.yml --env-file .env.localhost ps 2>/dev/null || echo "Not running"
        echo
        
        # Check devnet connectivity
        info "Network Status:"
        if curl -s -X POST -H "Content-Type: application/json" \
           --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
           http://localhost:8545 > /dev/null 2>&1; then
            echo "  ✅ Devnet: Responding on http://localhost:8545"
        else
            echo "  ❌ Devnet: Not responding on http://localhost:8545"
        fi
        
        # Check node health
        if curl -s -f http://localhost:8080/healthz > /dev/null 2>&1; then
            echo "  ✅ Node: Healthy on http://localhost:8080/healthz"
        elif curl -s -f http://localhost:8080/health > /dev/null 2>&1; then
            echo "  ✅ Node: Healthy on http://localhost:8080/health"
        elif curl -s http://localhost:8080/ > /dev/null 2>&1; then
            echo "  ⚠️  Node: Responding on http://localhost:8080/ (health endpoint not available)"
        else
            echo "  ❌ Node: Not responding on http://localhost:8080"
        fi
    fi
}

# Show logs
logs() {
    local service=${1:-""}
    
    if [[ -n "$service" ]]; then
        ENVFILENAME=".env.localhost" docker compose -f node-compose.yml --env-file .env.localhost logs -f "$service" 2>/dev/null || docker logs -f "cartesi-$service" 2>/dev/null || error "Service not found: $service"
    else
        info "Available services:"
        docker ps --filter "name=cartesi-" --format "{{.Names}}" | sed 's/cartesi-//' || echo "None"
        echo
        echo "Usage: $0 logs [service-name]"
    fi
}

# Configuration management
config() {
    local action=${1:-"edit"}
    
    case $action in
        "edit")
            ${EDITOR:-nano} "${ENVFILE}.localhost"
            ;;
        "reset")
            rm -f "${ENVFILE}.localhost"
            create_default_env "localhost"
            log "Configuration reset to defaults"
            ;;
        *)
            echo "Usage: $0 config [edit|reset]"
            ;;
    esac
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
    
    deploy [options]       Deploy application
        --app-name NAME    Application name
        --image-path PATH  Snapshot location
    
    send                   Send transaction to Espresso
        -a, --app ADDRESS  App contract address (required)
        -d, --data DATA    Transaction data in hex (required)
        -k, --private-key  Private key for signing (required)
        Optional: -c chain-id (31337), -n node-url (localhost:8080)
    
    
    wait [--basic]         Wait for services to be ready
                           --basic: Only wait for basic connectivity
    status                 Show environment status
    logs [service]         Show logs for service
    config [edit|reset]    Manage configuration
    
    help                   Show this help

EXAMPLES:
    # First time setup
    curl -fsSL https://raw.githubusercontent.com/prototyp3-dev/node-recipes/feature/v2-alpha/dev.sh -o dev.sh && chmod +x dev.sh && ./dev.sh setup
    
    # Daily usage
    ./dev.sh start                     # Start with Espresso sequencer (default)
    ./dev.sh start ethereum            # Start with Ethereum sequencer
    ./dev.sh deploy                    # Deploy current application
    ./dev.sh send -a 0x1234... -d 0x48656c6c6f -k your_key  # Send transaction
    ./dev.sh logs node                 # Show node logs
    ./dev.sh stop                      # Stop everything

EOF
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
        wait)
            shift
            wait_for_services "$@"
            ;;
        status)
            status
            ;;
        logs)
            shift
            logs "$@"
            ;;
        config)
            shift
            config "$@"
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