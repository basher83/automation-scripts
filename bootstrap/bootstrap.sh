#!/bin/bash

# Bootstrap Script for Modern CLI Tools
# Installs eza, fd-find, uv, ripgrep, infisical, claude-code, taskfile, and direnv on Debian/Ubuntu systems
# 
# Usage:
#   ./bootstrap.sh
#   curl -fsSL https://example.com/bootstrap.sh | bash
#
# Environment Variables:
#   EZA_SKIP_GPG_VERIFY=1        Skip GPG verification for eza
#   UV_INSTALL_SKIP_CONFIRM=1    Skip confirmation for uv installer
#   INFISICAL_SKIP_GPG_VERIFY=1  Skip GPG verification for Infisical
#   CLAUDE_CODE_SKIP_CONFIRM=1   Skip confirmation for Claude Code
#   TASKFILE_SKIP_CONFIRM=1      Skip confirmation for Taskfile
#   DIRENV_SKIP_CONFIRM=1        Skip confirmation for direnv
#   NO_COLOR=1                   Disable colored output
#   NON_INTERACTIVE=1            Run in non-interactive mode

set -euo pipefail
IFS=$'\n\t'

# Define log file with timestamp to prevent overwriting
LOG_FILE="/var/log/bootstrap-tools-install-$(date +%Y%m%d_%H%M%S).log"

# Check if we can write to /var/log (need sudo)
if [[ $EUID -ne 0 ]] && [[ ! -w /var/log ]]; then
    # If not root and can't write to /var/log, use home directory
    LOG_FILE="$HOME/bootstrap-tools-install-$(date +%Y%m%d_%H%M%S).log"
fi

# Make LOG_FILE readonly after determining location
readonly LOG_FILE

# Array to track temporary files for cleanup
_tmp_files=()

# Cleanup function
cleanup() {
    local exit_code=$?
    
    # Clean up temporary files and directories
    for tmp_file in "${_tmp_files[@]}"; do
        if [[ -d "$tmp_file" ]]; then
            rm -rf "$tmp_file" 2>/dev/null || true
        elif [[ -f "$tmp_file" ]]; then
            rm -f "$tmp_file" 2>/dev/null || true
        fi
    done
    
    # Original cleanup logic
    if [[ $exit_code -ne 0 ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] Script failed with exit code: $exit_code" >> "$LOG_FILE"
        # Need to define print_error inline since colors might not be set yet
        echo -e "\033[0;31m[ERROR]\033[0m Script failed! Check the log for details: $LOG_FILE" >&2
    fi
}

# Set traps
trap 'echo "Error occurred at line $LINENO. Exit code: $?" >&2' ERR
trap cleanup EXIT

# Initialize log file
echo "Bootstrap script started at $(date)" > "$LOG_FILE"
chmod 640 "$LOG_FILE" 2>/dev/null || true

# Color codes for output (check if terminal supports colors)
if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]] && [[ -z "${NO_COLOR:-}" ]]; then
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly RED='\033[0;31m'
    readonly BLUE='\033[0;34m'
    readonly CYAN='\033[0;36m'
    readonly BOLD='\033[1m'
    readonly NC='\033[0m' # No Color
else
    readonly GREEN=''
    readonly YELLOW=''
    readonly RED=''
    readonly BLUE=''
    readonly CYAN=''
    readonly BOLD=''
    readonly NC=''
fi

# Logging functions - output to both console and file
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" >> "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >> "$LOG_FILE"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STEP] $*" >> "$LOG_FILE"
}

# Print functions that only go to console (not logged)
print_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Script header
log_info "Bootstrap Script - Installing Modern CLI Tools"
log_info "Tools: eza, fd-find, uv, ripgrep, infisical, claude-code, taskfile, direnv"
print_info "Log file: $LOG_FILE"
echo

# Log debug information
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Script version: 1.1" >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Running as user: $(whoami)" >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] System: $(uname -a)" >> "$LOG_FILE"

# Non-interactive mode support
INTERACTIVE=true
if [[ ! -t 0 ]] || [[ "${NON_INTERACTIVE:-}" == "true" ]] || [[ "$*" == *"--non-interactive"* ]]; then
    INTERACTIVE=false
fi
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] Interactive mode: $INTERACTIVE" >> "$LOG_FILE"

# (rest of bootstrap.sh follows)
# Install eza - a modern replacement for ls
# Security Note: GPG key verification is interactive by default to avoid hardcoding
# fingerprints that may change. For automated installations, set EZA_SKIP_GPG_VERIFY=1
# or verify the fingerprint manually at https://github.com/eza-community/eza
log_step "Checking eza..."

# Check if eza is already installed
if ! command -v eza &> /dev/null; then
    log_info "Installing eza..."
    
    # Ensure required tools are installed
    missing_tools=""
    ! command -v gpg &> /dev/null && missing_tools="$missing_tools gpg"
    ! command -v wget &> /dev/null && missing_tools="$missing_tools wget"
    
    if [ -n "$missing_tools" ]; then
        log_info "Installing required tools:$missing_tools"
        # Note: We'll update package index later after adding repository
        sudo apt-get update
        sudo apt-get install -y $missing_tools
    fi
    
    # Check if repository is already configured
    if [ ! -f "/etc/apt/keyrings/gierens.gpg" ] || [ ! -f "/etc/apt/sources.list.d/gierens.list" ]; then
        log_info "Adding eza repository..."
        sudo mkdir -p /etc/apt/keyrings
        
        # Remove existing file if it exists (shouldn't happen with the check above)
        [ -f "/etc/apt/keyrings/gierens.gpg" ] && sudo rm -f /etc/apt/keyrings/gierens.gpg
        
        # Download GPG key to temporary file
        log_info "Downloading eza repository key..."
        tmp_key=$(mktemp)
        _tmp_files+=("$tmp_key")
        
        if ! wget -qO "$tmp_key" https://raw.githubusercontent.com/eza-community/eza/main/deb.asc; then
            log_error "Failed to download eza GPG key"
            exit 1
        fi
        
        # Display key information for transparency
        echo "GPG key information:"
        # Import key to temporary keyring for verification
        tmp_keyring=$(mktemp -d)
        _tmp_files+=("$tmp_keyring")
        GNUPGHOME="$tmp_keyring" gpg --import "$tmp_key" 2>/dev/null
        key_info=$(GNUPGHOME="$tmp_keyring" gpg --list-keys 2>/dev/null)
        # Parse fingerprint using --with-colons for machine-readable output
        # The 'fpr' record contains the fingerprint in field 10
        # Use grep and cut for more predictable parsing
        key_fingerprint=$(GNUPGHOME="$tmp_keyring" gpg --with-colons --fingerprint 2>/dev/null \
          | grep "^fpr:" | head -1 | cut -d: -f10)
        
        # Validate fingerprint format (should be 40 hex characters for GPG keys)
        # Modern GPG keys use SHA1 (40 chars) or SHA256 (64 chars) for fingerprints
        # We check for 40 as that's most common, but could extend to support 64
        if [[ ! "$key_fingerprint" =~ ^[A-F0-9]{40}$ ]]; then
            # Try uppercase conversion in case of lowercase hex
            key_fingerprint_upper=$(echo "$key_fingerprint" | tr '[:lower:]' '[:upper:]')
            if [[ ! "$key_fingerprint_upper" =~ ^[A-F0-9]{40}$ ]]; then
                log_warn "Warning: Invalid or missing key fingerprint"
                echo "Expected 40 character hex string, got: '$key_fingerprint'"
                echo "GPG output format may have changed or locale settings may affect parsing"
                echo "Proceeding with key display for manual verification"
                key_fingerprint=""
            else
                key_fingerprint="$key_fingerprint_upper"
            fi
        fi
        
        echo "$key_info"
        if [ -n "$key_fingerprint" ]; then
            echo "Key fingerprint: $key_fingerprint"
        fi
        
        # For automated/CI environments, allow skipping confirmation
        if [ -n "${EZA_SKIP_GPG_VERIFY:-}" ]; then
            log_warn "Skipping GPG verification (EZA_SKIP_GPG_VERIFY is set)"
        elif [ -t 0 ]; then
            # Interactive mode - ask for confirmation
            echo ""
            echo "Please verify this key fingerprint matches the official eza key."
            echo "You can check: https://github.com/eza-community/eza"
            echo ""
            echo "Do you trust this key? [y/N]"
            read -r response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                echo "Key not trusted. Aborting."
                rm -f "$tmp_key"
                rm -rf "$tmp_keyring"
                exit 1
            fi
        else
            # Non-interactive mode without skip flag
            echo ""
            echo "WARNING: Running in non-interactive mode."
            echo "To skip this check, set EZA_SKIP_GPG_VERIFY=1"
            echo "To verify the key, check: https://github.com/eza-community/eza"
            echo "Proceeding with installation..."
        fi
        
        # Import the verified key
        sudo gpg --dearmor < "$tmp_key" -o /etc/apt/keyrings/gierens.gpg
        echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list
        sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
    else
        log_info "eza repository already configured"
    fi
    
    # Install eza
    log_info "Installing eza package..."
    sudo apt-get update 2>&1 | tee -a "$LOG_FILE"
    sudo apt-get install -y eza 2>&1 | tee -a "$LOG_FILE"
    log_info "✓ eza installed successfully!"
else
    log_info "eza is already installed"
fi

# Function to check if ~/.local/bin is in PATH and provide instructions
check_local_bin_path() {
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        echo ""
        echo "NOTE: $HOME/.local/bin is not in your PATH."
        echo "Add the following to your shell configuration file (.bashrc, .zshrc, etc.):"
        echo '  export PATH="$HOME/.local/bin:$PATH"'
        echo ""
        echo "For the current session, run:"
        echo '  export PATH="$HOME/.local/bin:$PATH"'
    fi
}

# Function to create fd symlink safely
create_fd_symlink() {
    local target=$(which fdfind)
    local link="$HOME/.local/bin/fd"
    
    mkdir -p "$HOME/.local/bin"
    
    # Check if fd already exists and handle appropriately
    if [ -e "$link" ] || [ -L "$link" ]; then
        # Check if it's already the correct symlink
        if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
            log_info "Symlink already correctly configured"
        else
            log_info "Removing existing fd file/symlink"
            rm -f "$link"
            ln -nsf "$target" "$link"
            log_info "Created symlink: fd -> $target"
        fi
    else
        ln -nsf "$target" "$link"
        log_info "Created symlink: fd -> $target"
    fi
}

# Install fd-find - a modern replacement for find
log_step "Checking fd..."

# Check if fd is already available (either as fd or fdfind)
if ! command -v fd &> /dev/null && ! command -v fdfind &> /dev/null; then
    log_info "Installing fd-find..."
    
    # Install fd-find package
    sudo apt-get update
    sudo apt-get install -y fd-find
    log_info "✓ fd-find installed successfully!"
    
    # Create symlink for fd command
    log_info "Setting up fd symlink..."
    create_fd_symlink
    
    # Check if ~/.local/bin is in PATH
    check_local_bin_path
else
    # Check if we have fd command specifically
    if command -v fdfind &> /dev/null && ! command -v fd &> /dev/null; then
        log_info "fd-find is installed but 'fd' command not available"
        log_info "Creating fd symlink..."
        create_fd_symlink
        
        # Check PATH again
        check_local_bin_path
    else
        log_info "fd is already installed and available"
    fi
fi

# Install uv - Python package installer
log_step "Checking uv..."

# Check if uv is already installed
if ! command -v uv &> /dev/null; then
    log_info "Installing uv..."
    
    # Ensure curl is installed
    if ! command -v curl &> /dev/null; then
        log_info "Installing curl..."
        sudo apt-get install -y curl || {
            log_error "Failed to install curl, updating package index..."
            sudo apt-get update
            sudo apt-get install -y curl
        }
    fi
    
    # Download installer to a temporary file for inspection
    log_info "Downloading uv installer..."
    tmp_installer=$(mktemp)
    _tmp_files+=("$tmp_installer")
    
    # Use the official installer URL
    UV_INSTALLER_URL="https://astral.sh/uv/install.sh"
    
    if ! curl -LsSf -o "$tmp_installer" "$UV_INSTALLER_URL"; then
        log_error "Failed to download uv installer"
        exit 1
    fi
    
    # Calculate actual checksum
    actual_sha=$(sha256sum "$tmp_installer" | cut -d' ' -f1)
    
    # Note: The installer script changes frequently, so we verify it's from the expected domain
    # and do additional safety checks rather than pinning to a specific checksum
    echo "Downloaded installer SHA-256: $actual_sha"
    
    # Basic validation - check if it's a shell script and not empty
    if [ ! -s "$tmp_installer" ]; then
        echo "Downloaded installer is empty"
        exit 1
    fi
    
    if ! head -n 1 "$tmp_installer" | grep -q "^#!/"; then
        echo "Downloaded file doesn't appear to be a shell script"
        exit 1
    fi
    
    # Additional safety check - verify the script contains expected uv installation markers
    # Modern uv installer downloads pre-built binaries, not via cargo install
    if ! grep -q "astral.sh/uv" "$tmp_installer" || ! grep -q "APP_NAME=\"uv\"" "$tmp_installer"; then
        echo "Installer doesn't appear to be the official uv installer"
        exit 1
    fi
    
    # Show installer details for transparency
    echo "Installer size: $(wc -c < "$tmp_installer") bytes"
    echo "First 10 lines of installer:"
    head -n 10 "$tmp_installer" | sed 's/^/  /'
    
    # Option for manual review if running interactively
    if [ -t 0 ] && [ -z "${UV_INSTALL_SKIP_CONFIRM:-}" ]; then
        echo ""
        echo "Would you like to review the full installer script before execution? [y/N]"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            less "$tmp_installer"
            echo ""
            echo "Proceed with installation? [Y/n]"
            read -r confirm
            if [[ "$confirm" =~ ^[Nn]$ ]]; then
                echo "Installation cancelled"
                exit 1
            fi
        fi
    fi
    
    # Execute the installer
    echo "Running uv installer..."
    sh "$tmp_installer"
    
    # The modern uv installer installs to ~/.local/bin, not ~/.cargo/bin
    # Add ~/.local/bin to PATH for current session (if not already there)
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        export PATH="$HOME/.local/bin:$PATH"
    fi
    
    # Persist PATH update for future sessions
    log_info "Updating shell configuration..."
    local_bin_path_line='export PATH="$HOME/.local/bin:$PATH"'
    
    # Update shell configuration files
    for rc_file in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        if [ -f "$rc_file" ] && ! grep -q "\\.local/bin" "$rc_file"; then
            echo "$local_bin_path_line" >> "$rc_file"
            log_info "Added .local/bin to $(basename "$rc_file")"
        fi
    done
    
    log_info "✓ uv installed successfully!"
else
    log_info "uv is already installed"
fi

# Install ripgrep - a fast search tool
log_step "Checking ripgrep..."

# Check if ripgrep is already installed
if ! command -v rg &> /dev/null; then
    log_info "Installing ripgrep package..."
    sudo apt-get update
    sudo apt-get install -y ripgrep
    log_info "✓ ripgrep installed successfully!"
else
    log_info "ripgrep is already installed"
fi

# Install Infisical CLI - secure secrets management
log_step "Checking Infisical CLI..."

# Check if infisical is already installed
if ! command -v infisical &> /dev/null; then
    log_info "Installing Infisical CLI..."
    
    # Ensure required tools are installed
    if ! command -v curl &> /dev/null; then
        log_info "Installing curl..."
        sudo apt-get update
        sudo apt-get install -y curl
    fi
    
    # Add Infisical repository
    # Download and verify repository setup script
    tmp_infisical_setup=$(mktemp)
    _tmp_files+=("$tmp_infisical_setup")
    
    INFISICAL_SETUP_URL="https://artifacts-cli.infisical.com/setup.deb.sh"
    
    log_info "Downloading Infisical repository setup script..."
    if ! curl -1sLf -o "$tmp_infisical_setup" "$INFISICAL_SETUP_URL"; then
        log_error "Failed to download Infisical setup script"
        exit 1
    fi
    
    # Basic validation - check if it's a shell script
    if [ ! -s "$tmp_infisical_setup" ]; then
        log_error "Downloaded Infisical setup script is empty"
        exit 1
    fi
    
    if ! head -n 1 "$tmp_infisical_setup" | grep -q "^#!/"; then
        log_error "Downloaded file doesn't appear to be a shell script"
        exit 1
    fi
    
    # Check for expected content markers
    if ! grep -q "infisical" "$tmp_infisical_setup"; then
        log_error "Setup script doesn't appear to be the official Infisical installer"
        exit 1
    fi
    
    # Show script details for transparency
    log_info "Setup script size: $(wc -c < "$tmp_infisical_setup") bytes"
    
    # For automated/CI environments, allow skipping confirmation
    if [ -n "${INFISICAL_SKIP_GPG_VERIFY:-}" ]; then
        log_warn "Skipping Infisical setup verification (INFISICAL_SKIP_GPG_VERIFY is set)"
    elif [ "$INTERACTIVE" == "true" ]; then
        # Interactive mode - ask for confirmation
        echo ""
        echo "About to add Infisical repository to your system."
        echo "This will execute the official setup script from artifacts-cli.infisical.com"
        echo ""
        echo "Do you trust this source? [y/N]"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Installation cancelled."
            exit 1
        fi
    else
        # Non-interactive mode
        log_info "Running in non-interactive mode, proceeding with Infisical repository setup"
    fi
    
    # Execute the setup script
    log_info "Setting up Infisical repository..."
    if ! sudo -E bash "$tmp_infisical_setup"; then
        log_error "Failed to setup Infisical repository"
        exit 1
    fi
    
    # Install infisical package
    log_info "Installing Infisical package..."
    sudo apt-get update
    sudo apt-get install -y infisical
    
    log_info "✓ Infisical CLI installed successfully!"
else
    log_info "Infisical CLI is already installed"
fi

# Install Claude Code - AI coding assistant
log_step "Checking Claude Code..."

# Check if claude is already installed (command is 'claude', not 'claude-code')
if ! command -v claude &> /dev/null; then
    log_info "Installing Claude Code..."
    
    # Check if Node.js is installed and version is 18+
    node_version=""
    if command -v node &> /dev/null; then
        node_version=$(node --version | sed 's/v//' | cut -d. -f1)
    fi
    
    if [ -z "$node_version" ] || [ "$node_version" -lt 18 ]; then
        log_info "Node.js 18+ is required for Claude Code"
        log_info "Installing Node.js via NodeSource repository..."
        
        # Install Node.js 20 LTS
        curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
        sudo apt-get install -y nodejs
        
        # Verify installation
        node_version=$(node --version)
        log_info "Installed Node.js $node_version"
    else
        log_info "Node.js $(node --version) is already installed"
    fi
    
    # Check if we're using nvm (common in GitHub Codespaces)
    if [ -n "${NVM_DIR:-}" ] && [ -s "$NVM_DIR/nvm.sh" ]; then
        log_info "Detected nvm environment (e.g., GitHub Codespaces)"
        log_info "Using nvm's global npm directory instead of custom prefix"
        
        # In nvm environments, global packages go to the nvm-managed location
        # We don't need to set a custom prefix or modify PATH as nvm handles this
        # Just ensure nvm is loaded for this session
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        
        # Get the global npm directory from nvm
        NPM_GLOBAL_DIR="$(npm config get prefix)/bin"
        log_info "npm global directory: $NPM_GLOBAL_DIR"
    else
        # Configure npm to use user directory for global packages
        # This avoids permission issues and follows security best practices
        log_info "Configuring npm for user-level global packages..."
        
        # Create npm global directory in user home
        mkdir -p "$HOME/.npm-global"
        
        # Configure npm
        npm config set prefix "$HOME/.npm-global"
        
        # Add to PATH if not already there
        if [[ ":$PATH:" != *":$HOME/.npm-global/bin:"* ]]; then
            export PATH="$HOME/.npm-global/bin:$PATH"
            
            # Persist PATH update for future sessions
            log_info "Updating shell configuration for npm global packages..."
            npm_path_line='export PATH="$HOME/.npm-global/bin:$PATH"'
            
            # Update shell configuration files
            for rc_file in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
                if [ -f "$rc_file" ] && ! grep -q "\.npm-global/bin" "$rc_file"; then
                    echo "$npm_path_line" >> "$rc_file"
                    log_info "Added npm global path to $(basename "$rc_file")"
                fi
            done
        else
            log_info "npm global path already in PATH"
        fi
        
        NPM_GLOBAL_DIR="$HOME/.npm-global/bin"
    fi
    
    # Install Claude Code
    log_info "Installing @anthropic-ai/claude-code package..."
    
    # For automated/CI environments, allow skipping confirmation
    if [ -n "${CLAUDE_CODE_SKIP_CONFIRM:-}" ] || [ "$INTERACTIVE" == "false" ]; then
        npm install -g @anthropic-ai/claude-code
    else
        # Interactive mode - provide information
        echo ""
        echo "About to install Claude Code globally via npm."
        if [ -n "${NVM_DIR:-}" ]; then
            echo "This will install to: $(npm config get prefix)"
        else
            echo "This will install to: $HOME/.npm-global"
        fi
        echo ""
        echo "Proceed with installation? [Y/n]"
        read -r response
        if [[ "$response" =~ ^[Nn]$ ]]; then
            echo "Installation cancelled."
        else
            npm install -g @anthropic-ai/claude-code
        fi
    fi
    
    # Force reload npm global bin path after installation (only if not using nvm)
    if [ -z "${NVM_DIR:-}" ]; then
        export PATH="$HOME/.npm-global/bin:$PATH"
    fi
    
    # Also try to rehash if using zsh
    if [ -n "${ZSH_VERSION:-}" ]; then
        hash -r 2>/dev/null || true
    fi
    
    # Verify installation with full path first (command is 'claude', not 'claude-code')
    if [ -x "$NPM_GLOBAL_DIR/claude" ]; then
        log_info "✓ Claude Code installed successfully!"
        log_info "You can now use 'claude' command"
        
        # Double check if it's available in PATH
        if ! command -v claude &> /dev/null; then
            if [ -n "${NVM_DIR:-}" ]; then
                log_warn "Note: You may need to reload nvm in your shell"
                log_info "Run: source \$NVM_DIR/nvm.sh"
            else
                log_warn "Note: You may need to restart your shell for the command to be available"
                log_info "Or run: export PATH=\"\$HOME/.npm-global/bin:\$PATH\""
            fi
        fi
    else
        log_warn "Claude Code installation completed but binary not found"
        log_warn "You may need to restart your shell or run: source ~/.bashrc"
    fi
else
    log_info "Claude Code is already installed"
fi

# Install Taskfile - task runner / build tool
log_step "Checking Taskfile..."

