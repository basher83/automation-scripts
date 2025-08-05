# Coding Standards for Automation Scripts

This document establishes coding standards and best practices for all shell scripts in the automation-scripts repository. Following these standards ensures consistency, maintainability, and reliability across all scripts.

## Table of Contents

1. [Shell Script Header Patterns](#shell-script-header-patterns)
1. [Remote Execution Optimization](#remote-execution-optimization)
1. [Logging Standards](#logging-standards)
1. [Color Output Functions](#color-output-functions)
1. [Error Handling and Cleanup](#error-handling-and-cleanup)
1. [Interactive vs Non-Interactive Mode](#interactive-vs-non-interactive-mode)
1. [Shell Globbing and File Patterns](#shell-globbing-and-file-patterns)
1. [Process Management and Safe Termination](#process-management-and-safe-termination)
1. [Temporary File Usage](#temporary-file-usage)
1. [Security Practices](#security-practices)
1. [Complete Cleanup Patterns](#complete-cleanup-patterns)
1. [Idempotency Requirements](#idempotency-requirements)
1. [Documentation Requirements](#documentation-requirements)

## Shell Script Header Patterns

Every shell script must begin with the following structure:

```bash
#!/bin/bash

# Script Name and Purpose
# Brief description of what this script does
# Additional context or usage information

set -euo pipefail
trap 'echo "Error occurred at line $LINENO. Exit code: $?" >&2' ERR
```

### Required Elements

1. **Shebang**: Always use `#!/bin/bash` for consistency
1. **Script documentation**: Clear comments explaining the script's purpose
1. **Error handling options**: 
   - `set -e`: Exit on error
   - `set -u`: Exit on undefined variable
   - `set -o pipefail`: Exit on pipe failure
1. **Error trap**: Capture and report the exact line where errors occur

### Example

```bash
#!/bin/bash

# Prometheus PVE Exporter Bootstrap Script
# This script installs and configures prometheus-pve-exporter on a Proxmox host
# Usage: ./install-pve-exporter.sh

set -euo pipefail
trap 'echo "Error occurred at line $LINENO. Exit code: $?" >&2' ERR
```

## Remote Execution Optimization

All scripts must be optimized for quick deployment and remote execution to support infrastructure automation across multiple nodes.

### Core Requirements

1. **Self-contained execution**: Scripts must not rely on external files or relative paths
1. **Minimal dependencies**: Check and install dependencies within the script
1. **Non-interactive by default**: Support fully automated execution via curl/wget
1. **Environment variable support**: Allow configuration via environment variables
1. **Graceful degradation**: Continue with warnings for non-critical failures

### Remote Execution Pattern

Every script should support this standard remote execution pattern:

```bash
# Basic remote execution
curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/path/to/script.sh | bash

# With sudo (when required)
curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/path/to/script.sh | sudo bash

# With parameters
curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/path/to/script.sh | bash -s -- --option value

# Non-interactive mode
curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/path/to/script.sh | bash -s -- --non-interactive
```

### Implementation Guidelines

```bash
# Support both local and remote execution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# For remote execution, SCRIPT_DIR may not be meaningful, so don't rely on it

# Environment variable configuration with defaults
readonly SERVICE_PORT="${SERVICE_PORT:-9100}"
readonly INSTALL_PATH="${INSTALL_PATH:-/opt/service}"
readonly LOG_LEVEL="${LOG_LEVEL:-info}"

# Non-interactive mode support
INTERACTIVE=true
if [[ ! -t 0 ]] || [[ "${NON_INTERACTIVE:-}" == "true" ]] || [[ "$*" == *"--non-interactive"* ]]; then
    INTERACTIVE=false
fi

# Auto-accept prompts in non-interactive mode
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
```

### Dependency Management

```bash
# Check and install dependencies
check_dependencies() {
    local deps=("curl" "jq" "systemctl")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warn "Missing dependencies: ${missing[*]}"
        if [[ "$INTERACTIVE" == "false" ]] || confirm_action "Install missing dependencies?"; then
            apt-get update && apt-get install -y "${missing[@]}"
        else
            log_error "Required dependencies not installed"
            exit 1
        fi
    fi
}
```

### URL-Safe Operations

```bash
# Download files with proper error handling
download_file() {
    local url="$1"
    local dest="$2"
    local max_retries=3
    local retry=0
    
    while [[ $retry -lt $max_retries ]]; do
        if curl -fsSL --connect-timeout 10 --max-time 60 "$url" -o "$dest"; then
            return 0
        fi
        retry=$((retry + 1))
        log_warn "Download failed, retry $retry/$max_retries"
        sleep 2
    done
    
    return 1
}

# Use raw GitHub URLs for configs
readonly CONFIG_URL="https://raw.githubusercontent.com/basher83/automation-scripts/main/configs/service.conf"
```

### Examples in README

Each script's README should include remote execution examples:

```markdown
## Quick Deployment

### Remote Execution

```bash
# Install on a single node
curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/service/install.sh | sudo bash

# Install across multiple nodes (example with Ansible)
ansible all -m shell -a "curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/service/install.sh | sudo bash"

# With custom configuration
export SERVICE_PORT=9200
export INSTALL_PATH=/usr/local/service
curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/service/install.sh | sudo bash

# Non-interactive installation
curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/service/install.sh | sudo NON_INTERACTIVE=true bash
```
```

### Infrastructure Automation Examples

Scripts should include examples for common infrastructure automation tools:

```bash
# Ansible - Deploy to inventory group
ansible webservers -m shell -a "curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/service/install.sh | sudo bash -s -- --non-interactive"

# Ansible - With variables
ansible nomad_cluster -m shell -a "curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/service/install.sh | sudo bash" \
  -e "SERVICE_PORT=9200 INSTALL_PATH=/opt/custom"

# Ansible - Using raw module for systems without Python
ansible all -m raw -a "curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/bootstrap/bootstrap.sh | sudo bash"

# Parallel SSH (pssh) - Deploy to multiple hosts
pssh -h hosts.txt -l ubuntu -A -i "curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/service/install.sh | sudo bash"

# GNU Parallel - Deploy with host-specific configs
parallel -j 10 --slf hosts.txt --nonall "curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/service/install.sh | sudo NFT_PORT={} bash" ::: 9100 9200 9300

# Salt - Execute across minions
salt '*' cmd.run "curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/service/install.sh | sudo bash"

# Fabric - Python-based deployment
fab -H host1,host2,host3 -- "curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/service/install.sh | sudo bash"
```

### Multi-Stage Deployment Pattern

For complex deployments, show progressive examples:

```bash
# Stage 1: Test on single node
curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/service/install.sh | sudo bash -s -- --dry-run

# Stage 2: Deploy to staging
ansible staging -m shell -a "curl -fsSL $SCRIPT_URL | sudo bash -s -- --non-interactive"

# Stage 3: Rolling deployment to production
ansible production -m shell -a "curl -fsSL $SCRIPT_URL | sudo bash -s -- --non-interactive" --forks 5

# Stage 4: Verify deployment
ansible all -m shell -a "systemctl status service-name"
```

## Logging Standards

Scripts that perform installations or significant system changes must save comprehensive logs to `/var/log/` with timestamped filenames to prevent overwriting.

### Standard Logging Pattern

```bash
# Define log file with timestamp to prevent overwriting
readonly LOG_FILE="/var/log/${SERVICE_NAME}-${ACTION}-$(date +%Y%m%d_%H%M%S).log"

# Initialize log file
echo "${ACTION^} started at $(date)" > "$LOG_FILE"
chmod 640 "$LOG_FILE"

# Notify user about log location at script start
print_info "Log file: $LOG_FILE"

# Combined console and file logging functions
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

# Log debug information
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Script version: 1.0" >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Running as user: $(whoami)" >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] System: $(uname -a)" >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Interactive mode: $INTERACTIVE" >> "$LOG_FILE"
```

### Key Requirements

1. **Log location**: Always use `/var/log/` for system-wide scripts
1. **Timestamped filenames**: Use format `${SERVICE_NAME}-${ACTION}-$(date +%Y%m%d_%H%M%S).log`
1. **Dual logging**: Log to both console and file simultaneously
1. **Log levels**: Use INFO, WARN, ERROR, and DEBUG appropriately
1. **System context**: Log script version, user, system info, and mode at start
1. **Command output**: Use `tee -a "$LOG_FILE"` to capture command outputs
1. **Permissions**: Set restrictive permissions (640) immediately after creation
1. **User notification**: Show log location at start, end, and on error

### Logging Levels

```bash
# INFO - Normal operations and milestones
log_info "Starting service installation"
log_info "Service installed successfully"

# WARN - Non-critical issues that don't stop execution
log_warn "Service already exists, will upgrade"
log_warn "Optional dependency not found, skipping"

# ERROR - Critical failures
log_error "Installation failed: missing required dependency"
log_error "Unable to start service"

# DEBUG - Detailed diagnostic information (only to file)
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Package details: $(dpkg -l | grep 'service')" >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Systemd units: $(systemctl list-units --all | grep 'service')" >> "$LOG_FILE"
```

### User Notification Patterns

```bash
# At script start
echo -e "${BOLD}${CYAN}Service Installation Script${NC}"
echo -e "${CYAN}===================================${NC}"
print_info "Log file: $LOG_FILE"
echo ""

# On successful completion
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Installation completed successfully!${NC}"
echo -e "${GREEN}✓ Log saved to: ${BOLD}$LOG_FILE${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"

# On error (in cleanup trap)
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed with exit code: $exit_code"
        print_error "Script failed! Check the log for details: $LOG_FILE"
    fi
}
trap cleanup EXIT
```

### Capturing Command Output

```bash
# Log command output while showing progress
if systemctl stop "$service" 2>&1 | tee -a "$LOG_FILE"; then
    log_info "Successfully stopped $service"
else
    log_warn "Failed to stop $service (may already be stopped)"
fi

# Log detailed output only to file
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Service status:" >> "$LOG_FILE"
systemctl status "$service" >> "$LOG_FILE" 2>&1

# Use process substitution for complex pipelines
dpkg -l | grep "package" | tee >(cat >> "$LOG_FILE") | head -5
```

### Examples

```bash
# Installation scripts
LOG_FILE="/var/log/checkmk-agent-install-$(date +%Y%m%d_%H%M%S).log"

# Uninstallation scripts
LOG_FILE="/var/log/checkmk-agent-uninstall-$(date +%Y%m%d_%H%M%S).log"

# Backup scripts
LOG_FILE="/var/log/pve-backup-$(date +%Y%m%d_%H%M%S).log"

# Update scripts
LOG_FILE="/var/log/${SERVICE_NAME}-update-$(date +%Y%m%d_%H%M%S).log"
```

## Color Output Functions

Define consistent color output functions for better user experience while supporting non-color terminals.

### Standard Color Functions

```bash
# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
```

### Color Detection Pattern

For scripts that need to support both colored and non-colored output:

```bash
# Color codes for output (check if terminal supports colors)
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
```

## Error Handling and Cleanup

Proper error handling ensures scripts fail gracefully and clean up resources.

### Trap Pattern

```bash
# Basic error trap with log notification
trap 'echo "Error occurred at line $LINENO. Exit code: $?" >&2' ERR

# Cleanup trap for temporary files
temp_file=$(mktemp)
trap 'rm -f "$temp_file"' EXIT

# Combined cleanup and error handling with log notification
cleanup() {
    local exit_code=$?
    [[ -f "$temp_file" ]] && rm -f "$temp_file"
    [[ -d "$temp_dir" ]] && rm -rf "$temp_dir"
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed with exit code: $exit_code"
        print_error "Script failed! Check the log for details: $LOG_FILE"
    fi
}
trap cleanup EXIT

# Advanced pattern with both ERR and EXIT traps
set -euo pipefail
trap 'echo "Error occurred at line $LINENO. Exit code: $?" >&2' ERR
trap cleanup EXIT
```

### Error Checking Examples

```bash
# Check command availability
if ! command -v rg &> /dev/null; then
    log_error "ripgrep (rg) is not installed"
    exit 1
fi

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

# Check directory exists
if [[ ! -d "$LOG_PATH" ]]; then
    log_error "Log path '$LOG_PATH' does not exist"
    exit 1
fi
```

## Interactive vs Non-Interactive Mode

Scripts should handle both interactive and non-interactive execution gracefully.

### TTY Detection

```bash
# Check if running interactively
if [[ -t 0 ]]; then
    # Interactive mode - can prompt user
    read -p "Continue? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    # Non-interactive mode - proceed without prompts
    log_info "Running in non-interactive mode"
fi
```

### Auto-Detection Example

```bash
# Auto-detect if we should use colors
if [[ ! -t 1 ]] || [[ "${TERM:-}" == "dumb" ]] || [[ -n "${NO_COLOR:-}" ]]; then
    USE_COLOR=false
fi

# Support command-line override
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-color|--plain)
            USE_COLOR=false
            shift
            ;;
    esac
done
```

## Shell Globbing and File Patterns

Proper handling of shell glob patterns prevents errors and improves script reliability.

### Glob Expansion Patterns

```bash
# INCORRECT - This will cause syntax errors
for file in /path/to/files/* 2>/dev/null; do
    # This doesn't work - can't redirect glob expansion
done

# CORRECT - Use nullglob to handle no matches gracefully
shopt -s nullglob  # Globs expand to nothing if no matches
for file in /path/to/files/*; do
    if [[ -e "$file" ]]; then
        # Process file
    fi
done
shopt -u nullglob  # Reset to default behavior
```

### Safe File Search Patterns

```bash
# Fast targeted search instead of slow filesystem-wide find
search_for_files() {
    local patterns=(
        "/etc/service/*"
        "/usr/bin/service*"
        "/var/lib/service/*"
    )
    
    local found_files=""
    for pattern in "${patterns[@]}"; do
        shopt -s nullglob
        for file in $pattern; do
            if [[ -e "$file" ]]; then
                found_files="${found_files}${file}\n"
            fi
        done
        shopt -u nullglob
    done
    
    if [[ -n "$found_files" ]]; then
        echo -e "$found_files"
    fi
}

# Filter false positives when searching
shopt -s nullglob
for file in /usr/bin/*mk*; do
    # Filter out unrelated matches
    if [[ ! "$file" =~ ipcmk ]] && [[ ! "$file" =~ somethingelse ]]; then
        echo "Found: $file"
    fi
done
shopt -u nullglob
```

### Performance Optimization

```bash
# SLOW - Searches entire filesystem
find /usr /etc /var -name "*pattern*" 2>/dev/null

# FAST - Targeted search with specific paths
local check_paths=(
    "/etc/pattern*"
    "/usr/bin/pattern*"
    "/usr/local/bin/pattern*"
    "/var/lib/pattern*"
)

for path in "${check_paths[@]}"; do
    shopt -s nullglob
    for file in $path; do
        # Process matches
    done
    shopt -u nullglob
done
```

### Glob Options

```bash
# Common shell options for glob handling
shopt -s nullglob    # Patterns that match nothing expand to nothing
shopt -s failglob    # Patterns that match nothing cause an error
shopt -s dotglob     # Include hidden files in matches
shopt -s globstar    # Enable ** for recursive matching

# Always reset options after use
shopt -u nullglob
```

## Process Management and Safe Termination

Scripts that manage processes must ensure they don't accidentally terminate themselves or critical system processes.

### Avoiding Self-Termination

When killing processes by pattern, always exclude the current script:

```bash
# INCORRECT - This can kill the script itself
pkill -f "service.*pattern"  # Dangerous if script name matches!

# CORRECT - Exclude current script's PID
local my_pid=$$
local target_pids=$(pgrep -f "service.*pattern" | grep -v "^${my_pid}$" || true)

if [[ -n "$target_pids" ]]; then
    echo "$target_pids" | while read -r pid; do
        # Double-check we're not killing critical processes
        local cmd=$(ps -p "$pid" -o comm= 2>/dev/null || true)
        if [[ -n "$cmd" ]] && [[ ! "$cmd" =~ uninstall ]] && [[ ! "$cmd" =~ upgrade ]]; then
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done
fi
```

### Safe Process Termination Pattern

```bash
kill_service_processes() {
    local service_name="$1"
    local my_pid=$$
    
    # Find processes, excluding our script
    local pids=$(pgrep -f "$service_name" | grep -v "^${my_pid}$" || true)
    
    if [[ -z "$pids" ]]; then
        log_info "No $service_name processes found"
        return 0
    fi
    
    log_info "Stopping $service_name processes..."
    
    # Try graceful termination first
    for pid in $pids; do
        if kill -TERM "$pid" 2>/dev/null; then
            log_info "Sent TERM signal to PID $pid"
        fi
    done
    
    # Wait for processes to exit
    sleep 2
    
    # Force kill if still running
    pids=$(pgrep -f "$service_name" | grep -v "^${my_pid}$" || true)
    if [[ -n "$pids" ]]; then
        for pid in $pids; do
            if kill -KILL "$pid" 2>/dev/null; then
                log_warn "Force killed PID $pid"
            fi
        done
    fi
    
    log_info "$service_name processes terminated"
}
```

### Process Discovery Best Practices

```bash
# Use specific patterns to avoid false positives
# BAD: Too broad
pgrep -f "mk"  # Matches too many things

# GOOD: More specific
pgrep -f "check_mk_agent"  # Specific binary name
pgrep -f "cmk-agent-ctl"   # Exact service name

# When searching for multiple patterns
local check_pids=$(pgrep -f "check_mk_agent" || true)
local cmk_pids=$(pgrep -f "cmk-agent-ctl" || true)
local all_pids="$check_pids $cmk_pids"
```

### PID Validation

Always validate PIDs before operations to avoid errors with stale or invalid PIDs:

```bash
# Validate PIDs before displaying or killing
validate_and_show_processes() {
    local pids="$1"
    local valid_pids=""
    
    # Filter out invalid PIDs
    for pid in $pids; do
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            valid_pids="$valid_pids $pid"
        fi
    done
    
    if [[ -n "$valid_pids" ]]; then
        for pid in $valid_pids; do
            # Get process info without headers
            local info=$(ps -p "$pid" -o pid,comm,args --no-headers 2>/dev/null || true)
            if [[ -n "$info" ]]; then
                echo "  $info"
            fi
        done
    fi
}

# Check if PID is still valid
is_pid_valid() {
    local pid="$1"
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

# Safe PID iteration with validation
for pid in $pids; do
    if is_pid_valid "$pid"; then
        # Process is valid, perform operations
        kill -TERM "$pid" 2>/dev/null || true
    fi
done
```

### Systemd Service Management

For systemd services, prefer using systemctl over process killing:

```bash
# Stop services properly
stop_systemd_services() {
    local services=(
        "service-name.service"
        "service-name.socket"
        "service-name-helper.service"
    )
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_info "Stopping $service..."
            systemctl stop "$service" 2>/dev/null || true
        fi
        
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            log_info "Disabling $service..."
            systemctl disable "$service" 2>/dev/null || true
        fi
    done
    
    # Reload systemd after changes
    systemctl daemon-reload
}
```

### Signal Handling

```bash
# Common signals and their meanings
# TERM (15) - Graceful termination request
# KILL (9)  - Force termination (cannot be caught)
# HUP (1)   - Reload configuration
# INT (2)   - Interrupt (Ctrl+C)

# Send signals safely with timeout
terminate_with_timeout() {
    local pid="$1"
    local timeout="${2:-5}"
    
    # Send TERM and wait
    if kill -TERM "$pid" 2>/dev/null; then
        local count=0
        while kill -0 "$pid" 2>/dev/null && [[ $count -lt $timeout ]]; do
            sleep 1
            ((count++))
        done
        
        # Force kill if still running
        if kill -0 "$pid" 2>/dev/null; then
            kill -KILL "$pid" 2>/dev/null
            return 1  # Had to force kill
        fi
    fi
    return 0  # Clean termination
}
```

## Temporary File Usage

Always use `mktemp` for temporary files and ensure cleanup.

### Basic Pattern

```bash
# Create temporary file
tmp_file=$(mktemp)
trap 'rm -f "$tmp_file"' EXIT

# Create temporary directory
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
```

### Advanced Pattern

```bash
# Multiple temporary resources
tmp_installer=$(mktemp)
tmp_keyring=$(mktemp -d)
trap 'rm -f "$tmp_installer"; rm -rf "$tmp_keyring"' EXIT

# Named temporary files
tmp_log=$(mktemp /tmp/script-name.XXXXXX.log)
```

## Security Practices

### File Permissions

```bash
# Configuration files with sensitive data
chmod 640 "$CONFIG_FILE"
chown "$USER:$USER" "$CONFIG_FILE"

# Log files
chmod 640 "$LOG_FILE"
chown "$USER:$USER" "$LOG_FILE"

# Executable scripts
chmod 755 "$SCRIPT_FILE"
```

### Validation Examples

```bash
# GPG verification (optional)
if [[ "${SKIP_GPG_VERIFY:-0}" != "1" ]]; then
    log_info "Verifying GPG signature..."
    gpg --verify "$signature_file" "$package_file"
fi

# Checksum validation
expected_sha256="abc123..."
actual_sha256=$(sha256sum "$file" | awk '{print $1}')
if [[ "$expected_sha256" != "$actual_sha256" ]]; then
    log_error "Checksum mismatch!"
    exit 1
fi

# Safe variable expansion
# Always quote variables that might contain spaces
cd "${INSTALL_DIR}"
cp "$source_file" "$dest_file"
```

### Input Validation

```bash
# Validate numeric input
if [[ ! "$1" =~ ^[0-9]+$ ]] || [[ "$1" -le 0 ]]; then
    log_error "Invalid number: $1"
    exit 1
fi

# Validate paths
if [[ "$path" =~ \.\. ]]; then
    log_error "Path traversal detected"
    exit 1
fi
```

## Complete Cleanup Patterns

When uninstalling services or cleaning up, ensure all components are removed:

### File and Directory Cleanup

```bash
# Define comprehensive cleanup lists
cleanup_files() {
    local cleanup_items=(
        # Configuration directories
        "/etc/service-name"
        "/etc/service-name.d"
        
        # Data directories
        "/var/lib/service-name"
        "/var/cache/service-name"
        "/var/log/service-name"
        
        # Binary files
        "/usr/bin/service-binary"
        "/usr/sbin/service-daemon"
        "/usr/local/bin/service-helper"
        
        # Systemd files
        "/lib/systemd/system/service.service"
        "/etc/systemd/system/service.service"
    )
    
    for item in "${cleanup_items[@]}"; do
        if [[ -e "$item" ]]; then
            log_info "Removing: $item"
            if rm -rf "$item" 2>&1 | tee -a "$LOG_FILE"; then
                log_info "Successfully removed $item"
            else
                log_warn "Failed to remove $item"
            fi
        fi
    done
}
```

### Systemd Cleanup

```bash
# Remove all systemd traces
cleanup_systemd() {
    # Remove symlinks from all target directories
    local symlink_patterns=(
        "/etc/systemd/system/*.wants/service*"
        "/lib/systemd/system/*.wants/service*"
        "/usr/lib/systemd/system/*.wants/service*"
    )
    
    for pattern in "${symlink_patterns[@]}"; do
        shopt -s nullglob
        for symlink in $pattern; do
            if [[ -L "$symlink" ]]; then
                log_info "Removing systemd symlink: $symlink"
                rm -f "$symlink"
            fi
        done
        shopt -u nullglob
    done
    
    # Reload daemon after cleanup
    systemctl daemon-reload
}
```

### Verification After Cleanup

```bash
# Verify complete removal
verify_cleanup() {
    local issues=0
    
    # Check for remaining files
    local check_paths=(
        "/etc/service*"
        "/usr/bin/service*"
        "/var/lib/service*"
    )
    
    local remaining=""
    for pattern in "${check_paths[@]}"; do
        shopt -s nullglob
        for file in $pattern; do
            if [[ -e "$file" ]]; then
                remaining="${remaining}${file}\n"
            fi
        done
        shopt -u nullglob
    done
    
    if [[ -n "$remaining" ]]; then
        log_warn "Found remaining files:"
        echo -e "$remaining"
        issues=$((issues + 1))
    fi
    
    return $issues
}
```

## Idempotency Requirements

Scripts must be safe to run multiple times without causing errors or unintended side effects.

### Checking Existing State

```bash
# Check if user exists before creating
if ! id "$USER" &>/dev/null; then
    log_info "Creating system user: $USER"
    useradd -r -s /bin/false -d /var/lib/prometheus -m $USER
else
    log_warn "User $USER already exists"
fi

# Check if service is already installed
if systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
    log_warn "Service $SERVICE_NAME already exists, will upgrade"
    systemctl stop $SERVICE_NAME
fi

# Backup existing configuration
if [[ -f "$CONFIG_FILE" ]]; then
    BACKUP_FILE="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    log_warn "Backing up existing config to $BACKUP_FILE"
    cp "$CONFIG_FILE" "$BACKUP_FILE"
fi
```

### Safe Operations

```bash
# Create directory only if needed
[[ ! -d "$INSTALL_DIR" ]] && mkdir -p "$INSTALL_DIR"

# Remove and recreate to ensure clean state
[[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"
```

## Documentation Requirements

### Script Header Documentation

Every script must include:

```bash
#!/bin/bash

# Script Name: install-checkmk-agent.sh
# Purpose: Installs the CheckMK monitoring agent on Debian/Ubuntu systems
# Author: Your Name (optional)
# Version: 1.0
# 
# Usage:
#   ./install-checkmk-agent.sh [--with-docker]
#
# Options:
#   --with-docker    Also install the Docker monitoring plugin
#
# Requirements:
#   - Debian/Ubuntu system
#   - Root or sudo access
#   - Internet connectivity to CheckMK server
#
# Examples:
#   # Basic installation
#   ./install-checkmk-agent.sh
#
#   # Installation with Docker plugin
#   ./install-checkmk-agent.sh --with-docker
```

### Inline Documentation

```bash
# Complex operations should be documented
# Calculate the backup retention date (30 days ago)
retention_date=$(date -d "30 days ago" +%Y%m%d)

# Explain non-obvious commands
# Use ripgrep to find all backup references, excluding binary files
# The -U flag enables multiline matching for complex patterns
rg -U --type-not binary "backup.*success" "$log_dir"
```

### Function Documentation

```bash
# update_tree_in_file - Updates tree representation between markers
# Arguments:
#   $1 - Path to the markdown file to update
#   $2 - Directory to generate tree from
#   $3 - Additional tree flags (optional)
# Returns:
#   0 on success, 1 on failure
update_tree_in_file() {
    local file="$1"
    local dir="$2"
    local flags="${3:-}"
    
    # Function implementation...
}
```

### User Output

Always provide clear feedback to users:

```bash
# Start of operation
log_info "Starting Prometheus PVE Exporter installation..."

# Progress updates
log_info "Creating Python virtual environment in $INSTALL_DIR"

# Completion with next steps
echo ""
echo "================================================================="
echo "Installation completed successfully!"
echo ""
echo "Next steps:"
echo "1. Verify the service is running:"
echo "   systemctl status ${SERVICE_NAME}"
echo ""
echo "2. Test the metrics endpoint:"
echo "   curl http://localhost:9221/metrics"
echo ""
echo "3. Add to Prometheus configuration:"
echo "   - job_name: 'pve'"
echo "     static_configs:"
echo "       - targets: ['$(hostname -f):9221']"
echo "================================================================="
```

## Summary

Following these coding standards ensures:

1. **Consistency**: All scripts follow the same patterns
1. **Reliability**: Proper error handling and cleanup
1. **Security**: Appropriate permissions and validation
1. **Maintainability**: Clear documentation and structure
1. **User Experience**: Helpful output and logging

Remember: These standards are living guidelines. Update them as new patterns emerge or better practices are discovered.