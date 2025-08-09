#!/bin/bash

# Proxmox Backup Server Health Check Script
# Checks if specified VMs have recent backups in PBS
#
# Usage:
#   ./pbs-backup-health.sh
#
# Configuration:
#   Requires Infisical CLI for secrets management
#   Set PBS_HOST and PBS_DATASTORE environment variables or modify defaults below
#
# Required Infisical secrets:
#   /proxmox/PBS_API_KEY - PBS API token in format "user@realm!token=value"

set -euo pipefail
trap 'echo "Error occurred at line $LINENO. Exit code: $?" >&2' ERR

# Configuration
readonly PBS_HOST="${PBS_HOST:-https://pbs.local:8007}"
readonly PBS_DATASTORE="${PBS_DATASTORE:-your-datastore-name}"
readonly VMID_LIST=("100" "101" "105")

# Get API token from Infisical
PBS_TOKEN=$(infisical secrets get PBS_API_KEY --path="/proxmox" --plain 2>/dev/null || true)

# Color codes for output (check if terminal supports colors)
if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]] && [[ -z "${NO_COLOR:-}" ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly NC='\033[0m' # No Color
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly NC=''
fi

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Check prerequisites
if ! command -v curl &>/dev/null; then
    log_error "curl is required but not installed"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    log_error "jq is required but not installed"
    exit 1
fi

if ! command -v infisical &>/dev/null; then
    log_error "infisical CLI is required but not installed"
    log_info "Install with: brew install infisical/get-cli/infisical"
    exit 1
fi

# Validate API token
if [[ -z "$PBS_TOKEN" ]]; then
    log_error "Failed to retrieve PBS_API_KEY from Infisical"
    log_info "Ensure you are logged in: infisical login"
    log_info "And have access to /proxmox/PBS_API_KEY secret"
    exit 1
fi

log_info "Checking backup health for VMs: ${VMID_LIST[*]}"
log_info "PBS Host: $PBS_HOST"
log_info "Datastore: $PBS_DATASTORE"

# Track overall status
backup_failures=0

# Check each VM
for vmid in "${VMID_LIST[@]}"; do
    log_info "Checking VM $vmid..."

    # Make API request with proper error handling
    if response=$(curl -s --fail \
        --header "Authorization: PVEAPIToken=${PBS_TOKEN}" \
        "${PBS_HOST}/api2/json/datastore/${PBS_DATASTORE}/snapshots?type=vm&vmid=${vmid}" 2>/dev/null); then

        # Check if backup exists
        if echo "$response" | jq -e '.[0] | select(."backup-type" == "vm")' >/dev/null 2>&1; then
            backup_time=$(echo "$response" | jq -r '.[0]."backup-time" // empty' 2>/dev/null || echo "unknown")
            if [[ -n "$backup_time" ]] && [[ "$backup_time" != "unknown" ]]; then
                # Convert epoch to human-readable date
                backup_date=$(date -d "@$backup_time" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$backup_time")
                log_info "✓ VM $vmid has backup (last: $backup_date)"
            else
                log_info "✓ VM $vmid has backup"
            fi
        else
            log_warn "⚠️  No recent backup found for VM $vmid"
            ((backup_failures++))
        fi
    else
        log_error "Failed to query PBS for VM $vmid"
        ((backup_failures++))
    fi
done

# Summary
echo
if [[ $backup_failures -eq 0 ]]; then
    log_info "✅ All VMs have recent backups"
    exit 0
else
    log_warn "⚠️  $backup_failures VM(s) missing recent backups"
    exit 1
fi
