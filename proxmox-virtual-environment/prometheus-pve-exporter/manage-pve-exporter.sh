#!/bin/bash
#
# Prometheus PVE Exporter Management Script
#
# This script provides maintenance functions for the prometheus-pve-exporter,
# including token recreation, service management, and troubleshooting.
#
# Usage:
#   ./manage-pve-exporter.sh [command] [options]
#
# Commands:
#   status          Show service and token status
#   recreate-token  Recreate the API token
#   test            Test the exporter functionality
#   logs            Show recent service logs
#   restart         Restart the service
#

set -euo pipefail

# Configuration
USER="prometheus"
USERNAME="prometheus@pve"
TOKEN_NAME="monitoring"
CONFIG_FILE="/etc/prometheus/pve.yml"
SERVICE_NAME="prometheus-pve-exporter"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
       log_error "This script must be run as root"
       exit 1
    fi
}

# Check for required commands
check_requirements() {
    local missing_cmds=()
    
    # Check for curl (required for testing)
    if ! command -v curl &>/dev/null; then
        missing_cmds+=("curl")
    fi
    
    # Check for pveum (required for token management)
    if ! command -v pveum &>/dev/null; then
        missing_cmds+=("pveum (Proxmox VE)")
    fi
    
    if [[ ${#missing_cmds[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing_cmds[*]}"
        log_error "Please install the missing dependencies"
        exit 1
    fi
}

# Function to create token securely
create_token_securely() {
    local user="$1"
    local token_name="$2"
    local privsep_value="$3"
    local temp_file
    
    temp_file=$(mktemp -p /dev/shm pve-token.XXXXXX)
    chmod 600 "$temp_file"
    
    if pveum user token add "$user" "$token_name" --privsep "$privsep_value" > "$temp_file" 2>&1; then
        local token_value
        token_value=$(grep "│ value" "$temp_file" | grep -v "│ key" | awk -F'│' '{print $3}' | xargs)
        shred -u "$temp_file" 2>/dev/null || rm -f "$temp_file"
        
        if [[ -n "$token_value" ]]; then
            echo "$token_value"
            return 0
        else
            return 1
        fi
    else
        cat "$temp_file" >&2
        shred -u "$temp_file" 2>/dev/null || rm -f "$temp_file"
        return 1
    fi
}

# Function to show status
show_status() {
    echo "========================================="
    echo "Prometheus PVE Exporter Status"
    echo "========================================="
    echo ""
    
    # Service status
    echo "Service Status:"
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "  ${GREEN}● Service is running${NC}"
        echo "  PID: $(systemctl show -p MainPID --value $SERVICE_NAME)"
        
        # Show memory if numfmt is available
        local mem_value
        mem_value=$(systemctl show -p MemoryCurrent --value $SERVICE_NAME)
        if [[ -n "$mem_value" ]] && [[ "$mem_value" != "[not set]" ]] && command -v numfmt &>/dev/null; then
            echo "  Memory: $(echo "$mem_value" | numfmt --to=iec-i --suffix=B 2>/dev/null || echo "$mem_value bytes")"
        fi
    else
        echo -e "  ${RED}● Service is not running${NC}"
    fi
    echo ""
    
    # Token status
    echo "Token Information:"
    if pveum user token list $USERNAME 2>/dev/null | grep -q "$TOKEN_NAME"; then
        echo -e "  ${GREEN}✓ Token exists${NC}: ${USERNAME}!${TOKEN_NAME}"
        
        # Check token permissions
        local token_perms
        token_perms=$(pveum acl list --path / | grep "${USERNAME}!${TOKEN_NAME}" || true)
        if [[ -n "$token_perms" ]]; then
            echo "  Permissions: Found at /"
        else
            echo -e "  ${YELLOW}⚠ No permissions found${NC}"
        fi
    else
        echo -e "  ${RED}✗ Token does not exist${NC}"
    fi
    echo ""
    
    # Config file status
    echo "Configuration:"
    if [[ -f "$CONFIG_FILE" ]]; then
        echo -e "  ${GREEN}✓ Config file exists${NC}: $CONFIG_FILE"
        local verify_ssl
        verify_ssl=$(grep "verify_ssl:" "$CONFIG_FILE" | awk '{print $2}')
        echo "  SSL Verification: $verify_ssl"
    else
        echo -e "  ${RED}✗ Config file missing${NC}"
    fi
    echo ""
    
    # Test endpoint
    echo "Endpoint Test:"
    if curl -s -f -o /dev/null --connect-timeout 5 --max-time 10 "http://localhost:9221/"; then
        echo -e "  ${GREEN}✓ Base endpoint responding${NC}"
        
        # Test metrics
        if curl -s -f --connect-timeout 5 --max-time 10 "http://localhost:9221/pve?target=localhost" | grep -q "pve_up"; then
            echo -e "  ${GREEN}✓ Metrics collection working${NC}"
        else
            echo -e "  ${RED}✗ Metrics collection failing${NC}"
            echo "    Check token authentication"
        fi
    else
        echo -e "  ${RED}✗ Endpoint not responding${NC}"
    fi
    echo ""
}

# Function to recreate token
recreate_token() {
    check_root
    
    local privsep="${1:-0}"
    
    # Validate privsep value
    if [[ ! "$privsep" =~ ^[01]$ ]]; then
        log_error "Invalid privilege separation value: $privsep (must be 0 or 1)"
        return 1
    fi
    
    log_info "Recreating token for $USERNAME"
    
    # Stop service
    log_info "Stopping service..."
    systemctl stop $SERVICE_NAME
    
    # Remove existing token if exists
    if pveum user token list $USERNAME 2>/dev/null | grep -q "$TOKEN_NAME"; then
        log_info "Removing existing token..."
        pveum user token remove $USERNAME $TOKEN_NAME
    fi
    
    # Create new token
    log_info "Creating new token with privsep=$privsep..."
    local token_value
    token_value=$(create_token_securely "$USERNAME" "$TOKEN_NAME" "$privsep")
    
    if [[ -z "$token_value" ]]; then
        log_error "Failed to create token"
        return 1
    fi
    
    # Grant permissions
    log_info "Granting PVEAuditor role to token..."
    pveum acl modify / --tokens ${USERNAME}!${TOKEN_NAME} --roles PVEAuditor
    
    # Update config file
    log_info "Updating configuration..."
    if [[ -f "$CONFIG_FILE" ]]; then
        # Backup current config
        cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Update token value in config (use | as delimiter to avoid issues with / in token)
        sed -i "s|token_value:.*|token_value: ${token_value}|" "$CONFIG_FILE"
    else
        log_error "Config file not found: $CONFIG_FILE"
        return 1
    fi
    
    # Start service
    log_info "Starting service..."
    systemctl start $SERVICE_NAME
    
    # Wait and test
    sleep 3
    if systemctl is-active --quiet $SERVICE_NAME; then
        log_info "Service restarted successfully"
        
        # Test metrics
        if curl -s -f --connect-timeout 5 --max-time 10 "http://localhost:9221/pve?target=localhost" | grep -q "pve_up"; then
            log_info "Token recreation successful! Metrics are working."
        else
            log_warn "Service is running but metrics may have issues"
            log_warn "Try with different privsep setting: $0 recreate-token 1"
        fi
    else
        log_error "Service failed to start"
        return 1
    fi
}

# Function to test exporter
test_exporter() {
    echo "========================================="
    echo "Testing Prometheus PVE Exporter"
    echo "========================================="
    echo ""
    
    # Test base endpoint
    log_info "Testing base endpoint..."
    if curl -s -f --connect-timeout 5 --max-time 10 "http://localhost:9221/" | head -5; then
        echo -e "\n${GREEN}✓ Base endpoint OK${NC}\n"
    else
        echo -e "\n${RED}✗ Base endpoint failed${NC}\n"
        return 1
    fi
    
    # Test metrics endpoint
    log_info "Testing metrics endpoint..."
    local metrics_output
    metrics_output=$(curl -s --connect-timeout 5 --max-time 10 "http://localhost:9221/pve?target=localhost" 2>&1)
    
    if echo "$metrics_output" | grep -q "pve_up"; then
        echo -e "${GREEN}✓ Metrics collection working${NC}"
        echo ""
        echo "Sample metrics:"
        echo "$metrics_output" | grep -E "^(pve_up|pve_version_info|pve_node_info)" | head -10
    else
        echo -e "${RED}✗ Metrics collection failed${NC}"
        echo ""
        echo "Response:"
        echo "$metrics_output" | head -20
        
        # Check for common errors
        if echo "$metrics_output" | grep -q "401"; then
            echo ""
            log_error "Authentication error detected (401)"
            log_info "Try recreating token: $0 recreate-token"
        fi
    fi
    echo ""
}

# Function to show logs
show_logs() {
    local lines="${1:-50}"
    
    echo "========================================="
    echo "Recent Service Logs (last $lines lines)"
    echo "========================================="
    echo ""
    
    journalctl -u $SERVICE_NAME -n "$lines" --no-pager
}

# Function to restart service
restart_service() {
    check_root
    
    log_info "Restarting $SERVICE_NAME..."
    systemctl restart $SERVICE_NAME
    
    sleep 2
    if systemctl is-active --quiet $SERVICE_NAME; then
        log_info "Service restarted successfully"
    else
        log_error "Service failed to restart"
        log_info "Check logs: journalctl -xeu $SERVICE_NAME"
        return 1
    fi
}

# Show usage
usage() {
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  status                    Show service and token status"
    echo "  recreate-token [privsep]  Recreate API token (privsep: 0 or 1, default: 0)"
    echo "  test                      Test exporter functionality"
    echo "  logs [lines]              Show service logs (default: 50 lines)"
    echo "  restart                   Restart the service"
    echo "  help                      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 status"
    echo "  $0 recreate-token 0      # Recreate token without privilege separation"
    echo "  $0 recreate-token 1      # Recreate token with privilege separation"
    echo "  $0 logs 100"
    echo ""
}

# Main command handling
case "${1:-help}" in
    status)
        check_requirements
        show_status
        ;;
    recreate-token)
        check_requirements
        recreate_token "${2:-0}"
        ;;
    test)
        check_requirements
        test_exporter
        ;;
    logs)
        show_logs "${2:-50}"
        ;;
    restart)
        restart_service
        ;;
    help|-h|--help)
        usage
        ;;
    *)
        log_error "Unknown command: $1"
        usage
        exit 1
        ;;
esac