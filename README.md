# Automation Scripts

[![Shell Script](https://img.shields.io/badge/shell_script-%23121011.svg?style=flat&logo=gnu-bash&logoColor=white)](https://github.com/basher83/automation-scripts)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?style=flat&logo=ubuntu&logoColor=white)](https://ubuntu.com/)
[![Debian](https://img.shields.io/badge/Debian-D70A53?style=flat&logo=debian&logoColor=white)](https://www.debian.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A collection of production-ready automation scripts for DevOps and system administration tasks. All scripts are written in Bash with a focus on security, error handling, and idempotency.

## Table of Contents

1. [Overview](#overview)
1. [Features](#features)
1. [Repository Structure](#repository-structure)
1. [Installation](#installation)
1. [Usage](#usage)
1. [Scripts](#scripts)
1. [Requirements](#requirements)
1. [Security](#security)
1. [Development](#development)
1. [Contributing](#contributing)
1. [License](#license)

## Overview

This repository provides battle-tested automation scripts for common infrastructure and development tasks:

- **Bootstrap Scripts**: Install modern CLI tools (eza, fd, uv, ripgrep)
- **Monitoring**: CheckMK agent installation, configuration, and removal
- **Backup Management**: Proxmox Backup Server health checks and status monitoring
- **Infrastructure**: Proxmox Virtual Environment utilities and exporters
- **Firewall Management**: NFTables port management utilities
- **Service Discovery**: Consul integration and Prometheus exporters
- **Documentation**: Automated documentation maintenance tools

All scripts follow consistent patterns for error handling, security validation, and user interaction.

## Features

- **Self-contained Scripts**: Each script can run independently without external dependencies
- **Security First**: GPG verification, checksum validation, and interactive confirmations
- **Idempotent Design**: Safe to run multiple times without side effects
- **Enhanced Error Handling**: Uses `set -euo pipefail` and proper trap handlers
- **Color Output**: Smart TTY detection for colored output when appropriate
- **Cross-Platform**: Focused on Ubuntu/Debian systems with consistent behavior

## Repository Structure

```tree
automation-scripts/
├── bootstrap/                      # Development environment setup
│   ├── bootstrap.sh               # Install modern CLI tools
│   └── README.md                  # Detailed bootstrap documentation
├── consul/                        # Consul integration tools
│   └── prometheus/                # Prometheus exporters
│       ├── prometheus-consul-exporter.sh
│       └── README.md
├── documentation/                 # Documentation utilities
│   ├── update-trees.sh           # Update ASCII trees in docs
│   └── README.md                 # Documentation tools guide
├── monitoring/                    # Monitoring tools
│   └── checkmk/                  # CheckMK monitoring
│       ├── install-agent.sh      # Install CheckMK agent
│       ├── uninstall-agent.sh    # Uninstall CheckMK agent
│       └── README.md             # CheckMK setup guide
├── nftables/                      # Firewall management
│   ├── open-port.sh              # Port management utility
│   └── README.md
├── proxmox-backup-server/         # PBS utilities
│   ├── pbs-backup-health.sh      # Check backup health status
│   └── README.md
├── proxmox-virtual-environment/   # PVE utilities
│   ├── pve-backup-status.sh      # Display backup task status
│   ├── prometheus-pve-exporter/  # Prometheus exporter
│   │   ├── install-pve-exporter.sh
│   │   ├── manage-pve-exporter.sh
│   │   └── uninstall-pve-exporter.sh
│   └── README.md
├── CLAUDE.md                      # AI assistant guidelines
├── CODING_STANDARDS.md            # Development standards
├── LICENSE                        # MIT License
└── README.md                      # This file
```

## Installation

### Clone the Repository

```bash
git clone https://github.com/basher83/automation-scripts.git
cd automation-scripts
```

### Make Scripts Executable

```bash
# Make all scripts executable
find . -name "*.sh" -type f -exec chmod +x {} \;
```

## Usage

### Quick Start

Each script is self-contained and can be run directly:

```bash
# Bootstrap development environment
./bootstrap/bootstrap.sh

# Install CheckMK monitoring agent
./checkmk/install-agent.sh

# Check Proxmox backup status
./proxmox-virtual-environment/pve-backup-status.sh
```

### Remote Execution

Many scripts support remote execution for automated deployments:

```bash
# Bootstrap script via curl
curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/bootstrap/bootstrap.sh | bash

# With environment variables for automation
curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/bootstrap/bootstrap.sh | \
  EZA_SKIP_GPG_VERIFY=1 UV_INSTALL_SKIP_CONFIRM=1 bash
```

## Scripts

### Bootstrap Script (`bootstrap/bootstrap.sh`)

Installs essential modern CLI tools for enhanced productivity:

- **eza**: Modern replacement for `ls` with colors and Git integration
- **fd-find**: User-friendly alternative to `find`
- **uv**: Ultra-fast Python package installer
- **ripgrep**: Lightning-fast recursive search tool

```bash
# Interactive installation
./bootstrap/bootstrap.sh

# Automated installation (skip confirmations)
EZA_SKIP_GPG_VERIFY=1 UV_INSTALL_SKIP_CONFIRM=1 ./bootstrap/bootstrap.sh
```

### CheckMK Agent (`monitoring/checkmk/`)

Install, manage, and uninstall the CheckMK monitoring agent on Ubuntu/Debian systems:

```bash
# Install agent
./monitoring/checkmk/install-agent.sh

# Install with Docker plugin
./monitoring/checkmk/install-agent.sh --docker

# Uninstall agent
./monitoring/checkmk/uninstall-agent.sh
```

### Proxmox Backup Status (`proxmox-virtual-environment/pve-backup-status.sh`)

Displays colorized backup task status from Proxmox VE logs:

```bash
# Show last 10 backup tasks (default)
./proxmox-virtual-environment/pve-backup-status.sh

# Show last 20 backup tasks
./proxmox-virtual-environment/pve-backup-status.sh 20

# Disable colors for piping/logging
./proxmox-virtual-environment/pve-backup-status.sh 10 --no-color
```

Features:

- Parses task logs to show backup status (OK/ERROR/UNKNOWN)
- Displays VM names, duration, and success/failure counts
- Supports both single VM and "all VMs" backup jobs
- Auto-detects terminal color support

### PBS Backup Health (`proxmox-backup-server/pbs-backup-health.sh`)

Checks backup health status from Proxmox Backup Server via API:

```bash
./proxmox-backup-server/pbs-backup-health.sh
```

### Documentation Tree Updater (`documentation/update-trees.sh`)

Updates ASCII tree representations in documentation files between special marker comments:

```bash
./documentation/update-trees.sh
```

### Prometheus PVE Exporter

Install or uninstall the Prometheus exporter for Proxmox Virtual Environment:

```bash
# Install exporter
./proxmox-virtual-environment/prometheus-pve-exporter/install-pve-exporter.sh

# Uninstall exporter
./proxmox-virtual-environment/prometheus-pve-exporter/uninstall-pve-exporter.sh
```

## Requirements

### Operating System

- Ubuntu 20.04+ or Debian 10+
- x86_64 (amd64) architecture
- Bash shell

### Permissions

- sudo access for system package installation
- Read access to Proxmox logs (for status scripts)
- API credentials for Proxmox Backup Server (where applicable)

### Dependencies

Most scripts automatically install their required dependencies. Common requirements include:

- `curl` or `wget` for downloading
- `gpg` for signature verification
- `jq` for JSON processing (API scripts)
- `ripgrep` for efficient log parsing

## Security

### Best Practices

1. **GPG Verification**: Package installations include GPG signature verification
1. **Checksum Validation**: Downloaded scripts are validated with SHA-256 checksums
1. **Interactive Confirmations**: Security-sensitive operations require manual confirmation
1. **No Stored Credentials**: Scripts never store API keys or passwords

### Environment Variables

For automated deployments, these environment variables control security features:

- `EZA_SKIP_GPG_VERIFY`: Skip GPG verification for eza installation
- `UV_INSTALL_SKIP_CONFIRM`: Skip confirmation for uv installer

**Warning**: Only use these in trusted, controlled environments.

## Development

### Code Standards

All scripts follow these conventions:

```bash
#!/bin/bash
set -euo pipefail  # Strict error handling

# Color output with TTY detection
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    NC=''
fi

# Cleanup on exit
trap cleanup EXIT
```

### Testing Scripts

```bash
# Validate shell script syntax
find . -name "*.sh" -type f -exec bash -n {} \;

# Search codebase with ripgrep
rg "pattern" --type sh

# List files with modern tools
eza -la --tree --level=2
```

### CI/CD

- GitHub Actions validates all shell scripts on push
- Renovate bot manages dependency updates
- Label definitions synced from basher83/docs repository

## Contributing

Contributions are welcome! Please follow these guidelines:

1. Fork the repository
1. Create a feature branch (`git checkout -b feature/amazing-script`)
1. Follow existing script patterns and conventions
1. Test thoroughly on Ubuntu/Debian systems
1. Update relevant documentation
1. Submit a pull request

### Script Checklist

- [ ] Starts with `#!/bin/bash`
- [ ] Uses `set -euo pipefail`
- [ ] Includes proper error handling
- [ ] Has color output with TTY detection
- [ ] Cleans up resources on exit
- [ ] Is idempotent (safe to run multiple times)
- [ ] Includes helpful comments
- [ ] Has a corresponding README if complex

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

Copyright (c) 2025 basher83

---

For detailed documentation on specific scripts, see the README files in each subdirectory. For AI assistant integration guidelines, refer to [CLAUDE.md](CLAUDE.md).
