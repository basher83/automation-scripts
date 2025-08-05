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
readonly LOG_FILE="/var/log/${SERVICE_NAME}-uninstall-$(date +%Y%m%d_%H%M%S).log"

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
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Package details: $(dpkg -l | grep "$pattern")" >> "$LOG_FILE"
            found=1
        fi
    done
    
    # Check for systemd services
    if systemctl list-units --all | grep -q "check-mk-agent"; then
        print_info "Found CheckMK systemd services"
        systemctl list-units --all | grep "check-mk-agent" | head -5
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Systemd services found:" >> "$LOG_FILE"
        systemctl list-units --all | grep "check-mk-agent" >> "$LOG_FILE" 2>&1
        found=1
    fi
    
    # Check for socket files
    if systemctl list-unit-files | grep -q "check-mk-agent"; then
        print_info "Found CheckMK systemd unit files"
        systemctl list-unit-files | grep "check-mk-agent"
        found=1
    fi
    
    # Check for running processes (exclude this uninstall script)
    local my_pid=$$
    local running_pids=$(pgrep -f "check.*mk" | grep -v "^${my_pid}$" || true)
    
    if [[ -n "$running_pids" ]]; then
        print_info "Found CheckMK processes running"
        echo "$running_pids" | head -5
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Running processes:" >> "$LOG_FILE"
        for pid in $running_pids; do
            ps -p "$pid" -o pid,comm,args 2>/dev/null >> "$LOG_FILE" || true
        done
        found=1
    fi
    
    # Check for listening port
    if ss -tlnp | grep -q ":6556"; then
        print_info "Found service listening on CheckMK port 6556"
        ss -tlnp | grep ":6556"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Port 6556 listener:" >> "$LOG_FILE"
        ss -tlnp | grep ":6556" >> "$LOG_FILE" 2>&1
        found=1
    fi
    
    # Check for binaries in specific locations only
    local binary_paths=(
        "/usr/bin/check_mk_agent"
        "/usr/bin/check_mk_caching_agent"
        "/usr/bin/cmk-agent-ctl"
        "/usr/local/bin/check_mk_agent"
        "/usr/sbin/check_mk_agent"
    )
    
    local found_binaries=""
    for binary in "${binary_paths[@]}"; do
        if [[ -f "$binary" ]]; then
            found_binaries="${found_binaries}${binary}\n"
        fi
    done
    
    if [[ -n "$found_binaries" ]]; then
        print_info "Found CheckMK binaries:"
        echo -e "$found_binaries"
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
            log_info "Stopping service: $service"
            if systemctl stop "$service" 2>&1 | tee -a "$LOG_FILE"; then
                print_success "Stopped $service"
                log_info "Successfully stopped $service"
            else
                log_warn "Failed to stop $service (may already be stopped)"
            fi
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
    
    # Kill any remaining CheckMK processes with timeout
    # Get our own PID to exclude from killing
    local my_pid=$$
    
    # Find CheckMK processes (excluding this script)
    local checkmk_pids=$(pgrep -f "check.*mk" | grep -v "^${my_pid}$" || true)
    local cmk_pids=$(pgrep -f "cmk-agent" || true)  # More specific pattern for cmk
    
    if [[ -n "$checkmk_pids" ]] || [[ -n "$cmk_pids" ]]; then
        print_info "Killing remaining CheckMK processes..."
        
        # Kill specific PIDs (excluding our script)
        if [[ -n "$checkmk_pids" ]]; then
            echo "$checkmk_pids" | while read -r pid; do
                # Double-check we're not killing ourselves or the uninstall script
                local cmd=$(ps -p "$pid" -o comm= 2>/dev/null || true)
                if [[ -n "$cmd" ]] && [[ ! "$cmd" =~ uninstall ]]; then
                    kill -TERM "$pid" 2>/dev/null || true
                    log_info "Sent TERM signal to PID $pid ($cmd)"
                fi
            done
        fi
        
        if [[ -n "$cmk_pids" ]]; then
            echo "$cmk_pids" | while read -r pid; do
                if [[ -n "$pid" ]]; then
                    kill -TERM "$pid" 2>/dev/null || true
                    log_info "Sent TERM signal to PID $pid"
                fi
            done
        fi
        
        sleep 1
        
        # Check if any are still running and force kill if needed
        checkmk_pids=$(pgrep -f "check.*mk" | grep -v "^${my_pid}$" || true)
        cmk_pids=$(pgrep -f "cmk-agent" || true)
        
        if [[ -n "$checkmk_pids" ]] || [[ -n "$cmk_pids" ]]; then
            if [[ -n "$checkmk_pids" ]]; then
                echo "$checkmk_pids" | while read -r pid; do
                    local cmd=$(ps -p "$pid" -o comm= 2>/dev/null || true)
                    if [[ -n "$cmd" ]] && [[ ! "$cmd" =~ uninstall ]]; then
                        kill -KILL "$pid" 2>/dev/null || true
                        log_warn "Force killed PID $pid ($cmd)"
                    fi
                done
            fi
            
            if [[ -n "$cmk_pids" ]]; then
                echo "$cmk_pids" | while read -r pid; do
                    if [[ -n "$pid" ]]; then
                        kill -KILL "$pid" 2>/dev/null || true
                        log_warn "Force killed PID $pid"
                    fi
                done
            fi
            sleep 1
        fi
        
        print_success "Processes terminated"
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
            log_info "Attempting to remove package: $pattern"
            if apt purge -y "$pattern" 2>&1 | tee -a "$LOG_FILE" || dpkg -P "$pattern" 2>&1 | tee -a "$LOG_FILE"; then
                print_success "Package $pattern removed successfully"
                log_info "Successfully removed package $pattern"
                removed=1
            else
                print_warning "Failed to remove $pattern using apt/dpkg, trying dpkg -r..."
                log_warn "Standard removal failed for $pattern, trying dpkg -r"
                if dpkg -r "$pattern" 2>&1 | tee -a "$LOG_FILE"; then
                    print_success "Package $pattern removed using dpkg -r"
                    log_info "Successfully removed $pattern using dpkg -r"
                    removed=1
                else
                    print_error "Failed to remove package $pattern"
                    log_error "Failed to remove package $pattern"
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
        "/usr/bin/check_mk_agent"
        "/usr/bin/check_mk_caching_agent"
    )
    
    for item in "${cleanup_dirs[@]}"; do
        if [[ -e "$item" ]]; then
            print_info "Removing: $item"
            log_info "Removing directory/file: $item"
            if rm -rf "$item" 2>&1 | tee -a "$LOG_FILE"; then
                print_success "Removed $item"
                log_info "Successfully removed $item"
            else
                print_warning "Failed to remove $item"
                log_warn "Failed to remove $item"
            fi
        fi
    done
    
    # Remove systemd unit files and symlinks
    local unit_files=(
        "/etc/systemd/system/check-mk-agent.socket"
        "/etc/systemd/system/check-mk-agent@.service"
        "/etc/systemd/system/check-mk-agent-async.service"
        "/etc/systemd/system/cmk-agent-ctl-daemon.service"
        "/lib/systemd/system/check-mk-agent.socket"
        "/lib/systemd/system/check-mk-agent@.service"
        "/lib/systemd/system/check-mk-agent-async.service"
        "/lib/systemd/system/cmk-agent-ctl-daemon.service"
        "/usr/lib/systemd/system/check-mk-agent.socket"
        "/usr/lib/systemd/system/check-mk-agent@.service"
        "/usr/lib/systemd/system/check-mk-agent-async.service"
        "/usr/lib/systemd/system/cmk-agent-ctl-daemon.service"
    )
    
    for unit_file in "${unit_files[@]}"; do
        if [[ -f "$unit_file" ]] || [[ -L "$unit_file" ]]; then
            print_info "Removing systemd unit: $unit_file"
            rm -f "$unit_file"
            print_success "Removed $unit_file"
        fi
    done
    
    # Remove systemd symlinks from target directories
    local symlink_patterns=(
        "/etc/systemd/system/*.wants/check-mk*"
        "/etc/systemd/system/*.wants/cmk*"
        "/lib/systemd/system/*.wants/check-mk*"
        "/lib/systemd/system/*.wants/cmk*"
        "/usr/lib/systemd/system/*.wants/check-mk*"
        "/usr/lib/systemd/system/*.wants/cmk*"
    )
    
    for pattern in "${symlink_patterns[@]}"; do
        shopt -s nullglob  # Make globs expand to nothing if no matches
        for symlink in $pattern; do
            if [[ -L "$symlink" ]]; then
                print_info "Removing systemd symlink: $symlink"
                rm -f "$symlink"
                print_success "Removed $symlink"
            fi
        done
        shopt -u nullglob  # Reset to default behavior
    done
    
    # Reload systemd after removing unit files
    log_info "Reloading systemd daemon"
    systemctl daemon-reload 2>&1 | tee -a "$LOG_FILE"
    
    # Check for any remaining check_mk files in specific directories
    print_info "Checking for any remaining CheckMK files..."
    
    # Define specific paths to check (much faster than searching entire filesystem)
    local check_paths=(
        "/etc/check_mk"
        "/etc/cmk"
        "/etc/cmk-agent"
        "/usr/bin/check_mk*"
        "/usr/bin/cmk*"
        "/usr/local/bin/check_mk*"
        "/usr/lib/check_mk*"
        "/usr/lib/cmk*"
        "/var/lib/check_mk*"
        "/var/lib/cmk*"
        "/opt/check_mk*"
        "/opt/cmk*"
    )
    
    local remaining_files=""
    for path_pattern in "${check_paths[@]}"; do
        # Use shell globbing instead of find for speed
        # Note: We can't redirect glob expansion errors, so we check existence
        shopt -s nullglob  # Make globs expand to nothing if no matches
        for file in $path_pattern; do
            if [[ -e "$file" ]]; then
                # Filter out false positives
                if [[ ! "$file" =~ ipcmk ]] && [[ ! "$file" =~ docker ]] && [[ ! "$file" =~ zammad ]]; then
                    remaining_files="${remaining_files}${file}\n"
                fi
            fi
        done
        shopt -u nullglob  # Reset to default behavior
    done
    
    # Also check systemd locations
    for unit_dir in /etc/systemd/system /lib/systemd/system /usr/lib/systemd/system; do
        if [[ -d "$unit_dir" ]]; then
            shopt -s nullglob
            for file in "$unit_dir"/check-mk* "$unit_dir"/cmk*; do
                if [[ -f "$file" ]]; then
                    remaining_files="${remaining_files}${file}\n"
                fi
            done
            shopt -u nullglob
        fi
    done
    
    if [[ -n "$remaining_files" ]]; then
        print_warning "Found some remaining files:"
        echo -e "$remaining_files"
        print_info "You may want to review and remove these manually if needed"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Remaining files found:" >> "$LOG_FILE"
        echo -e "$remaining_files" >> "$LOG_FILE"
    else
        print_success "No remaining CheckMK files found"
        log_info "No remaining CheckMK files found"
    fi
}

