#!/bin/bash

# Master bootstrap script - sets up entire environment with one command
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create logs directory first
mkdir -p logs
BOOTSTRAP_LOG="${SCRIPT_DIR}/logs/bootstrap-$(date +%Y%m%d_%H%M%S).log"

# Logging functions
log_step() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[${timestamp}]${NC} ${message}"
    echo "[${timestamp}] ${message}" >> "$BOOTSTRAP_LOG"
}

log_success() {
    local message="$1"
    echo -e "${GREEN}✅ ${message}${NC}"
    echo "SUCCESS: ${message}" >> "$BOOTSTRAP_LOG"
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}⚠️  ${message}${NC}"
    echo "WARNING: ${message}" >> "$BOOTSTRAP_LOG"
}

log_error() {
    local message="$1"
    echo -e "${RED}❌ ${message}${NC}"
    echo "ERROR: ${message}" >> "$BOOTSTRAP_LOG"
}

# Step 1: Environment Configuration Setup
setup_environment_config() {
    log_step "Setting up environment configuration..."
    
    if [ ! -f ".env" ]; then
        if [ -f ".env.template" ]; then
            cp .env.template .env
            log_warning "Created .env from template. PLEASE EDIT .env with your actual Solace broker details!"
            echo ""
            echo "Required changes in .env:"
            echo "  - SOLACE_BROKER_HOST (your broker hostname)"
            echo "  - SOLACE_ADMIN_PASSWORD (your admin password)"
            echo "  - User passwords if different from defaults"
            echo ""
            read -p "Press Enter after you've edited .env file..."
        else
            log_error ".env.template not found!"
            return 1
        fi
    else
        log_success "Found existing .env file"
    fi
    
    # Load and validate environment
    if ! source .env; then
        log_error "Failed to load .env file"
        return 1
    fi
    
    # Validate critical variables
    local required_vars=(
        "SOLACE_BROKER_HOST"
        "SOLACE_ADMIN_USER"
        "SOLACE_ADMIN_PASSWORD"
        "CHAOS_GENERATOR_USER"
        "SDKPERF_TOOLS_DIR"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            log_error "Required environment variable $var is not set in .env"
            return 1
        fi
    done
    
    log_success "Environment configuration validated"
    return 0
}

# Step 2: SDKPerf Tool Setup
setup_sdkperf() {
    log_step "Setting up SDKPerf tools..."
    
    # Check if SDKPerf script already exists
    if [ -f "${SDKPERF_SCRIPT_PATH}" ]; then
        log_success "SDKPerf already installed at ${SDKPERF_SCRIPT_PATH}"
        return 0
    fi
    
    # Look for ZIP files in sdkperf-tools directory
    local zip_files=($(find "${SDKPERF_TOOLS_DIR}" -maxdepth 1 -name "*.zip" -type f))
    
    if [ ${#zip_files[@]} -eq 0 ]; then
        log_error "No SDKPerf ZIP files found in ${SDKPERF_TOOLS_DIR}/"
        log_error "Please download SDKPerf and place the ZIP file in ${SDKPERF_TOOLS_DIR}/"
        log_error "Visit: https://docs.solace.com/API/SDKPerf/Command-Line-Options.htm"
        return 1
    elif [ ${#zip_files[@]} -gt 1 ]; then
        log_warning "Multiple ZIP files found in ${SDKPERF_TOOLS_DIR}/:"
        for zip_file in "${zip_files[@]}"; do
            log_warning "  - $(basename "$zip_file")"
        done
        log_step "Using first ZIP file: $(basename "${zip_files[0]}")"
    fi
    
    local selected_zip="${zip_files[0]}"
    log_step "Extracting SDKPerf from $(basename "$selected_zip")..."
    
    # Create extraction directory
    mkdir -p "${SDKPERF_EXTRACT_DIR}"
    
    # Extract SDKPerf
    if unzip -o -q "$selected_zip" -d "${SDKPERF_EXTRACT_DIR}"; then
        # Find the actual sdkperf_java.sh script
        local script_path=$(find "${SDKPERF_EXTRACT_DIR}" -name "sdkperf_java.sh" -type f | head -1)
        
        if [ -n "$script_path" ]; then
            # Update .env with actual path
            sed -i.bak "s|SDKPERF_SCRIPT_PATH=.*|SDKPERF_SCRIPT_PATH=${script_path}|" .env
            # Reload .env
            source .env
            log_success "SDKPerf extracted and configured at ${script_path}"
        else
            log_error "Could not find sdkperf_java.sh in extracted archive"
            log_error "Please ensure you downloaded the correct SDKPerf Java version"
            return 1
        fi
    else
        log_error "Failed to extract SDKPerf archive: $(basename "$selected_zip")"
        return 1
    fi
    
    return 0
}

# Step 3: Project Structure Setup
setup_project_structure() {
    log_step "Creating project directory structure..."
    
    # Create all necessary directories
    local directories=(
        "logs"
        "scripts"
        "traffic-generators"
        "error-generators"
        "terraform/environments/base"
        "terraform/modules/vpn"
        "terraform/modules/queue"
        "terraform/modules/user"
        "terraform/modules/bridge"
    )
    
    for dir in "${directories[@]}"; do
        mkdir -p "$dir"
    done
    
    log_success "Project structure created"
    return 0
}

# Step 4: Terraform Installation and Setup
install_terraform_if_needed() {
    log_step "Checking Terraform installation..."
    
    if command -v terraform &> /dev/null; then
        local tf_version=$(terraform version -json 2>/dev/null | grep '"version"' | cut -d'"' -f4 | head -1)
        log_success "Terraform already installed: version ${tf_version:-"unknown"}"
        return 0
    fi
    
    log_step "Terraform not found - installing automatically..."
    
    # Detect OS
    local os_type=""
    case "$(uname -s)" in
        Darwin) os_type="darwin" ;;
        Linux)  os_type="linux" ;;
        *) 
            log_error "Unsupported OS: $(uname -s). Please install Terraform manually from https://terraform.io"
            return 1
            ;;
    esac
    
    # Detect architecture
    local arch_type=""
    case "$(uname -m)" in
        x86_64) arch_type="amd64" ;;
        arm64)  arch_type="arm64" ;;
        aarch64) arch_type="arm64" ;;
        *)
            log_error "Unsupported architecture: $(uname -m). Please install Terraform manually."
            return 1
            ;;
    esac
    
    # Download and install Terraform
    local tf_version="1.6.6"  # Latest stable as of Feb 2026
    local tf_zip="terraform_${tf_version}_${os_type}_${arch_type}.zip"
    local tf_url="https://releases.hashicorp.com/terraform/${tf_version}/${tf_zip}"
    local tf_dir="${HOME}/.local/bin"
    
    log_step "Downloading Terraform ${tf_version} for ${os_type}_${arch_type}..."
    
    # Create local bin directory
    mkdir -p "$tf_dir"
    
    # Download Terraform
    if command -v curl &> /dev/null; then
        curl -sL "$tf_url" -o "/tmp/${tf_zip}"
    elif command -v wget &> /dev/null; then
        wget -q "$tf_url" -O "/tmp/${tf_zip}"
    else
        log_error "Neither curl nor wget found. Cannot download Terraform."
        log_error "Please install Terraform manually from https://terraform.io"
        return 1
    fi
    
    # Extract and install
    if command -v unzip &> /dev/null; then
        unzip -q "/tmp/${tf_zip}" -d "$tf_dir"
        chmod +x "${tf_dir}/terraform"
        rm "/tmp/${tf_zip}"
    else
        log_error "unzip not found. Cannot extract Terraform."
        return 1
    fi
    
    # Update PATH for current session
    export PATH="${tf_dir}:${PATH}"
    
    # Check if installation was successful
    if command -v terraform &> /dev/null; then
        local installed_version=$(terraform version -json 2>/dev/null | grep '"version"' | cut -d'"' -f4 | head -1)
        log_success "Terraform ${installed_version} installed successfully to ${tf_dir}"
        log_step "Note: Add ${tf_dir} to your PATH in ~/.zshrc or ~/.bash_profile for permanent access"
    else
        log_error "Terraform installation failed"
        return 1
    fi
    
    return 0
}

