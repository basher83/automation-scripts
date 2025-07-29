#!/bin/bash

# Consul Prometheus Exporter Setup Script
# Creates Consul ACL policies and tokens for Prometheus/Netdata scraping
# 
# Usage:
#   ./prometheus-consul-exporter.sh [OPTIONS]
#
# Options:
#   --force              Force recreation of existing policies/tokens
#   --skip-netdata       Skip Netdata configuration
#   --non-interactive    Run without prompts (for automation)
#   --consul-addr URL    Custom Consul address (default: http://127.0.0.1:8500)
#   --help               Show this help message
#
# Requirements:
#   - Consul CLI with ACL management permissions
#   - Infisical CLI for secrets management
#   - jq for JSON processing
#   - Root/sudo access for Netdata configuration
#
# Infisical secrets required:
#   /apollo-13/consul/CONSUL_MASTER_TOKEN - Consul management token

set -euo pipefail
trap 'echo "Error occurred at line $LINENO. Exit code: $?" >&2' ERR

# Configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/var/log/consul-prometheus-setup.log"
readonly POLICY_NAME="prometheus-scraping"
readonly TOKEN_DESCRIPTION="Prometheus/Netdata scraping token"
readonly CONSUL_ADDR_DEFAULT="http://127.0.0.1:8500"

