#!/bin/bash

# NFTables Port Management Script
# Opens specified ports in nftables firewall and persists the configuration
# Supports backup, rollback, and idempotent operations
#
# Usage:
#   ./open-port.sh [OPTIONS]
#
# Options:
#   -p, --port PORT       Port number to open (default: 19999)
#   -P, --protocol PROTO  Protocol to open (tcp/udp, default: tcp)
#   -c, --chain CHAIN     Chain name (default: input)
#   -t, --table TABLE     Table name (default: filter)
#   -f, --family FAMILY   Address family (inet/ip/ip6, default: inet)
#   -r, --remove          Remove the rule instead of adding it
#   -b, --backup-only     Only create a backup of current ruleset
#   -h, --help            Show this help message
#   --no-color            Disable colored output
#   --dry-run             Show what would be done without making changes
#
# Examples:
#   # Open port 19999 (default)
#   ./open-port.sh
#
#   # Open port 8080
#   ./open-port.sh --port 8080
#
#   # Open UDP port 53
#   ./open-port.sh --port 53 --protocol udp
#
#   # Remove a rule for port 8080
#   ./open-port.sh --port 8080 --remove
#
#   # Dry run to see what would happen
#   ./open-port.sh --port 443 --dry-run
#
# Requirements:
#   - nftables installed and running
#   - Root or sudo access
#   - systemd (for service management)

set -euo pipefail
trap 'handle_error $? $LINENO' ERR

# Default values
readonly DEFAULT_PORT=19999
readonly DEFAULT_PROTOCOL="tcp"
readonly DEFAULT_CHAIN="input"
readonly DEFAULT_TABLE="filter"
readonly DEFAULT_FAMILY="inet"
readonly BACKUP_DIR="/var/backups/nftables"
readonly LOG_FILE="/var/log/nftables-port-management.log"
readonly CONFIG_FILE="/etc/nftables.conf"

# Variables
PORT="${DEFAULT_PORT}"
PROTOCOL="${DEFAULT_PROTOCOL}"
CHAIN="${DEFAULT_CHAIN}"
TABLE="${DEFAULT_TABLE}"
FAMILY="${DEFAULT_FAMILY}"
ACTION="add"
BACKUP_ONLY=false
DRY_RUN=false
USE_COLOR=true

# Color codes for output (check if terminal supports colors)
setup_colors() {
    if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]] && [[ -z "${NO_COLOR:-}" ]] && [[ "$USE_COLOR" == "true" ]]; then
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
}

