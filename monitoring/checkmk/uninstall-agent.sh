#!/bin/bash

# Script Name: uninstall-agent.sh
# Purpose: Removes the CheckMK monitoring agent from Debian/Ubuntu systems
# Version: 1.0
# 
# Usage:
#   ./uninstall-agent.sh [OPTIONS]
#
# Options:
#   --non-interactive    Run without prompts (auto-confirm removal)
#   --help, -h          Show help message
#
# Requirements:
#   - Debian/Ubuntu system
#   - Root or sudo access
#   - CheckMK agent installed
#
# Examples:
#   # Interactive uninstallation
#   sudo ./uninstall-agent.sh
#
#   # Non-interactive uninstallation (for automation)
#   sudo ./uninstall-agent.sh --non-interactive
#
#   # Remote execution
#   curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/monitoring/checkmk/uninstall-agent.sh | sudo bash

set -euo pipefail
trap 'echo "Error occurred at line $LINENO. Exit code: $?" >&2' ERR
trap cleanup EXIT

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

# Constants
readonly SERVICE_NAME="checkmk-agent"
readonly LOG_FILE="/var/log/${SERVICE_NAME}-uninstall.log"

# Non-interactive mode support
INTERACTIVE=true
if [[ ! -t 0 ]] || [[ "${NON_INTERACTIVE:-}" == "true" ]] || [[ "$*" == *"--non-interactive"* ]]; then
    INTERACTIVE=false
fi

# Helper functions
print_header() {
    echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

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

# Show usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Uninstall CheckMK monitoring agent from Debian/Ubuntu systems"
    echo ""
    echo "Options:"
    echo "  --non-interactive   Run without prompts (auto-confirm removal)"
    echo "  --help, -h          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                      # Interactive uninstallation"
    echo "  $0 --non-interactive    # Automated uninstallation"
    exit 0
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
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
}

# Check if running as root
check_privileges() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Check if agent is installed
check_installation() {
    print_header "Checking CheckMK Agent Installation"
    
    local found=0
    
    # Check for various package names
    local package_patterns=("check-mk-agent" "checkmk-agent" "cmk-agent")
    for pattern in "${package_patterns[@]}"; do
        if dpkg -l | grep -q "$pattern"; then
            print_info "Found package: $pattern"
            local version_info=$(dpkg -l | grep "$pattern" | awk '{print $3}' || echo "unknown")
            print_info "Version: $version_info"
            log_info "Found package $pattern version $version_info"
            found=1
        fi
    done
    
    # Check for systemd services
    if systemctl list-units --all | grep -q "check-mk-agent"; then
        print_info "Found CheckMK systemd services"
        systemctl list-units --all | grep "check-mk-agent" | head -5
        found=1
    fi
    
    # Check for socket files
    if systemctl list-unit-files | grep -q "check-mk-agent"; then
        print_info "Found CheckMK systemd unit files"
        systemctl list-unit-files | grep "check-mk-agent"
        found=1
    fi
    
    # Check for running processes
    if pgrep -f "check.*mk" >/dev/null 2>&1; then
        print_info "Found CheckMK processes running"
        pgrep -f "check.*mk" | head -5
        found=1
    fi
    
    # Check for listening port
    if ss -tlnp | grep -q ":6556"; then
        print_info "Found service listening on CheckMK port 6556"
        ss -tlnp | grep ":6556"
        found=1
    fi
    
    # Check for binaries
    local binaries=$(find /usr -name "*check*mk*" -type f 2>/dev/null | head -5)
    if [[ -n "$binaries" ]]; then
        print_info "Found CheckMK binaries:"
        echo "$binaries"
        found=1
    fi
    
    if [[ $found -eq 1 ]]; then
        return 0
    else
        print_warning "CheckMK agent does not appear to be installed"
        return 1
    fi
}