# Step 5: Terraform Infrastructure Setup
setup_terraform() {
    log_step "Setting up Terraform infrastructure..."
    
    # Install Terraform if needed
    if ! install_terraform_if_needed; then
        return 1
    fi
    
    cd terraform/environments/base || return 1
    
    # Initialize Terraform (safe to run multiple times)
    if terraform init; then
        log_success "Terraform initialized"
    else
        log_error "Terraform initialization failed"
        cd - > /dev/null
        return 1
    fi
    
    # Generate terraform.tfvars from environment variables
    log_step "Generating Terraform variables..."
    cat > terraform.tfvars <<EOF
# Auto-generated from .env - Multi-VPN Configuration
# Generated on: $(date)

solace_broker_url = "${SOLACE_SEMP_URL}"
solace_admin_user = "${SOLACE_ADMIN_USER}"
solace_admin_password = "${SOLACE_ADMIN_PASSWORD}"

# VPN Configuration
vpns = {
  "market_data" = {
    name = "${MARKET_DATA_VPN}"
    max_connections = 50
    max_subscriptions = 10000
  }
  "trading" = {
    name = "${TRADING_VPN}"
    max_connections = 100
    max_subscriptions = 5000
  }
  "integration" = {
    name = "${INTEGRATION_VPN}"
    max_connections = 25
    max_subscriptions = 2000
  }
}

# Queue Configuration by VPN
queues = {
  "equity_order_queue" = {
    vpn = "${TRADING_VPN}"
    quota = 2
    topic_subscriptions = ["trading/orders/equity/>"]
  }
  "options_order_queue" = {
    vpn = "${TRADING_VPN}"
    quota = 1
    topic_subscriptions = ["trading/orders/options/>"]
  }
  "settlement_queue" = {
    vpn = "${TRADING_VPN}"
    quota = 3
    topic_subscriptions = ["trading/settlement/>"]
  }
  "baseline_queue" = {
    vpn = "${TRADING_VPN}"
    quota = 5
    topic_subscriptions = ["trading/baseline/>"]
  }
  "cross_market_data_queue" = {
    vpn = "${INTEGRATION_VPN}"
    quota = 4
    topic_subscriptions = ["market-data/bridge-stress/>"]
  }
  "risk_calculation_queue" = {
    vpn = "${INTEGRATION_VPN}"
    quota = 5
    topic_subscriptions = ["trading/risk/>"]
  }
}

# User Configuration by VPN
vpn_users = {
  "market_data_feed" = {
    vpn = "${MARKET_DATA_VPN}"
    username = "$(echo ${MARKET_DATA_FEED_USER} | cut -d'@' -f1)"
    password = "${MARKET_DATA_FEED_PASSWORD}"
    acl_profile = "market_data_publisher"
  }
  "market_data_consumer" = {
    vpn = "${MARKET_DATA_VPN}"
    username = "$(echo ${MARKET_DATA_CONSUMER_USER} | cut -d'@' -f1)"
    password = "${MARKET_DATA_CONSUMER_PASSWORD}"
    acl_profile = "market_data_subscriber"
  }
  "restricted_market" = {
    vpn = "${MARKET_DATA_VPN}"
    username = "$(echo ${RESTRICTED_MARKET_USER} | cut -d'@' -f1)"
    password = "${RESTRICTED_MARKET_PASSWORD}"
    acl_profile = "restricted_market_access"
  }
  "order_router" = {
    vpn = "${TRADING_VPN}"
    username = "$(echo ${ORDER_ROUTER_USER} | cut -d'@' -f1)"
    password = "${ORDER_ROUTER_PASSWORD}"
    acl_profile = "trade_processor"
  }
  "chaos_generator" = {
    vpn = "${TRADING_VPN}"
    username = "$(echo ${CHAOS_GENERATOR_USER} | cut -d'@' -f1)"
    password = "${CHAOS_GENERATOR_PASSWORD}"
    acl_profile = "chaos_testing"
  }
  "restricted_trade" = {
    vpn = "${TRADING_VPN}"
    username = "$(echo ${RESTRICTED_TRADE_USER} | cut -d'@' -f1)"
    password = "${RESTRICTED_TRADE_PASSWORD}"
    acl_profile = "restricted_trade_access"
  }
  "risk_calculator" = {
    vpn = "${INTEGRATION_VPN}"
    username = "$(echo ${RISK_CALCULATOR_USER} | cut -d'@' -f1)"
    password = "${RISK_CALCULATOR_PASSWORD}"
    acl_profile = "risk_management"
  }
  "integration_user" = {
    vpn = "${INTEGRATION_VPN}"
    username = "$(echo ${INTEGRATION_USER} | cut -d'@' -f1)"
    password = "${INTEGRATION_PASSWORD}"
    acl_profile = "integration_service"
  }
}

# Bridge Configuration
enable_cross_vpn_bridge = ${ENABLE_CROSS_VPN_BRIDGE}
bridges = {
  "market_to_integration" = {
    source_vpn = "${MARKET_DATA_VPN}"
    target_vpn = "${INTEGRATION_VPN}"
    topics = ["market-data/bridge-stress/>"]
  }
}
EOF
    
    log_success "Terraform variables generated"
    
    # Validate configuration
    if terraform validate; then
        log_success "Terraform configuration validated"
    else
        log_error "Terraform configuration validation failed"
        cd - > /dev/null
        return 1
    fi
    
    cd - > /dev/null
    return 0
}