# Logging functions
log_info() {
    local message="$*"
    echo -e "${GREEN}[INFO]${NC} $message"
    if [[ -w "$LOG_FILE" ]] || [[ -w "$(dirname "$LOG_FILE")" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

log_warn() {
    local message="$*"
    echo -e "${YELLOW}[WARN]${NC} $message"
    if [[ -w "$LOG_FILE" ]] || [[ -w "$(dirname "$LOG_FILE")" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

log_error() {
    local message="$*"
    echo -e "${RED}[ERROR]${NC} $message" >&2
    if [[ -w "$LOG_FILE" ]] || [[ -w "$(dirname "$LOG_FILE")" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

log_step() {
    local message="$*"
    echo -e "${BLUE}[STEP]${NC} $message"
    if [[ -w "$LOG_FILE" ]] || [[ -w "$(dirname "$LOG_FILE")" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] STEP: $message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

log_success() {
    local message="$*"
    echo -e "${GREEN}[SUCCESS]${NC} $message"
    if [[ -w "$LOG_FILE" ]] || [[ -w "$(dirname "$LOG_FILE")" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# Confirm action helper
confirm_action() {
    local prompt="$1"
    if [[ "$INTERACTIVE" == "true" ]]; then
        read -p "$prompt [y/N] " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]]
    else
        log_info "Auto-accepting: $prompt"
        return 0
    fi
}

# Error handler
handle_error() {
    local exit_code=$1
    local line_number=$2
    log_error "Script failed at line $line_number with exit code $exit_code"
    
    # Check if we have a backup to suggest restore
    if [[ -d "$BACKUP_DIR" ]] && ls -1 "$BACKUP_DIR"/nftables-backup-*.conf 2>/dev/null | grep -q .; then
        log_warn "Recent backups available in $BACKUP_DIR"
        log_warn "To restore, run: sudo cp $BACKUP_DIR/nftables-backup-TIMESTAMP.conf $CONFIG_FILE && sudo systemctl restart nftables"
    fi
    
    exit "$exit_code"
}

# Show usage
show_usage() {
    echo "NFTables Port Management Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -p, --port PORT       Port number to open (default: $DEFAULT_PORT)"
    echo "  -P, --protocol PROTO  Protocol to open (tcp/udp, default: $DEFAULT_PROTOCOL)"
    echo "  -c, --chain CHAIN     Chain name (default: $DEFAULT_CHAIN)"
    echo "  -t, --table TABLE     Table name (default: $DEFAULT_TABLE)"
    echo "  -f, --family FAMILY   Address family (inet/ip/ip6, default: $DEFAULT_FAMILY)"
    echo "  -r, --remove          Remove the rule instead of adding it"
    echo "  -b, --backup-only     Only create a backup of current ruleset"
    echo "  -h, --help            Show this help message"
    echo "  --no-color            Disable colored output"
    echo "  --dry-run             Show what would be done without making changes"
    echo ""
    echo "Examples:"
    echo "  # Open port 19999 (default)"
    echo "  $0"
    echo ""
    echo "  # Open port 8080"
    echo "  $0 --port 8080"
    echo ""
    echo "  # Open UDP port 53"
    echo "  $0 --port 53 --protocol udp"
    echo ""
    echo "  # Remove a rule for port 8080"
    echo "  $0 --port 8080 --remove"
    echo ""
    echo "  # Dry run to see what would happen"
    echo "  $0 --port 443 --dry-run"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--port)
                PORT="$2"
                shift 2
                ;;
            -P|--protocol)
                PROTOCOL="$2"
                shift 2
                ;;
            -c|--chain)
                CHAIN="$2"
                shift 2
                ;;
            -t|--table)
                TABLE="$2"
                shift 2
                ;;
            -f|--family)
                FAMILY="$2"
                shift 2
                ;;
            -r|--remove)
                ACTION="remove"
                shift
                ;;
            -b|--backup-only)
                BACKUP_ONLY=true
                shift
                ;;
            --no-color)
                USE_COLOR=false
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Validate inputs
validate_inputs() {
    # Validate port number
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [[ "$PORT" -lt 1 ]] || [[ "$PORT" -gt 65535 ]]; then
        log_error "Invalid port number: $PORT (must be 1-65535)"
        exit 1
    fi
    
    # Validate protocol
    if [[ "$PROTOCOL" != "tcp" ]] && [[ "$PROTOCOL" != "udp" ]]; then
        log_error "Invalid protocol: $PROTOCOL (must be tcp or udp)"
        exit 1
    fi
    
    # Validate family
    if [[ "$FAMILY" != "inet" ]] && [[ "$FAMILY" != "ip" ]] && [[ "$FAMILY" != "ip6" ]]; then
        log_error "Invalid address family: $FAMILY (must be inet, ip, or ip6)"
        exit 1
    fi
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

# Check if nftables is installed
check_nftables() {
    if ! command -v nft &> /dev/null; then
        log_error "nftables is not installed. Please install it first:"
        log_error "  sudo apt update && sudo apt install nftables"
        exit 1
    fi
    
    # Check if nftables service exists (non-fatal if missing)
    if systemctl list-unit-files 2>/dev/null | grep -q "^nftables\.service"; then
        # Service exists, check if it's running
        if ! systemctl is-active --quiet nftables 2>/dev/null; then
            log_warn "nftables service is not running"
            if [[ "$INTERACTIVE" == "true" ]] && [[ "$DRY_RUN" == "false" ]]; then
                if confirm_action "Start nftables service?"; then
                    systemctl start nftables
                    log_info "Started nftables service"
                fi
            fi
        fi
    else
        # Service doesn't exist, but nft command works - this is OK
        log_warn "nftables service not found, but nft command is available"
        log_info "Rules will be applied but may not persist after reboot without service"
    fi
    
    # Test if we can actually use nft
    if ! nft list tables &>/dev/null; then
        log_error "Cannot access nftables. Are you running as root?"
        exit 1
    fi
}

# Create backup directory if it doesn't exist
ensure_backup_dir() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        chmod 700 "$BACKUP_DIR"
        log_info "Created backup directory: $BACKUP_DIR"
    fi
}

# Create a backup of current ruleset
create_backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/nftables-backup-${timestamp}.conf"
    
    log_step "Creating backup of current ruleset..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create backup at: $backup_file"
        return 0
    fi
    
    # Save current ruleset
    if nft list ruleset > "$backup_file" 2>/dev/null; then
        chmod 600 "$backup_file"
        log_success "Backup created: $backup_file"
        
        # Keep only last 10 backups
        local backup_count=$(ls -1 "$BACKUP_DIR"/nftables-backup-*.conf 2>/dev/null | wc -l)
        if [[ $backup_count -gt 10 ]]; then
            ls -1t "$BACKUP_DIR"/nftables-backup-*.conf | tail -n +11 | xargs rm -f
            log_info "Cleaned up old backups (kept last 10)"
        fi
    else
        log_error "Failed to create backup"
        exit 1
    fi
}

# Check if rule already exists
rule_exists() {
    local port="$1"
    local protocol="$2"
    local chain="$3"
    local table="$4"
    local family="$5"
    
    # Check if the table and chain exist first
    if ! nft list table "$family" "$table" &>/dev/null; then
        return 1
    fi
    
    # Check for the specific rule
    if nft list chain "$family" "$table" "$chain" 2>/dev/null | grep -qE "${protocol}[[:space:]]+dport[[:space:]]+${port}[[:space:]]+accept"; then
        return 0
    fi
    
    return 1
}

# Add firewall rule
add_rule() {
    local port="$1"
    local protocol="$2"
    local chain="$3"
    local table="$4"
    local family="$5"
    
    log_step "Adding rule to allow $protocol port $port..."
    
    # Check if rule already exists
    if rule_exists "$port" "$protocol" "$chain" "$table" "$family"; then
        log_warn "Rule already exists for $protocol port $port"
        return 0
    fi
    
    # Ensure table exists
    if ! nft list table "$family" "$table" &>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would create table: $family $table"
        else
            log_info "Creating table: $family $table"
            nft add table "$family" "$table"
        fi
    fi
    
    # Ensure chain exists
    if ! nft list chain "$family" "$table" "$chain" &>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would create chain: $family $table $chain"
        else
            log_info "Creating chain: $family $table $chain"
            nft add chain "$family" "$table" "$chain" '{ type filter hook input priority 0; policy accept; }'
        fi
    fi
    
    # Add the rule at the beginning of the chain
    # insert rule adds at the beginning by default (no position parameter needed)
    local cmd="nft insert rule $family $table $chain $protocol dport $port accept"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute: $cmd"
    else
        if eval "$cmd"; then
            log_success "Added rule: $protocol port $port -> ACCEPT (at beginning of chain)"
        else
            log_error "Failed to add rule"
            return 1
        fi
    fi
}

# Remove firewall rule
remove_rule() {
    local port="$1"
    local protocol="$2"
    local chain="$3"
    local table="$4"
    local family="$5"
    
    log_step "Removing rule for $protocol port $port..."
    
    # Check if rule exists
    if ! rule_exists "$port" "$protocol" "$chain" "$table" "$family"; then
        log_warn "Rule does not exist for $protocol port $port"
        return 0
    fi
    
    # Get rule handle
    local handle=$(nft -a list chain "$family" "$table" "$chain" 2>/dev/null | \
        grep -E "${protocol}[[:space:]]+dport[[:space:]]+${port}[[:space:]]+accept" | \
        grep -oE 'handle[[:space:]]+[0-9]+' | \
        awk '{print $2}' | \
        head -1)
    
    if [[ -z "$handle" ]]; then
        log_error "Could not find rule handle"
        return 1
    fi
    
    local cmd="nft delete rule $family $table $chain handle $handle"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute: $cmd"
    else
        if $cmd; then
            log_success "Removed rule: $protocol port $port (handle $handle)"
        else
            log_error "Failed to remove rule"
            return 1
        fi
    fi
}

# Save ruleset to config file
save_ruleset() {
    log_step "Saving ruleset to $CONFIG_FILE..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would save ruleset to $CONFIG_FILE"
        return 0
    fi
    
    # Create temporary file
    local tmp_file=$(mktemp)
    
    # Save ruleset to temporary file
    if ! nft list ruleset > "$tmp_file" 2>/dev/null; then
        log_error "Failed to export ruleset"
        rm -f "$tmp_file"
        return 1
    fi
    
    # Validate the exported ruleset
    if ! nft -c -f "$tmp_file" 2>/dev/null; then
        log_error "Exported ruleset validation failed"
        rm -f "$tmp_file"
        return 1
    fi
    
    # Copy to config file
    cp "$tmp_file" "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"
    
    # Clean up temporary file
    rm -f "$tmp_file"
    
    log_success "Ruleset saved to $CONFIG_FILE"
}

# Enable nftables service
enable_service() {
    # Check if service exists before trying to enable it
    if ! systemctl list-unit-files 2>/dev/null | grep -q "^nftables\.service"; then
        log_warn "nftables service not found, skipping service enablement"
        log_info "You may need to manually configure nftables to start at boot"
        return 0
    fi
    
    if systemctl is-enabled --quiet nftables 2>/dev/null; then
        log_info "nftables service is already enabled"
    else
        log_step "Enabling nftables service..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would enable nftables service"
        else
            systemctl enable nftables
            log_success "nftables service enabled"
        fi
    fi
}

# Display current rules for verification
show_rules() {
    log_step "Current rules in $FAMILY $TABLE $CHAIN:"
    
    if nft list chain "$FAMILY" "$TABLE" "$CHAIN" &>/dev/null; then
        nft -a list chain "$FAMILY" "$TABLE" "$CHAIN" | sed 's/^/  /'
    else
        log_warn "Chain $FAMILY $TABLE $CHAIN does not exist"
    fi
}

# Main function
main() {
    # Parse arguments first (before setting up colors)
    parse_args "$@"
    
    # Setup colors based on parsed arguments
    setup_colors
    
    # Start logging
    log_info "Starting nftables port management script..."
    log_info "Parameters: port=$PORT protocol=$PROTOCOL family=$FAMILY table=$TABLE chain=$CHAIN action=$ACTION"
    
    # Validate inputs
    validate_inputs
    
    # Check prerequisites
    check_root
    check_nftables
    
    # Ensure backup directory exists
    ensure_backup_dir
    
    # Create backup
    create_backup
    
    # If backup-only mode, exit here
    if [[ "$BACKUP_ONLY" == "true" ]]; then
        log_success "Backup-only mode completed"
        exit 0
    fi
    
    # Perform the requested action
    if [[ "$ACTION" == "add" ]]; then
        add_rule "$PORT" "$PROTOCOL" "$CHAIN" "$TABLE" "$FAMILY"
    else
        remove_rule "$PORT" "$PROTOCOL" "$CHAIN" "$TABLE" "$FAMILY"
    fi
    
    # Save ruleset if not in dry-run mode
    if [[ "$DRY_RUN" == "false" ]]; then
        save_ruleset
        enable_service
    fi
    
    # Show current rules
    show_rules
    
    # Success message
    echo
    echo "================================================================="
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN completed - no changes were made"
    else
        log_success "Operation completed successfully!"
        echo
        echo "Next steps:"
        echo "1. Verify the rules are working:"
        echo "   nft list chain $FAMILY $TABLE $CHAIN"
        echo
        echo "2. Test connectivity:"
        echo "   nc -zv localhost $PORT"
        echo
        echo "3. If issues occur, restore from backup:"
        echo "   sudo cp $BACKUP_DIR/nftables-backup-*.conf $CONFIG_FILE"
        echo "   sudo systemctl restart nftables"
    fi
    echo "================================================================="
}

# Run main function
main "$@"