#!/bin/bash

# Script Name: check-netdata-status.sh
# Purpose: Check the status of Netdata streaming and replication
# Version: 1.0
#
# Usage:
#   ./check-netdata-status.sh [OPTIONS]
#
# Options:
#   --type TYPE     Node type: parent or child (default: auto-detect)
#   --verbose       Show detailed information
#   --help, -h      Show this help message
#
# Requirements:
#   - Netdata installed and running
#   - Root or sudo access for some checks

set -euo pipefail
trap 'echo "Error occurred at line $LINENO. Exit code: $?" >&2' ERR

# Constants
readonly NETDATA_CONFIG_DIR="/etc/netdata"
readonly STREAM_CONF="${NETDATA_CONFIG_DIR}/stream.conf"
readonly NETDATA_API="http://localhost:19999/api/v1"
readonly ERROR_LOG="/var/log/netdata/error.log"

# Variables
NODE_TYPE=""
VERBOSE=false

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

# Helper functions
print_header() {
    echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

# Show usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Check the status of Netdata streaming and replication

Options:
    --type TYPE     Node type: parent or child (default: auto-detect)
    --verbose       Show detailed information
    --help, -h      Show this help message

Examples:
    # Auto-detect and check status
    $0

    # Check as parent node with verbose output
    $0 --type parent --verbose

EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --type)
                NODE_TYPE="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help | -h)
                usage
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Check if Netdata is running
check_netdata_service() {
    print_header "Netdata Service Status"

    if systemctl is-active --quiet netdata 2>/dev/null; then
        print_success "Netdata service is running"

        if [[ "$VERBOSE" == "true" ]]; then
            systemctl status netdata --no-pager | head -10
        fi
    else
        print_error "Netdata service is not running"
        exit 1
    fi
}

# Auto-detect node type
auto_detect_node_type() {
    if [[ -n "$NODE_TYPE" ]]; then
        return 0
    fi

    print_info "Auto-detecting node type..."

    # Check if streaming is enabled
    if grep -q "^\s*enabled\s*=\s*yes" "$STREAM_CONF" 2>/dev/null; then
        NODE_TYPE="child"
    else
        NODE_TYPE="parent"
    fi

    # Double-check by looking for API key sections
    if grep -qE "^\[[a-f0-9-]+\]" "$STREAM_CONF" 2>/dev/null; then
        NODE_TYPE="parent"
    fi

    print_info "Detected node type: $NODE_TYPE"
}

# Check API connectivity
check_api_connectivity() {
    print_header "API Connectivity"

    if curl -s -f "${NETDATA_API}/info" >/dev/null 2>&1; then
        print_success "Netdata API is accessible"

        if [[ "$VERBOSE" == "true" ]]; then
            local version=$(curl -s "${NETDATA_API}/info" | jq -r '.version' 2>/dev/null || echo "unknown")
            print_info "Netdata version: $version"
        fi
    else
        print_error "Cannot access Netdata API at ${NETDATA_API}"
    fi
}

# Check parent node status
check_parent_status() {
    print_header "Parent Node Status"

    # Check for API key sections
    local api_keys=$(grep -E "^\[[a-f0-9-]+\]" "$STREAM_CONF" 2>/dev/null | wc -l)
    if [[ $api_keys -gt 0 ]]; then
        print_success "Found $api_keys API key configuration(s)"

        if [[ "$VERBOSE" == "true" ]]; then
            grep -E "^\[[a-f0-9-]+\]" "$STREAM_CONF"
        fi
    else
        print_warning "No API key configurations found"
    fi

    # Check for connected children
    print_header "Connected Children"

    if [[ -f "$ERROR_LOG" ]]; then
        local recent_connections=$(grep "new client" "$ERROR_LOG" 2>/dev/null | tail -10)
        if [[ -n "$recent_connections" ]]; then
            print_success "Recent child connections detected"

            if [[ "$VERBOSE" == "true" ]]; then
                echo "$recent_connections"
            fi
        else
            print_warning "No recent child connections found in logs"
        fi
    fi

    # Check streaming metrics via API
    local stream_info=$(curl -s "${NETDATA_API}/info" | jq '.stream' 2>/dev/null)
    if [[ -n "$stream_info" ]] && [[ "$stream_info" != "null" ]]; then
        print_info "Streaming information available via API"

        if [[ "$VERBOSE" == "true" ]]; then
            echo "$stream_info" | jq .
        fi
    fi
}

# Check child node status
check_child_status() {
    print_header "Child Node Status"

    # Check streaming configuration
    local streaming_enabled=$(grep -E "^\s*enabled\s*=\s*yes" "$STREAM_CONF" 2>/dev/null | head -1)
    if [[ -n "$streaming_enabled" ]]; then
        print_success "Streaming is enabled"
    else
        print_error "Streaming is not enabled"
        return 1
    fi

    # Get destination parents
    local destinations=$(grep -E "^\s*destination\s*=" "$STREAM_CONF" 2>/dev/null | sed 's/.*destination\s*=\s*//')
    if [[ -n "$destinations" ]]; then
        print_success "Configured parent destinations: $destinations"
    else
        print_error "No parent destinations configured"
    fi

    # Check for streaming connections
    print_header "Streaming Connection Status"

    if [[ -f "$ERROR_LOG" ]]; then
        local established=$(grep "established communication" "$ERROR_LOG" 2>/dev/null | tail -5)
        if [[ -n "$established" ]]; then
            print_success "Streaming connections established"

            if [[ "$VERBOSE" == "true" ]]; then
                echo "$established"
            fi
        else
            print_warning "No established connections found in logs"
        fi

        # Check for recent errors
        local stream_errors=$(grep -i "stream.*error\|failed to connect" "$ERROR_LOG" 2>/dev/null | tail -5)
        if [[ -n "$stream_errors" ]]; then
            print_warning "Recent streaming errors detected:"
            echo "$stream_errors"
        fi
    fi
}

# Check replication status
check_replication_status() {
    if [[ "$NODE_TYPE" != "parent" ]]; then
        return 0
    fi

    print_header "Replication Status"

    # Check if streaming to other parents is enabled
    local replication_enabled=$(grep -A5 "^\[stream\]" "$STREAM_CONF" 2>/dev/null | grep "enabled\s*=\s*yes")
    if [[ -n "$replication_enabled" ]]; then
        print_success "Parent-to-parent replication is enabled"

        local peer_destinations=$(grep -A5 "^\[stream\]" "$STREAM_CONF" 2>/dev/null | grep "destination" | sed 's/.*destination\s*=\s*//')
        if [[ -n "$peer_destinations" ]]; then
            print_info "Replicating to: $peer_destinations"
        fi
    else
        print_info "Parent-to-parent replication is not enabled"
    fi

    # Check for replication connections
    if [[ -f "$ERROR_LOG" ]]; then
        local replication_logs=$(grep "replication\|parent.*parent" "$ERROR_LOG" 2>/dev/null | tail -5)
        if [[ -n "$replication_logs" ]] && [[ "$VERBOSE" == "true" ]]; then
            print_info "Recent replication activity:"
            echo "$replication_logs"
        fi
    fi
}

# Check system resources
check_resources() {
    print_header "Resource Usage"

    # Get Netdata process info
    local netdata_pid=$(pidof netdata 2>/dev/null || true)
    if [[ -n "$netdata_pid" ]]; then
        local mem_usage=$(ps -p "$netdata_pid" -o %mem= 2>/dev/null | xargs)
        local cpu_usage=$(ps -p "$netdata_pid" -o %cpu= 2>/dev/null | xargs)

        print_info "Memory usage: ${mem_usage}%"
        print_info "CPU usage: ${cpu_usage}%"

        if [[ "$VERBOSE" == "true" ]]; then
            # Get more detailed info
            local virt_mem=$(ps -p "$netdata_pid" -o vsz= 2>/dev/null | xargs)
            local res_mem=$(ps -p "$netdata_pid" -o rss= 2>/dev/null | xargs)

            print_info "Virtual memory: $((virt_mem / 1024)) MB"
            print_info "Resident memory: $((res_mem / 1024)) MB"
        fi
    fi
}

# Show summary
show_summary() {
    print_header "Summary"

    echo -e "${BOLD}Node Type:${NC} $NODE_TYPE"

    if [[ "$NODE_TYPE" == "parent" ]]; then
        echo -e "${BOLD}Role:${NC} Parent node accepting child streams"

        # Count connected children if possible
        local child_count=$(grep -c "new client" "$ERROR_LOG" 2>/dev/null || echo "0")
        echo -e "${BOLD}Recent connections:${NC} $child_count"
    else
        echo -e "${BOLD}Role:${NC} Child node streaming to parents"
    fi

    echo ""
    echo -e "${CYAN}Configuration files:${NC}"
    echo "  - Stream config: $STREAM_CONF"
    echo "  - Error log: $ERROR_LOG"
    echo "  - API endpoint: $NETDATA_API"
}

# Main execution
main() {
    parse_args "$@"

    echo -e "${BOLD}${CYAN}Netdata Status Check${NC}"
    echo -e "${CYAN}===================${NC}"

    check_netdata_service
    auto_detect_node_type
    check_api_connectivity

    if [[ "$NODE_TYPE" == "parent" ]]; then
        check_parent_status
        check_replication_status
    else
        check_child_status
    fi

    check_resources
    show_summary
}

# Run main function
main "$@"
