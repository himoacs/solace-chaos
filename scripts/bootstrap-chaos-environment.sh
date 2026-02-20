#!/bin/bash

# Master bootstrap script - sets up entire environment with one command
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Change to project root to ensure correct directory structure
cd "$PROJECT_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create logs directory first
mkdir -p scripts/logs
BOOTSTRAP_LOG="$PROJECT_ROOT/scripts/logs/bootstrap-$(date +%Y%m%d_%H%M%S).log"

# Function to clean up old log files (older than 24 hours)
cleanup_old_logs() {
    echo "$(date): 🧹 Cleaning up log files older than 24 hours..." | tee -a "$BOOTSTRAP_LOG"
    
    # Clean main logs directory (files older than 1440 minutes = 24 hours)
    local cleaned=0
    cleaned=$(find "logs" -name "*.log" -type f -mmin +1440 -print -exec rm -f {} \; 2>/dev/null | wc -l)
    
    # Clean scripts/logs directory  
    local scripts_cleaned=0
    scripts_cleaned=$(find "scripts/logs" -name "*.log" -type f -mmin +1440 -print -exec rm -f {} \; 2>/dev/null | wc -l)
    scripts_cleaned=$((scripts_cleaned + $(find "scripts/logs" -name "*.start" -type f -mmin +1440 -print -exec rm -f {} \; 2>/dev/null | wc -l)))
    
    # Clean old log backups (older than 7 days)
    local backups_cleaned=0
    backups_cleaned=$(find "scripts/log-backups" -type d -mtime +7 -print -exec rm -rf {} \; 2>/dev/null | wc -l)
    
    echo "$(date): ✅ Bootstrap log cleanup completed: $cleaned main logs, $scripts_cleaned script logs, $backups_cleaned old backups" | tee -a "$BOOTSTRAP_LOG"
}

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
        "scripts/logs"
        "traffic-generators"
        "error-generators"
        "terraform/environments/base"
        "terraform/environments/software"
        "terraform/environments/appliance"
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
    
    # Determine broker type (detected or manual)
    local broker_type="${DETECTED_BROKER_TYPE:-software}"
    local terraform_dir="terraform/environments/${broker_type}"
    
    log_step "Detected broker type: ${broker_type}"
    log_step "Using Terraform config: ${terraform_dir}"
    
    cd "${terraform_dir}" || return 1
    
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

# VPN Configuration (2-VPN Standard Edition)
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
}