# Stop agent services
stop_services() {
    print_header "Stopping CheckMK Agent Services"
    
    # List of CheckMK services to stop
    local checkmk_services=(
        "check-mk-agent-async.service"
        "cmk-agent-ctl-daemon.service"
        "check-mk-agent.socket"
        "check-mk-agent@.service"
    )
    
    # Stop specific CheckMK services
    for service in "${checkmk_services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            print_info "Stopping $service..."
            systemctl stop "$service" 2>/dev/null || true
            print_success "Stopped $service"
        fi
    done
    
    # Stop any running check-mk-agent@ instances
    local running_instances=$(systemctl list-units --all | grep "check-mk-agent@" | awk '{print $1}' | grep -v "check-mk-agent@.service" || true)
    if [[ -n "$running_instances" ]]; then
        while IFS= read -r instance; do
            if [[ -n "$instance" ]]; then
                print_info "Stopping instance: $instance"
                systemctl stop "$instance" 2>/dev/null || true
            fi
        done <<< "$running_instances"
    fi
    
    # Disable services
    for service in "${checkmk_services[@]}"; do
        if systemctl list-unit-files | grep -q "^$service"; then
            print_info "Disabling $service..."
            systemctl disable "$service" 2>/dev/null || true
            print_success "Disabled $service"
        fi
    done
    
    # Kill any remaining CheckMK processes
    if pgrep -f "check.*mk" >/dev/null 2>&1 || pgrep -f "cmk" >/dev/null 2>&1; then
        print_info "Killing remaining CheckMK processes..."
        pkill -f "check.*mk" 2>/dev/null || true
        pkill -f "cmk" 2>/dev/null || true
        sleep 2
        print_success "Processes killed"
    fi
}

# Remove the package
remove_package() {
    print_header "Removing CheckMK Agent Package"
    
    # Try different package names
    local package_patterns=("check-mk-agent" "checkmk-agent" "cmk-agent")
    local removed=0
    
    for pattern in "${package_patterns[@]}"; do
        if dpkg -l | grep -q "$pattern"; then
            print_info "Removing package: $pattern"
            if apt purge -y "$pattern" 2>/dev/null || dpkg -P "$pattern" 2>/dev/null; then
                print_success "Package $pattern removed successfully"
                removed=1
            else
                print_warning "Failed to remove $pattern using apt/dpkg, trying dpkg -r..."
                if dpkg -r "$pattern" 2>/dev/null; then
                    print_success "Package $pattern removed using dpkg -r"
                    removed=1
                else
                    print_error "Failed to remove package $pattern"
                fi
            fi
        fi
    done
    
    if [[ $removed -eq 0 ]]; then
        print_warning "No CheckMK packages found to remove"
        print_info "The agent might be installed manually or via a different method"
    fi
}

# Clean up remaining files
cleanup_files() {
    print_header "Cleaning Up Remaining Files"
    
    local cleanup_dirs=(
        "/etc/check_mk"
        "/var/lib/check_mk_agent"
        "/usr/lib/check_mk_agent"
        "/var/lib/cmk-agent"
        "/etc/cmk-agent"
        "/usr/bin/cmk-agent-ctl"
    )
    
    for item in "${cleanup_dirs[@]}"; do
        if [[ -e "$item" ]]; then
            print_info "Removing: $item"
            rm -rf "$item"
            print_success "Removed $item"
        fi
    done
    
    # Remove systemd unit files
    local unit_files=(
        "/etc/systemd/system/check-mk-agent.socket"
        "/etc/systemd/system/check-mk-agent@.service"
        "/etc/systemd/system/check-mk-agent-async.service"
        "/etc/systemd/system/cmk-agent-ctl-daemon.service"
        "/lib/systemd/system/check-mk-agent.socket"
        "/lib/systemd/system/check-mk-agent@.service"
        "/lib/systemd/system/check-mk-agent-async.service"
        "/lib/systemd/system/cmk-agent-ctl-daemon.service"
    )
    
    for unit_file in "${unit_files[@]}"; do
        if [[ -f "$unit_file" ]]; then
            print_info "Removing systemd unit: $unit_file"
            rm -f "$unit_file"
            print_success "Removed $unit_file"
        fi
    done
    
    # Reload systemd after removing unit files
    systemctl daemon-reload
    
    # Check for any remaining check_mk files
    print_info "Checking for any remaining CheckMK files..."
    local remaining_files=$(find /usr /etc /var -name "*check*mk*" -o -name "*cmk*" 2>/dev/null | grep -v "/proc/" | head -10)
    if [[ -n "$remaining_files" ]]; then
        print_warning "Found some remaining files:"
        echo "$remaining_files"
        print_info "You may want to review and remove these manually if needed"
    else
        print_success "No remaining CheckMK files found"
    fi
}

