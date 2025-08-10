#!/bin/bash

# Enhanced Proxmox backup status checker with improved error handling and performance
# Usage: ./pve-backup-status.sh [number_of_entries] [--no-color]

set -euo pipefail
trap 'echo "Error occurred at line $LINENO. Exit code: $?" >&2' ERR

# Input validation and constants
NUM_ENTRIES=10
USE_COLOR=true

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-color | --plain)
            USE_COLOR=false
            shift
            ;;
        -*)
            echo "Unknown option $1" >&2
            exit 1
            ;;
        *)
            if [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -gt 0 ]]; then
                NUM_ENTRIES="$1"
            else
                echo "Invalid number: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

readonly LOG_PATH="${LOG_PATH:-/var/log/pve/tasks}"

# Auto-detect if we should use colors (check if output is to a terminal and colors are supported)
if [[ ! -t 1 ]] || [[ "${TERM:-}" == "dumb" ]] || [[ -n "${NO_COLOR:-}" ]]; then
    USE_COLOR=false
fi

# Colors - conditional based on USE_COLOR
if $USE_COLOR; then
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

# Validate directory exists
if [[ ! -d "$LOG_PATH" ]]; then
    echo "Error: Log path '$LOG_PATH' does not exist" >&2
    exit 1
fi

# Helper function for safe ripgrep operations
safe_rg() {
    local pattern="$1"
    local file="$2"
    local flags="${3:-}"

    if [[ -f "$file" && -r "$file" ]]; then
        rg $flags "$pattern" "$file" 2>/dev/null || true
    fi
}

echo -e "${BOLD}${CYAN}Proxmox Backup Status - Last ${NUM_ENTRIES} Tasks${NC}"
echo -e "${CYAN}================================================${NC}"
printf "%-9s %-19s %-12s %s\n" "STATUS" "TIMESTAMP" "SCOPE" "DETAILS"
echo "------------------------------------------------------------------------"

# Create temporary file for better error handling
temp_file=$(mktemp)
trap 'rm -f "$temp_file"' EXIT

# Find vzdump task files, sort by modification time
find "$LOG_PATH" -name "*vzdump*" -type f -printf "%T@ %p\n" |
    sort -nr |
    head -n "$NUM_ENTRIES" >"$temp_file"

while read -r timestamp filepath; do
    # Parse UPID from filename
    task_file=$(basename "$filepath")

    # Extract components from UPID format: UPID:node:pid:starttime:timestamp:type:vmid:user:
    IFS=':' read -r upid_prefix node pid starttime hex_timestamp task_type vmid user rest <<<"$task_file"

    # Convert hex timestamp to readable format
    if [[ "$hex_timestamp" =~ ^[0-9A-Fa-f]+$ ]] && [ ${#hex_timestamp} -eq 8 ]; then
        readable_timestamp=$(date -d "@$((0x$hex_timestamp))" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
    else
        readable_timestamp="Unknown"
    fi

    # Check task status from the end of the log file using ripgrep
    if tail -n 5 "$filepath" 2>/dev/null | rg -q "TASK OK"; then
        if $USE_COLOR; then
            status="${GREEN}✓ OK${NC}    "
        else
            status="✓ OK     "
        fi
    elif tail -n 5 "$filepath" 2>/dev/null | rg -q "TASK ERROR"; then
        if $USE_COLOR; then
            status="${RED}✗ ERROR${NC} "
        else
            status="✗ ERROR  "
        fi
    else
        if $USE_COLOR; then
            status="${YELLOW}? UNKNOWN${NC}"
        else
            status="? UNKNOWN"
        fi
    fi

    # Determine scope and get details from the log
    if [ -f "$filepath" ]; then
        # Check if it's a single VM backup or all VMs
        if [ -n "$vmid" ] && [ "$vmid" != "" ] && [ "$vmid" != ":" ]; then
            scope="VM $vmid"
            # Try to get VM/CT name for single VM backups using ripgrep
            vm_name=$(safe_rg "INFO: (CT|VM) Name:" "$filepath" "-m 1" | sed 's/.*Name: //')
            if [ -n "$vm_name" ]; then
                scope="$scope ($vm_name)"
            fi
        else
            # This is likely an "all VMs" backup job
            scope="All VMs"
            # Count how many VMs were processed
            vm_count=$(safe_rg "INFO: Starting Backup of VM" "$filepath" "-c")
            if [[ "$vm_count" =~ ^[0-9]+$ ]] && [ "$vm_count" -gt 0 ]; then
                scope="All VMs ($vm_count VMs)"
            fi
        fi

        # Get error/success details using ripgrep
        details=""
        if safe_rg "job errors" "$filepath" "-q" >/dev/null; then
            failed_count=$(safe_rg "TASK ERROR|ERROR:" "$filepath" "-c")
            success_count=$(safe_rg "Finished Backup of VM.*successfully" "$filepath" "-c")
            if [[ "$failed_count" =~ ^[0-9]+$ ]] && [[ "$success_count" =~ ^[0-9]+$ ]] &&
                ([ "$failed_count" -gt 0 ] || [ "$success_count" -gt 0 ]); then
                details="✓${success_count} ✗${failed_count}"
            else
                details="Some failed"
            fi
        elif safe_rg "ERROR:" "$filepath" "-q" >/dev/null; then
            error_count=$(safe_rg "ERROR:" "$filepath" "-c")
            if [[ "$error_count" =~ ^[0-9]+$ ]]; then
                details="${error_count} errors"
            fi
        elif safe_rg "successfully" "$filepath" "-q" >/dev/null; then
            details="Success"
        fi

        # Get duration if available using ripgrep
        duration=$(safe_rg "INFO: Backup finished at" "$filepath" "-m 1" | tail -n 1)
        if [ -n "$duration" ]; then
            # Try to calculate duration from start and end times
            start_time=$(safe_rg "INFO: Backup started at" "$filepath" "-m 1" | sed 's/.*at //')
            end_time=$(echo "$duration" | sed 's/.*at //')
            if [ -n "$start_time" ] && [ -n "$end_time" ]; then
                start_epoch=$(date -d "$start_time" +%s 2>/dev/null)
                end_epoch=$(date -d "$end_time" +%s 2>/dev/null)
                if [ -n "$start_epoch" ] && [ -n "$end_epoch" ]; then
                    duration_secs=$((end_epoch - start_epoch))
                    if [ $duration_secs -gt 0 ]; then
                        duration_mins=$((duration_secs / 60))
                        details="$details (${duration_mins}m)"
                    fi
                fi
            fi
        fi
    else
        scope="Unknown"
        details="Log not found"
    fi

    printf "%-18s %-19s %-12s %s\n" "$status" "$readable_timestamp" "$scope" "$details"
done <"$temp_file"

echo ""
echo -e "${YELLOW}💡 Tips:${NC}"
echo "  • View detailed log: cat /var/log/pve/tasks/\$HASH/\$UPID"
echo "  • Monitor real-time: tail -f /var/log/pve/tasks/active"
echo "  • Check specific VM: rg 'vmid.*123' /var/log/pve/tasks/*/*vzdump*"
echo "  • View all errors: rg 'ERROR:' /var/log/pve/tasks/*/*vzdump* | tail -20"
echo "  • Check backup storage: pvesm status"
echo "  • Run with plain text: $(basename "$0") --no-color"
