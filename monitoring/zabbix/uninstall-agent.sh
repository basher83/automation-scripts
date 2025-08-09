#!/bin/bash

# Script Name: uninstall-agent.sh
# Purpose: Removes the Zabbix monitoring agent from Debian/Ubuntu systems
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
#   - Zabbix agent installed
#
# Examples:
#   # Interactive uninstallation
#   sudo ./uninstall-agent.sh
#
#   # Non-interactive uninstallation (for automation)
#   sudo ./uninstall-agent.sh --non-interactive
#
#   # Remote execution
#   curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/monitoring/zabbix/uninstall-agent.sh | sudo bash

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
readonly SERVICE_NAME="zabbix-agent"
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
    echo "Uninstall Zabbix monitoring agent from Debian/Ubuntu systems"
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
    print_header "Checking Zabbix Agent Installation"
    
    local found=0
    
    # Check for various package names - use exact match to avoid duplicates
    local package_patterns=("zabbix-agent" "zabbix-agent2")
    for pattern in "${package_patterns[@]}"; do
        if dpkg -l | grep -q "^ii  ${pattern} "; then
            local version_info=$(dpkg -l | grep "^ii  ${pattern} " | awk '{print $3}' | head -1 || echo "unknown")
            print_info "Found package: $pattern"
            print_info "Version: $version_info"
            log_info "Found package $pattern version $version_info"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Package details: $(dpkg -l | grep "^ii  ${pattern} ")" >> "$LOG_FILE"
            found=1
        fi
    done
    
    # Also check for Zabbix agent2 plugins
    local plugin_packages=$(dpkg -l | grep "^ii  zabbix-agent2-plugin" | awk '{print $2}' || true)
    if [[ -n "$plugin_packages" ]]; then
        print_info "Found Zabbix agent2 plugins:"
        echo "$plugin_packages" | while read -r plugin; do
            if [[ -n "$plugin" ]]; then
                echo "  - $plugin"
            fi
        done
        log_info "Found Zabbix agent2 plugins: $(echo $plugin_packages | tr '\n' ' ')"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Plugin packages: $plugin_packages" >> "$LOG_FILE"
        found=1
    fi
    
    # Check for systemd services
    if systemctl list-units --all | grep -q "zabbix-agent"; then
        print_info "Found Zabbix systemd services"
        systemctl list-units --all | grep "zabbix-agent" | head -5
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Systemd services found:" >> "$LOG_FILE"
        systemctl list-units --all | grep "zabbix-agent" >> "$LOG_FILE" 2>&1
        found=1
    fi
    
    # Check for socket files
    if systemctl list-unit-files | grep -q "zabbix-agent"; then
        print_info "Found Zabbix systemd unit files"
        systemctl list-unit-files | grep "zabbix-agent"
        found=1
    fi
    
    # Check for running processes (exclude this uninstall script)
    local my_pid=$$
    local running_pids=$(pgrep -f "zabbix_agent" | grep -v "^${my_pid}$" || true)
    
    if [[ -n "$running_pids" ]]; then
        print_info "Found Zabbix processes running"
        echo "$running_pids" | head -5
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Running processes:" >> "$LOG_FILE"
        for pid in $running_pids; do
            ps -p "$pid" -o pid,comm,args 2>/dev/null >> "$LOG_FILE" || true
        done
        found=1
    fi
    
    # Check for listening ports (Zabbix agent ports: 10050 and 10051)
    if ss -tlnp | grep -E ":(10050|10051)"; then
        print_info "Found service listening on Zabbix agent ports (10050/10051)"
        ss -tlnp | grep -E ":(10050|10051)"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Port listeners:" >> "$LOG_FILE"
        ss -tlnp | grep -E ":(10050|10051)" >> "$LOG_FILE" 2>&1
        found=1
    fi
    
    # Check for binaries in specific locations only
    local binary_paths=(
        "/usr/sbin/zabbix_agentd"
        "/usr/sbin/zabbix_agent2"
        "/usr/bin/zabbix_get"
        "/usr/bin/zabbix_sender"
        "/usr/local/sbin/zabbix_agentd"
        "/usr/local/sbin/zabbix_agent2"
    )
    
    local found_binaries=""
    for binary in "${binary_paths[@]}"; do
        if [[ -f "$binary" ]]; then
            found_binaries="${found_binaries}${binary}\n"
        fi
    done
    
    if [[ -n "$found_binaries" ]]; then
        print_info "Found Zabbix binaries:"
        echo -e "$found_binaries"
        found=1
    fi
    
    if [[ $found -eq 1 ]]; then
        return 0
    else
        print_warning "Zabbix agent does not appear to be installed"
        return 1
    fi
}