# Queue Configuration by VPN (Quotas in MB for long-term operation)
queues = {
  "equity_order_queue" = {
    vpn = "${TRADING_VPN}"
    quota = 50
    topic_subscriptions = ["trading/orders/equities/>"]
  }
  "baseline_queue" = {
    vpn = "${TRADING_VPN}"
    quota = 80
    topic_subscriptions = ["trading/orders/>"]
  }
  "bridge_receive_queue" = {
    vpn = "${TRADING_VPN}"
    quota = 120
    topic_subscriptions = ["market-data/bridge-stress/>"]
  }
  "cross_market_data_queue" = {
    vpn = "${MARKET_DATA_VPN}"
    quota = 150
    topic_subscriptions = ["market-data/bridge-stress/>"]
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
  "integration_user" = {
    vpn = "${MARKET_DATA_VPN}"
    username = "$(echo ${INTEGRATION_USER} | cut -d'@' -f1)"
    password = "${INTEGRATION_PASSWORD}"
    acl_profile = "integration_service"
  }
}

# Bridge Configuration
enable_cross_vpn_bridge = ${ENABLE_CROSS_VPN_BRIDGE}
bridge_username = "admin"
bridge_password = "admin"
bridges = {}
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
    
    # Determine broker type for deployment
    local broker_type="${DETECTED_BROKER_TYPE:-software}"
    local terraform_dir="terraform/environments/${broker_type}"
    
    cd "${terraform_dir}" || return 1
    
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
        echo "  cd terraform/environments/${broker_type:-software}"
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
        -ptl="bootstrap/connectivity-test" \
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

# Cleanup function for graceful shutdown
cleanup_baseline_market() {
    echo "$(date): Baseline market data shutting down - cleaning up processes"
    cleanup_sdkperf_processes "market-data/equities/quotes"
    exit 0
}

# Set up signal handlers
trap cleanup_baseline_market SIGTERM SIGINT

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
    
    # Publish to multiple securities across different exchanges
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${MARKET_DATA_FEED_USER}" \
        -cp="${MARKET_DATA_FEED_PASSWORD}" \
        -ptl="market-data/equities/quotes/NYSE/AAPL,market-data/equities/quotes/NASDAQ/MSFT,market-data/equities/quotes/LSE/GOOGL" \
        -stl="market-data/equities/quotes/>" \
        -mr="${CURRENT_RATE}" \
        -mn=999999999 \
        -msa=256 >> logs/baseline-market.log 2>&1 &
        
    # Let it run for 1 hour then restart for rate adjustments
    sleep 3600
    pkill -f "market-data/equities/quotes" 2>/dev/null
    
    echo "$(date): Baseline market data cycle completed - restarting for rate check"
done
EOF

    # Baseline trade flow generator
    cat > traffic-generators/baseline-trade-flow.sh <<'EOF'
#!/bin/bash
source scripts/load-env.sh

# Cleanup function for graceful shutdown
cleanup_baseline_trade() {
    echo "$(date): Baseline trade flow shutting down - cleaning up processes"
    cleanup_sdkperf_processes "trading/orders/equities"
    cleanup_sdkperf_processes "equity_order_queue" 
    cleanup_sdkperf_processes "baseline_queue"
    exit 0
}

# Set up signal handlers
trap cleanup_baseline_trade SIGTERM SIGINT

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
    
    # Publish trade executions for multiple securities
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${ORDER_ROUTER_USER}" \
        -cp="${ORDER_ROUTER_PASSWORD}" \
        -ptl="trading/orders/equities/NYSE/AAPL,trading/orders/equities/NASDAQ/TSLA" \
        -mt=persistent \
        -mr="${CURRENT_RATE}" \
        -mn=999999999 \
        -msa=512 >> logs/baseline-trade.log 2>&1 &
    
    # Add limited queue consumers for automatic draining (prevents permanent queue buildup)
    # NOTE: Skip equity_order_queue - reserved for chaos testing (queue-killer)
    # bash "${SDKPERF_SCRIPT_PATH}" \
    #     -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
    #     -cu="${ORDER_ROUTER_USER}" \
    #     -cp="${ORDER_ROUTER_PASSWORD}" \
    #     -sql="equity_order_queue" >> logs/baseline-trade.log 2>&1 &
    # EQUITY_CONSUMER_PID=$!
    
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${ORDER_ROUTER_USER}" \
        -cp="${ORDER_ROUTER_PASSWORD}" \
        -sql="baseline_queue" >> logs/baseline-trade.log 2>&1 &
    BASELINE_CONSUMER_PID=$!
        
    # Let it run for 1 hour then restart for rate adjustments
    sleep 3600
    
    # Kill processes by PID to ensure cleanup
    pkill -f "trading/orders/equities" 2>/dev/null
    [ -n "$EQUITY_CONSUMER_PID" ] && kill $EQUITY_CONSUMER_PID 2>/dev/null
    [ -n "$BASELINE_CONSUMER_PID" ] && kill $BASELINE_CONSUMER_PID 2>/dev/null
    
    # Wait a moment for cleanup
    sleep 2
    
    echo "$(date): Baseline trade flow cycle completed - restarting for rate check"
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

# Target queue configuration
TARGET_QUEUE="equity_order_queue"
TARGET_VPN="trading"
FULL_THRESHOLD=85  # Consider queue "full" at 85%
DRAIN_THRESHOLD=20 # Resume attacks when below 20%
DRAIN_PIDS=""      # Track drain consumer PIDs for cleanup
PUBLISHER_PID=""   # Track publisher PID for control

while true; do
    echo "$(date): Starting intelligent queue killer attack on ${TARGET_QUEUE}"
    DRAIN_PIDS=""  # Reset drain consumer tracking for new cycle
    
    # Check if queue is already full
    if check_queue_full "${TARGET_QUEUE}" "${TARGET_VPN}" "${FULL_THRESHOLD}"; then
        echo "$(date): 🚨 Queue ${TARGET_QUEUE} already at ${FULL_THRESHOLD}%! Starting drain consumer immediately..."
        
        # Start drain consumer - exclusive queues allow only one consumer per queue
        bash "${SDKPERF_SCRIPT_PATH}" \
                -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
                -cu="${ORDER_ROUTER_USER}" \
                -cp="${ORDER_ROUTER_PASSWORD}" \
                -sql="${TARGET_QUEUE}" >> logs/queue-killer.log 2>&1 &
        DRAIN_PIDS="$!"
        
        echo "$(date): 🔄 Started 1 drain consumer, waiting for queue to drop to ${DRAIN_THRESHOLD}%..."
        wait_for_queue_to_drain "${TARGET_QUEUE}" "${TARGET_VPN}" "${DRAIN_THRESHOLD}" 300
        
        # Stop all drain consumers
        if [ -n "$DRAIN_PIDS" ]; then
            echo "$(date): ✅ Queue drained! Stopping all drain consumers..."
            kill $DRAIN_PIDS 2>/dev/null
            wait_for_pids_to_exit $DRAIN_PIDS
        fi
        
        echo "$(date): 💤 Queue drained, waiting 60 seconds before starting fill cycle..."
        sleep 60
    fi
    
    # Start persistent publisher in background to fill queue (very high rate to overcome active consumers)
    echo "$(date): Starting persistent publisher to fill queue to ${FULL_THRESHOLD}%..."
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${CHAOS_GENERATOR_USER}" \
        -cp="${CHAOS_GENERATOR_PASSWORD}" \
        -ptl="trading/orders/equities/NYSE/new" \
        -mt=persistent \
        -mr=10000 \
        -mn=500000 \
        -msa=5000 >> logs/queue-killer.log 2>&1 &
    
    PUBLISHER_PID=$!
    echo "$(date): Publisher started (PID: ${PUBLISHER_PID}), monitoring queue fill..."
    
    # Monitor queue until it reaches the threshold
    fill_timeout=300  # 5 minutes max to fill
    start_time=$(date +%s)
    
    while true; do
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        
        if check_queue_full "${TARGET_QUEUE}" "${TARGET_VPN}" "${FULL_THRESHOLD}"; then
            echo "$(date): 🚨 Queue reached ${FULL_THRESHOLD}%! Stopping publisher and starting drain consumers..."
            
            # Stop the publisher first
            kill ${PUBLISHER_PID} 2>/dev/null
            
            # Start drain consumer - exclusive queues allow only one consumer per queue
            bash "${SDKPERF_SCRIPT_PATH}" \
                    -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
                    -cu="${ORDER_ROUTER_USER}" \
                    -cp="${ORDER_ROUTER_PASSWORD}" \
                    -sql="${TARGET_QUEUE}" >> logs/queue-killer.log 2>&1 &
                DRAIN_PIDS="$! $DRAIN_PIDS"
            done
            
            echo "$(date): 🔄 Started 2 drain consumers, waiting for queue to drop to ${DRAIN_THRESHOLD}%..."
            # Wait for queue to drain to threshold
            wait_for_queue_to_drain "${TARGET_QUEUE}" "${TARGET_VPN}" "${DRAIN_THRESHOLD}" 300
            
            # Stop all drain consumers
            if [ -n "$DRAIN_PIDS" ]; then
                echo "$(date): ✅ Queue drained! Stopping all drain consumers..."
                kill $DRAIN_PIDS 2>/dev/null
                wait_for_pids_to_exit $DRAIN_PIDS
            fi
            
            echo "$(date): 💤 Cycle complete. Waiting 60 seconds before next attack..."
            sleep 60
            break
            
        elif [ ${elapsed} -ge ${fill_timeout} ]; then
            echo "$(date): ⏰ Publisher timeout after ${fill_timeout}s"
            usage=$(get_queue_usage "${TARGET_QUEUE}" "${TARGET_VPN}")
            echo "$(date): Final queue usage: ${usage}%"
            
            # Kill publisher and clean up any partial fill
            kill ${PUBLISHER_PID} 2>/dev/null
            
            if [ "$usage" -gt 10 ]; then
                echo "$(date): Cleaning up ${usage}% partial fill..."
                bash "${SDKPERF_SCRIPT_PATH}" \
                    -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
                    -cu="${ORDER_ROUTER_USER}" \
                    -cp="${ORDER_ROUTER_PASSWORD}" \
                    -sql="${TARGET_QUEUE}" >> logs/queue-killer.log 2>&1 &
                DRAIN_PIDS="$!"
                
                wait_for_queue_to_drain "${TARGET_QUEUE}" "${TARGET_VPN}" 5 60
                
                if [ -n "$DRAIN_PIDS" ]; then
                    kill $DRAIN_PIDS 2>/dev/null
                fi
            fi
            
            break
        else
            # Show progress every 30 seconds
            if [ $((elapsed % 30)) -eq 0 ]; then
                current_usage=$(get_queue_usage "${TARGET_QUEUE}" "${TARGET_VPN}")
                echo "$(date): Queue at ${current_usage}% after ${elapsed}s (target: ${FULL_THRESHOLD}%)"
            fi
            sleep 10
        fi
    done
done
EOF

    # Multi-VPN ACL violator
    cat > error-generators/multi-vpn-acl-violator.sh <<'EOF'
#!/bin/bash
source scripts/load-env.sh

while true; do
    echo "$(date): Testing ACL violations across all VPNs"
    
    # Try to access premium market data with restricted user (gentle continuous)
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${RESTRICTED_MARKET_USER}" \
        -cp="${RESTRICTED_MARKET_PASSWORD}" \
        -ptl="market-data/premium/level3/NYSE/AAPL" \
        -mr=1 -mn=999999999 -msa=256 >> logs/acl-violator.log 2>&1 &
    
    # Try to access admin trading functions with restricted user (gentle continuous)
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${RESTRICTED_TRADE_USER}" \
        -cp="${RESTRICTED_TRADE_PASSWORD}" \
        -ptl="trading/admin/cancel-all-orders" \
        -mr=1 -mn=999999999 -msa=256 >> logs/acl-violator.log 2>&1 &
    
    # Try cross-VPN access without proper permissions (gentle continuous)
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${RESTRICTED_MARKET_USER}" \
        -cp="${RESTRICTED_MARKET_PASSWORD}" \
        -ptl="trading/orders/equities/NYSE/new" \
        -mr=1 -mn=999999999 -msa=256 >> logs/acl-violator.log 2>&1 &
    
    # Let run for 1 hour, then restart
    sleep 3600
    pkill -f "premium/level3\|admin/cancel-all-orders" 2>/dev/null
    echo "$(date): ACL violation test cycle completed - restarting"
done
EOF

    # Market data connection bomber
    cat > error-generators/market-data-connection-bomber.sh <<'EOF'
#!/bin/bash
source scripts/load-env.sh

# Cleanup function for graceful shutdown
cleanup_connection_bomber() {
    echo "$(date): Connection bomber shutting down - cleaning up processes"
    cleanup_sdkperf_processes "market-data/equities/quotes/NYSE"
    exit 0
}

# Set up signal handlers
trap cleanup_connection_bomber SIGTERM SIGINT

while true; do
    echo "$(date): Starting gentle connection pressure test"
    
    # Check resource limits before starting
    if ! check_resource_limits 75; then  # Higher limit for intensive connection testing
        echo "$(date): Resource limits exceeded - waiting before retry"
        sleep 300
        continue
    fi
    
    # Start 25 long-running market data consumers (intensive connection load)
    for i in {1..25}; do
        bash "${SDKPERF_SCRIPT_PATH}" \
            -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
            -cu="${MARKET_DATA_CONSUMER_USER}" \
            -cp="${MARKET_DATA_CONSUMER_PASSWORD}" \
            -stl="market-data/equities/quotes/NYSE/>" >> logs/connection-bomber.log 2>&1 &
    done
    
    # Let connections run for 2 hours then cycle
    sleep 7200
    cleanup_sdkperf_processes "market-data/equities/quotes/NYSE"
    echo "$(date): Connection pressure cycle completed - restarting"
    sleep 60
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
        -mr=2000 -mn=50000 -msa=2048 >> logs/bridge-killer.log 2>&1 &
    
    # Additional publishers for different exchanges and securities
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${MARKET_DATA_FEED_USER}" \
        -cp="${MARKET_DATA_FEED_PASSWORD}" \
        -ptl="market-data/bridge-stress/equities/NASDAQ/MSFT/L1" \
        -mr=2000 -mn=50000 -msa=2048 >> logs/bridge-killer.log 2>&1 &
        
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${MARKET_DATA_FEED_USER}" \
        -cp="${MARKET_DATA_FEED_PASSWORD}" \
        -ptl="market-data/bridge-stress/equities/LSE/TSLA/L2" \
        -mr=1000 -mn=50000 -msa=2048 >> logs/bridge-killer.log 2>&1 &
    
    PUB_PID=$!
    
    # Bridge client will consume from cross_market_data_queue automatically
    # No need for additional SDKPerf consumers
    
    # Cross-VPN bridge consumers on trading VPN (actual bridge testing)
    for i in {1..2}; do
        bash "${SDKPERF_SCRIPT_PATH}" \
            -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
            -cu="${ORDER_ROUTER_USER}" \
            -cp="${ORDER_ROUTER_PASSWORD}" \
            -sql=bridge_receive_queue \
            -pe >> logs/bridge-killer.log 2>&1 &
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
    cat > scripts/master-chaos.sh <<'EOF'
#!/bin/bash

# Master chaos orchestrator - runs all components with health monitoring
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Change to project root for consistent paths
cd "$PROJECT_ROOT"

# Load environment variables
source scripts/load-env.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

MASTER_LOG="scripts/logs/master-chaos-$(date +%Y%m%d_%H%M%S).log"
HEALTH_CHECK_INTERVAL=${HEALTH_CHECK_INTERVAL:-300}  # 5 minutes (configurable via .env)
CONSUMER_CLEANUP_FREQUENCY=${CONSUMER_CLEANUP_FREQUENCY:-10}  # Every 10 health checks (~5 minutes)

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

# Component management - bash 3.2 compatible arrays
COMPONENT_PIDS=()
COMPONENT_NAMES=()
COMPONENT_START_TIMES=()

find_component_index() {
    local component="$1"
    local i
    for i in "${!COMPONENT_NAMES[@]}"; do
        if [[ "${COMPONENT_NAMES[i]}" == "$component" ]]; then
            echo "$i"
            return 0
        fi
    done
    echo "-1"
}

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
    local existing_index
    
    existing_index=$(find_component_index "$component")
    if [[ "$existing_index" != "-1" ]] && kill -0 "${COMPONENT_PIDS[existing_index]}" 2>/dev/null; then
        return 0
    fi
    
    log_message "Starting component: $component_name"
    
    "./$component" &
    local pid=$!
    
    if [[ "$existing_index" == "-1" ]]; then
        COMPONENT_NAMES+=("$component")
        COMPONENT_PIDS+=("$pid")
        COMPONENT_START_TIMES+=($(date +%s))
    else
        COMPONENT_PIDS[existing_index]="$pid"
        COMPONENT_START_TIMES[existing_index]=$(date +%s)
    fi
    
    log_success "Started $component_name (PID: $pid)"
}

