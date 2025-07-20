# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a collection of automation scripts for DevOps and system administration tasks. All scripts are written in Bash and follow consistent security and error handling patterns.

## Common Development Commands

### Script Validation and Execution
```bash
# Validate all shell scripts for syntax errors
find . -name "*.sh" -type f -exec bash -n {} \;

# Make all scripts executable
find . -name "*.sh" -type f -exec chmod +x {} \;

# Run a script (scripts are self-contained and can be executed directly)
./path/to/script.sh
```

### Code Search and Navigation
```bash
# Search using ripgrep (preferred over grep)
rg "pattern" --type sh

# Find files using fd (preferred over find)
fd -e sh

# List directory contents using eza (preferred over ls)
eza -la --tree --level=2
```

### Documentation Updates
```bash
# Update tree structures in documentation files
./documentation/update-trees.sh
```

## Architecture and Conventions

### Directory Structure
- Each major feature has its own directory (bootstrap/, checkmk/, proxmox-backup-server/, proxmox-virtual-environment/)
- Scripts are self-contained and can be run independently
- README.md files in subdirectories provide component-specific documentation

### Shell Script Patterns
All scripts follow these conventions:
- Start with `#!/bin/bash`
- Use `set -euo pipefail` for strict error handling
- Include color output using ANSI escape codes
- Check for TTY (`[ -t 0 ]`) to handle interactive vs non-interactive modes
- Use `mktemp` for temporary files
- Include `trap` for cleanup on exit

### Security Practices
- GPG verification for package installations (optional in bootstrap.sh)
- SHA-256 checksum validation for downloaded scripts
- Interactive confirmation before executing downloaded content
- Never commit sensitive information (API keys, tokens)

### CI/CD
- GitHub Actions workflow validates shell scripts on every push
- Label definitions are synced from basher83/docs repository
- Renovate handles dependency updates

## Key Scripts

### bootstrap/bootstrap.sh
Installs modern CLI tools (eza, fd, uv, ripgrep). Supports both local and remote execution:
```bash
# Local execution
./bootstrap/bootstrap.sh

# Remote execution
curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/bootstrap/bootstrap.sh | bash
```

### checkmk/install-checkmk-agent.sh
Installs CheckMK monitoring agent on Ubuntu/Debian systems with proper validation.

### proxmox-backup-server/check-host-backup-health.sh
Checks backup health status from Proxmox Backup Server using API calls.

### proxmox-virtual-environment/pve-backup-status.sh
Displays Proxmox VE backup task status with enhanced error handling and colored output:
```bash
# Show last 10 backup tasks (default)
./proxmox-virtual-environment/pve-backup-status.sh

# Show last 20 backup tasks
./proxmox-virtual-environment/pve-backup-status.sh 20

# Show without colors (for piping/logging)
./proxmox-virtual-environment/pve-backup-status.sh 10 --no-color
```
Features:
- Parses Proxmox task logs to show backup status (OK/ERROR/UNKNOWN)
- Displays VM names, backup duration, and success/failure counts
- Uses ripgrep for efficient log parsing
- Supports both single VM and "all VMs" backup jobs
- Auto-detects terminal color support

### documentation/update-trees.sh
Updates ASCII tree representations in documentation files between marker comments.

## Development Notes

- No traditional build system exists (no Makefile, package.json)
- Scripts are designed to be idempotent (safe to run multiple times)
- Space-themed naming conventions in labels and emojis
- Focus on Ubuntu/Debian systems
- Integration with external docs repository for label management

## Markdown Conventions

1. Use all 1. for numbered lists for cleaner diffs in markdown