# Stop agent services
stop_services() {
    print_header "Stopping Zabbix Agent Services"
    
    # List of Zabbix services to stop
    local zabbix_services=(
        "zabbix-agent.service"
        "zabbix-agent2.service"
    )
    
    # Stop specific Zabbix services
    for service in "${zabbix_services[@]}"; do
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
    
    # Disable services
    for service in "${zabbix_services[@]}"; do
        if systemctl list-unit-files | grep -q "^$service"; then
            print_info "Disabling $service..."
            systemctl disable "$service" 2>/dev/null || true
            print_success "Disabled $service"
        fi
    done
    
    # Kill any remaining Zabbix processes with timeout
    # Get our own PID to exclude from killing
    local my_pid=$$
    
    # Find Zabbix processes (excluding this script)
    local zabbix_pids=$(pgrep -f "zabbix_agent" | grep -v "^${my_pid}$" || true)
    
    if [[ -n "$zabbix_pids" ]]; then
        print_info "Killing remaining Zabbix processes..."
        
        # Kill specific PIDs (excluding our script)
        if [[ -n "$zabbix_pids" ]]; then
            echo "$zabbix_pids" | while read -r pid; do
                # Double-check we're not killing ourselves or the uninstall script
                local cmd=$(ps -p "$pid" -o comm= 2>/dev/null || true)
                if [[ -n "$cmd" ]] && [[ ! "$cmd" =~ uninstall ]]; then
                    kill -TERM "$pid" 2>/dev/null || true
                    log_info "Sent TERM signal to PID $pid ($cmd)"
                fi
            done
        fi
        
        sleep 1
        
        # Check if any are still running and force kill if needed
        zabbix_pids=$(pgrep -f "zabbix_agent" | grep -v "^${my_pid}$" || true)
        
        if [[ -n "$zabbix_pids" ]]; then
            if [[ -n "$zabbix_pids" ]]; then
                echo "$zabbix_pids" | while read -r pid; do
                    local cmd=$(ps -p "$pid" -o comm= 2>/dev/null || true)
                    if [[ -n "$cmd" ]] && [[ ! "$cmd" =~ uninstall ]]; then
                        kill -KILL "$pid" 2>/dev/null || true
                        log_warn "Force killed PID $pid ($cmd)"
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
    print_header "Removing Zabbix Agent Package"
    
    # First remove agent2 plugins if present
    local plugin_packages=$(dpkg -l | grep "^ii  zabbix-agent2-plugin" | awk '{print $2}' || true)
    if [[ -n "$plugin_packages" ]]; then
        print_info "Removing Zabbix agent2 plugins first..."
        echo "$plugin_packages" | while read -r plugin; do
            if [[ -n "$plugin" ]]; then
                print_info "Removing plugin: $plugin"
                log_info "Attempting to remove plugin: $plugin"
                if apt purge -y "$plugin" 2>&1 | tee -a "$LOG_FILE"; then
                    print_success "Plugin $plugin removed successfully"
                    log_info "Successfully removed plugin $plugin"
                else
                    print_warning "Failed to remove plugin $plugin"
                    log_warn "Failed to remove plugin $plugin"
                fi
            fi
        done
    fi
    
    # Check for zabbix-release package
    if dpkg -l | grep -q "^ii  zabbix-release "; then
        print_info "Removing zabbix-release package..."
        log_info "Attempting to remove zabbix-release package"
        if apt purge -y zabbix-release 2>&1 | tee -a "$LOG_FILE"; then
            print_success "Package zabbix-release removed successfully"
            log_info "Successfully removed zabbix-release"
        else
            print_warning "Failed to remove zabbix-release"
            log_warn "Failed to remove zabbix-release package"
        fi
    fi
    
    # Try different package names
    local package_patterns=("zabbix-agent" "zabbix-agent2")
    local removed=0
    
    for pattern in "${package_patterns[@]}"; do
        if dpkg -l | grep -q "^ii  ${pattern} "; then
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
    
    # Remove any remaining zabbix packages with wildcard
    print_info "Checking for any other Zabbix packages..."
    local all_zabbix_packages=$(dpkg -l | grep "^ii.*zabbix" | awk '{print $2}' || true)
    if [[ -n "$all_zabbix_packages" ]]; then
        print_info "Removing remaining Zabbix packages with autoremove..."
        log_info "Found additional Zabbix packages: $(echo $all_zabbix_packages | tr '\n' ' ')"
        if apt-get purge --autoremove -y 'zabbix-*' 2>&1 | tee -a "$LOG_FILE"; then
            print_success "All Zabbix packages removed"
            removed=1
        else
            print_warning "Some Zabbix packages may remain"
        fi
    fi
    
    if [[ $removed -eq 0 ]]; then
        print_warning "No Zabbix packages found to remove"
        print_info "The agent might be installed manually or via a different method"
    fi
    
    # Clean APT cache
    print_info "Cleaning APT cache..."
    log_info "Running apt-get clean and autoclean"
    apt-get clean 2>&1 | tee -a "$LOG_FILE" > /dev/null
    apt-get autoclean 2>&1 | tee -a "$LOG_FILE" > /dev/null
    print_success "APT cache cleaned"
}

