# Checkmk useful tips

## Install Checkmk Agent on Debian/Ubuntu

### Automated Installation (Recommended)

Use the provided installation script for a streamlined experience:

```bash
sudo ./install-agent.sh
```

The script will:

- Verify system compatibility (Debian/Ubuntu)
- Download the latest agent from the CheckMK server
- Install the agent with proper error handling
- Check the agent status
- Clean up temporary files automatically

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

## Post-Installation

After installation, you'll need to:

1. Register the agent with your CheckMK server
1. Configure firewall rules if needed (port 6556)
1. Add the host to your CheckMK monitoring server