check_component_health() {
    local component="$1"
    local component_name=$(basename "$component" .sh)
    local component_index
    local pid
    
    component_index=$(find_component_index "$component")
    if [[ "$component_index" == "-1" ]]; then
        log_error "No PID tracked for $component_name"
        start_component "$component"
        return 1
    fi
    
    pid="${COMPONENT_PIDS[component_index]}"
    
    if ! kill -0 "$pid" 2>/dev/null; then
        log_warning "$component_name (PID: $pid) is not running - restarting"
        start_component "$component"
        return 1
    fi
    
    return 0
}

cleanup_and_exit() {
    local signal=$1
    log_message "Received signal $signal - shutting down gracefully"
    
    local i
    for i in "${!COMPONENT_NAMES[@]}"; do
        local component="${COMPONENT_NAMES[i]}"
        local pid="${COMPONENT_PIDS[i]}"
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
            
            # Run periodic consumer cleanup every N health checks
            if (( loop_counter % CONSUMER_CLEANUP_FREQUENCY == 0 )); then
                log_message "Running periodic consumer cleanup..."
                bash scripts/cleanup-excess-consumers.sh >> "$MASTER_LOG" 2>&1
                log_success "Consumer cleanup completed"
            fi
            
            for component in "${TRAFFIC_GENERATORS[@]}" "${ERROR_GENERATORS[@]}"; do
                check_component_health "$component"
            done
            
            last_health_check=$current_time
        fi
        
        # Heartbeat every hour
        if (( loop_counter % 120 == 0 )); then
            log_message "Orchestrator heartbeat - loop $loop_counter, components: ${#COMPONENT_NAMES[@]} managed"
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
    # Use eval for bash 3.2 compatibility instead of ${!var}
    value=$(eval echo \$$var)
    if [ -z "$value" ]; then
        echo "ERROR: Required environment variable $var is not set"
        exit 1
    fi
done

# SEMP API configuration
SOLACE_SEMP_URL="http://${SOLACE_BROKER_HOST}:8080"

# SEMP API Helper Functions
get_queue_usage() {
    local queue_name="$1"
    local vpn_name="$2"
    
    if [ -z "$queue_name" ] || [ -z "$vpn_name" ]; then
        echo "0"
        return 1
    fi
    
    # Query SEMP API for queue usage using collections.msgs.count
    local response=$(curl -s -u "${SOLACE_ADMIN_USER}:${SOLACE_ADMIN_PASSWORD}" \
        "${SOLACE_SEMP_URL}/SEMP/v2/monitor/msgVpns/${vpn_name}/queues/${queue_name}" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ ! -z "$response" ]; then
        # Get collections.msgs.count (number of available message objects)
        local msg_count=$(echo "$response" | jq -r '.collections.msgs.count // 0')
        
        if [ ! -z "$msg_count" ] && [ "$msg_count" != "null" ]; then
            # Calculate percentage based on reasonable queue capacity (1000 messages = 100%)
            local usage_percent=$((msg_count * 100 / 1000))
            # Cap at 100%
            if [ $usage_percent -gt 100 ]; then
                usage_percent=100
            fi
            echo "$usage_percent"
            return 0
        fi
        
        # Fall back to spooledMsgCount if collections data not available
        local spooled_count=$(echo "$response" | grep -o '"spooledMsgCount":[0-9]*' | cut -d':' -f2 | head -1)
        if [ ! -z "$spooled_count" ] && [ "$spooled_count" != "null" ]; then
            # Estimate percentage: assume full at ~120K messages
            local estimated_percent=$((spooled_count * 100 / 120000))
            # Cap at 100%
            if [ $estimated_percent -gt 100 ]; then
                estimated_percent=100
            fi
            echo "$estimated_percent"
            return 0
        fi
    fi
    
    echo "0"
    return 1
}

check_queue_full() {
    local queue_name="$1"
    local vpn_name="$2"
    local threshold="${3:-85}"
    
    local usage=$(get_queue_usage "$queue_name" "$vpn_name")
    
    if [ "$usage" -ge "$threshold" ]; then
        return 0  # Queue is full
    else
        return 1  # Queue is not full
    fi
}

# Function to wait for process IDs to exit cleanly
wait_for_pids_to_exit() {
    local pids="$@"
    local max_wait=10
    local count=0
    
    for pid in $pids; do
        while kill -0 "$pid" 2>/dev/null && [ $count -lt $max_wait ]; do
            sleep 1
            count=$((count + 1))
        done
    done
}

wait_for_queue_to_drain() {
    local queue_name="$1"
    local vpn_name="$2"
    local threshold="${3:-20}"
    local timeout="${4:-1800}"  # 30 minutes default
    
    echo "$(date): Waiting for queue ${queue_name} to drain below ${threshold}%..."
    
    local start_time=$(date +%s)
    while true; do
        local usage=$(get_queue_usage "$queue_name" "$vpn_name")
        
        if [ "$usage" -le "$threshold" ]; then
            echo "$(date): Queue drained to ${usage}% - continuing"
            return 0
        fi
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ "$elapsed" -ge "$timeout" ]; then
            echo "$(date): Drain timeout after ${timeout}s - queue still at ${usage}%"
            return 1
        fi
        
        sleep 30
    done
}