# Clean up remaining files
cleanup_files() {
    print_header "Cleaning Up Remaining Files"
    
    local cleanup_dirs=(
        "/etc/zabbix"
        "/var/lib/zabbix"
        "/var/lib/zabbix-agent"
        "/var/lib/zabbix-agent2"
        "/var/log/zabbix"
        "/var/log/zabbix-agent"
        "/var/log/zabbix-agent2"
        "/usr/sbin/zabbix_agentd"
        "/usr/sbin/zabbix_agent2"
        "/usr/sbin/zabbix-agent2-plugin"
        "/usr/bin/zabbix_get"
        "/usr/bin/zabbix_sender"
        "/usr/share/zabbix-agent"
        "/usr/share/zabbix-agent2"
        "/run/zabbix"
        "/var/run/zabbix"
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
        "/etc/systemd/system/zabbix-agent.service"
        "/etc/systemd/system/zabbix-agent2.service"
        "/lib/systemd/system/zabbix-agent.service"
        "/lib/systemd/system/zabbix-agent2.service"
        "/usr/lib/systemd/system/zabbix-agent.service"
        "/usr/lib/systemd/system/zabbix-agent2.service"
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
        "/etc/systemd/system/*.wants/zabbix*"
        "/lib/systemd/system/*.wants/zabbix*"
        "/usr/lib/systemd/system/*.wants/zabbix*"
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
    
    # Remove Zabbix APT repository configurations
    print_info "Removing Zabbix APT repository configurations..."
    
    # Find all Zabbix-related repository files
    shopt -s nullglob
    local repo_files=(/etc/apt/sources.list.d/*zabbix*.list /etc/apt/sources.list.d/*zabbix*.sources)
    shopt -u nullglob
    
    # Add any specific known files
    local known_repos=(
        "/etc/apt/sources.list.d/zabbix.list"
        "/etc/apt/sources.list.d/zabbix-agent.list"
        "/etc/apt/sources.list.d/zabbix-tools.list"
        "/etc/apt/sources.list.d/zabbix-official.list"
    )
    
    for known_repo in "${known_repos[@]}"; do
        if [[ -f "$known_repo" ]] && [[ ! " ${repo_files[*]} " =~ " ${known_repo} " ]]; then
            repo_files+=("$known_repo")
        fi
    done
    
    for repo_file in "${repo_files[@]}"; do
        if [[ -f "$repo_file" ]]; then
            print_info "Removing repository file: $repo_file"
            log_info "Removing APT repository: $repo_file"
            if rm -f "$repo_file" 2>&1 | tee -a "$LOG_FILE"; then
                print_success "Removed $repo_file"
            else
                print_warning "Failed to remove $repo_file"
                log_warn "Failed to remove repository file: $repo_file"
            fi
        fi
    done
    
    # Remove Zabbix GPG keys
    local gpg_keys=(
        "/usr/share/keyrings/zabbix-archive-keyring.gpg"
        "/etc/apt/trusted.gpg.d/zabbix.gpg"
        "/etc/apt/trusted.gpg.d/zabbix-official.gpg"
    )
    
    for gpg_key in "${gpg_keys[@]}"; do
        if [[ -f "$gpg_key" ]]; then
            print_info "Removing GPG key: $gpg_key"
            log_info "Removing GPG key: $gpg_key"
            if rm -f "$gpg_key" 2>&1 | tee -a "$LOG_FILE"; then
                print_success "Removed $gpg_key"
            else
                print_warning "Failed to remove $gpg_key"
                log_warn "Failed to remove GPG key: $gpg_key"
            fi
        fi
    done
    
    # Also check for any Zabbix sources in the main sources.list
    if grep -q "zabbix" /etc/apt/sources.list 2>/dev/null; then
        print_warning "Found Zabbix entries in /etc/apt/sources.list"
        print_info "You may want to manually remove these entries from /etc/apt/sources.list"
        log_warn "Zabbix entries found in /etc/apt/sources.list - manual removal required"
    fi
    
    # Update APT cache after removing repositories
    if [[ -n "$(ls -A /etc/apt/sources.list.d/*zabbix* 2>/dev/null || true)" ]] || \
       [[ -n "$(find /etc/apt/sources.list.d/ -name "*zabbix*" 2>/dev/null || true)" ]]; then
        print_info "Some Zabbix repository files may still exist"
    else
        print_info "Updating APT cache after repository removal..."
        log_info "Updating APT cache"
        if apt-get update 2>&1 | tee -a "$LOG_FILE" > /dev/null; then
            print_success "APT cache updated"
        else
            print_warning "Failed to update APT cache"
        fi
    fi
    
    # Check for any remaining zabbix files in specific directories
    print_info "Checking for any remaining Zabbix files..."
    
    # Define specific paths to check (much faster than searching entire filesystem)
    local check_paths=(
        "/etc/zabbix*"
        "/usr/bin/zabbix*"
        "/usr/sbin/zabbix*"
        "/usr/local/bin/zabbix*"
        "/usr/local/sbin/zabbix*"
        "/usr/lib/zabbix*"
        "/var/lib/zabbix*"
        "/var/log/zabbix*"
        "/opt/zabbix*"
    )
    
    local remaining_files=""
    for path_pattern in "${check_paths[@]}"; do
        # Use shell globbing instead of find for speed
        # Note: We can't redirect glob expansion errors, so we check existence
        shopt -s nullglob  # Make globs expand to nothing if no matches
        for file in $path_pattern; do
            if [[ -e "$file" ]]; then
                # Filter out false positives
                if [[ ! "$file" =~ docker ]] && [[ ! "$file" =~ backup ]]; then
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
            for file in "$unit_dir"/zabbix*; do
                if [[ -f "$file" ]]; then
                    remaining_files="${remaining_files}${file}\n"
                fi
            done
            shopt -u nullglob
        fi
    done
    
    # Clean up all Zabbix log files (except our uninstall log)
    print_info "Cleaning up all Zabbix log files..."
    local log_files=$(find /var/log -name "*zabbix*" 2>/dev/null || true)
    if [[ -n "$log_files" ]]; then
        echo "$log_files" | while read -r logfile; do
            if [[ -n "$logfile" ]] && [[ "$logfile" != "$LOG_FILE" ]]; then
                if [[ ! "$logfile" =~ uninstall ]]; then
                    print_info "Removing log: $logfile"
                    rm -rf "$logfile" 2>/dev/null || true
                fi
            fi
        done
    fi
    
    # Check for zabbix user and group
    if id zabbix &>/dev/null; then
        print_info "Found zabbix user account"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Zabbix user found: $(id zabbix)" >> "$LOG_FILE"
        
        if [[ "$INTERACTIVE" == "true" ]]; then
            if confirm_action "Do you want to remove the zabbix user account?"; then
                print_info "Removing zabbix user account..."
                log_info "Removing zabbix user account"
                if userdel -r zabbix 2>&1 | tee -a "$LOG_FILE"; then
                    print_success "Zabbix user account removed"
                    log_info "Successfully removed zabbix user"
                else
                    # Try without -r flag if home directory issues
                    if userdel zabbix 2>&1 | tee -a "$LOG_FILE"; then
                        print_success "Zabbix user account removed (without home)"
                        log_info "Successfully removed zabbix user (without home)"
                    else
                        print_warning "Failed to remove zabbix user account"
                        log_warn "Failed to remove zabbix user account"
                    fi
                fi
                
                # Also remove group if it exists
                if getent group zabbix >/dev/null 2>&1; then
                    print_info "Removing zabbix group..."
                    if groupdel zabbix 2>&1 | tee -a "$LOG_FILE"; then
                        print_success "Zabbix group removed"
                        log_info "Successfully removed zabbix group"
                    else
                        print_warning "Failed to remove zabbix group"
                        log_warn "Failed to remove zabbix group"
                    fi
                fi
            else
                print_info "Preserving zabbix user account as requested"
                log_info "User chose to preserve zabbix user account"
            fi
        else
            # In non-interactive mode, preserve by default but inform how to remove
            print_warning "Zabbix user account preserved (run 'userdel -r zabbix' to remove)"
            log_info "Zabbix user account preserved in non-interactive mode"
        fi
    fi
    
    if [[ -n "$remaining_files" ]]; then
        print_warning "Found some remaining files:"
        echo -e "$remaining_files"
        print_info "You may want to review and remove these manually if needed"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Remaining files found:" >> "$LOG_FILE"
        echo -e "$remaining_files" >> "$LOG_FILE"
    else
        print_success "No remaining Zabbix files found"
        log_info "No remaining Zabbix files found"
    fi
}

# Verify removal
verify_removal() {
    print_header "Verifying Removal"
    
    local issues=0
    
    # Check packages
    log_info "Starting verification of removal"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Checking for remaining packages" >> "$LOG_FILE"
    
    # Check for main packages and plugins
    local remaining_packages=$(dpkg -l | grep "^ii.*zabbix-agent" | awk '{print $2}' || true)
    if [[ -n "$remaining_packages" ]]; then
        print_error "Zabbix packages still appear to be installed:"
        echo "$remaining_packages" | while read -r pkg; do
            if [[ -n "$pkg" ]]; then
                echo "  - $pkg"
            fi
        done
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] Packages still installed:" >> "$LOG_FILE"
        echo "$remaining_packages" >> "$LOG_FILE"
        issues=1
    else
        print_success "All Zabbix packages successfully removed"
        log_info "Package removal verified"
    fi
    
    # Check for specific services
    local zabbix_services=(
        "zabbix-agent.service"
        "zabbix-agent2.service"
    )
    
    for service in "${zabbix_services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            print_warning "Service $service is still running"
            issues=1
        fi
    done
    
    if [[ $issues -eq 0 ]]; then
        print_success "No Zabbix services are running"
    fi
    
    # Check for any remaining Zabbix units (not-found units are expected after uninstall)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Checking for remaining systemd units" >> "$LOG_FILE"
    local remaining_units=$(systemctl list-units --all | grep -i "zabbix" | grep -v "slice" | grep -v "not-found" || true)
    if [[ -n "$remaining_units" ]]; then
        print_warning "Found remaining Zabbix systemd units:"
        echo "$remaining_units"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] Remaining systemd units:" >> "$LOG_FILE"
        echo "$remaining_units" >> "$LOG_FILE"
        issues=1
    else
        print_success "No active Zabbix systemd units remaining"
        log_info "No active systemd units found"
    fi
    
    # Check listening ports (Zabbix agent ports: 10050 and 10051)
    if ss -tlnp | grep -E ":(10050|10051)"; then
        print_warning "Zabbix agent ports (10050/10051) are still in use"
        ss -tlnp | grep -E ":(10050|10051)"
        issues=1
    else
        print_success "Zabbix agent ports (10050/10051) are not in use"
    fi
    
    # Check for running processes (excluding this script)
    local my_pid=$$
    local remaining_pids=$(pgrep -f "zabbix_agent" | grep -v "^${my_pid}$" || true)
    
    # Filter out any invalid PIDs
    local valid_pids=""
    for pid in $remaining_pids; do
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            valid_pids="$valid_pids $pid"
        fi
    done
    
    if [[ -n "$valid_pids" ]]; then
        print_warning "Zabbix processes are still running:"
        for pid in $valid_pids; do
            local info=$(ps -p "$pid" -o pid,comm,args --no-headers 2>/dev/null || true)
            if [[ -n "$info" ]]; then
                echo "  $info"
            fi
        done
        issues=1
    else
        print_success "No Zabbix processes running"
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
    
    echo -e "${BOLD}${CYAN}Zabbix Agent Uninstallation Script${NC}"
    echo -e "${CYAN}==================================${NC}"
    print_info "Log file: $LOG_FILE"
    echo ""
    
    log_info "Starting Zabbix agent uninstallation"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Script version: 1.0" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Running as user: $(whoami)" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] System: $(uname -a)" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Interactive mode: $INTERACTIVE" >> "$LOG_FILE"
    
    check_privileges
    
    if ! check_installation; then
        log_info "Zabbix agent not found. Nothing to uninstall."
        print_info "Nothing to uninstall. Exiting."
        exit 0
    fi
    
    # Ask for confirmation in interactive mode
    if ! confirm_action "Are you sure you want to uninstall the Zabbix agent?"; then
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
    print_success "Zabbix agent has been successfully removed!"
    print_info "Your system is no longer being monitored by Zabbix"
    
    # Save completion to log
    echo "Uninstallation completed at $(date)" >> "$LOG_FILE"
    log_info "Zabbix agent uninstallation completed successfully"
    
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ Uninstallation log saved to: ${BOLD}$LOG_FILE${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
}

# Run main function
main "$@"