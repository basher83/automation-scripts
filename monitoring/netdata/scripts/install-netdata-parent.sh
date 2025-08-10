#!/bin/bash

# Script Name: install-netdata-parent.sh
# Purpose: Installs and configures Netdata as a parent node for streaming architecture
# Version: 1.0
#
# Usage:
#   ./install-netdata-parent.sh [OPTIONS]
#
# Options:
#   --hostname NAME      Set the hostname for this parent (default: current hostname)
#   --api-key KEY       Set the API key for child connections (default: generate new)
#   --replication-key   Set the API key for parent replication (default: generate new)
#   --peers IPS         Comma-separated list of peer parent IPs for replication
#   --children IPS      Comma-separated list of allowed child IPs
#   --retention DAYS    Set data retention in days (default: 30)
#   --non-interactive   Run without prompts
#   --help, -h          Show this help message
#
# Requirements:
#   - Ubuntu/Debian system
#   - Root or sudo access
#   - Internet connectivity
#
# Examples:
#   # Interactive installation
#   sudo ./install-netdata-parent.sh
#
#   # Non-interactive with options
#   sudo ./install-netdata-parent.sh --hostname holly --bind-ip 192.168.11.2 --peers "192.168.11.3,192.168.11.4" --children "192.168.11.11-13,192.168.11.20-22"

set -euo pipefail
trap 'echo "Error occurred at line $LINENO. Exit code: $?" >&2' ERR

# Constants
readonly SERVICE_NAME="netdata"
readonly LOG_FILE="/var/log/${SERVICE_NAME}-parent-install.log"
readonly CONFIG_DIR="/etc/netdata"
readonly STREAM_CONF="${CONFIG_DIR}/stream.conf"
readonly NETDATA_CONF="${CONFIG_DIR}/netdata.conf"

# Default values
HOSTNAME="${HOSTNAME:-$(hostname)}"
API_KEY=""
REPLICATION_KEY=""
PEER_IPS=""
CHILD_IPS=""
RETENTION_DAYS=30
BIND_IP=""
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
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >>"$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" >>"$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >>"$LOG_FILE"
}

print_header() {
    echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}\n"
}

# Show usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Install and configure Netdata as a parent node for streaming architecture

Options:
    --hostname NAME      Set the hostname for this parent (default: current hostname)
    --bind-ip IP        Bind Netdata to specific IP address (default: all interfaces)
    --api-key KEY       Set the API key for child connections (default: generate new)
    --replication-key   Set the API key for parent replication (default: generate new)
    --peers IPS         Comma-separated list of peer parent IPs for replication
    --children IPS      Comma-separated list of allowed child IPs or ranges
    --retention DAYS    Set data retention in days (default: 30)
    --non-interactive   Run without prompts
    --help, -h          Show this help message

Examples:
    # Interactive installation
    sudo $0

    # Non-interactive with options
    sudo $0 --hostname holly --bind-ip 192.168.11.2 --peers "192.168.11.3,192.168.11.4" \\
            --children "192.168.11.11 192.168.11.12 192.168.11.13 192.168.11.20-22"

EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --hostname)
                HOSTNAME="$2"
                shift 2
                ;;
            --bind-ip)
                BIND_IP="$2"
                shift 2
                ;;
            --api-key)
                API_KEY="$2"
                shift 2
                ;;
            --replication-key)
                REPLICATION_KEY="$2"
                shift 2
                ;;
            --peers)
                PEER_IPS="$2"
                shift 2
                ;;
            --children)
                CHILD_IPS="$2"
                shift 2
                ;;
            --retention)
                RETENTION_DAYS="$2"
                shift 2
                ;;
            --non-interactive)
                INTERACTIVE=false
                shift
                ;;
            --help | -h)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
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

    log_info "Prerequisites check passed"
}

# Generate UUID
generate_uuid() {
    if command -v uuidgen &>/dev/null; then
        uuidgen
    else
        # Fallback UUID generation
        cat /proc/sys/kernel/random/uuid 2>/dev/null ||
            echo "$(date +%s)-$(head -c 16 /dev/urandom | xxd -p)"
    fi
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
        curl -s https://get.netdata.cloud/kickstart.sh >/tmp/netdata-kickstart.sh
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

# Configure stream.conf for parent node
configure_streaming() {
    print_header "Configuring Streaming"

    # Generate API keys if not provided
    if [[ -z "$API_KEY" ]]; then
        API_KEY=$(generate_uuid)
        log_info "Generated child API key: $API_KEY"
    fi

    if [[ -z "$REPLICATION_KEY" ]]; then
        REPLICATION_KEY=$(generate_uuid)
        log_info "Generated replication API key: $REPLICATION_KEY"
    fi

    # Backup existing configuration
    if [[ -f "$STREAM_CONF" ]]; then
        cp "$STREAM_CONF" "${STREAM_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Backed up existing stream.conf"
    fi

    # Create stream.conf
    cat >"$STREAM_CONF" <<EOF
# Netdata Parent Node Streaming Configuration
# Generated by install-netdata-parent.sh on $(date)

[stream]
    enabled = no
    # Will be enabled if peer IPs are configured
    
# Configuration for accepting metrics from children
[$API_KEY]
    enabled = yes
EOF

    # Add allowed child IPs if provided
    if [[ -n "$CHILD_IPS" ]]; then
        echo "    allow from = $CHILD_IPS" >>"$STREAM_CONF"
    else
        echo "    allow from = *" >>"$STREAM_CONF"
        log_warn "No child IPs specified, allowing connections from all IPs"
    fi

    cat >>"$STREAM_CONF" <<EOF
    db = dbengine
    health enabled = yes
    postpone alarms on connect = 60s
    
# Configuration for accepting metrics from other parents (mutual replication)
[$REPLICATION_KEY]
    enabled = yes
EOF

    # Add allowed peer IPs if provided
    if [[ -n "$PEER_IPS" ]]; then
        echo "    allow from = $PEER_IPS" >>"$STREAM_CONF"

        # Enable streaming to peers
        sed -i 's/enabled = no/enabled = yes/' "$STREAM_CONF"
        sed -i "/\[stream\]/a\\    destination = ${PEER_IPS// /:19999 }:19999\\n    api key = $REPLICATION_KEY" "$STREAM_CONF"
    else
        echo "    allow from = *" >>"$STREAM_CONF"
        log_warn "No peer IPs specified, allowing replication from all IPs"
    fi

    echo "    db = dbengine" >>"$STREAM_CONF"

    log_info "Streaming configuration completed"
}

# Configure netdata.conf for parent node
configure_netdata() {
    print_header "Configuring Netdata Settings"

    # Calculate retention in seconds
    local retention_seconds=$((RETENTION_DAYS * 86400))

    # Update or create netdata.conf settings
    if [[ -f "$NETDATA_CONF" ]]; then
        cp "$NETDATA_CONF" "${NETDATA_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
    fi

    # Configure retention and other parent-specific settings
    cat >>"$NETDATA_CONF" <<EOF

# Parent Node Configuration
# Generated by install-netdata-parent.sh on $(date)

[db]
    mode = dbengine
    storage tiers = 3
    
    # Tier 0 (high resolution)
    dbengine tier 0 retention days = 1
    dbengine tier 0 retention space MB = 1024
    
    # Tier 1 (medium resolution) 
    dbengine tier 1 retention days = 7
    dbengine tier 1 retention space MB = 1024
    
    # Tier 2 (low resolution)
    dbengine tier 2 retention days = $RETENTION_DAYS
    dbengine tier 2 retention space MB = 1024

[global]
    hostname = $HOSTNAME
    
[web]
    bind to = ${BIND_IP:+$BIND_IP:19999}${BIND_IP:-*}
    
[ml]
    enabled = yes
    
[health]
    enabled = yes
EOF

    log_info "Netdata configuration completed"
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

# Display summary
display_summary() {
    print_header "Installation Summary"

    echo -e "${GREEN}Netdata Parent Node Configuration:${NC}"
    echo -e "  Hostname: ${BOLD}$HOSTNAME${NC}"
    echo -e "  Child API Key: ${BOLD}$API_KEY${NC}"
    echo -e "  Replication API Key: ${BOLD}$REPLICATION_KEY${NC}"
    echo -e "  Data Retention: ${BOLD}$RETENTION_DAYS days${NC}"

    if [[ -n "$BIND_IP" ]]; then
        echo -e "  Bind IP: ${BOLD}$BIND_IP:19999${NC}"
    else
        echo -e "  Bind IP: ${BOLD}All interfaces${NC}"
    fi

    if [[ -n "$CHILD_IPS" ]]; then
        echo -e "  Allowed Children: ${BOLD}$CHILD_IPS${NC}"
    fi

    if [[ -n "$PEER_IPS" ]]; then
        echo -e "  Peer Parents: ${BOLD}$PEER_IPS${NC}"
    fi

    echo ""
    echo -e "${CYAN}Next Steps:${NC}"
    echo "1. Configure child nodes to stream to this parent using:"
    if [[ -n "$BIND_IP" ]]; then
        echo "   - Destination: $BIND_IP:19999"
    else
        echo "   - Destination: $(hostname -I | awk '{print $1}'):19999"
    fi
    echo "   - API Key: $API_KEY"
    echo ""
    echo "2. Configure peer parents for mutual replication using:"
    echo "   - API Key: $REPLICATION_KEY"
    echo ""
    echo "3. Access Netdata dashboard at:"
    if [[ -n "$BIND_IP" ]]; then
        echo "   - http://$BIND_IP:19999"
    else
        echo "   - http://$(hostname -I | awk '{print $1}'):19999"
    fi
    echo ""
    echo "4. Check logs for any issues:"
    echo "   - /var/log/netdata/error.log"
    echo ""

    # Save configuration summary
    cat >"${CONFIG_DIR}/parent-config-summary.txt" <<EOF
Netdata Parent Configuration Summary
Generated: $(date)

Hostname: $HOSTNAME
Bind IP: ${BIND_IP:-"all interfaces"}
Child API Key: $API_KEY
Replication API Key: $REPLICATION_KEY
Data Retention: $RETENTION_DAYS days
Allowed Children: ${CHILD_IPS:-"all"}
Peer Parents: ${PEER_IPS:-"none"}
EOF

    log_info "Configuration summary saved to: ${CONFIG_DIR}/parent-config-summary.txt"
    log_info "Installation log saved to: $LOG_FILE"
}

# Main execution
main() {
    # Set up logging
    echo "Installation started at $(date)" >"$LOG_FILE"
    chmod 640 "$LOG_FILE"

    parse_args "$@"

    echo -e "${BOLD}${CYAN}Netdata Parent Node Installation${NC}"
    echo -e "${CYAN}=================================${NC}"

    check_prerequisites
    install_netdata
    configure_streaming
    configure_netdata
    restart_netdata
    display_summary

    echo "Installation completed at $(date)" >>"$LOG_FILE"
}

# Run main function
main "$@"