# Verify removal
verify_removal() {
    print_header "Verifying Removal"
    
    local issues=0
    
    # Check packages
    if dpkg -l | grep -q "check-mk-agent"; then
        print_error "CheckMK package still appears to be installed"
        issues=1
    else
        print_success "CheckMK package successfully removed"
    fi
    
    # Check for specific services
    local checkmk_services=(
        "check-mk-agent-async.service"
        "cmk-agent-ctl-daemon.service"
        "check-mk-agent.socket"
    )
    
    for service in "${checkmk_services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            print_warning "Service $service is still running"
            issues=1
        fi
    done
    
    if [[ $issues -eq 0 ]]; then
        print_success "No CheckMK services are running"
    fi
    
    # Check for any remaining CheckMK units
    local remaining_units=$(systemctl list-units --all | grep -i "check-mk\|cmk" | grep -v "slice" || true)
    if [[ -n "$remaining_units" ]]; then
        print_warning "Found remaining CheckMK systemd units:"
        echo "$remaining_units"
        issues=1
    else
        print_success "No CheckMK systemd units remaining"
    fi
    
    # Check listening ports
    if ss -tlnp | grep -q ":6556"; then
        print_warning "Port 6556 is still in use"
        ss -tlnp | grep ":6556"
        issues=1
    else
        print_success "CheckMK agent port (6556) is not in use"
    fi
    
    # Check for running processes
    if pgrep -f "check.*mk\|cmk" >/dev/null 2>&1; then
        print_warning "CheckMK processes are still running:"
        pgrep -fl "check.*mk\|cmk"
        issues=1
    else
        print_success "No CheckMK processes running"
    fi
    
    if [[ $issues -eq 0 ]]; then
        print_success "Complete removal verified!"
    else
        print_warning "Some issues found during verification"
        return 1
    fi
}

# Cleanup function
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Uninstallation failed with exit code: $exit_code"
    fi
}

# Confirm action in interactive mode
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

# Main execution
main() {
    # Parse command line arguments
    parse_args "$@"
    
    # Set up logging
    echo "Uninstallation started at $(date)" > "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    
    echo -e "${BOLD}${CYAN}CheckMK Agent Uninstallation Script${NC}"
    echo -e "${CYAN}===================================${NC}"
    
    log_info "Starting CheckMK agent uninstallation"
    
    check_privileges
    
    if ! check_installation; then
        log_info "CheckMK agent not found. Nothing to uninstall."
        print_info "Nothing to uninstall. Exiting."
        exit 0
    fi
    
    # Ask for confirmation in interactive mode
    if ! confirm_action "Are you sure you want to uninstall the CheckMK agent?"; then
        log_info "Uninstallation cancelled by user"
        print_info "Uninstallation cancelled."
        exit 0
    fi
    
    log_info "User confirmed uninstallation"
    
    stop_services
    remove_package
    cleanup_files
    verify_removal
    
    print_header "Uninstallation Complete"
    print_success "CheckMK agent has been successfully removed!"
    print_info "Your system is no longer being monitored by CheckMK"
    
    # Save completion to log
    echo "Uninstallation completed at $(date)" >> "$LOG_FILE"
    log_info "CheckMK agent uninstallation completed successfully"
    log_info "Uninstallation log saved to: $LOG_FILE"
}

# Run main function
main "$@"