# Step 6: Infrastructure Deployment
deploy_infrastructure() {
    log_step "Deploying Solace infrastructure..."
    
    cd terraform/environments/base || return 1
    
    # Plan the deployment
    log_step "Planning infrastructure deployment..."
    if terraform plan -out=tfplan; then
        log_success "Terraform plan generated"
    else
        log_error "Terraform planning failed"
        cd - > /dev/null
        return 1
    fi
    
    # Apply the deployment
    if [ "${TERRAFORM_AUTO_APPROVE}" = "true" ]; then
        log_step "Applying infrastructure changes..."
        if terraform apply tfplan; then
            log_success "Infrastructure deployed successfully"
        else
            log_error "Infrastructure deployment failed"
            cd - > /dev/null
            return 1
        fi
    else
        echo ""
        echo "Ready to deploy infrastructure. Run the following to proceed:"
        echo "  cd terraform/environments/base"
        echo "  terraform apply tfplan"
        echo ""
    fi
    
    cd - > /dev/null
    return 0
}

# Step 7: Connectivity Validation
validate_connectivity() {
    log_step "Validating connectivity to Solace broker..."
    
    # Test basic connectivity using curl
    if curl -s --max-time 10 "${SOLACE_SEMP_URL}/SEMP/v2/monitor" >/dev/null; then
        log_success "SEMP API connectivity confirmed"
    else
        log_warning "SEMP API not accessible - check broker URL and credentials"
    fi
    
    # Test SDKPerf connectivity (quick test)
    log_step "Testing SDKPerf connectivity..."
    timeout 30s "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${CHAOS_GENERATOR_USER}" \
        -cp="${CHAOS_GENERATOR_PASSWORD}" \
        -ptl="bootstrap/test" \
        -mr=1 -mn=5 >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_success "SDKPerf connectivity confirmed"
    else
        log_warning "SDKPerf connectivity test failed - check credentials"
    fi
    
    return 0
}