check_resource_limits() {
    local max_connections="${1:-40}"
    
    # Count current SDKPerf connections using process counting
    local current_connections=$(pgrep -f "sdkperf_java" | wc -l | tr -d ' ')
    
    echo "Connection usage - Default: , Trading: , Total: ${current_connections}/${max_connections}"
    
    if [ "$current_connections" -ge "$max_connections" ]; then
        echo "$(date): Connection limit reached (${current_connections}/${max_connections})"
        return 1  # Limit exceeded
    else
        return 0  # Within limits
    fi
}

# Direct queue clearing using SEMP API (immediate and efficient)
clear_queue_messages() {
    local queue_name="$1"
    local vpn_name="$2"
    
    if [ -z "$queue_name" ] || [ -z "$vpn_name" ]; then
        echo "Usage: clear_queue_messages <queue_name> <vpn_name>"
        return 1
    fi
    
    echo "$(date): Clearing all messages from queue ${queue_name} in VPN ${vpn_name}..."
    
    # Use SEMP API action endpoint to delete all messages (correct method: PUT)
    local response=$(curl -X PUT \
        -u "${SOLACE_ADMIN_USER}:${SOLACE_ADMIN_PASSWORD}" \
        -H "Content-Type: application/json" \
        "${SOLACE_SEMP_URL}/SEMP/v2/action/msgVpns/${vpn_name}/queues/${queue_name}/deleteMsgs" \
        -d "{}" \
        -s -w "%{http_code}")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [[ "$http_code" =~ ^(200|204)$ ]]; then
        echo "$(date): Successfully cleared queue ${queue_name}"
        sleep 2  # Brief pause for queue stats to update
        local new_usage=$(get_queue_usage "$queue_name" "$vpn_name")
        echo "$(date): Queue usage after clearing: ${new_usage}%"
        return 0
    else
        echo "$(date): Failed to clear queue ${queue_name} - HTTP ${http_code}"
        echo "Response: ${body}"
        echo "$(date): Falling back to consumer-based draining..."
        # Fallback to consumer-based clearing
        drain_queue_manually "$queue_name" "$vpn_name" "consumer"
        return 1
    fi
}
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
    
    # Clean up old logs before starting
    cleanup_old_logs
    
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
    echo "  2. Start the chaos testing: ./scripts/master-chaos.sh"
    echo "  3. Check status anytime: ./scripts/status-check.sh"
    echo ""
    echo "The environment is ready for long-term chaos testing!"
    echo ""
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi