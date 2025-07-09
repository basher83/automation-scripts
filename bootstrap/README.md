# 🚀 Bootstrap Script

![Shell Script](https://img.shields.io/badge/shell_script-%23121011.svg?style=flat&logo=gnu-bash&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?style=flat&logo=ubuntu&logoColor=white)
![Debian](https://img.shields.io/badge/Debian-D70A53?style=flat&logo=debian&logoColor=white)

This script bootstraps your development environment by installing essential
command-line tools that enhance productivity and provide modern alternatives to
traditional Unix utilities.

## 🛠️ Installed Tools

The bootstrap script installs the following tools:

### [eza](https://github.com/eza-community/eza) - Modern `ls` replacement

- **Purpose**: Enhanced file listing with colors, icons, and improved readability
- **Features**: Git integration, tree view, file type detection
- **Security**: GPG signature verification (interactive by default)

### [fd-find](https://github.com/sharkdp/fd) - Modern `find` replacement

- **Purpose**: Fast and user-friendly alternative to `find`
- **Features**: Intuitive syntax, colored output, smart case handling
- **Alias**: Available as both `fd` and `fdfind`

### [uv](https://github.com/astral-sh/uv) - Python package installer

- **Purpose**: Extremely fast Python package resolver and installer
- **Features**: Drop-in replacement for pip, virtualenv management
- **Installation**: Downloaded from official Astral source with verification

### [ripgrep](https://github.com/BurntSushi/ripgrep) - Fast search tool

- **Purpose**: Recursively search directories for regex patterns
- **Features**: Faster than grep, respects .gitignore, colored output
- **Command**: Available as `rg`

## 📋 Requirements

- **Operating System**: Ubuntu/Debian-based Linux distributions
- **Privileges**: sudo access for system package installation
- **Internet Connection**: Required to download packages and GPG keys
- **Architecture**: x86_64 (amd64)

### Dependencies

The following tools are automatically installed if missing:

- `curl` - for downloading installers
- `wget` - for downloading GPG keys  
- `gpg` - for signature verification

## 🚀 Usage

### Local Execution

```bash
# Clone the repository
git clone https://github.com/basher83/automation-scripts.git
cd automation-scripts/bootstrap

# Make executable and run
chmod +x bootstrap.sh
./bootstrap.sh
```

### Remote Execution

```bash
# Direct execution from GitHub
curl -sSL \
  https://raw.githubusercontent.com/basher83/automation-scripts/main/\
bootstrap/bootstrap.sh \
  | bash

# Or with wget
wget -qO- \
  https://raw.githubusercontent.com/basher83/automation-scripts/main/\
bootstrap/bootstrap.sh \
  | bash
```

## 🔧 Environment Variables

For automated installations (CI/CD environments), you can use these environment variables:

### `EZA_SKIP_GPG_VERIFY`

- **Purpose**: Skips interactive GPG verification for eza
- **Usage**: `EZA_SKIP_GPG_VERIFY=1 ./bootstrap.sh`
- **Security Note**: Only use in trusted environments

### `UV_INSTALL_SKIP_CONFIRM`

- **Purpose**: Skips confirmation prompts for uv installer
- **Usage**: `UV_INSTALL_SKIP_CONFIRM=1 ./bootstrap.sh`
- **Default**: Interactive confirmation in terminal sessions

## 🔐 Security Features

- **GPG Verification**: eza packages are verified using GPG signatures
- **Source Verification**: uv installer is validated against official Astral source
- **Interactive Prompts**: Manual confirmation required for security-sensitive operations
- **Transparent Installation**: Shows installer details before execution

## 📝 Shell Configuration

The script automatically updates your shell configuration files:

- Adds `~/.local/bin` to PATH (for fd symlink)
- Adds `~/.cargo/bin` to PATH (for uv)
- Updates `.bashrc`, `.zshrc`, and `.profile` as needed

## 🔄 Idempotency

The script is designed to be run multiple times safely:

- Checks if tools are already installed before attempting installation
- Skips configuration steps if already completed
- No duplicate entries in shell configuration files

## 📖 Examples

### Standard Installation

```bash
./bootstrap.sh
```

### Automated/CI Installation

```bash
EZA_SKIP_GPG_VERIFY=1 UV_INSTALL_SKIP_CONFIRM=1 ./bootstrap.sh
```

### Remote Installation with Environment Variables

```bash
curl -sSL \
  https://raw.githubusercontent.com/basher83/automation-scripts/main/\
bootstrap/bootstrap.sh \
  | EZA_SKIP_GPG_VERIFY=1 bash
```

## 🆘 Troubleshooting

### Permission Issues

- Ensure you have sudo privileges
- Check that `/etc/apt/keyrings` is writable by root

### Network Issues

- Verify internet connectivity
- Check firewall settings for HTTPS traffic
- Ensure DNS resolution is working

### GPG Verification Failures

- For automated environments, use `EZA_SKIP_GPG_VERIFY=1`
- Manually verify GPG key at <https://github.com/eza-community/eza>

## 🔗 Related Links

- [eza documentation](https://github.com/eza-community/eza)
- [fd-find documentation](https://github.com/sharkdp/fd)
- [uv documentation](https://github.com/astral-sh/uv)
- [ripgrep documentation](https://github.com/BurntSushi/ripgrep)