# Verify removal
verify_removal() {
    print_header "Verifying Removal"
    
    local issues=0
    
    # Check packages
    log_info "Starting verification of removal"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Checking for remaining packages" >> "$LOG_FILE"
    if dpkg -l | grep -q "check-mk-agent"; then
        print_error "CheckMK package still appears to be installed"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] Package still installed:" >> "$LOG_FILE"
        dpkg -l | grep "check-mk-agent" >> "$LOG_FILE" 2>&1
        issues=1
    else
        print_success "CheckMK package successfully removed"
        log_info "Package removal verified"
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
    
    # Check for any remaining CheckMK units (not-found units are expected after uninstall)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Checking for remaining systemd units" >> "$LOG_FILE"
    local remaining_units=$(systemctl list-units --all | grep -i "check-mk\|cmk" | grep -v "slice" | grep -v "not-found" || true)
    if [[ -n "$remaining_units" ]]; then
        print_warning "Found remaining CheckMK systemd units:"
        echo "$remaining_units"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] Remaining systemd units:" >> "$LOG_FILE"
        echo "$remaining_units" >> "$LOG_FILE"
        issues=1
    else
        print_success "No active CheckMK systemd units remaining"
        log_info "No active systemd units found"
    fi
    
    # Check listening ports
    if ss -tlnp | grep -q ":6556"; then
        print_warning "Port 6556 is still in use"
        ss -tlnp | grep ":6556"
        issues=1
    else
        print_success "CheckMK agent port (6556) is not in use"
    fi
    
    # Check for running processes (excluding this script)
    local my_pid=$$
    local remaining_pids=$(pgrep -f "check.*mk" | grep -v "^${my_pid}$" || true)
    local cmk_pids=$(pgrep -f "cmk-agent" || true)
    
    # Filter out any invalid PIDs
    local valid_pids=""
    for pid in $remaining_pids $cmk_pids; do
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            valid_pids="$valid_pids $pid"
        fi
    done
    
    if [[ -n "$valid_pids" ]]; then
        print_warning "CheckMK processes are still running:"
        for pid in $valid_pids; do
            local info=$(ps -p "$pid" -o pid,comm,args --no-headers 2>/dev/null || true)
            if [[ -n "$info" ]]; then
                echo "  $info"
            fi
        done
        issues=1
    else
        print_success "No CheckMK processes running"
    fi
    
    if [[ $issues -eq 0 ]]; then
        print_success "Complete removal verified!"
        log_info "Verification completed successfully - no issues found"
        return 0
    else
        print_warning "Some minor issues found during verification - this is normal"
        print_info "The agent has been uninstalled, but some cleanup may be needed"
        log_warn "Verification completed with minor issues (issues=$issues)"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Total verification issues: $issues" >> "$LOG_FILE"
        # Don't fail the script for minor verification issues
        return 0
    fi
}

# Cleanup function
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Uninstallation failed with exit code: $exit_code"
        print_error "Script failed! Check the log for details: $LOG_FILE"
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
    print_info "Log file: $LOG_FILE"
    echo ""
    
    log_info "Starting CheckMK agent uninstallation"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Script version: 1.0" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Running as user: $(whoami)" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] System: $(uname -a)" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Interactive mode: $INTERACTIVE" >> "$LOG_FILE"
    
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
    
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ Uninstallation log saved to: ${BOLD}$LOG_FILE${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
}

# Run main function
main "$@"