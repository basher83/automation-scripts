#!/bin/bash
#
# Prometheus PVE Exporter Bootstrap Script
# 
# This script installs and configures prometheus-pve-exporter on a Proxmox host
# using a Python virtual environment for production stability.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/install-pve-exporter.sh | bash
#   or
#   wget -qO- https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/install-pve-exporter.sh | bash
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

log_info "Starting Prometheus PVE Exporter installation..."

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

# Check if token already exists
if pveum user token list $USERNAME 2>/dev/null | grep -q "$TOKEN_NAME"; then
    log_warn "Token $TOKEN_NAME already exists for $USERNAME"
    log_warn "To use a new token, please manually remove the old one with:"
    log_warn "  pveum user token remove $USERNAME $TOKEN_NAME"
    log_error "Exiting to prevent token conflicts"
    exit 1
fi

# Create token with privilege separation
log_info "Creating API token..."
TOKEN_OUTPUT=$(pveum user token add $USERNAME $TOKEN_NAME --privsep 1)

# Extract the token value
TOKEN_VALUE=$(echo "$TOKEN_OUTPUT" | grep "│ value" | awk -F'│' '{print $3}' | xargs)

if [[ -z "$TOKEN_VALUE" ]]; then
    log_error "Failed to extract token value"
    echo "$TOKEN_OUTPUT"
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
  verify_ssl: false
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
fi

systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME

# Wait a moment for service to start
sleep 2

# Check service status
if systemctl is-active --quiet $SERVICE_NAME; then
    log_info "Service started successfully!"
else
    log_error "Service failed to start. Check logs with: journalctl -xeu $SERVICE_NAME"
    exit 1
fi

# Test the exporter
log_info "Testing exporter endpoint..."
if curl -s -f -o /dev/null "http://localhost:9221/"; then
    log_info "Exporter is responding correctly"
else
    log_warn "Exporter test failed, but service is running. It may need a moment to initialize."
fi

# Print summary
echo ""
echo "================================================================="
echo -e "${GREEN}Installation completed successfully!${NC}"
echo "================================================================="
echo ""
echo "Token information has been saved to: $CONFIG_FILE"
echo ""
echo "Service status: systemctl status $SERVICE_NAME"
echo "Service logs:   journalctl -u $SERVICE_NAME -f"
echo ""
echo "Metrics URL:    http://$(hostname -I | awk '{print $1}'):9221/pve"
echo "Local test:     curl http://localhost:9221/pve?target=localhost"
echo ""
echo "To configure Prometheus, add this to your prometheus.yml:"
echo ""
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
echo "================================================================="

# Save installation log
LOG_FILE="/var/log/${SERVICE_NAME}-install.log"
echo "Installation completed at $(date)" >> $LOG_FILE
echo "Token: ${USERNAME}!${TOKEN_NAME}" >> $LOG_FILE
chown $USER:$USER $LOG_FILE
chmod 640 $LOG_FILE

log_info "Installation log saved to: $LOG_FILE"