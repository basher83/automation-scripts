#!/bin/bash

# CheckMK Agent Installation Script
# Installs the CheckMK monitoring agent on Debian/Ubuntu systems
# Based on instructions from checkmk/README.md

set -euo pipefail
trap 'echo "Error occurred at line $LINENO. Exit code: $?" >&2' ERR

# Constants
readonly AGENT_URL="http://checkmk.lab.spaceships.work/homelab/check_mk/agents/check-mk-agent_2.4.0p7-1_all.deb"
readonly AGENT_FILENAME="check-mk-agent_2.4.0p7-1_all.deb"
readonly TMP_DIR="/tmp/checkmk-agent"
readonly DOCKER_PLUGIN_URL="http://checkmk.lab.spaceships.work/homelab/check_mk/agents/plugins/mk_docker.py"
readonly DOCKER_PLUGIN_FILENAME="mk_docker.py"
readonly PLUGIN_DIR="/usr/lib/check_mk_agent/plugins"

# Flags
INSTALL_DOCKER_PLUGIN=false

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

# Show usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Install CheckMK monitoring agent on Debian/Ubuntu systems"
    echo ""
    echo "Options:"
    echo "  --docker        Also install the Docker monitoring plugin"
    echo "  --help, -h      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Install agent only"
    echo "  $0 --docker     # Install agent and Docker plugin"
    exit 0
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --docker)
                INSTALL_DOCKER_PLUGIN=true
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

# Check if running on supported system
check_system() {
    print_header "System Check"

    if [[ ! -f /etc/debian_version ]]; then
        print_error "This script is designed for Debian/Ubuntu systems only"
        exit 1
    fi

    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi

    # Check for required commands
    local required_commands=("wget" "dpkg")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            print_error "Required command '$cmd' is not installed"
            exit 1
        fi
    done

    print_success "System checks passed"
}

# Create temporary directory
setup_temp_dir() {
    print_header "Setting up temporary directory"

    if [[ -d "$TMP_DIR" ]]; then
        print_warning "Temporary directory already exists, cleaning up..."
        rm -rf "$TMP_DIR"
    fi

    mkdir -p "$TMP_DIR"
    cd "$TMP_DIR"
    print_success "Created temporary directory: $TMP_DIR"
}

# Download agent package
download_agent() {
    print_header "Downloading CheckMK Agent"

    # Ensure we're in the correct directory
    if [[ "$PWD" != "$TMP_DIR" ]]; then
        cd "$TMP_DIR" || {
            print_error "Failed to change to temporary directory"
            exit 1
        }
    fi

    print_info "Downloading from: $AGENT_URL"

    if wget -q --show-progress "$AGENT_URL" -O "$AGENT_FILENAME"; then
        print_success "Downloaded agent package successfully"

        # Verify download with full path
        local full_path="$TMP_DIR/$AGENT_FILENAME"
        if [[ ! -f "$full_path" ]]; then
            print_error "Downloaded file not found at: $full_path"
            exit 1
        fi

        local file_size=$(stat -f%z "$full_path" 2>/dev/null || stat -c%s "$full_path" 2>/dev/null || echo "0")
        if [[ "$file_size" -eq 0 ]]; then
            print_error "Downloaded file is empty"
            exit 1
        fi

        print_info "File size: $(numfmt --to=iec-i --suffix=B "$file_size" 2>/dev/null || echo "$file_size bytes")"
    else
        print_error "Failed to download agent package"
        exit 1
    fi
}

# Make package executable (not strictly necessary for dpkg, but following README)
make_executable() {
    print_header "Setting permissions"

    # Ensure we're in the correct directory
    if [[ "$PWD" != "$TMP_DIR" ]]; then
        cd "$TMP_DIR" || {
            print_error "Failed to change to temporary directory"
            exit 1
        }
    fi

    local full_path="$TMP_DIR/$AGENT_FILENAME"
    if [[ ! -f "$full_path" ]]; then
        print_error "Agent package not found at: $full_path"
        exit 1
    fi

    chmod +x "$full_path"
    print_success "Set executable permissions on package"
}

# Install the agent
install_agent() {
    print_header "Installing CheckMK Agent"

    # Ensure we're in the correct directory
    if [[ "$PWD" != "$TMP_DIR" ]]; then
        cd "$TMP_DIR" || {
            print_error "Failed to change to temporary directory"
            exit 1
        }
    fi

    local full_path="$TMP_DIR/$AGENT_FILENAME"
    if [[ ! -f "$full_path" ]]; then
        print_error "Agent package not found at: $full_path"
        exit 1
    fi

    # Check if agent is already installed
    if dpkg -l | grep -q "check-mk-agent"; then
        print_warning "CheckMK agent appears to be already installed"
        print_info "This will upgrade/reinstall the agent"

        # Show current version if possible
        if command -v check_mk_agent &>/dev/null; then
            local current_version=$(check_mk_agent --version 2>/dev/null | head -n1 || echo "unknown")
            print_info "Current version: $current_version"
        fi
    fi

    print_info "Installing agent package..."
    if dpkg -i "$full_path"; then
        print_success "CheckMK agent installed successfully"
    else
        print_error "Failed to install agent package"
        print_info "You may need to run: apt-get install -f"
        exit 1
    fi
}

# Check agent status
check_status() {
    print_header "Checking Agent Status"

    if command -v cmk-agent-ctl &>/dev/null; then
        print_info "Running agent status check..."
        cmk-agent-ctl status || {
            print_warning "Agent is installed but not yet registered with a monitoring server"
            print_info "To register with a monitoring server, use:"
            print_info "  cmk-agent-ctl register --hostname $(hostname) --server <your-checkmk-server> --site <site-name> --user <username>"
        }
    else
        print_warning "cmk-agent-ctl command not found"
        print_info "The agent may be an older version without the control utility"
    fi

    # Check if agent service is running (for systemd systems)
    if systemctl is-active --quiet check-mk-agent 2>/dev/null; then
        print_success "CheckMK agent service is active"
    elif systemctl list-units --type=socket | grep -q check-mk-agent; then
        print_success "CheckMK agent socket is available"
    fi
}