# Check if task is already installed
if ! command -v task &> /dev/null; then
    log_info "Installing Taskfile..."
    
    # Download and verify installer script
    tmp_taskfile_installer=$(mktemp)
    _tmp_files+=("$tmp_taskfile_installer")
    
    TASKFILE_INSTALLER_URL="https://taskfile.dev/install.sh"
    
    log_info "Downloading Taskfile installer..."
    if ! curl -fsSL -o "$tmp_taskfile_installer" "$TASKFILE_INSTALLER_URL"; then
        log_error "Failed to download Taskfile installer"
        exit 1
    fi
    
    # Basic validation - check if it's a shell script
    if [ ! -s "$tmp_taskfile_installer" ]; then
        log_error "Downloaded Taskfile installer is empty"
        exit 1
    fi
    
    if ! head -n 1 "$tmp_taskfile_installer" | grep -q "^#!/"; then
        log_error "Downloaded file doesn't appear to be a shell script"
        exit 1
    fi
    
    # Check for expected content markers - look for go-task/task which is the official repo
    if ! grep -q "go-task/task" "$tmp_taskfile_installer" && ! grep -q "goreleaser/godownloader" "$tmp_taskfile_installer"; then
        log_error "Installer doesn't appear to be the official Taskfile installer"
        log_error "Expected to find 'go-task/task' in installer content"
        exit 1
    fi
    
    # Show installer details for transparency
    log_info "Installer size: $(wc -c < "$tmp_taskfile_installer") bytes"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] First 5 lines of installer:" >> "$LOG_FILE"
    head -5 "$tmp_taskfile_installer" >> "$LOG_FILE"
    
    # For automated/CI environments, allow skipping confirmation
    if [ -n "${TASKFILE_SKIP_CONFIRM:-}" ] || [ "$INTERACTIVE" == "false" ]; then
        log_info "Installing Taskfile to $HOME/.local/bin"
        # Install to user's local bin directory
        # The correct syntax is: sh -c "$(cat installer)" -- -d -b <dir>
        sh -c "$(cat "$tmp_taskfile_installer")" -- -d -b "$HOME/.local/bin"
    else
        # Interactive mode - ask for confirmation
        echo ""
        echo "About to install Taskfile task runner."
        echo "This will download the binary from taskfile.dev"
        echo "Installation directory: $HOME/.local/bin"
        echo ""
        echo "Do you want to install Taskfile? [Y/n]"
        read -r response
        if [[ "$response" =~ ^[Nn]$ ]]; then
            echo "Installation cancelled."
        else
            log_info "Installing Taskfile to $HOME/.local/bin"
            # The correct syntax is: sh -c "$(cat installer)" -- -d -b <dir>
            sh -c "$(cat "$tmp_taskfile_installer")" -- -d -b "$HOME/.local/bin"
        fi
    fi
    
    # Add ~/.local/bin to PATH if not already there (should already be done for fd)
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        export PATH="$HOME/.local/bin:$PATH"
    fi
    
    # Verify installation
    if command -v task &> /dev/null; then
        task_version=$(task --version | head -n 1)
        log_info "✓ Taskfile installed successfully! Version: $task_version"
    else
        log_warn "Taskfile installation completed but 'task' command not found in PATH"
        log_warn "You may need to restart your shell or run: source ~/.bashrc"
    fi
else
    task_version=$(task --version | head -n 1)
    log_info "Taskfile is already installed. Version: $task_version"
fi

# Install direnv - automatic environment variable loader
log_step "Checking direnv..."

