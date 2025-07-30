# Coding Standards for Automation Scripts

This document establishes coding standards and best practices for all shell scripts in the automation-scripts repository. Following these standards ensures consistency, maintainability, and reliability across all scripts.

## Table of Contents

1. [Shell Script Header Patterns](#shell-script-header-patterns)
1. [Remote Execution Optimization](#remote-execution-optimization)
1. [Logging Standards](#logging-standards)
1. [Color Output Functions](#color-output-functions)
1. [Error Handling and Cleanup](#error-handling-and-cleanup)
1. [Interactive vs Non-Interactive Mode](#interactive-vs-non-interactive-mode)
1. [Temporary File Usage](#temporary-file-usage)
1. [Security Practices](#security-practices)
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

Scripts that perform installations or significant system changes must save logs to `/var/log/` with descriptive names.

### Standard Logging Pattern

The following pattern from `install-pve-exporter.sh` serves as our standard:

```bash
# Save installation log
LOG_FILE="/var/log/${SERVICE_NAME}-install.log"
echo "Installation completed at $(date)" >> $LOG_FILE
echo "Token: ${USERNAME}!${TOKEN_NAME}" >> $LOG_FILE
chown $USER:$USER $LOG_FILE
chmod 640 $LOG_FILE

log_info "Installation log saved to: $LOG_FILE"
```

### Key Requirements

1. **Log location**: Always use `/var/log/` for system-wide scripts
1. **Descriptive names**: Use format `${SERVICE_NAME}-${ACTION}.log`
1. **Timestamps**: Include date/time for all log entries
1. **Permissions**: Set appropriate ownership and restrictive permissions (640)
1. **User notification**: Inform the user where logs are saved

### Examples

```bash
# For installation scripts
LOG_FILE="/var/log/checkmk-agent-install.log"

# For backup scripts
LOG_FILE="/var/log/pve-backup-$(date +%Y%m%d).log"

# For update scripts
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
# Basic error trap
trap 'echo "Error occurred at line $LINENO. Exit code: $?" >&2' ERR

# Cleanup trap for temporary files
temp_file=$(mktemp)
trap 'rm -f "$temp_file"' EXIT

# Combined cleanup and error handling
cleanup() {
    local exit_code=$?
    [[ -f "$temp_file" ]] && rm -f "$temp_file"
    [[ -d "$temp_dir" ]] && rm -rf "$temp_dir"
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed with exit code: $exit_code"
    fi
}
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