# Cleanup
cleanup() {
    print_header "Cleaning up"

    cd ~
    if [[ -d "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR"
        print_success "Removed temporary directory"
    fi
}

# Download Docker plugin
download_docker_plugin() {
    print_header "Downloading Docker Plugin"

    # Ensure we're in the correct directory
    if [[ "$PWD" != "$TMP_DIR" ]]; then
        cd "$TMP_DIR" || {
            print_error "Failed to change to temporary directory"
            exit 1
        }
    fi

    print_info "Downloading from: $DOCKER_PLUGIN_URL"

    if wget -q --show-progress "$DOCKER_PLUGIN_URL" -O "$DOCKER_PLUGIN_FILENAME"; then
        print_success "Downloaded Docker plugin successfully"

        # Verify download with full path
        local full_path="$TMP_DIR/$DOCKER_PLUGIN_FILENAME"
        if [[ ! -f "$full_path" ]]; then
            print_error "Downloaded plugin not found at: $full_path"
            exit 1
        fi

        local file_size=$(stat -f%z "$full_path" 2>/dev/null || stat -c%s "$full_path" 2>/dev/null || echo "0")
        if [[ "$file_size" -eq 0 ]]; then
            print_error "Downloaded plugin file is empty"
            exit 1
        fi

        print_info "Plugin size: $(numfmt --to=iec-i --suffix=B "$file_size" 2>/dev/null || echo "$file_size bytes")"
    else
        print_error "Failed to download Docker plugin"
        exit 1
    fi
}

# Check Docker plugin dependencies
check_docker_plugin_deps() {
    print_header "Checking Docker Plugin Dependencies"

    local deps_missing=false

    # Check for Python 3
    if ! command -v python3 &>/dev/null; then
        print_error "Python 3 is not installed"
        deps_missing=true
    else
        local python_version=$(python3 --version 2>&1 | awk '{print $2}')
        print_success "Python 3 is installed: $python_version"
    fi

    # Check for python3-docker module
    if command -v python3 &>/dev/null; then
        if ! python3 -c "import docker" 2>/dev/null; then
            print_error "Python Docker library is not installed"
            deps_missing=true
        else
            print_success "Python Docker library is installed"
        fi
    fi

    # Check if Docker is installed
    if ! command -v docker &>/dev/null; then
        print_warning "Docker is not installed on this system"
        print_info "The Docker plugin requires Docker to function properly"
    else
        print_success "Docker is installed"
    fi

    if [[ "$deps_missing" == "true" ]]; then
        print_header "Missing Dependencies"
        print_error "The Docker plugin requires Python 3 and the python3-docker library"
        print_info "Please install the missing dependencies with:"
        print_info "  sudo apt install python3 python3-docker"
        print_info ""
        print_info "After installing dependencies, run this script again with --docker"
        exit 1
    fi
}

# Install Docker plugin
install_docker_plugin() {
    print_header "Installing Docker Plugin"

    # Create plugin directory if it doesn't exist
    if [[ ! -d "$PLUGIN_DIR" ]]; then
        print_info "Creating plugin directory: $PLUGIN_DIR"
        mkdir -p "$PLUGIN_DIR" || {
            print_error "Failed to create plugin directory"
            exit 1
        }
    fi

    # Install the plugin with correct permissions
    local source_path="$TMP_DIR/$DOCKER_PLUGIN_FILENAME"
    local dest_path="$PLUGIN_DIR/$DOCKER_PLUGIN_FILENAME"

    if [[ ! -f "$source_path" ]]; then
        print_error "Docker plugin not found at: $source_path"
        exit 1
    fi

    print_info "Installing plugin to: $dest_path"
    if install -m 0755 "$source_path" "$dest_path"; then
        print_success "Docker plugin installed successfully"

        # Verify installation
        if [[ -f "$dest_path" && -x "$dest_path" ]]; then
            print_success "Plugin is properly installed and executable"
        else
            print_error "Plugin installation verification failed"
            exit 1
        fi
    else
        print_error "Failed to install Docker plugin"
        exit 1
    fi
}

# Main execution
main() {
    # Parse command line arguments
    parse_args "$@"

    echo -e "${BOLD}${CYAN}CheckMK Agent Installation Script${NC}"
    echo -e "${CYAN}=================================${NC}"

    # Run all steps
    check_system
    setup_temp_dir
    download_agent
    make_executable
    install_agent

    # Install Docker plugin if requested
    if [[ "$INSTALL_DOCKER_PLUGIN" == "true" ]]; then
        check_docker_plugin_deps
        download_docker_plugin
        install_docker_plugin
    fi

    check_status
    cleanup

    print_header "Installation Complete"
    print_success "CheckMK agent has been installed successfully!"

    if [[ "$INSTALL_DOCKER_PLUGIN" == "true" ]]; then
        print_success "Docker monitoring plugin has been installed"
    fi

    print_info "Next steps:"
    print_info "  1. Register the agent with your CheckMK server"
    print_info "  2. Configure any necessary firewall rules (port 6556)"
    print_info "  3. Add this host to your CheckMK monitoring server"

    if [[ "$INSTALL_DOCKER_PLUGIN" == "true" ]]; then
        print_info "  4. Ensure the CheckMK agent can access Docker (may require adding user to docker group)"
        print_info "  5. The Docker plugin requires Python 3 and python3-docker to function"
    fi
}

# Run main function
main "$@"
