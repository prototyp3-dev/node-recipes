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
    echo "  3. Stop the development environment:"
    echo "     ./dev.sh stop"
    echo
    echo "For help: ./dev.sh help"
    echo "For status: ./dev.sh status"
    echo
}

# Setup node environment
setup_node() {
    log "Setting up Cartesi node environment..."
    
    # Pull required images
    docker pull ghcr.io/prototyp3-dev/test-node:2.0.0-alpha
    docker pull ghcr.io/prototyp3-dev/test-devnet:2.0.0
}

# Create default environment file
create_default_env() {
    local env_suffix=${1:-"localhost"}
    local env_file="${ENVFILE}.${env_suffix}"
    
    if [[ ! -f "$env_file" ]]; then
        log "Creating default environment file: $env_file"
        
        cat > "$env_file" << 'EOF'
# Cartesi Node Configuration for Local Development
CARTESI_LOG_LEVEL=info
CARTESI_BLOCKCHAIN_HTTP_ENDPOINT=http://devnet:8545
CARTESI_BLOCKCHAIN_WS_ENDPOINT=ws://devnet:8545
CARTESI_BLOCKCHAIN_ID=31337
CARTESI_AUTH_PRIVATE_KEY=ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Cartesi Contract Addresses (for localhost devnet)
CARTESI_CONTRACTS_INPUT_BOX_ADDRESS=0xc7007368E1b9929488744fa4dea7BcAEea000051
CARTESI_CONTRACTS_AUTHORITY_FACTORY_ADDRESS=0xC7003566dD09Aa0fC0Ce201aC2769aFAe3BF0051
CARTESI_CONTRACTS_APPLICATION_FACTORY_ADDRESS=0xc7000e3A627f91AFDE0ba7F79dbcB41bF1EA0051
CARTESI_CONTRACTS_SELF_HOSTED_APPLICATION_FACTORY_ADDRESS=0xC700bc767f8A21Dad91cB13CF1F629C257850051

# Sequencer Configuration (Default: Espresso)
MAIN_SEQUENCER=espresso
ESPRESSO_BASE_URL=http://espresso:10040
ESPRESSO_NAMESPACE=55555

# Features
CARTESI_FEATURE_GRAPHQL_ENABLED=true
CARTESI_FEATURE_RPC_ENABLED=true
EOF
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

# Start node environment
start_node() {
    local sequencer=${1:-"espresso"}
    local port=${2:-8080}
    
    # Update environment file for sequencer choice
    if [[ "$sequencer" == "ethereum" ]]; then
        log "Configuring for Ethereum sequencer..."
        # Update .env.localhost to use ethereum sequencer
        if grep -q "MAIN_SEQUENCER=espresso" .env.localhost 2>/dev/null; then
            sed -i.bak 's/MAIN_SEQUENCER=espresso/MAIN_SEQUENCER=ethereum/' .env.localhost
        fi
    else
        log "Configuring for Espresso sequencer..."
        # Update .env.localhost to use espresso sequencer
        if grep -q "MAIN_SEQUENCER=ethereum" .env.localhost 2>/dev/null; then
            sed -i.bak 's/MAIN_SEQUENCER=ethereum/MAIN_SEQUENCER=espresso/' .env.localhost
        fi
    fi
    
    # Start database and devnet
    ENVFILENAME=".env.localhost" make -f node.mk run-database-localhost
    ENVFILENAME=".env.localhost" make -f node.mk run-devnet-localhost
    
    if [[ "$sequencer" == "espresso" ]]; then
        log "Starting Espresso sequencer..."
        ENVFILENAME=".env.localhost" make -f node.mk run-espresso-localhost
    fi
    
    # Start node
    ENVFILENAME=".env.localhost" make -f node.mk run-node-localhost
    
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

# Create snapshot
create_snapshot() {
    log "Creating Cartesi snapshot..."
    
    if command -v cartesi &> /dev/null; then
        log "Using Cartesi CLI to build snapshot..."
        cartesi build
    else
        warn "Cartesi CLI not found. Installing locally..."
        if command -v npm &> /dev/null; then
            npm install @cartesi/cli@2.0.0-alpha.2
            npx cartesi build
        else
            error "npm not found. Please install Node.js and npm, or install Cartesi CLI manually"
            exit 1
        fi
    fi
    
    log "Snapshot created at $IMAGE_PATH"
}

# Show status
status() {
    log "Cartesi Node Environment Status"
    echo
    
    info "App Name: $APP_NAME"
    info "Image Path: $IMAGE_PATH"
    
    # Show sequencer configuration
    if [[ -f ".env.localhost" ]]; then
        local sequencer=$(grep "MAIN_SEQUENCER=" .env.localhost 2>/dev/null | cut -d'=' -f2)
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
    
    create-snapshot        Build Cartesi snapshot
    
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
        create-snapshot)
            create_snapshot
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