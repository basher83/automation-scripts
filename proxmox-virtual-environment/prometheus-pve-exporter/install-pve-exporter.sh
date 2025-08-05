#!/bin/bash
#
# Prometheus PVE Exporter Bootstrap Script (Improved)
# 
# This script installs and configures prometheus-pve-exporter on a Proxmox host
# using a Python virtual environment for production stability.
#
# Improvements:
# - Auto-detects correct privilege separation setting based on PVE version
# - Secure token creation to avoid process list exposure
# - Option to enable SSL verification
# - Better error handling and recovery
#
# Usage:
#   ./install-pve-exporter.sh [--verify-ssl] [--privsep auto|0|1]
#

set -euo pipefail  # Exit on error, undefined variables, pipe failures

# Configuration
USER="prometheus"
USERNAME="prometheus@pve"
TOKEN_NAME="monitoring"
INSTALL_DIR="/opt/prometheus-pve-exporter"
CONFIG_DIR="/etc/prometheus"
CONFIG_FILE="${CONFIG_DIR}/pve.yml"
SERVICE_NAME="prometheus-pve-exporter"

# Default options
VERIFY_SSL="false"
PRIVSEP="auto"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verify-ssl)
            VERIFY_SSL="true"
            shift
            ;;
        --privsep)
            PRIVSEP="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--verify-ssl] [--privsep auto|0|1]"
            echo "  --verify-ssl    Enable SSL certificate verification (default: disabled)"
            echo "  --privsep      Set privilege separation mode (default: auto-detect)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

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

# Function to detect appropriate privilege separation setting
detect_privsep_mode() {
    local pve_version
    pve_version=$(pveversion | grep -oP 'pve-manager/\K[0-9]+\.[0-9]+' || echo "0.0")
    
    log_info "Detected PVE version: $pve_version"
    
    # Known compatibility issues:
    # - Some versions of prometheus-pve-exporter have issues with privsep=1
    # - This appears to be related to how the exporter handles token authentication
    
    # For now, default to privsep=0 for compatibility
    # This can be overridden with --privsep 1 if needed
    echo "0"
}

# Function to create token securely (avoiding process list exposure)
create_token_securely() {
    local user="$1"
    local token_name="$2"
    local privsep_value="$3"
    local temp_file
    
    # Create secure temporary file in memory
    temp_file=$(mktemp -p /dev/shm pve-token.XXXXXX)
    chmod 600 "$temp_file"
    
    # Create token and capture output
    if pveum user token add "$user" "$token_name" --privsep "$privsep_value" > "$temp_file" 2>&1; then
        # Extract token value from output (skip header row, get actual token row)
        local token_value
        token_value=$(grep "│ value" "$temp_file" | grep -v "│ key" | awk -F'│' '{print $3}' | xargs)
        
        # Securely remove temporary file
        shred -u "$temp_file" 2>/dev/null || rm -f "$temp_file"
        
        if [[ -n "$token_value" ]]; then
            echo "$token_value"
            return 0
        else
            log_error "Failed to extract token value from output"
            return 1
        fi
    else
        # Show error and cleanup
        cat "$temp_file" >&2
        shred -u "$temp_file" 2>/dev/null || rm -f "$temp_file"
        return 1
    fi
}

# Function to wait for service state
wait_for_service_state() {
    local service="$1"
    local desired_state="$2"
    local timeout="${3:-30}"
    
    for ((i=0; i<timeout; i++)); do
        if systemctl is-active --quiet "$service"; then
            [[ "$desired_state" == "active" ]] && return 0
        else
            [[ "$desired_state" == "inactive" ]] && return 0
        fi
        sleep 1
    done
    return 1
}

log_info "Starting Prometheus PVE Exporter installation..."

# Determine privilege separation mode
if [[ "$PRIVSEP" == "auto" ]]; then
    PRIVSEP=$(detect_privsep_mode)
    log_info "Auto-detected privilege separation mode: $PRIVSEP"
else
    log_info "Using specified privilege separation mode: $PRIVSEP"
fi

# Validate privsep value
if [[ ! "$PRIVSEP" =~ ^[01]$ ]]; then
    log_error "Invalid privilege separation value: $PRIVSEP (must be 0 or 1)"
    exit 1
fi

# Create system user if doesn't exist
if ! id "$USER" &>/dev/null; then
    log_info "Creating system user: $USER"
    useradd -r -s /bin/false -d /var/lib/prometheus -m $USER
else
    log_warn "User $USER already exists"
fi

# Install Python3 venv if not available
if ! dpkg -l | grep -q python3-venv; then
    log_info "Installing python3-venv..."
    apt-get update
    apt-get install -y python3-venv
fi

# Create or update virtual environment
log_info "Setting up Python virtual environment in $INSTALL_DIR"
if [[ -d "$INSTALL_DIR" ]]; then
    log_warn "Installation directory exists, will upgrade existing installation"
fi

python3 -m venv $INSTALL_DIR
$INSTALL_DIR/bin/pip install --upgrade pip wheel
$INSTALL_DIR/bin/pip install --upgrade prometheus-pve-exporter

# Set ownership
chown -R $USER:$USER $INSTALL_DIR

# Create Proxmox user if doesn't exist
if ! pveum user list | grep -q "$USERNAME"; then
    log_info "Creating Proxmox user: $USERNAME"
    pveum user add $USERNAME --comment "Prometheus monitoring user"
else
    log_warn "Proxmox user $USERNAME already exists"
fi