# Step 8: Generate Scripts
generate_scripts() {
    log_step "Generating traffic and error generator scripts..."
    
    create_traffic_generators
    create_error_generators
    create_master_orchestrator
    create_utility_scripts
    
    log_success "All scripts generated and ready to use"
    return 0
}

# Function to create traffic generators
create_traffic_generators() {
    # Baseline market data generator
    cat > traffic-generators/baseline-market-data.sh <<'EOF'
#!/bin/bash
source scripts/load-env.sh

get_weekend_rate() {
    local day_of_week=$(date +%u)
    if [ $day_of_week -eq 6 ] || [ $day_of_week -eq 7 ]; then
        echo "${WEEKEND_MARKET_DATA_RATE}"
    else
        echo "${WEEKDAY_MARKET_DATA_RATE}"
    fi
}

while true; do
    CURRENT_RATE=$(get_weekend_rate)
    echo "$(date): Starting baseline market data feed - rate: ${CURRENT_RATE} msgs/sec"
    
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${MARKET_DATA_FEED_USER}" \
        -cp="${MARKET_DATA_FEED_PASSWORD}" \
        -ptl="market-data/baseline/heartbeat" \
        -mr="${CURRENT_RATE}" \
        -mn=3600 \
        -msa=256 2>&1 | tee -a logs/baseline-market.log
        
    echo "$(date): Baseline market data cycle completed - restarting in 30 seconds"
    sleep 30
done
EOF

    # Baseline trade flow generator
    cat > traffic-generators/baseline-trade-flow.sh <<'EOF'
#!/bin/bash
source scripts/load-env.sh

get_weekend_rate() {
    local day_of_week=$(date +%u)
    if [ $day_of_week -eq 6 ] || [ $day_of_week -eq 7 ]; then
        echo "${WEEKEND_TRADE_FLOW_RATE}"
    else
        echo "${WEEKDAY_TRADE_FLOW_RATE}"
    fi
}

while true; do
    CURRENT_RATE=$(get_weekend_rate)
    echo "$(date): Starting baseline trade flow - rate: ${CURRENT_RATE} msgs/sec"
    
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${ORDER_ROUTER_USER}" \
        -cp="${ORDER_ROUTER_PASSWORD}" \
        -ptl="trading/baseline/heartbeat" \
        -mt=persistent \
        -mr="${CURRENT_RATE}" \
        -mn=3600 \
        -msa=512 2>&1 | tee -a logs/baseline-trade.log
        
    echo "$(date): Baseline trade flow cycle completed - restarting in 30 seconds"
    sleep 30
done
EOF

    chmod +x traffic-generators/*.sh
}

# Function to create error generators
create_error_generators() {
    # Queue killer
    cat > error-generators/queue-killer.sh <<'EOF'
#!/bin/bash
source scripts/load-env.sh

while true; do
    echo "$(date): Starting queue killer attack on equity-order-queue"
    
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${CHAOS_GENERATOR_USER}" \
        -cp="${CHAOS_GENERATOR_PASSWORD}" \
        -ptl="trading/orders/equity/NYSE/new" \
        -mt=persistent \
        -mr=1000 \
        -mn=100000 \
        -msa=5000 2>&1 | tee -a logs/queue-killer.log
        
    echo "$(date): Queue killer stopped (queue probably full!) - waiting 120 seconds"
    sleep 120
done
EOF

    # Multi-VPN ACL violator
    cat > error-generators/multi-vpn-acl-violator.sh <<'EOF'
#!/bin/bash
source scripts/load-env.sh

while true; do
    echo "$(date): Testing ACL violations across all VPNs"
    
    # Try to access premium market data with restricted user
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${RESTRICTED_MARKET_USER}" \
        -cp="${RESTRICTED_MARKET_PASSWORD}" \
        -ptl="market-data/premium/level3/NYSE/AAPL" \
        -mr=5 -mn=50 -msa=256 2>&1 | tee -a logs/acl-violator.log &
    
    # Try to access admin trading functions with restricted user
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${RESTRICTED_TRADE_USER}" \
        -cp="${RESTRICTED_TRADE_PASSWORD}" \
        -ptl="trading/admin/cancel-all-orders" \
        -mr=5 -mn=50 -msa=256 2>&1 | tee -a logs/acl-violator.log &
    
    # Try cross-VPN access without proper permissions
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${RESTRICTED_MARKET_USER}" \
        -cp="${RESTRICTED_MARKET_PASSWORD}" \
        -ptl="trading/orders/equity/NYSE/new" \
        -mr=5 -mn=50 -msa=256 2>&1 | tee -a logs/acl-violator.log &
    
    wait
    echo "$(date): Multi-VPN ACL violation tests completed - waiting 90 seconds"
    sleep 90
done
EOF

    # Market data connection bomber
    cat > error-generators/market-data-connection-bomber.sh <<'EOF'
#!/bin/bash
source scripts/load-env.sh

while true; do
    echo "$(date): Bombing default VPN with connections"
    
    # Start 25 market data consumers to hit connection limits
    for i in {1..25}; do
        bash "${SDKPERF_SCRIPT_PATH}" \
            -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
            -cu="${MARKET_DATA_CONSUMER_USER}" \
            -cp="${MARKET_DATA_CONSUMER_PASSWORD}" \
            -stl="market-data/equities/NYSE/+/quotes" \
            -mr=1 -mn=1000 2>&1 | tee -a logs/connection-bomber.log &
    done
    
    wait
    echo "$(date): Market data connection bombing completed - waiting 300 seconds"
    sleep 300
done
EOF

    # Cross-VPN bridge stress tester
    cat > error-generators/cross-vpn-bridge-killer.sh <<'EOF'
#!/bin/bash
source scripts/load-env.sh

while true; do
    echo "$(date): Starting cross-VPN bridge stress test"
    
    # Heavy publisher on default VPN
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${MARKET_DATA_FEED_USER}" \
        -cp="${MARKET_DATA_FEED_PASSWORD}" \
        -ptl="market-data/bridge-stress/equities/NYSE/AAPL/L1" \
        -mr=5000 -mn=50000 -msa=2048 2>&1 | tee -a logs/bridge-killer.log &
    
    PUB_PID=$!
    
    # Multiple consumers on default VPN (simplified - no bridge needed)
    for i in {1..5}; do
        bash "${SDKPERF_SCRIPT_PATH}" \
            -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
            -cu="${RISK_CALCULATOR_USER}" \
            -cp="${RISK_CALCULATOR_PASSWORD}" \
            -stl="market-data/bridge-stress/equities/NYSE/AAPL/L1" \
            -sql=cross-market-data-queue \
            -pe -md 2>&1 | tee -a logs/bridge-killer.log &
    done
    
    # Let it run for 10 minutes then kill
    sleep 600
    kill $PUB_PID 2>/dev/null
    pkill -f "bridge-stress" 2>/dev/null
    
    echo "$(date): Bridge stress test completed - waiting 300 seconds"
    sleep 300
done
EOF

    chmod +x error-generators/*.sh
}

# Function to create master orchestrator
create_master_orchestrator() {
    cat > master-chaos.sh <<'EOF'
#!/bin/bash

# Master chaos orchestrator - runs all components with health monitoring
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables
source scripts/load-env.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

MASTER_LOG="logs/master-chaos-$(date +%Y%m%d_%H%M%S).log"
HEALTH_CHECK_INTERVAL=300  # 5 minutes

# Components to manage
TRAFFIC_GENERATORS=(
    "traffic-generators/baseline-market-data.sh"
    "traffic-generators/baseline-trade-flow.sh"
)

ERROR_GENERATORS=(
    "error-generators/queue-killer.sh"
    "error-generators/multi-vpn-acl-violator.sh"
    "error-generators/market-data-connection-bomber.sh"
    "error-generators/cross-vpn-bridge-killer.sh"
)

# Component management
declare -A COMPONENT_PIDS
declare -A COMPONENT_START_TIMES

log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[${timestamp}]${NC} ${message}"
    echo "[${timestamp}] ${message}" >> "$MASTER_LOG"
}

log_success() {
    local message="$1"
    echo -e "${GREEN}✅ ${message}${NC}"
    echo "SUCCESS: ${message}" >> "$MASTER_LOG"
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}⚠️  ${message}${NC}"
    echo "WARNING: ${message}" >> "$MASTER_LOG"
}

log_error() {
    local message="$1"
    echo -e "${RED}❌ ${message}${NC}"
    echo "ERROR: ${message}" >> "$MASTER_LOG"
}

start_component() {
    local component="$1"
    local component_name=$(basename "$component" .sh)
    
    if [[ -n "${COMPONENT_PIDS[$component]}" ]] && kill -0 "${COMPONENT_PIDS[$component]}" 2>/dev/null; then
        return 0
    fi
    
    log_message "Starting component: $component_name"
    
    "./$component" &
    local pid=$!
    COMPONENT_PIDS[$component]=$pid
    COMPONENT_START_TIMES[$component]=$(date +%s)
    
    log_success "Started $component_name (PID: $pid)"
}

check_component_health() {
    local component="$1"
    local component_name=$(basename "$component" .sh)
    local pid="${COMPONENT_PIDS[$component]}"
    
    if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
        log_warning "Component $component_name is not running - restarting"
        start_component "$component"
        return 1
    fi
    
    return 0
}

cleanup_and_exit() {
    local signal=$1
    log_message "Received signal $signal - shutting down gracefully"
    
    for component in "${!COMPONENT_PIDS[@]}"; do
        local pid="${COMPONENT_PIDS[$component]}"
        local component_name=$(basename "$component" .sh)
        
        if kill -0 "$pid" 2>/dev/null; then
            log_message "Stopping $component_name (PID: $pid)"
            kill -TERM "$pid"
            sleep 2
            kill -KILL "$pid" 2>/dev/null
        fi
    done
    
    log_message "Master chaos orchestrator shutdown completed"
    exit 0
}

# Signal handlers
trap 'cleanup_and_exit SIGTERM' SIGTERM
trap 'cleanup_and_exit SIGINT' SIGINT
trap 'cleanup_and_exit SIGHUP' SIGHUP

# Main orchestration loop
main_orchestrator_loop() {
    local loop_counter=0
    local last_health_check=0
    
    log_message "Starting master chaos orchestrator"
    log_message "Broker: ${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}"
    
    # Start all components
    for component in "${TRAFFIC_GENERATORS[@]}" "${ERROR_GENERATORS[@]}"; do
        start_component "$component"
        sleep 2
    done
    
    log_success "All components started - entering monitoring loop"
    echo ""
    echo "Master orchestrator running. Press Ctrl+C to stop."
    
    while true; do
        current_time=$(date +%s)
        loop_counter=$((loop_counter + 1))
        
        # Health check cycle
        if (( current_time - last_health_check >= HEALTH_CHECK_INTERVAL )); then
            log_message "Health check cycle $loop_counter"
            
            for component in "${TRAFFIC_GENERATORS[@]}" "${ERROR_GENERATORS[@]}"; do
                check_component_health "$component"
            done
            
            last_health_check=$current_time
        fi
        
        # Heartbeat every hour
        if (( loop_counter % 120 == 0 )); then
            log_message "Orchestrator heartbeat - loop $loop_counter, components: ${#COMPONENT_PIDS[@]} managed"
        fi
        
        sleep 30
    done
}

# Main execution
main() {
    echo ""
    echo "🚀 Solace Chaos Testing Master Orchestrator"
    echo "==========================================="
    echo ""
    
    # Validate environment
    if [ ! -f "scripts/load-env.sh" ]; then
        echo "❌ Environment script not found. Run bootstrap-chaos-environment.sh first."
        exit 1
    fi
    
    # Start orchestration
    main_orchestrator_loop
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
EOF

    chmod +x master-chaos.sh
}

# Function to create utility scripts
create_utility_scripts() {
    # Environment loading script
    cat > scripts/load-env.sh <<'EOF'
#!/bin/bash

# Load environment variables from .env file
ENV_FILE="$(dirname $0)/../.env"

if [ -f "$ENV_FILE" ]; then
    export $(cat "$ENV_FILE" | grep -v '^#' | xargs)
else
    echo "ERROR: .env file not found at $ENV_FILE"
    echo "Please run bootstrap-chaos-environment.sh first"
    exit 1
fi

# Validate critical variables are set
REQUIRED_VARS=(
    "SOLACE_BROKER_HOST"
    "SOLACE_BROKER_PORT"
    "SDKPERF_SCRIPT_PATH"
    "CHAOS_GENERATOR_USER"
    "CHAOS_GENERATOR_PASSWORD"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "ERROR: Required environment variable $var is not set"
        exit 1
    fi
done
EOF

    # Status check script
    cat > scripts/status-check.sh <<'EOF'
#!/bin/bash

source scripts/load-env.sh

echo "🔍 Solace Chaos Environment Status"
echo "=================================="
echo ""

# Check if master orchestrator is running
if pgrep -f "master-chaos.sh" > /dev/null; then
    echo "✅ Master orchestrator: RUNNING"
else
    echo "❌ Master orchestrator: STOPPED"
fi

echo ""
echo "Component Status:"
echo "----------------"

components=(
    "baseline-market-data.sh"
    "baseline-trade-flow.sh"
    "queue-killer.sh"
    "multi-vpn-acl-violator.sh"
    "market-data-connection-bomber.sh"
    "cross-vpn-bridge-killer.sh"
)

for component in "${components[@]}"; do
    if pgrep -f "$component" > /dev/null; then
        echo "✅ $component: RUNNING"
    else
        echo "❌ $component: STOPPED"
    fi
done

echo ""
echo "Recent Log Activity:"
echo "-------------------"

for log in logs/*.log; do
    if [ -f "$log" ]; then
        echo "📄 $(basename $log): $(tail -1 $log 2>/dev/null | cut -c1-60)..."
    fi
done
EOF

    chmod +x scripts/*.sh
}

# Main execution function
main() {
    echo ""
    echo "🚀 Solace Chaos Testing Environment Bootstrap"
    echo "============================================="
    echo ""
    
    # Execute all setup steps
    if ! setup_environment_config; then
        log_error "Environment setup failed"
        exit 1
    fi
    
    if ! setup_sdkperf; then
        log_error "SDKPerf setup failed"
        exit 1
    fi
    
    if ! setup_project_structure; then
        log_error "Project structure setup failed"
        exit 1
    fi
    
    if ! setup_terraform; then
        log_error "Terraform setup failed"
        exit 1
    fi
    
    if [ "${SETUP_VPNS}" = "true" ]; then
        if ! deploy_infrastructure; then
            log_error "Infrastructure deployment failed"
            exit 1
        fi
    fi
    
    if [ "${VALIDATE_CONNECTIVITY}" = "true" ]; then
        validate_connectivity
    fi
    
    if ! generate_scripts; then
        log_error "Script generation failed"
        exit 1
    fi
    
    echo ""
    echo "🎉 Bootstrap completed successfully!"
    echo "=================================="
    echo ""
    echo "Next steps:"
    echo "  1. Review the setup log: ${BOOTSTRAP_LOG}"
    echo "  2. Start the chaos testing: ./master-chaos.sh"
    echo "  3. Check status anytime: ./scripts/status-check.sh"
    echo ""
    echo "The environment is ready for long-term chaos testing!"
    echo ""
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi