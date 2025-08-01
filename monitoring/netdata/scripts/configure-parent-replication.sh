#!/bin/bash

# Script Name: configure-parent-replication.sh
# Purpose: Configure mutual replication between Netdata parent nodes
# Version: 1.0
# 
# Usage:
#   ./configure-parent-replication.sh [OPTIONS]
#
# Options:
#   --node-ip IP        IP address of this parent node (required)
#   --peer-ips IPS      Comma-separated list of peer parent IPs (required)
#   --replication-key   Replication API key (required)
#   --enable-streaming  Enable streaming to peers (default: yes)
#   --dry-run          Show what would be changed without applying
#   --help, -h         Show this help message
#
# Requirements:
#   - Netdata already installed as parent node
#   - Root or sudo access
#
# Examples:
#   # Configure holly to replicate to lloyd and mable (using 10G network)
#   sudo ./configure-parent-replication.sh --node-ip 192.168.11.2 \
#        --peer-ips "192.168.11.3,192.168.11.4" --replication-key "parent-replication-key"

set -euo pipefail
trap 'echo "Error occurred at line $LINENO. Exit code: $?" >&2' ERR

# Constants
readonly STREAM_CONF="/etc/netdata/stream.conf"
readonly LOG_FILE="/var/log/netdata-replication-config.log"

# Variables
NODE_IP=""
PEER_IPS=""
REPLICATION_KEY=""
ENABLE_STREAMING="yes"
DRY_RUN=false

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

Configure mutual replication between Netdata parent nodes

Options:
    --node-ip IP        IP address of this parent node (required)
    --peer-ips IPS      Comma-separated list of peer parent IPs (required)
    --replication-key   Replication API key (required)
    --enable-streaming  Enable streaming to peers (default: yes)
    --dry-run          Show what would be changed without applying
    --help, -h         Show this help message

Examples:
    # Configure holly (192.168.11.2) to replicate to lloyd and mable
    sudo $0 --node-ip 192.168.11.2 \\
            --peer-ips "192.168.11.3,192.168.11.4" \\
            --replication-key "parent-replication-key"

    # Dry run to see changes
    sudo $0 --node-ip 192.168.11.2 \\
            --peer-ips "192.168.11.3,192.168.11.4" \\
            --replication-key "parent-replication-key" \\
            --dry-run

EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --node-ip)
                NODE_IP="$2"
                shift 2
                ;;
            --peer-ips)
                PEER_IPS="$2"
                shift 2
                ;;
            --replication-key)
                REPLICATION_KEY="$2"
                shift 2
                ;;
            --enable-streaming)
                ENABLE_STREAMING="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
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
    if [[ -z "$NODE_IP" ]]; then
        log_error "Node IP is required (--node-ip)"
        usage
    fi
    
    if [[ -z "$PEER_IPS" ]]; then
        log_error "Peer IPs are required (--peer-ips)"
        usage
    fi
    
    if [[ -z "$REPLICATION_KEY" ]]; then
        log_error "Replication key is required (--replication-key)"
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
    
    # Check if Netdata is installed
    if ! systemctl is-active --quiet netdata 2>/dev/null; then
        log_error "Netdata is not running. Please install Netdata first."
        exit 1
    fi
    
    # Check if stream.conf exists
    if [[ ! -f "$STREAM_CONF" ]]; then
        log_error "stream.conf not found at $STREAM_CONF"
        exit 1
    fi
    
    log_info "Prerequisites check passed"
}

# Backup configuration
backup_config() {
    local backup_file="${STREAM_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would backup $STREAM_CONF to $backup_file"
    else
        cp "$STREAM_CONF" "$backup_file"
        log_info "Backed up stream.conf to $backup_file"
    fi
}

# Update stream.conf for replication
update_stream_config() {
    print_header "Updating Stream Configuration"
    
    # Convert comma-separated IPs to space-separated with ports
    local destinations=""
    local peer_array=(${PEER_IPS//,/ })
    for peer in "${peer_array[@]}"; do
        destinations="${destinations}${peer}:19999 "
    done
    destinations="${destinations% }" # Remove trailing space
    
    # Create temporary config file
    local temp_conf="/tmp/stream.conf.tmp"
    
    # Read existing config and update
    local in_stream_section=false
    local stream_section_updated=false
    local replication_section_exists=false
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^\[stream\] ]]; then
            in_stream_section=true
            echo "$line" >> "$temp_conf"
            
            if [[ "$ENABLE_STREAMING" == "yes" ]]; then
                echo "    enabled = yes" >> "$temp_conf"
                echo "    destination = $destinations" >> "$temp_conf"
                echo "    api key = $REPLICATION_KEY" >> "$temp_conf"
                stream_section_updated=true
            else
                echo "    enabled = no" >> "$temp_conf"
            fi
            
        elif [[ "$line" =~ ^\[.*\] ]] && [[ "$in_stream_section" == "true" ]]; then
            in_stream_section=false
            echo "$line" >> "$temp_conf"
            
        elif [[ "$line" =~ ^\[$REPLICATION_KEY\] ]]; then
            replication_section_exists=true
            echo "$line" >> "$temp_conf"
            
        elif [[ "$in_stream_section" == "true" ]] && [[ "$stream_section_updated" == "false" ]]; then
            # Skip existing stream settings, we're replacing them
            continue
            
        else
            echo "$line" >> "$temp_conf"
        fi
    done < "$STREAM_CONF"
    
    # Add replication key section if it doesn't exist
    if [[ "$replication_section_exists" == "false" ]]; then
        echo "" >> "$temp_conf"
        echo "# Parent replication configuration" >> "$temp_conf"
        echo "[$REPLICATION_KEY]" >> "$temp_conf"
        echo "    enabled = yes" >> "$temp_conf"
        echo "    allow from = ${PEER_IPS//,/ } $NODE_IP" >> "$temp_conf"
        echo "    db = dbengine" >> "$temp_conf"
    fi
    
    # Show diff or apply changes
    if [[ "$DRY_RUN" == "true" ]]; then
        print_header "Configuration Changes (DRY RUN)"
        if command -v diff &>/dev/null; then
            diff -u "$STREAM_CONF" "$temp_conf" || true
        else
            echo "Old configuration: $STREAM_CONF"
            echo "New configuration would be:"
            cat "$temp_conf"
        fi
        rm -f "$temp_conf"
    else
        mv "$temp_conf" "$STREAM_CONF"
        log_info "Updated stream.conf successfully"
    fi
}

# Restart Netdata
restart_netdata() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would restart Netdata service"
    else
        print_header "Restarting Netdata"
        systemctl restart netdata
        sleep 5
        
        if systemctl is-active --quiet netdata; then
            log_info "Netdata service restarted successfully"
        else
            log_error "Failed to restart Netdata service"
            exit 1
        fi
    fi
}

# Verify replication
verify_replication() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    print_header "Verifying Replication"
    
    log_info "Waiting for replication connections..."
    sleep 10
    
    # Check for replication connections in logs
    if grep -q "new client.*$REPLICATION_KEY" /var/log/netdata/error.log 2>/dev/null; then
        log_info "Replication connections detected"
        grep "new client.*$REPLICATION_KEY" /var/log/netdata/error.log | tail -5
    else
        log_warn "Could not verify replication connections yet"
        log_info "Check /var/log/netdata/error.log for details"
    fi
}

# Display summary
display_summary() {
    print_header "Configuration Summary"
    
    echo -e "${GREEN}Parent Replication Configuration:${NC}"
    echo -e "  This Node IP: ${BOLD}$NODE_IP${NC}"
    echo -e "  Peer Parent IPs: ${BOLD}$PEER_IPS${NC}"
    echo -e "  Replication Key: ${BOLD}$REPLICATION_KEY${NC}"
    echo -e "  Streaming Enabled: ${BOLD}$ENABLE_STREAMING${NC}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        echo -e "${YELLOW}This was a DRY RUN. No changes were applied.${NC}"
        echo -e "Remove --dry-run to apply the configuration."
    else
        echo ""
        echo -e "${CYAN}Next Steps:${NC}"
        echo "1. Configure the same replication key on peer parents"
        echo "2. Verify replication in Netdata logs:"
        echo "   - grep 'replication' /var/log/netdata/error.log"
        echo "3. Check parent dashboards for replicated data"
    fi
    
    log_info "Configuration completed"
}

# Main execution
main() {
    # Set up logging
    echo "Configuration started at $(date)" > "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    
    parse_args "$@"
    
    echo -e "${BOLD}${CYAN}Netdata Parent Replication Configuration${NC}"
    echo -e "${CYAN}=======================================${NC}"
    
    check_prerequisites
    backup_config
    update_stream_config
    restart_netdata
    verify_replication
    display_summary
    
    echo "Configuration completed at $(date)" >> "$LOG_FILE"
}

# Run main function
main "$@"