# Parse command line arguments
FORCE_MODE=false
SKIP_NETDATA=false
NON_INTERACTIVE=false
CONSUL_ADDR="$CONSUL_ADDR_DEFAULT"

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_MODE=true
            shift
            ;;
        --skip-netdata)
            SKIP_NETDATA=true
            shift
            ;;
        --non-interactive)
            NON_INTERACTIVE=true
            shift
            ;;
        --consul-addr)
            CONSUL_ADDR="$2"
            shift 2
            ;;
        --help|-h)
            grep "^#" "$0" | grep -E "^# (Usage|Options|Requirements|Infisical)" | sed 's/^# //'
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Color codes for output (check if terminal supports colors)
if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]] && [[ -z "${NO_COLOR:-}" ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly NC='\033[0m' # No Color
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly NC=''
fi

# Logging functions
log_info() {
    local message="$*"
    echo -e "${GREEN}[INFO]${NC} $message"
    [[ -w "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $message" >> "$LOG_FILE" || true
}

log_warn() {
    local message="$*"
    echo -e "${YELLOW}[WARN]${NC} $message"
    [[ -w "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $message" >> "$LOG_FILE" || true
}

log_error() {
    local message="$*"
    echo -e "${RED}[ERROR]${NC} $message" >&2
    [[ -w "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $message" >> "$LOG_FILE" || true
}

log_success() {
    local message="$*"
    echo -e "${BLUE}[SUCCESS]${NC} $message"
    [[ -w "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $message" >> "$LOG_FILE" || true
}

# Function to check prerequisites
check_prerequisites() {
    local missing_tools=()
    
    # Check required tools
    if ! command -v consul &> /dev/null; then
        missing_tools+=("consul")
    fi
    
    if ! command -v infisical &> /dev/null; then
        missing_tools+=("infisical")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Install missing tools:"
        for tool in "${missing_tools[@]}"; do
            case $tool in
                consul)
                    log_info "  consul: https://www.consul.io/downloads"
                    ;;
                infisical)
                    log_info "  infisical: brew install infisical/get-cli/infisical"
                    ;;
                jq)
                    log_info "  jq: sudo apt-get install jq"
                    ;;
            esac
        done
        exit 1
    fi
}

# Function to get Consul management token from Infisical
get_consul_token() {
    log_info "Retrieving Consul management token from Infisical..."
    
    # Check if already authenticated to Infisical
    if ! infisical secrets 2>&1 | grep -q "apollo-13"; then
        log_error "Not authenticated to Infisical or missing access to apollo-13 project"
        log_info "Please run: infisical login"
        exit 1
    fi
    
    # Get token from Infisical
    CONSUL_MASTER_TOKEN=$(infisical secrets get CONSUL_MASTER_TOKEN --path="/apollo-13/consul" --projectId="7b832220-24c0-45bc-a5f1-ce9794a31259" --plain 2>/dev/null || true)

    if [[ -z "$CONSUL_MASTER_TOKEN" ]]; then
        log_error "Failed to retrieve CONSUL_MASTER_TOKEN from Infisical"
        log_info "Ensure you have access to /apollo-13/consul/CONSUL_MASTER_TOKEN"
        exit 1
    fi
    
    # Export for consul commands
    export CONSUL_HTTP_TOKEN="$CONSUL_MASTER_TOKEN"
    export CONSUL_HTTP_ADDR="$CONSUL_ADDR"
    
    log_success "Successfully retrieved Consul management token"
}

# Function to check if policy exists
policy_exists() {
    consul acl policy read -name "$POLICY_NAME" &>/dev/null
}

# Function to create ACL policy
create_acl_policy() {
    log_info "Creating Consul ACL policy: $POLICY_NAME"
    
    # Check if policy already exists
    if policy_exists; then
        if [[ "$FORCE_MODE" == "true" ]]; then
            log_warn "Policy '$POLICY_NAME' exists. Force mode enabled - deleting existing policy..."
            consul acl policy delete -name "$POLICY_NAME"
        else
            log_warn "Policy '$POLICY_NAME' already exists. Use --force to recreate."
            return 0
        fi
    fi
    
    # Create the policy
    consul acl policy create -name "$POLICY_NAME" -rules - <<EOF
# Policy for Prometheus/Netdata scraping
operator = "read"

node_prefix "" {
  policy = "read"
}

agent_prefix "" {
  policy = "read"
}

service_prefix "" {
  policy = "read"
}
EOF
    
    log_success "ACL policy '$POLICY_NAME' created successfully"
}

# Function to create ACL token
create_acl_token() {
    log_info "Creating Consul ACL token for Prometheus scraping..."
    
    # Create the token
    local token_output
    token_output=$(consul acl token create \
        -description "$TOKEN_DESCRIPTION" \
        -policy-name "$POLICY_NAME" \
        -format json)
    
    # Extract the token
    local secret_id
    secret_id=$(echo "$token_output" | jq -r '.SecretID')
    
    if [[ -z "$secret_id" || "$secret_id" == "null" ]]; then
        log_error "Failed to create ACL token"
        exit 1
    fi
    
    # Save token info (with restricted permissions)
    {
        echo "Token created at: $(date)"
        echo "Description: $TOKEN_DESCRIPTION"
        echo "Policy: $POLICY_NAME"
        echo "SecretID: $secret_id"
    } >> "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    
    log_success "ACL token created successfully"
    log_info "Token SecretID saved to: $LOG_FILE (restricted access)"
    
    # Return the token
    echo "$secret_id"
}

# Function to configure Netdata
configure_netdata() {
    local token="$1"
    
    log_info "Configuring Netdata Consul collector..."
    
    # Find Netdata configuration directory
    local netdata_dir
    if [[ -d "/etc/netdata" ]]; then
        netdata_dir="/etc/netdata"
    elif [[ -d "/opt/netdata/etc/netdata" ]]; then
        netdata_dir="/opt/netdata/etc/netdata"
    else
        log_error "Netdata configuration directory not found"
        log_info "Netdata may not be installed or is in a non-standard location"
        return 1
    fi
    
    # Create go.d directory if it doesn't exist
    local god_dir="$netdata_dir/go.d"
    if [[ ! -d "$god_dir" ]]; then
        log_info "Creating go.d configuration directory..."
        mkdir -p "$god_dir"
    fi
    
    local consul_conf="$god_dir/consul.conf"
    
    # Backup existing configuration
    if [[ -f "$consul_conf" ]]; then
        local backup_file="${consul_conf}.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Backing up existing configuration to: $backup_file"
        cp "$consul_conf" "$backup_file"
    fi
    
    # Write new configuration
    log_info "Writing Netdata Consul configuration..."
    cat > "$consul_conf" <<EOF
# Netdata Consul collector configuration
# Generated by $SCRIPT_NAME on $(date)

jobs:
  - name: local
    url: $CONSUL_ADDR
    acl_token: "$token"
    # Update interval in seconds
    update_every: 1
    # Timeout for API requests
    timeout: 2
    # Enable autodetection of services
    autodetection_retry: 0
    # Collect additional metrics
    collect_node_metadata: yes
    collect_service_metadata: yes
EOF
    
    # Set appropriate permissions
    chmod 640 "$consul_conf"
    if command -v netdata &>/dev/null; then
        local netdata_user=$(ps aux | grep -m1 '[n]etdata' | awk '{print $1}' || echo "netdata")
        chown "$netdata_user:$netdata_user" "$consul_conf" 2>/dev/null || true
    fi
    
    log_success "Netdata configuration updated"
    log_info "Configuration file: $consul_conf"
    
    # Restart Netdata if it's running
    if systemctl is-active --quiet netdata 2>/dev/null; then
        log_info "Restarting Netdata service..."
        systemctl restart netdata
        log_success "Netdata restarted"
    else
        log_warn "Netdata service not found or not running"
        log_info "You may need to restart Netdata manually"
    fi
}

# Function to verify Consul connectivity
verify_consul() {
    log_info "Verifying Consul connectivity..."
    
    if ! consul info &>/dev/null; then
        log_error "Cannot connect to Consul at $CONSUL_ADDR"
        log_info "Check if Consul is running and accessible"
        exit 1
    fi
    
    log_success "Successfully connected to Consul"
}

# Main execution
main() {
    log_info "Starting Consul Prometheus exporter setup..."
    log_info "Script: $SCRIPT_NAME"
    log_info "Consul address: $CONSUL_ADDR"
    
    # Check if running as root (needed for Netdata config and log file)
    if [[ $EUID -ne 0 ]] && [[ "$SKIP_NETDATA" != "true" ]]; then
        log_error "This script must be run as root to configure Netdata"
        log_info "Use sudo or run as root, or use --skip-netdata"
        log_info "For remote execution: curl -fsSL <url> | sudo bash"
        exit 1
    fi
    
    # Initialize log file after root check
    if [[ $EUID -eq 0 ]]; then
        mkdir -p "$(dirname "$LOG_FILE")"
        touch "$LOG_FILE"
        chmod 640 "$LOG_FILE"
        log_info "Logging to: $LOG_FILE"
    else
        log_warn "Not running as root - log file creation skipped"
    fi
    
    # Confirmation prompt
    if [[ "$NON_INTERACTIVE" != "true" ]] && [[ -t 0 ]]; then
        echo
        log_warn "This script will:"
        echo "  1. Create Consul ACL policy: $POLICY_NAME"
        echo "  2. Generate a new ACL token for Prometheus/Netdata"
        if [[ "$SKIP_NETDATA" != "true" ]]; then
            echo "  3. Configure Netdata to use the token"
        fi
        echo
        read -p "Continue? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Setup cancelled by user"
            exit 0
        fi
    fi
    
    # Run setup steps
    check_prerequisites
    get_consul_token
    verify_consul
    create_acl_policy
    
    # Create token
    local prometheus_token
    prometheus_token=$(create_acl_token)
    
    # Configure Netdata if not skipped
    if [[ "$SKIP_NETDATA" != "true" ]]; then
        configure_netdata "$prometheus_token"
    else
        log_info "Skipping Netdata configuration (--skip-netdata specified)"
        log_info "Token created: Use the SecretID from $LOG_FILE for manual configuration"
    fi
    
    # Summary
    echo
    log_success "🎉 Consul Prometheus exporter setup complete!"
    echo
    log_info "Next steps:"
    echo "  1. Verify ACL policy: consul acl policy read -name $POLICY_NAME"
    echo "  2. Check Consul metrics endpoint: curl -H \"X-Consul-Token: <token>\" $CONSUL_ADDR/v1/agent/metrics"
    if [[ "$SKIP_NETDATA" != "true" ]]; then
        echo "  3. Verify Netdata is collecting metrics: check Netdata dashboard"
    fi
    echo "  4. Review setup log: sudo cat $LOG_FILE"
}

# Run main function
main "$@"