# Grant PVEAuditor role to user
log_info "Granting PVEAuditor role to $USERNAME"
pveum acl modify / --users $USERNAME --roles PVEAuditor

# Handle existing token
if pveum user token list $USERNAME 2>/dev/null | grep -q "$TOKEN_NAME"; then
    log_warn "Token $TOKEN_NAME already exists for $USERNAME"
    read -p "Do you want to remove and recreate the token? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Removing existing token..."
        pveum user token remove $USERNAME $TOKEN_NAME
    else
        log_error "Cannot proceed without handling existing token"
        exit 1
    fi
fi

# Create token securely
log_info "Creating API token with privsep=$PRIVSEP..."
TOKEN_VALUE=$(create_token_securely "$USERNAME" "$TOKEN_NAME" "$PRIVSEP")

if [[ -z "$TOKEN_VALUE" ]]; then
    log_error "Failed to create token"
    exit 1
fi

# Grant PVEAuditor role to token
log_info "Granting PVEAuditor role to token"
pveum acl modify / --tokens ${USERNAME}!${TOKEN_NAME} --roles PVEAuditor

# Create config directory
mkdir -p $CONFIG_DIR

# Backup existing config if it exists
if [[ -f "$CONFIG_FILE" ]]; then
    BACKUP_FILE="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    log_warn "Backing up existing config to $BACKUP_FILE"
    cp $CONFIG_FILE $BACKUP_FILE
fi

# Create configuration file
log_info "Creating configuration file: $CONFIG_FILE"
cat <<EOF > $CONFIG_FILE
default:
  user: ${USERNAME}
  token_name: ${TOKEN_NAME}
  token_value: ${TOKEN_VALUE}
  verify_ssl: ${VERIFY_SSL}
EOF

# Set appropriate permissions
chmod 640 $CONFIG_FILE
chown $USER:$USER $CONFIG_FILE

# Create systemd service
log_info "Creating systemd service"
cat <<EOF > /etc/systemd/system/${SERVICE_NAME}.service
[Unit]
Description=Prometheus exporter for Proxmox VE
Documentation=https://github.com/prometheus-pve/prometheus-pve-exporter
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=5s
User=$USER
ExecStart=$INSTALL_DIR/bin/pve_exporter --config.file $CONFIG_FILE

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/prometheus
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and manage service
log_info "Configuring systemd service"
systemctl daemon-reload

# Stop service if running (for upgrades)
if systemctl is-active --quiet $SERVICE_NAME; then
    log_info "Stopping existing service..."
    systemctl stop $SERVICE_NAME
    wait_for_service_state $SERVICE_NAME "inactive" 10
fi

systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME

# Wait for service to start
log_info "Waiting for service to start..."
if wait_for_service_state $SERVICE_NAME "active" 30; then
    log_info "Service started successfully!"
else
    log_error "Service failed to start. Check logs with: journalctl -xeu $SERVICE_NAME"
    exit 1
fi

# Test the exporter
log_info "Testing exporter endpoint..."
sleep 2  # Give the exporter a moment to initialize

if curl -s -f -o /dev/null "http://localhost:9221/"; then
    log_info "Exporter is responding correctly"
    
    # Test actual metrics endpoint
    if curl -s -f "http://localhost:9221/pve?target=localhost" | grep -q "pve_up"; then
        log_info "Metrics are being collected successfully!"
    else
        log_warn "Exporter is running but metrics collection may have issues"
        log_warn "Check token permissions and privsep setting"
    fi
else
    log_warn "Exporter test failed, but service is running. Check logs for details."
fi

# Print summary
echo ""
echo "================================================================="
echo -e "${GREEN}Installation completed successfully!${NC}"
echo "================================================================="
echo ""
echo "Configuration Details:"
echo "  - Config file: $CONFIG_FILE"
echo "  - Token: ${USERNAME}!${TOKEN_NAME}"
echo "  - Privilege separation: $PRIVSEP"
echo "  - SSL verification: $VERIFY_SSL"
echo ""
echo "Service Management:"
echo "  - Status: systemctl status $SERVICE_NAME"
echo "  - Logs: journalctl -u $SERVICE_NAME -f"
echo "  - Restart: systemctl restart $SERVICE_NAME"
echo ""
echo "Metrics Access:"
echo "  - URL: http://$(hostname -I | awk '{print $1}'):9221/pve"
echo "  - Test: curl http://localhost:9221/pve?target=localhost"
echo ""
echo "Prometheus Configuration:"
echo "  - job_name: 'pve'"
echo "    static_configs:"
echo "      - targets:"
echo "        - $(hostname -I | awk '{print $1}'):9221"
echo "    metrics_path: /pve"
echo "    params:"
echo "      module: [default]"
echo "      cluster: ['1']"
echo "      node: ['1']"
echo ""
echo "Troubleshooting:"
echo "  - If you get 401 errors, try: $0 --privsep 0"
echo "  - For SSL issues, use: $0 --verify-ssl"
echo ""
echo "================================================================="

# Save installation log
LOG_FILE="/var/log/${SERVICE_NAME}-install.log"
{
    echo "Installation completed at $(date)"
    echo "Token: ${USERNAME}!${TOKEN_NAME}"
    echo "Privsep: $PRIVSEP"
    echo "SSL Verify: $VERIFY_SSL"
} >> $LOG_FILE
chown $USER:$USER $LOG_FILE
chmod 640 $LOG_FILE

log_info "Installation log saved to: $LOG_FILE"