# Mise Development Environment Guide

This guide covers the use of [mise](https://mise.jdx.dev/) (formerly rtx) for managing development tools and environments in the automation-scripts repository.

## Table of Contents

1. [Overview](#overview)
1. [Installation](#installation)
1. [Configuration](#configuration)
1. [Daily Usage](#daily-usage)
1. [Available Tasks](#available-tasks)
1. [Tool Management](#tool-management)
1. [Integration with Other Tools](#integration-with-other-tools)
1. [CI/CD Integration](#cicd-integration)
1. [Troubleshooting](#troubleshooting)
1. [Best Practices](#best-practices)

## Overview

Mise is a polyglot tool version manager that ensures all developers use consistent versions of tools like Node.js, Python, shellcheck, and more. It replaces tools like nvm, pyenv, and others with a single, unified solution.

### Why Mise?

- **Consistency**: All developers use the exact same tool versions
- **Simplicity**: One tool to manage all language runtimes and utilities
- **Speed**: Fast, written in Rust
- **Flexibility**: Supports local overrides for personal preferences
- **Integration**: Works seamlessly with direnv for automatic activation

## Installation

### Quick Install (Recommended)

```bash
# Run the bootstrap script which includes mise
./bootstrap/bootstrap.sh
```

### Manual Install

```bash
# Official installer
curl https://mise.run | sh

# Or with Homebrew (macOS/Linux)
brew install mise

# Or with cargo
cargo install mise
```

### Shell Setup

Add mise to your shell configuration:

```bash
# Bash (~/.bashrc)
eval "$(mise activate bash)"

# Zsh (~/.zshrc)
eval "$(mise activate zsh)"

# Fish (~/.config/fish/config.fish)
mise activate fish | source
```

## Configuration

### Project Configuration (`.mise.toml`)

The repository includes a `.mise.toml` file that defines:

```toml
[tools]
shellcheck = "0.10.0"        # Shell script static analysis
shfmt = "3.10.0"             # Shell script formatter
python = "3.12"              # Python runtime
node = "22"                  # Node.js runtime
golang = "1.23"              # Go runtime
task = "latest"              # Taskfile task runner
mdbook = "latest"            # Documentation builder

[tasks]
validate = "find . -name '*.sh' -type f -exec shellcheck {} +"
format = "shfmt -w -i 4 -ci ."
check-format = "shfmt -d -i 4 -ci ."
test = "./run-shellcheck.sh"
```

### Local Overrides (`.mise.local.toml`)

Create a `.mise.local.toml` file (gitignored) for personal preferences:

```toml
[tools]
# Override specific versions locally
node = "20.11.0"
python = "3.11.7"

[env]
# Set personal environment variables
EDITOR = "vim"
```

### Environment Variables

Mise can manage environment variables per project:

```toml
[env]
# Static values
DATABASE_URL = "postgresql://localhost/mydb"

# Dynamic values using templates
PROJECT_ROOT = "{{config_root}}"
PATH_add = ["{{config_root}}/scripts"]
```

## Daily Usage

### Initial Setup

When first cloning the repository:

```bash
# Clone the repository
git clone https://github.com/basher83/automation-scripts.git
cd automation-scripts

# Trust the mise configuration
mise trust

# Install all tools
mise install

# Verify installation
mise ls
```

### Common Commands

```bash
# Install all tools from .mise.toml
mise install

# Update all tools to latest versions
mise upgrade

# List installed tools
mise ls

# Show current tool versions in use
mise current

# Run a defined task
mise run validate
mise run format

# Execute commands with specific tool versions
mise exec python@3.11 -- python script.py
mise exec node@20 -- npm test
```

### Shell Integration

With direnv installed, tools are automatically available:

```bash
# Enter the project directory
cd /path/to/automation-scripts

# Tools are automatically activated
which shellcheck  # Uses mise-managed version
python --version  # Uses mise-managed version
```

## Available Tasks

Tasks are defined in `.mise.toml` and can be run with `mise run <task>`:

### Validation Tasks

```bash
# Run shellcheck on all shell scripts
mise run validate

# Run comprehensive test suite
mise run test
```

### Formatting Tasks

```bash
# Format all shell scripts
mise run format

# Check formatting without changes
mise run check-format
```

### Custom Tasks

Add your own tasks to `.mise.toml`:

```toml
[tasks]
# Simple command
clean = "rm -rf build/"

# Multi-line script
deploy = """
#!/bin/bash
set -e
echo "Building..."
./build.sh
echo "Deploying..."
./deploy.sh
"""

# Task with dependencies
build = { depends = ["clean", "validate"], run = "make build" }
```

## Tool Management

### Installing Specific Versions

```bash
# Install a specific version
mise install python@3.11.7
mise install node@20.11.0

# Install latest version
mise install shellcheck@latest

# Install from .mise.toml
mise install
```

### Switching Versions

```bash
# Use a specific version globally
mise use --global python@3.12

# Use a specific version in current project
mise use python@3.11

# Temporarily use a different version
mise shell python@3.10
```

### Listing Available Versions

```bash
# List all available versions of a tool
mise ls-remote python
mise ls-remote node

# List installed versions
mise ls python
mise ls --installed
```

### Updating Tools

```bash
# Update all tools to latest matching versions
mise upgrade

# Update specific tool
mise upgrade python

# Update to latest version (ignoring .mise.toml)
mise install python@latest
```

## Integration with Other Tools

### Direnv Integration

The repository's `.envrc` file automatically activates mise:

```bash
# .envrc
if command -v mise &> /dev/null; then
  eval "$(mise activate bash)"
  mise trust --quiet 2>/dev/null || true
  mise install --quiet 2>/dev/null || true
fi
```

### Git Hooks

Ensure tools are installed before running hooks:

```bash
#!/bin/bash
# .git/hooks/pre-commit

# Ensure mise tools are available
if command -v mise &> /dev/null; then
  eval "$(mise activate bash)"
fi

# Run validation
mise run validate
```

### VS Code Integration

Configure VS Code to use mise-managed tools:

```json
// .vscode/settings.json
{
  "python.defaultInterpreterPath": "~/.local/share/mise/installs/python/3.12/bin/python",
  "shellcheck.executablePath": "~/.local/share/mise/installs/shellcheck/0.10.0/bin/shellcheck",
  "shfmt.executablePath": "~/.local/share/mise/installs/shfmt/3.10.0/bin/shfmt"
}
```

## CI/CD Integration

### GitHub Actions

Use mise in GitHub Actions workflows:

```yaml
name: CI
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install mise
        run: |
          curl https://mise.run | sh
          echo "$HOME/.local/bin" >> $GITHUB_PATH
          
      - name: Setup tools
        run: |
          mise trust
          mise install
          
      - name: Run validation
        run: mise run validate
        
      - name: Run tests
        run: mise run test
```

### Docker Integration

Include mise in Docker images:

```dockerfile
FROM ubuntu:22.04

# Install mise
RUN curl https://mise.run | sh && \
    echo 'eval "$(mise activate bash)"' >> ~/.bashrc

# Copy mise configuration
COPY .mise.toml /app/
WORKDIR /app

# Install tools
RUN mise trust && mise install

# Tools are now available
RUN mise run validate
```

## Troubleshooting

### Common Issues

#### Tools not found after installation

```bash
# Ensure mise is activated in your shell
eval "$(mise activate bash)"

# Verify installation
mise ls

# Check PATH
echo $PATH | grep -o mise
```

#### Permission denied errors

```bash
# Fix permissions on mise directory
chmod -R u+rwX ~/.local/share/mise

# Reinstall problematic tool
mise uninstall python@3.12
mise install python@3.12
```

#### Configuration not trusted

```bash
# Trust the configuration
mise trust

# Or trust without prompt
mise trust --yes
```

#### Slow installation

```bash
# Use parallel installation
mise install --jobs 4

# Or install tools individually
mise install python
mise install node
```

### Debugging

```bash
# Enable verbose output
MISE_DEBUG=1 mise install

# Check mise configuration
mise doctor

# View resolved configuration
mise config

# Clear cache if needed
mise cache clear
```

### Resetting Mise

If you encounter persistent issues:

```bash
# Remove mise completely
rm -rf ~/.local/share/mise
rm -rf ~/.cache/mise
rm -rf ~/.config/mise

# Reinstall
curl https://mise.run | sh
```

## Best Practices

### 1. Version Pinning

Pin versions for production stability:

```toml
[tools]
# Good: Specific versions
shellcheck = "0.10.0"
python = "3.12.7"

# Avoid in production
node = "latest"  # Can change unexpectedly
```

### 2. Documentation

Document tool requirements in README:

```markdown
## Requirements

This project uses mise for tool management. Run:
\`\`\`bash
mise install
\`\`\`

Required tools:
- shellcheck 0.10.0
- Python 3.12+
- Node.js 22+
```

### 3. CI/CD Consistency

Ensure CI uses the same versions:

```yaml
# Read versions from mise
- name: Get tool versions
  run: |
    echo "PYTHON_VERSION=$(mise list python --json | jq -r '.version')" >> $GITHUB_ENV
    echo "NODE_VERSION=$(mise list node --json | jq -r '.version')" >> $GITHUB_ENV
```

### 4. Team Onboarding

Include in onboarding documentation:

```bash
# New developer setup
git clone <repo>
cd <repo>
./bootstrap/bootstrap.sh  # Installs mise and other tools
mise trust
mise install
mise run validate  # Verify setup
```

### 5. Security

Review configuration before trusting:

```bash
# Review configuration first
cat .mise.toml

# Then trust if safe
mise trust
```

### 6. Performance

Optimize for faster operations:

```toml
[settings]
# Enable experimental features for better performance
experimental = true

# Use parallel jobs
jobs = 4

# Cache downloads
always_keep_download = true
```

## Related Resources

- [Official Mise Documentation](https://mise.jdx.dev/)
- [Mise GitHub Repository](https://github.com/jdx/mise)
- [Migration from asdf](https://mise.jdx.dev/guide/migrating-from-asdf.html)
- [Plugin Development](https://mise.jdx.dev/plugins.html)
- [IDE Integration Guide](https://mise.jdx.dev/ide-integration.html)

## Summary

Mise provides a robust, fast, and user-friendly solution for managing development tools and environments. By following this guide, you can:

- Ensure consistent tool versions across the team
- Simplify developer onboarding
- Integrate seamlessly with CI/CD pipelines
- Maintain flexibility for local preferences

For questions or issues specific to this repository's mise configuration, please open an issue on GitHub.