# Check if direnv is already installed
if ! command -v direnv &> /dev/null; then
    log_info "Installing direnv..."
    
    # Download and verify installer script
    tmp_direnv_installer=$(mktemp)
    _tmp_files+=("$tmp_direnv_installer")
    
    DIRENV_INSTALLER_URL="https://direnv.net/install.sh"
    
    log_info "Downloading direnv installer..."
    if ! curl -sfL -o "$tmp_direnv_installer" "$DIRENV_INSTALLER_URL"; then
        log_error "Failed to download direnv installer"
        exit 1
    fi
    
    # Basic validation - check if it's a shell script
    if [ ! -s "$tmp_direnv_installer" ]; then
        log_error "Downloaded direnv installer is empty"
        exit 1
    fi
    
    if ! head -n 1 "$tmp_direnv_installer" | grep -q "^#!/"; then
        log_error "Downloaded file doesn't appear to be a shell script"
        exit 1
    fi
    
    # Check for expected content markers
    if ! grep -q "direnv" "$tmp_direnv_installer"; then
        log_error "Installer doesn't appear to be the official direnv installer"
        exit 1
    fi
    
    # Show installer details for transparency
    log_info "Installer size: $(wc -c < "$tmp_direnv_installer") bytes"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] First 5 lines of installer:" >> "$LOG_FILE"
    head -5 "$tmp_direnv_installer" >> "$LOG_FILE"
    
    # For automated/CI environments, allow skipping confirmation
    if [ -n "${DIRENV_SKIP_CONFIRM:-}" ] || [ "$INTERACTIVE" == "false" ]; then
        log_info "Installing direnv to $HOME/.local/bin"
        # Install to user's local bin directory
        export bin_path="$HOME/.local/bin"
        bash "$tmp_direnv_installer"
    else
        # Interactive mode - ask for confirmation
        echo ""
        echo "About to install direnv."
        echo "This will download the binary from direnv.net"
        echo "Installation directory: $HOME/.local/bin"
        echo ""
        echo "Do you want to install direnv? [Y/n]"
        read -r response
        if [[ "$response" =~ ^[Nn]$ ]]; then
            echo "Installation cancelled."
        else
            log_info "Installing direnv to $HOME/.local/bin"
            export bin_path="$HOME/.local/bin"
            bash "$tmp_direnv_installer"
        fi
    fi
    
    # Add ~/.local/bin to PATH if not already there (should already be done for fd)
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        export PATH="$HOME/.local/bin:$PATH"
    fi
    
    # Verify installation
    if command -v direnv &> /dev/null; then
        direnv_version=$(direnv version)
        log_info "✓ direnv installed successfully! Version: $direnv_version"
        
        # Add shell hook configuration
        log_info "Setting up direnv shell hook..."
        
        # Detect shell and add appropriate hook
        direnv_hook_bash='eval "$(direnv hook bash)"'
        direnv_hook_zsh='eval "$(direnv hook zsh)"'
        
        # Add to bash
        if [ -f "$HOME/.bashrc" ] && ! grep -q "direnv hook bash" "$HOME/.bashrc"; then
            echo "" >> "$HOME/.bashrc"
            echo "# direnv hook" >> "$HOME/.bashrc"
            echo "$direnv_hook_bash" >> "$HOME/.bashrc"
            log_info "Added direnv hook to ~/.bashrc"
        fi
        
        # Add to zsh
        if [ -f "$HOME/.zshrc" ] && ! grep -q "direnv hook zsh" "$HOME/.zshrc"; then
            echo "" >> "$HOME/.zshrc"
            echo "# direnv hook" >> "$HOME/.zshrc"
            echo "$direnv_hook_zsh" >> "$HOME/.zshrc"
            log_info "Added direnv hook to ~/.zshrc"
        fi
        
        log_info "Note: You need to restart your shell or run the appropriate hook command:"
        log_info "  For bash: eval \"\$(direnv hook bash)\""
        log_info "  For zsh:  eval \"\$(direnv hook zsh)\""
    else
        log_warn "direnv installation completed but 'direnv' command not found in PATH"
        log_warn "You may need to restart your shell or run: source ~/.bashrc"
    fi
else
    direnv_version=$(direnv version)
    log_info "direnv is already installed. Version: $direnv_version"
fi

# Summary
echo
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
log_info "Bootstrap completed successfully!"
log_info "Installed tools:"
log_info "  - eza: Modern replacement for ls"
log_info "  - fd: User-friendly alternative to find"
log_info "  - uv: Ultra-fast Python package installer"
log_info "  - ripgrep: Lightning-fast recursive search"
log_info "  - infisical: Secure secrets management CLI"
log_info "  - claude: AI-powered coding assistant (Claude Code)"
log_info "  - taskfile: Modern task runner and build tool"
log_info "  - direnv: Automatic environment variable loader"
echo -e "${GREEN}✓ Log saved to: ${BOLD}$LOG_FILE${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo
log_info "You may need to restart your shell or run: source ~/.bashrc"