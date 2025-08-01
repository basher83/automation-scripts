#!/bin/bash

# Script Name: install-netdata-child.sh
# Purpose: Installs and configures Netdata as a child node streaming to parent nodes
# Version: 1.0
# 
# Usage:
#   ./install-netdata-child.sh [OPTIONS]
#
# Options:
#   --parents IPS       Comma-separated list of parent IPs (required)
#   --api-key KEY      API key for parent connection (required)
#   --hostname NAME    Set the hostname for this child (default: current hostname)
#   --thin-mode        Enable thin mode (minimal resources, no local DB)
#   --consul           Enable Consul monitoring
#   --docker           Enable Docker monitoring
#   --non-interactive  Run without prompts
#   --help, -h         Show this help message
#
# Requirements:
#   - Ubuntu/Debian system
#   - Root or sudo access
#   - Network connectivity to parent nodes
#
# Examples:
#   # Interactive installation (using 10G network for parents)
#   sudo ./install-netdata-child.sh --parents "192.168.11.2,192.168.11.3,192.168.11.4" --api-key "your-api-key"
#
#   # Thin mode with Consul monitoring
#   sudo ./install-netdata-child.sh --parents "192.168.11.2,192.168.11.3,192.168.11.4" --api-key "key" --thin-mode --consul

set -euo pipefail
trap 'echo "Error occurred at line $LINENO. Exit code: $?" >&2' ERR

# Constants
readonly SERVICE_NAME="netdata"
readonly LOG_FILE="/var/log/${SERVICE_NAME}-child-install.log"
readonly CONFIG_DIR="/etc/netdata"
readonly STREAM_CONF="${CONFIG_DIR}/stream.conf"
readonly NETDATA_CONF="${CONFIG_DIR}/netdata.conf"
readonly CONSUL_CONF="${CONFIG_DIR}/go.d/consul.conf"

# Default values
PARENT_IPS=""
API_KEY=""
HOSTNAME="${HOSTNAME:-$(hostname)}"
THIN_MODE=false
ENABLE_CONSUL=false
ENABLE_DOCKER=false
INTERACTIVE=true

# Non-interactive mode support
if [[ ! -t 0 ]] || [[ "${NON_INTERACTIVE:-}" == "true" ]] || [[ "$*" == *"--non-interactive"* ]]; then
    INTERACTIVE=false
fi

# Color codes for output
if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]] && [[ -z "${NO_COLOR:-}" ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly CYAN='\033[0;36m'
    readonly NC='\033[0m' # No Color
    readonly BOLD='\033[1m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly CYAN=''
    readonly NC=''
    readonly BOLD=''
fi

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE"
}

print_header() {
    echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}\n"
}

# Show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Install and configure Netdata as a child node streaming to parent nodes

Options:
    --parents IPS       Comma-separated list of parent IPs (required)
    --api-key KEY      API key for parent connection (required)
    --hostname NAME    Set the hostname for this child (default: current hostname)
    --thin-mode        Enable thin mode (minimal resources, no local DB)
    --consul           Enable Consul monitoring
    --docker           Enable Docker monitoring
    --non-interactive  Run without prompts
    --help, -h         Show this help message

Examples:
    # Basic installation (using 10G network)
    sudo $0 --parents "192.168.11.2,192.168.11.3,192.168.11.4" --api-key "nomad-cluster-api-key"

    # Thin mode with service monitoring
    sudo $0 --parents "192.168.11.2,192.168.11.3,192.168.11.4" --api-key "key" --thin-mode --consul --docker

EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --parents)
                PARENT_IPS="$2"
                shift 2
                ;;
            --api-key)
                API_KEY="$2"
                shift 2
                ;;
            --hostname)
                HOSTNAME="$2"
                shift 2
                ;;
            --thin-mode)
                THIN_MODE=true
                shift
                ;;
            --consul)
                ENABLE_CONSUL=true
                shift
                ;;
            --docker)
                ENABLE_DOCKER=true
                shift
                ;;
            --non-interactive)
                INTERACTIVE=false
                shift
                ;;
            --help|-h)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "$PARENT_IPS" ]]; then
        log_error "Parent IPs are required (--parents)"
        usage
    fi
    
    if [[ -z "$API_KEY" ]]; then
        log_error "API key is required (--api-key)"
        usage
    fi
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Check OS
    if [[ ! -f /etc/debian_version ]]; then
        log_error "This script is designed for Debian/Ubuntu systems only"
        exit 1
    fi
    
    # Test connectivity to parent nodes
    local parent_array=(${PARENT_IPS//,/ })
    for parent in "${parent_array[@]}"; do
        if ! ping -c 1 -W 2 "$parent" &>/dev/null; then
            log_warn "Cannot reach parent node: $parent"
        else
            log_info "Successfully pinged parent: $parent"
        fi
    done
    
    log_info "Prerequisites check completed"
}

# Install Netdata
install_netdata() {
    print_header "Installing Netdata"
    
    if systemctl is-active --quiet netdata 2>/dev/null; then
        log_warn "Netdata is already installed and running"
        return 0
    fi
    
    log_info "Installing Netdata using official installer..."
    
    # Download and run the official installer
    if command -v curl &>/dev/null; then
        curl -s https://get.netdata.cloud/kickstart.sh > /tmp/netdata-kickstart.sh
    else
        wget -qO /tmp/netdata-kickstart.sh https://get.netdata.cloud/kickstart.sh
    fi
    
    # Make it executable and run
    chmod +x /tmp/netdata-kickstart.sh
    bash /tmp/netdata-kickstart.sh --dont-wait --stable-channel
    
    # Clean up
    rm -f /tmp/netdata-kickstart.sh
    
    log_info "Netdata installation completed"
}

# Configure stream.conf for child node
configure_streaming() {
    print_header "Configuring Streaming to Parents"
    
    # Backup existing configuration
    if [[ -f "$STREAM_CONF" ]]; then
        cp "$STREAM_CONF" "${STREAM_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Backed up existing stream.conf"
    fi
    
    # Convert comma-separated IPs to space-separated with ports
    local destinations=""
    local parent_array=(${PARENT_IPS//,/ })
    for parent in "${parent_array[@]}"; do
        destinations="${destinations}${parent}:19999 "
    done
    destinations="${destinations% }" # Remove trailing space
    
    # Create stream.conf
    cat > "$STREAM_CONF" << EOF
# Netdata Child Node Streaming Configuration
# Generated by install-netdata-child.sh on $(date)

[stream]
    enabled = yes
    destination = $destinations
    api key = $API_KEY
    timeout seconds = 60
    buffer size bytes = 1048576
    reconnect delay seconds = 5
    initial clock resync iterations = 60
    
    # Send everything to parents
    send charts matching = *
EOF

    # Add thin mode configuration if enabled
    if [[ "$THIN_MODE" == "true" ]]; then
        cat >> "$STREAM_CONF" << EOF
    
    # Thin mode configuration
    mode = ram
    health enabled = auto
EOF
    fi
    
    log_info "Streaming configuration completed"
    log_info "Configured to stream to: $destinations"
}

# Configure netdata.conf for child node
configure_netdata() {
    print_header "Configuring Netdata Settings"
    
    # Backup existing configuration
    if [[ -f "$NETDATA_CONF" ]]; then
        cp "$NETDATA_CONF" "${NETDATA_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Base configuration
    cat > "$NETDATA_CONF" << EOF
# Netdata Child Node Configuration
# Generated by install-netdata-child.sh on $(date)

[global]
    hostname = $HOSTNAME
    
[web]
    bind to = *
EOF

    # Add thin mode configuration if enabled
    if [[ "$THIN_MODE" == "true" ]]; then
        cat >> "$NETDATA_CONF" << EOF

# Thin mode configuration - minimal resource usage
[db]
    mode = ram
    retention = 300
    
[ml]
    enabled = no
    
[health]
    enabled = no
EOF
    else
        cat >> "$NETDATA_CONF" << EOF

# Standard child configuration
[db]
    mode = dbengine
    storage tiers = 1
    dbengine tier 0 retention days = 1
    
[ml]
    enabled = yes
    
[health]
    enabled = yes
EOF
    fi
    
    log_info "Netdata configuration completed"
}

# Configure Consul monitoring
configure_consul() {
    if [[ "$ENABLE_CONSUL" != "true" ]]; then
        return 0
    fi
    
    print_header "Configuring Consul Monitoring"
    
    # Check if Consul is running
    if ! systemctl is-active --quiet consul 2>/dev/null; then
        log_warn "Consul service not found, skipping Consul configuration"
        return 0
    fi
    
    # Create Consul configuration
    mkdir -p "${CONFIG_DIR}/go.d"
    cat > "$CONSUL_CONF" << EOF
# Consul monitoring configuration
# Generated by install-netdata-child.sh on $(date)

jobs:
  - name: consul_local
    url: 'http://127.0.0.1:8500/v1/agent/metrics?format=prometheus'
    # If Consul requires authentication, add:
    # username: 'your_username'
    # password: 'your_password'
EOF
    
    log_info "Consul monitoring configured"
}

# Configure Docker monitoring
configure_docker() {
    if [[ "$ENABLE_DOCKER" != "true" ]]; then
        return 0
    fi
    
    print_header "Configuring Docker Monitoring"
    
    # Check if Docker is installed
    if ! command -v docker &>/dev/null; then
        log_warn "Docker not found, skipping Docker configuration"
        return 0
    fi
    
    # Add netdata user to docker group
    if getent group docker &>/dev/null; then
        usermod -a -G docker netdata
        log_info "Added netdata user to docker group"
    fi
    
    # Enable Docker plugin
    if [[ -f "${CONFIG_DIR}/go.d.conf" ]]; then
        sed -i 's/# docker:/docker:/' "${CONFIG_DIR}/go.d.conf"
        log_info "Docker monitoring enabled"
    fi
}

# Restart Netdata service
restart_netdata() {
    print_header "Restarting Netdata"
    
    log_info "Restarting Netdata service..."
    systemctl restart netdata
    
    # Wait for service to start
    sleep 5
    
    if systemctl is-active --quiet netdata; then
        log_info "Netdata service restarted successfully"
    else
        log_error "Failed to restart Netdata service"
        systemctl status netdata
        exit 1
    fi
}

# Verify streaming connection
verify_streaming() {
    print_header "Verifying Streaming Connection"
    
    log_info "Waiting for streaming connection to establish..."
    sleep 10
    
    # Check logs for successful connection
    if grep -q "established communication" /var/log/netdata/error.log 2>/dev/null; then
        log_info "Streaming connection established successfully"
        
        # Show connection details
        grep "established communication" /var/log/netdata/error.log | tail -1
    else
        log_warn "Could not verify streaming connection"
        log_info "Check /var/log/netdata/error.log for details"
    fi
}

# Display summary
display_summary() {
    print_header "Installation Summary"
    
    echo -e "${GREEN}Netdata Child Node Configuration:${NC}"
    echo -e "  Hostname: ${BOLD}$HOSTNAME${NC}"
    echo -e "  Parent Nodes: ${BOLD}$PARENT_IPS${NC}"
    echo -e "  API Key: ${BOLD}$API_KEY${NC}"
    echo -e "  Mode: ${BOLD}$([ "$THIN_MODE" == "true" ] && echo "Thin" || echo "Standard")${NC}"
    
    if [[ "$ENABLE_CONSUL" == "true" ]]; then
        echo -e "  Consul Monitoring: ${BOLD}Enabled${NC}"
    fi
    
    if [[ "$ENABLE_DOCKER" == "true" ]]; then
        echo -e "  Docker Monitoring: ${BOLD}Enabled${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}Next Steps:${NC}"
    echo "1. Verify streaming connection in parent dashboard"
    echo "2. Check local dashboard (if not in thin mode):"
    echo "   - http://$(hostname -I | awk '{print $1}'):19999"
    echo "3. Monitor logs for any issues:"
    echo "   - /var/log/netdata/error.log"
    echo ""
    
    # Save configuration summary
    cat > "${CONFIG_DIR}/child-config-summary.txt" << EOF
Netdata Child Configuration Summary
Generated: $(date)

Hostname: $HOSTNAME
Parent Nodes: $PARENT_IPS
API Key: $API_KEY
Mode: $([ "$THIN_MODE" == "true" ] && echo "Thin" || echo "Standard")
Consul Monitoring: $([ "$ENABLE_CONSUL" == "true" ] && echo "Enabled" || echo "Disabled")
Docker Monitoring: $([ "$ENABLE_DOCKER" == "true" ] && echo "Enabled" || echo "Disabled")
EOF
    
    log_info "Configuration summary saved to: ${CONFIG_DIR}/child-config-summary.txt"
    log_info "Installation log saved to: $LOG_FILE"
}

# Main execution
main() {
    # Set up logging
    echo "Installation started at $(date)" > "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    
    parse_args "$@"
    
    echo -e "${BOLD}${CYAN}Netdata Child Node Installation${NC}"
    echo -e "${CYAN}================================${NC}"
    
    check_prerequisites
    install_netdata
    configure_streaming
    configure_netdata
    configure_consul
    configure_docker
    restart_netdata
    verify_streaming
    display_summary
    
    echo "Installation completed at $(date)" >> "$LOG_FILE"
}

# Run main function
main "$@"