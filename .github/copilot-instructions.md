# GitHub Copilot Instructions for automation-scripts

**ALWAYS follow these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.**

## Repository Overview

This is a collection of DevOps automation scripts written in Bash for system administration tasks. **This is NOT a traditional software project** - there is no compilation, no package.json, no Makefile, and no complex build system. All functionality is delivered through standalone Bash scripts that can be executed directly.

## Working Effectively

### Validation and "Build" Process

The primary validation process is **shell script linting**, which is very fast:

```bash
# REQUIRED: Validate all shell scripts with ShellCheck (takes ~3.6 seconds)
find . -name "*.sh" -type f -not -path './.git/*' -exec shellcheck -S error {} \;

# REQUIRED: Syntax validation (takes <1 second)  
find . -name "*.sh" -type f -exec bash -n {} \;

# OPTIONAL: Comprehensive validation report (takes ~5 seconds)
./run-shellcheck.sh
```

**TIMING**: All validation completes in under 5 seconds. **NEVER CANCEL** these commands - they are very fast.

### Making Scripts Executable

```bash
# REQUIRED: Make all scripts executable before testing
find . -name "*.sh" -type f -exec chmod +x {} \;
```

### Development Environment Setup (Optional)

The repository supports mise for tool management, but **validation can be done without it**:

```bash
# OPTIONAL: Install mise and tools (if you want enhanced development experience)
# This takes 2-5 minutes but is not required for basic validation
curl https://mise.run | sh
mise trust && mise install

# OPTIONAL: Run validation via mise (equivalent to manual commands above)
mise run validate    # ShellCheck all scripts  
mise run format      # Format with shfmt (if you modify scripts)
```

## Validation Requirements

### ALWAYS Run Before Committing
```bash
# 1. Syntax check (required, <1 second)
find . -name "*.sh" -type f -exec bash -n {} \;

# 2. ShellCheck validation (required, ~3.6 seconds) 
find . -name "*.sh" -type f -not -path './.git/*' -exec shellcheck -S error {} \;
```

**NEVER CANCEL**: These validation commands are very fast (under 5 seconds total). Wait for completion.

**NOTE**: There are currently 2 known ShellCheck errors in the repository:
- `./monitoring/zabbix/uninstall-agent.sh` (line 508) - Array concatenation issue
- `./proxmox-virtual-environment/prometheus-pve-exporter/uninstall-pve-exporter.sh` (line 245) - Local variable outside function

These are existing issues - focus on not introducing NEW errors.

### CI/CD Validation
The GitHub Actions workflow (`.github/workflows/shellcheck.yml`) will fail if:
- Any script has syntax errors  
- Any script fails ShellCheck with error severity
- **ALWAYS run the validation commands above before committing to prevent CI failures**

## Manual Validation Scenarios

Since these are system administration scripts, **ALWAYS test actual functionality** after making changes:

### For Bootstrap/Installation Scripts
```bash
# CAUTION: Bootstrap script starts installing packages immediately
# Test in safe way first
NON_INTERACTIVE=1 ./bootstrap/bootstrap.sh  # Will start actual installation

# Test idempotency (scripts should be safe to run multiple times)
./script-name.sh  # First run  
./script-name.sh  # Second run - should not fail
```

### For Monitoring/Status Scripts  
```bash
# Test PVE backup status with different parameters
./proxmox-virtual-environment/pve-backup-status.sh 10           # Show last 10 entries
./proxmox-virtual-environment/pve-backup-status.sh 20 --no-color # Test without colors

# Expected output when Proxmox logs don't exist:
# "Error: Log path '/var/log/pve/tasks' does not exist"
```

### For Documentation Scripts
```bash
# Test documentation tree updates (safe to run)
./documentation/update-trees.sh  # First run
./documentation/update-trees.sh  # Second run - test idempotency

# Expected behavior: Warns about missing files, but completes successfully
```

### Remote Execution Testing (Critical Pattern)
Many scripts support remote execution via curl. **ALWAYS test this pattern** for scripts that will be deployed:

```bash
# Test script can be piped (simulates remote execution)
cat script-name.sh | bash

# Test with environment variables  
cat script-name.sh | NON_INTERACTIVE=1 bash

# Test with parameters
cat script-name.sh | bash -s -- --option value

# VALIDATED EXAMPLE: Documentation script works via piping
cat ./documentation/update-trees.sh | bash
```

## Common Development Tasks

### Repository Structure
```
automation-scripts/
├── bootstrap/                    # Development environment setup tools
├── monitoring/                   # CheckMK, Zabbix monitoring agents  
├── proxmox-backup-server/        # PBS backup health checks
├── proxmox-virtual-environment/  # PVE utilities and exporters
├── nftables/                     # Firewall management
├── consul/                       # Service discovery tools
├── documentation/                # Documentation maintenance
├── .github/workflows/            # CI/CD (ShellCheck validation)
├── .mise.toml                   # Tool version management
├── .shellcheckrc                # ShellCheck configuration
└── run-shellcheck.sh            # Validation script
```

### Key Scripts by Category

