# Mise Quick Reference

A quick reference guide for common mise commands in the automation-scripts repository.

## Essential Commands

### Initial Setup

```bash
mise trust                  # Trust project configuration
mise install                # Install all tools from .mise.toml
mise ls                     # List installed tools and versions
```

### Daily Development

```bash
mise run validate           # Run shellcheck with error severity (CI mode)
mise run validate-all       # Run shellcheck with all warnings
mise run format             # Format shell scripts with shfmt
mise run check-format       # Check formatting without changes
mise run test              # Run comprehensive tests
mise run lint              # Alias for validate
```

## Command Reference

### Installation & Setup

| Command | Description |
|---------|-------------|
| `mise trust` | Trust the project's .mise.toml configuration |
| `mise install` | Install all tools defined in .mise.toml |
| `mise install <tool>` | Install specific tool (e.g., `mise install python`) |
| `mise install <tool>@<version>` | Install specific version (e.g., `mise install python@3.11`) |
| `mise doctor` | Check mise installation and configuration |

### Tool Management

| Command | Description |
|---------|-------------|
| `mise ls` | List all installed tools with versions |
| `mise ls <tool>` | List installed versions of specific tool |
| `mise ls-remote <tool>` | List all available versions of a tool |
| `mise current` | Show currently active tool versions |
| `mise use <tool>@<version>` | Set tool version for current project |
| `mise use --global <tool>@<version>` | Set global default version |
| `mise upgrade` | Upgrade all tools to latest versions |
| `mise upgrade <tool>` | Upgrade specific tool |
| `mise uninstall <tool>@<version>` | Remove specific tool version |

### Task Execution

| Command | Description |
|---------|-------------|
| `mise tasks` | List all available tasks |
| `mise run <task>` | Execute a task (e.g., `mise run validate`) |
| `mise run --list` | List tasks with descriptions |

### Environment Management

| Command | Description |
|---------|-------------|
| `mise env` | Show environment variables set by mise |
| `mise shell <tool>@<version>` | Temporarily use different version in current shell |
| `mise exec <tool>@<version> -- <cmd>` | Run command with specific tool version |

### Configuration

| Command | Description |
|---------|-------------|
| `mise config` | Show resolved configuration |
| `mise config ls` | List all config files in use |
| `mise trust --yes` | Trust configuration without prompt |
| `mise trust --untrust` | Remove trust for current directory |

### Troubleshooting

| Command | Description |
|---------|-------------|
| `mise doctor` | Diagnose common issues |
| `mise cache clear` | Clear download cache |
| `mise version` | Show mise version |
| `MISE_DEBUG=1 mise <cmd>` | Run command with debug output |
| `mise self-update` | Update mise itself |

## Project-Specific Tasks

These tasks are defined in our `.mise.toml`:

### Validation & Testing

```bash
mise run validate           # Run shellcheck with error severity (matches CI)
mise run validate-all       # Run shellcheck with all warnings  
mise run test              # Run comprehensive test suite
mise run lint              # Alias for validate
```

### Code Formatting

```bash
mise run format            # Format all shell scripts (modifies files)
mise run check-format      # Check formatting without changes
```

## Environment Variables

### Mise Configuration

```bash
MISE_DEBUG=1               # Enable debug output
MISE_QUIET=1               # Suppress non-error output
MISE_JOBS=4                # Number of parallel jobs
MISE_RAW=1                 # Output raw format (no colors)
MISE_YES=1                 # Auto-confirm prompts
```

### Project Environment

Set in `.mise.toml`:

```bash
AUTOMATION_SCRIPTS_DIR     # Project root directory
```

## Shell Integration

### Bash

```bash
# Add to ~/.bashrc
eval "$(mise activate bash)"
```

### Zsh

```bash
# Add to ~/.zshrc
eval "$(mise activate zsh)"
```

### Direnv

```bash
# Already configured in .envrc
# Just run:
direnv allow
```

## Common Workflows

### First Time Setup

```bash
git clone https://github.com/basher83/automation-scripts.git
cd automation-scripts
mise trust
mise install
mise run validate
```

### Before Committing

```bash
mise run validate          # Check for shell script errors
mise run check-format      # Verify formatting
mise run test             # Run tests
```

### Updating Tools

```bash
mise upgrade              # Update all tools
mise ls                   # Verify new versions
mise run validate         # Test with new versions
```

### Using Different Version Temporarily

```bash
# For single command (always works)
mise exec python@3.11 -- python --version
mise exec node@20 -- npm test

# In current shell (requires mise activation)
mise shell python@3.11  # Only works if mise is activated in shell
```

### Creating Local Overrides

```bash
# Create .mise.local.toml (gitignored)
cat > .mise.local.toml << EOF
[tools]
python = "3.11"
node = "20"
EOF
```

## Tips & Tricks

### Speed Up Installation

```bash
# Install tools in parallel
mise install --jobs 4
```

### Check What Would Be Installed

```bash
# Dry run
mise install --dry-run
```

### See Task Details

```bash
# View task definition
grep -A 5 "tasks" .mise.toml
```

### Quick Version Check

```bash
# See all active versions
mise current
```

### Clean Reinstall

```bash
# If having issues
mise uninstall <tool>
mise cache clear
mise install <tool>
```

## File Locations

| File | Purpose |
|------|---------|
| `.mise.toml` | Project tool configuration (committed) |
| `.mise.local.toml` | Personal overrides (gitignored) |
| `~/.config/mise/` | Global mise configuration |
| `~/.local/share/mise/` | Installed tools location |
| `~/.cache/mise/` | Download cache |

## Getting Help

```bash
mise --help               # General help
mise <command> --help     # Command-specific help
mise doctor              # Diagnose issues
```

## See Also

- [Full Mise Guide](MISE_GUIDE.md) - Comprehensive documentation
- [Development Workflow](DEVELOPMENT_WORKFLOW.md) - Overall development process
- [Official Docs](https://mise.jdx.dev/) - Mise documentation
