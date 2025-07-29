#!/bin/bash

# Prometheus PVE Exporter Uninstall Script
# Safely removes prometheus-pve-exporter and related components
# 
# Usage:
#   ./uninstall-pve-exporter.sh [--force]
#
# Options:
#   --force    Skip confirmation prompts

set -euo pipefail
trap 'echo "Error occurred at line $LINENO. Exit code: $?" >&2' ERR

# Configuration
readonly SERVICE_NAME="prometheus-pve-exporter"
readonly USER="prometheus"
readonly PVE_USERNAME="prometheus@pve"
readonly INSTALL_DIR="/opt/prometheus-pve-exporter"
readonly CONFIG_DIR="/etc/prometheus"
readonly USER_HOME="/var/lib/prometheus"

# Parse arguments
FORCE_MODE=false
if [[ "${1:-}" == "--force" ]]; then
    FORCE_MODE=true
fi

# Colors for output (check if terminal supports colors)
if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]] && [[ -z "${NO_COLOR:-}" ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly NC='\033[0m' # No Color
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly NC=''
fi

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

# Function to check if a systemd service exists
service_exists() {
    systemctl list-unit-files | grep -q "^${1}.service"
}

# Function to check if a user exists
user_exists() {
    id "$1" &>/dev/null
}

# Function to check if PVE user exists
pve_user_exists() {
    command -v pveum &> /dev/null && pveum user list | grep -q "$1"
}

# Confirmation prompt
if [[ "$FORCE_MODE" != "true" ]] && [[ -t 0 ]]; then
    echo -e "${YELLOW}Warning: This will remove prometheus-pve-exporter and all related data${NC}"
    echo
    echo "Components to be removed:"
    
    if service_exists "$SERVICE_NAME"; then
        echo "  ✓ Systemd service: $SERVICE_NAME"
    fi
    
    if [[ -d "$INSTALL_DIR" ]]; then
        echo "  ✓ Installation directory: $INSTALL_DIR"
    fi
    
    if [[ -d "$CONFIG_DIR" ]]; then
        echo "  ✓ Configuration directory: $CONFIG_DIR"
    fi
    
    if user_exists "$USER"; then
        echo "  ✓ System user: $USER"
    fi
    
    if [[ -d "$USER_HOME" ]]; then
        echo "  ✓ User home directory: $USER_HOME"
    fi
    
    if pve_user_exists "$PVE_USERNAME"; then
        echo "  ✓ Proxmox VE user: $PVE_USERNAME"
    fi
    
    echo
    read -p "Are you sure you want to continue? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Uninstall cancelled"
        exit 0
    fi
fi

log_info "Starting uninstallation of prometheus-pve-exporter..."

# Stop and disable service
if service_exists "$SERVICE_NAME"; then
    log_info "Stopping and disabling service..."
    
    # Stop service if running
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        systemctl stop "$SERVICE_NAME" || log_warn "Failed to stop service"
    else
        log_info "Service is not running"
    fi
    
    # Disable service if enabled
    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl disable "$SERVICE_NAME" || log_warn "Failed to disable service"
    else
        log_info "Service is not enabled"
    fi
    
    # Remove service file
    if [[ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
        rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
        systemctl daemon-reload
        log_info "Service removed"
    fi
else
    log_warn "Service $SERVICE_NAME not found"
fi

# Remove installation directory
if [[ -d "$INSTALL_DIR" ]]; then
    log_info "Removing installation directory..."
    rm -rf "$INSTALL_DIR"
    log_info "Installation directory removed"
else
    log_warn "Installation directory $INSTALL_DIR not found"
fi

# Remove Proxmox VE user
if pve_user_exists "$PVE_USERNAME"; then
    log_info "Removing Proxmox VE user..."
    pveum user delete "$PVE_USERNAME" || log_warn "Failed to remove PVE user"
    log_info "Proxmox VE user removed"
else
    log_warn "Proxmox VE user $PVE_USERNAME not found"
fi

# Remove system user (after removing files owned by the user)
if user_exists "$USER"; then
    log_info "Removing system user..."
    
    # Kill any processes owned by the user
    pkill -u "$USER" 2>/dev/null || true
    
    # Remove user
    userdel "$USER" || log_warn "Failed to remove user"
    log_info "System user removed"
else
    log_warn "System user $USER not found"
fi

# Remove user home directory (if it still exists after userdel)
if [[ -d "$USER_HOME" ]]; then
    log_info "Removing user home directory..."
    rm -rf "$USER_HOME"
    log_info "User home directory removed"
fi

# Remove configuration directory
if [[ -d "$CONFIG_DIR" ]]; then
    log_info "Removing configuration directory..."
    rm -rf "$CONFIG_DIR"
    log_info "Configuration directory removed"
else
    log_warn "Configuration directory $CONFIG_DIR not found"
fi

# Create uninstall log
LOG_DIR="/var/log"
LOG_FILE="${LOG_DIR}/${SERVICE_NAME}-uninstall.log"
{
    echo "Uninstallation completed at $(date)"
    echo "Uninstalled by: $(whoami)"
    echo "Components removed:"
    echo "  - Service: $SERVICE_NAME"
    echo "  - Installation: $INSTALL_DIR"
    echo "  - Configuration: $CONFIG_DIR"
    echo "  - System user: $USER"
    echo "  - PVE user: $PVE_USERNAME"
} >> "$LOG_FILE"
chmod 640 "$LOG_FILE"

log_info "✅ Prometheus PVE Exporter has been successfully removed"
log_info "Uninstall log saved to: $LOG_FILE"