**Bootstrap (`bootstrap/bootstrap.sh`)**:
- Installs modern CLI tools (eza, fd, uv, ripgrep)  
- Supports both local and remote execution
- **CAUTION**: Starts installing packages immediately when run

**Monitoring (`monitoring/checkmk/`)**:
- `install-agent.sh` - Installs CheckMK monitoring agent
- `uninstall-agent.sh` - Removes CheckMK agent completely

**Proxmox VE (`proxmox-virtual-environment/`)**:  
- `pve-backup-status.sh` - Shows backup task status with colors
- `prometheus-pve-exporter/` - Prometheus exporter management

### Code Search and Navigation
```bash
# Search using ripgrep (if available, otherwise use grep)
rg "pattern" --type sh

# Find specific files  
find . -name "*backup*" -type f

# List directory structure
ls -la --tree || tree || ls -la
```

## Script Development Patterns

All scripts follow these conventions:

### Required Header Pattern
```bash
#!/bin/bash
set -euo pipefail
trap 'echo "Error occurred at line $LINENO. Exit code: $?" >&2' ERR
```

### Logging Pattern (for installation/system modification scripts)
```bash
# Define timestamped log file
LOG_FILE="/var/log/script-name-$(date +%Y%m%d_%H%M%S).log"

# Combined console and file logging
log_info() {
    echo -e "[INFO] $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"
}
```

### Color Output Pattern
```bash
# Auto-detect color support
if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]] && [[ -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    NC=''
fi
```

### Non-Interactive Mode Pattern
```bash
INTERACTIVE=true
if [[ ! -t 0 ]] || [[ "${NON_INTERACTIVE:-}" == "true" ]]; then
    INTERACTIVE=false
fi
```

## Security and Safety

### GPG Verification
Scripts may include GPG verification for package installations:
```bash
# Can be skipped for testing with environment variables
EZA_SKIP_GPG_VERIFY=1 ./bootstrap/bootstrap.sh
```

### Idempotency
**All scripts must be safe to run multiple times**. Always test:
```bash
./script.sh  # First run
./script.sh  # Second run - should not fail or create duplicates
```

### Process Safety
Scripts that kill processes use safe patterns to avoid self-termination:
```bash
# CORRECT: Exclude current script PID
my_pid=$$
pgrep -f "pattern" | grep -v "^${my_pid}$"
```

## Documentation Updates

```bash
# Update tree structures in documentation files
./documentation/update-trees.sh
```

## Troubleshooting

### Common Issues

**ShellCheck Errors**: Check `.shellcheckrc` for configuration. Common fixes:
- Use proper array syntax: `"${array[@]}"` 
- Avoid `local` outside functions
- Quote variables: `"$variable"`

**Script Won't Execute**: Check permissions:
```bash
chmod +x script-name.sh
```

**Hanging on Prompts**: Use non-interactive mode:
```bash
NON_INTERACTIVE=1 ./script.sh
```

## Important Notes

- **No traditional "build"**: These are standalone scripts, not compiled software
- **Fast validation**: All linting completes in seconds, never cancel
- **Remote execution**: Key pattern for infrastructure deployment
- **Logging required**: Scripts that modify system state must log to `/var/log/`
- **Idempotency critical**: Scripts must handle being run multiple times safely
- **CI/CD**: GitHub Actions validates all scripts on every push

## Testing Checklist for Changes

When modifying scripts, ALWAYS:

1. **Syntax validation**: `find . -name "*.sh" -type f -exec bash -n {} \;` (takes <1 second)
2. **ShellCheck**: `find . -name "*.sh" -type f -not -path './.git/*' -exec shellcheck -S error {} \;` (takes ~3.6 seconds)
3. **Execute the script**: Test actual functionality, not just syntax
4. **Test idempotency**: Run the script twice to ensure safety  
5. **Test non-interactive mode**: `NON_INTERACTIVE=1 ./script.sh` (if applicable)
6. **Test remote execution**: `cat script.sh | bash` (if script supports it)
7. **Verify logging**: Check that log files are created properly (if applicable)

### Real-World Testing Examples

```bash
# Complete validation workflow (takes ~4 seconds total)
find . -name "*.sh" -type f -exec bash -n {} \;                           # Syntax
find . -name "*.sh" -type f -not -path './.git/*' -exec shellcheck -S error {} \;  # Linting

# Test a safe script (documentation updater)
./documentation/update-trees.sh     # First run
./documentation/update-trees.sh     # Test idempotency  
cat ./documentation/update-trees.sh | bash  # Test remote execution

# Test script that requires environment
./proxmox-virtual-environment/pve-backup-status.sh 5 --no-color  # Fails gracefully without Proxmox

# NEVER run installation scripts unless you intend to install:
# ./bootstrap/bootstrap.sh  # Starts installing packages immediately!
```

### Expected Error Handling

Scripts should handle missing dependencies gracefully:
- PVE scripts: "Error: Log path '/var/log/pve/tasks' does not exist"  
- Documentation scripts: "File not found, skipping..." warnings
- Missing tools: Scripts check for requirements and provide clear error messages

**Remember**: This repository is about DevOps automation scripts that need to work reliably in production environments. Focus on validation, safety, and real-world testing scenarios.