#!/bin/bash
#
# Fix Prometheus PVE Exporter Token Issue
# 
# This script recreates the API token for prometheus-pve-exporter
# when encountering "401 Unauthorized: invalid token value!" errors
#
# Usage:
#   ./fix-token.sh
#   NON_INTERACTIVE=true ./fix-token.sh
#
# Remote execution:
#   curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/proxmox-virtual-environment/prometheus-pve-exporter/fix-token.sh | sudo bash
#

set -euo pipefail
trap 'echo "Error occurred at line $LINENO. Exit code: $?" >&2' ERR

# Configuration (must match install script)
readonly USER="prometheus"
readonly USERNAME="prometheus@pve"
readonly TOKEN_NAME="monitoring"
readonly CONFIG_DIR="/etc/prometheus"
readonly CONFIG_FILE="${CONFIG_DIR}/pve.yml"
readonly SERVICE_NAME="prometheus-pve-exporter"

# Support for non-interactive mode
INTERACTIVE=true
if [[ ! -t 0 ]] || [[ "${NON_INTERACTIVE:-}" == "true" ]]; then
    INTERACTIVE=false
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check command dependencies
check_dependencies() {
    local deps=("pveum" "curl" "systemctl" "awk" "grep")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing[*]}"
        exit 1
    fi
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

# Check if running on Proxmox
if ! command -v pveum &> /dev/null; then
    log_error "This script must be run on a Proxmox VE host"
    exit 1
fi

# Check all dependencies
check_dependencies

# Check if service is installed
if ! systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
    log_error "Service $SERVICE_NAME not found. Please run the installation script first."
    exit 1
fi

log_info "Starting token recreation process..."

# Check current token status
log_info "Checking current token status..."
if pveum user token list $USERNAME 2>/dev/null | grep -q "$TOKEN_NAME"; then
    log_warn "Token $TOKEN_NAME exists, removing it..."
    pveum user token remove $USERNAME $TOKEN_NAME
    log_info "Old token removed successfully"
else
    log_info "Token $TOKEN_NAME does not exist"
fi

# Create new token
log_info "Creating new API token..."
log_warn "Note: The token will be briefly visible in the process list during creation."
log_warn "This is a limitation of the Proxmox CLI tools."
TOKEN_OUTPUT=$(pveum user token add $USERNAME $TOKEN_NAME --privsep 1)

# Extract the token value with better validation
TOKEN_VALUE=$(echo "$TOKEN_OUTPUT" | grep "│ value" | awk -F'│' '{print $3}' | xargs)

if [[ -z "$TOKEN_VALUE" ]] || [[ "$TOKEN_VALUE" == *"│"* ]]; then
    log_error "Failed to extract token value or invalid format"
    echo "$TOKEN_OUTPUT"
    exit 1
fi

log_info "New token created successfully"

# Grant PVEAuditor role to token
log_info "Granting PVEAuditor role to token"
pveum acl modify / --tokens ${USERNAME}!${TOKEN_NAME} --roles PVEAuditor

# Backup existing config
if [[ -f "$CONFIG_FILE" ]]; then
    BACKUP_FILE="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    log_info "Backing up existing config to $BACKUP_FILE"
    cp $CONFIG_FILE $BACKUP_FILE
fi

# Update configuration file
log_info "Updating configuration file: $CONFIG_FILE"
cat <<EOF > $CONFIG_FILE
default:
  user: ${USERNAME}
  token_name: ${TOKEN_NAME}
  token_value: ${TOKEN_VALUE}
  verify_ssl: false
EOF

# Set appropriate permissions
chmod 640 $CONFIG_FILE
chown $USER:$USER $CONFIG_FILE

# Restart the service with retry mechanism
start_service_with_retry() {
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        log_info "Restarting $SERVICE_NAME service (attempt $attempt/$max_attempts)..."
        if systemctl restart "$SERVICE_NAME"; then
            sleep 3  # Give service time to start
            if systemctl is-active --quiet "$SERVICE_NAME"; then
                log_info "Service restarted successfully!"
                return 0
            fi
        fi
        log_warn "Service start attempt $attempt failed, retrying..."
        sleep $((2 ** attempt))
        ((attempt++))
    done
    return 1
}

if ! start_service_with_retry; then
    log_error "Service failed to start after $max_attempts attempts. Check logs with: journalctl -xeu $SERVICE_NAME"
    exit 1
fi

# Test the exporter with timeout
log_info "Testing exporter endpoint..."
if curl -s -f -o /dev/null --connect-timeout 5 --max-time 10 "http://localhost:9221/"; then
    log_info "Exporter is responding correctly"
    
    # Test metrics endpoint with timeout
    log_info "Testing metrics collection..."
    if curl -s --connect-timeout 5 --max-time 10 "http://localhost:9221/pve?target=localhost" | head -n 5; then
        echo ""
        log_info "Metrics are being collected successfully!"
    else
        log_warn "Could not retrieve metrics, but service is running"
    fi
else
    log_error "Exporter test failed"
    exit 1
fi

# Save fix log
LOG_FILE="/var/log/${SERVICE_NAME}-token-fix.log"
echo "Token fix completed at $(date)" >> $LOG_FILE
echo "New token: ${USERNAME}!${TOKEN_NAME}" >> $LOG_FILE
chown $USER:$USER $LOG_FILE
chmod 640 $LOG_FILE

# Print summary
echo ""
echo "================================================================="
echo -e "${GREEN}Token recreation completed successfully!${NC}"
echo "================================================================="
echo ""
echo "The new token has been saved to: $CONFIG_FILE"
echo "Service status: systemctl status $SERVICE_NAME"
echo ""
echo "You can verify it's working with:"
echo "  curl http://localhost:9221/pve?target=localhost | head"
echo ""
echo "Recent logs:"
journalctl -u $SERVICE_NAME -n 10 --no-pager
echo ""
echo "================================================================="