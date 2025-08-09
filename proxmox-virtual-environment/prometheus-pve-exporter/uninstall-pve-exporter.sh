#!/bin/bash

# Prometheus PVE Exporter Uninstall Script
# Safely removes prometheus-pve-exporter and related components
# 
# Usage:
#   ./uninstall-pve-exporter.sh [OPTIONS]
#
# Options:
#   --force    Skip confirmation prompts
#   --backup   Backup configuration before removal
#   --help     Show help message

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
BACKUP_CONFIG=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_MODE=true
            shift
            ;;
        --backup)
            BACKUP_CONFIG=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force    Skip confirmation prompts"
            echo "  --backup   Backup configuration before removal"
            echo "  --help     Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

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

# Check if exporter is currently responding (might be manually installed)
if command -v curl &>/dev/null && curl -s -f -o /dev/null --connect-timeout 2 --max-time 5 "http://localhost:9221/" 2>/dev/null; then
    log_warn "PVE exporter appears to be running on port 9221"
    log_info "Will attempt to stop it during uninstallation"
fi

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

# Remove Proxmox VE user and associated tokens/ACLs
if pve_user_exists "$PVE_USERNAME"; then
    log_info "Removing Proxmox VE user and permissions..."
    
    # First remove any ACL entries for this user
    log_info "Cleaning up ACL entries..."
    pveum acl delete / --users "$PVE_USERNAME" 2>/dev/null || true
    pveum acl delete / --tokens "${PVE_USERNAME}!monitoring" 2>/dev/null || true
    
    # Then remove the user (this also removes associated tokens)
    pveum user delete "$PVE_USERNAME" || log_warn "Failed to remove PVE user"
    log_info "Proxmox VE user and permissions removed"
else
    log_warn "Proxmox VE user $PVE_USERNAME not found"
fi

# Remove system user (after removing files owned by the user)
if user_exists "$USER"; then
    log_info "Removing system user..."
    
    # Kill any processes owned by the user gracefully
    if pgrep -u "$USER" > /dev/null 2>&1; then
        log_info "Stopping processes owned by $USER..."
        pkill -TERM -u "$USER" 2>/dev/null || true
        sleep 2
        # Force kill if still running
        pkill -KILL -u "$USER" 2>/dev/null || true
    fi
    
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

# Handle configuration backup if requested
if [[ "$BACKUP_CONFIG" == "true" ]] && [[ -f "$CONFIG_DIR/pve.yml" ]]; then
    BACKUP_DIR="/root/pve-exporter-backup-$(date +%Y%m%d_%H%M%S)"
    log_info "Creating backup of configuration..."
    mkdir -p "$BACKUP_DIR"
    cp "$CONFIG_DIR/pve.yml" "$BACKUP_DIR/"
    cp "$CONFIG_DIR/pve.yml.backup"* "$BACKUP_DIR/" 2>/dev/null || true
    log_info "Configuration backed up to: $BACKUP_DIR"
fi

# Remove PVE exporter configuration (be careful not to remove other Prometheus configs)
if [[ -d "$CONFIG_DIR" ]]; then
    log_info "Removing PVE exporter configuration..."
    
    # Remove only PVE-specific files
    pve_files=(
        "$CONFIG_DIR/pve.yml"
        "$CONFIG_DIR/pve.yml.backup"*
    )
    
    for file in "${pve_files[@]}"; do
        if [[ -e "$file" ]]; then
            rm -f "$file"
            log_info "Removed: $(basename "$file")"
        fi
    done
    
    # Remove directory only if empty
    if [[ -z "$(ls -A "$CONFIG_DIR" 2>/dev/null)" ]]; then
        rmdir "$CONFIG_DIR"
        log_info "Configuration directory removed (was empty)"
    else
        log_info "Configuration directory kept (contains other files)"
    fi
else
    log_warn "Configuration directory $CONFIG_DIR not found"
fi

# Create uninstall log with proper permissions
LOG_DIR="/var/log"
LOG_FILE="${LOG_DIR}/${SERVICE_NAME}-uninstall-$(date +%Y%m%d_%H%M%S).log"

# Create log file with correct permissions first
touch "$LOG_FILE"
chmod 640 "$LOG_FILE"

{
    echo "Uninstallation completed at $(date)"
    echo "Uninstalled by: $(whoami)"
    echo "Components removed:"
    echo "  - Service: $SERVICE_NAME"
    echo "  - Installation: $INSTALL_DIR"
    echo "  - Configuration: $CONFIG_DIR/pve.yml"
    echo "  - System user: $USER"
    echo "  - PVE user: $PVE_USERNAME"
    echo "  - ACL permissions for $PVE_USERNAME"
} >> "$LOG_FILE"

log_info "✅ Prometheus PVE Exporter has been successfully removed"
log_info "Uninstall log saved to: $LOG_FILE"