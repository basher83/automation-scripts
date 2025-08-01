# CheckMK Agent Management

This directory contains scripts for installing and uninstalling the CheckMK monitoring agent on Debian/Ubuntu systems.

## Quick Install

For a quick installation, run this command to download and execute the installation script directly:

```bash
# Install agent only
curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/monitoring/checkmk/install-agent.sh | sudo bash

# Install agent with Docker plugin
curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/monitoring/checkmk/install-agent.sh | sudo bash -s -- --docker
```

## Quick Uninstall

To uninstall the CheckMK agent:

```bash
# Uninstall agent
curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/monitoring/checkmk/uninstall-agent.sh | sudo bash
```

## Installation

### Automated Installation (Local)

If you've cloned this repository, use the provided installation script:

```bash
# Install agent only
sudo ./install-agent.sh

# Install agent with Docker plugin
sudo ./install-agent.sh --docker

# Show help
./install-agent.sh --help
```

The script will:

- Verify system compatibility (Debian/Ubuntu)
- Download the latest agent from the CheckMK server
- Install the agent with proper error handling
- Check the agent status
- Clean up temporary files automatically
- Optionally install the Docker monitoring plugin (requires Python 3 and python3-docker)

### Manual Installation

If you prefer to install manually, follow these steps:

1. Create a tmp directory for the agent

```bash
mkdir -p /tmp/checkmk-agent
cd /tmp/checkmk-agent
```

1. Pull the latest agent from the remote host

```bash
wget http://checkmk.lab.spaceships.work/homelab/check_mk/agents/check-mk-agent_2.4.0p7-1_all.deb
```

1. Make executable

```bash
chmod +x check-mk-agent_2.4.0p7-1_all.deb
```

1. Update/Install (must run as root)

```bash
sudo dpkg -i check-mk-agent_2.4.0p7-1_all.deb
```

1. Check status

```bash
cmk-agent-ctl status
```

1. Clean up

```bash
cd ~
rm -rf /tmp/checkmk-agent
```

## Docker Plugin

The Docker monitoring plugin requires:

- Python 3
- python3-docker library
- Docker installed and running

Install dependencies:

```bash
sudo apt install python3 python3-docker
```

## Post-Installation

After installation, you'll need to:

1. Register the agent with your CheckMK server
1. Configure firewall rules if needed (port 6556)
1. Add the host to your CheckMK monitoring server
1. If using Docker plugin: ensure the CheckMK agent can access Docker (may require adding user to docker group)

## Uninstallation

### Automated Uninstallation (Local)

If you've cloned this repository:

```bash
# Uninstall the agent
sudo ./uninstall-agent.sh
```

The uninstall script will:

- Check for existing CheckMK agent installation
- Stop all CheckMK services and processes
- Remove CheckMK packages (check-mk-agent, checkmk-agent, cmk-agent)
- Clean up configuration files and directories
- Remove systemd unit files
- Verify complete removal

### What Gets Removed

The uninstallation script removes:

- CheckMK agent packages
- Configuration directories:
  - `/etc/check_mk`
  - `/etc/cmk-agent`
- Data directories:
  - `/var/lib/check_mk_agent`
  - `/var/lib/cmk-agent`
- Plugin directories:
  - `/usr/lib/check_mk_agent`
- Systemd unit files:
  - `check-mk-agent.socket`
  - `check-mk-agent@.service`
  - `check-mk-agent-async.service`
  - `cmk-agent-ctl-daemon.service`
- All CheckMK processes

### Post-Uninstallation

After uninstallation:

1. The host will no longer be monitored by CheckMK
1. Port 6556 will be freed up
1. You may need to remove the host from your CheckMK monitoring server
1. Any custom plugins or local checks will be removed
