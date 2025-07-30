# NFTables Scripts

This directory contains scripts for managing nftables firewall rules on Linux systems.

## Scripts

### open-port.sh

A production-ready script for managing port rules in nftables with backup, rollback, and idempotent operations.

#### Features

- **Idempotent Operations**: Safe to run multiple times - checks if rules already exist
- **Automatic Backups**: Creates timestamped backups before any changes
- **Dry Run Mode**: Preview changes without applying them
- **Comprehensive Logging**: All operations logged to `/var/log/nftables-port-management.log`
- **Color Output**: Clear, colored output with TTY detection
- **Error Handling**: Robust error handling with cleanup on failure
- **Service Management**: Automatically enables nftables service
- **Rule Validation**: Validates all inputs and checks prerequisites

#### Requirements

- Debian/Ubuntu Linux system
- nftables installed (`apt install nftables`)
- Root or sudo access
- systemd for service management

#### Quick Deployment

##### Remote Execution

```bash
# Open port 19999 on a single node
curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/nftables/open-port.sh | sudo bash

# Open custom port
curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/nftables/open-port.sh | sudo bash -s -- --port 8080

# Non-interactive mode (auto-confirm)
curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/nftables/open-port.sh | sudo bash -s -- --non-interactive

# Deploy across multiple nodes with Ansible
ansible nomad_cluster -m shell -a "curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/nftables/open-port.sh | sudo bash -s -- --port 19999 --non-interactive"

# With environment variables
export NFT_PORT=19999
export NFT_POSITION=0
curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/nftables/open-port.sh | sudo bash -s -- --non-interactive
```

##### Local Usage

```bash
# Basic usage - open default port 19999
sudo ./open-port.sh

# Open a specific port
sudo ./open-port.sh --port 8080

# Open UDP port
sudo ./open-port.sh --port 53 --protocol udp

# Remove a rule
sudo ./open-port.sh --port 8080 --remove

# Dry run to preview changes
sudo ./open-port.sh --port 443 --dry-run

# Create backup only
sudo ./open-port.sh --backup-only

# Disable colors (for automation)
sudo ./open-port.sh --port 80 --no-color
```

#### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-p, --port PORT` | Port number to open | 19999 |
| `-P, --protocol PROTO` | Protocol (tcp/udp) | tcp |
| `-c, --chain CHAIN` | NFTables chain name | input |
| `-t, --table TABLE` | NFTables table name | filter |
| `-f, --family FAMILY` | Address family (inet/ip/ip6) | inet |
| `-r, --remove` | Remove rule instead of adding | - |
| `-b, --backup-only` | Only create backup | - |
| `--dry-run` | Preview changes without applying | - |
| `--no-color` | Disable colored output | - |
| `-h, --help` | Show help message | - |

#### Examples

##### Open port for Netdata monitoring
```bash
sudo ./open-port.sh --port 19999
```

##### Open HTTPS port with dry run first
```bash
# Preview changes
sudo ./open-port.sh --port 443 --dry-run

# Apply changes
sudo ./open-port.sh --port 443
```

##### Open multiple ports
```bash
# Web server ports
sudo ./open-port.sh --port 80
sudo ./open-port.sh --port 443

# SSH on custom port
sudo ./open-port.sh --port 2222
```

##### Remove a port rule
```bash
sudo ./open-port.sh --port 8080 --remove
```

#### Backup and Recovery

The script automatically creates backups before making any changes:

- Backups stored in `/var/backups/nftables/`
- Keeps last 10 backups automatically
- Timestamped format: `nftables-backup-YYYYMMDD_HHMMSS.conf`

To restore from backup:
```bash
# List available backups
ls -la /var/backups/nftables/

# Restore specific backup
sudo cp /var/backups/nftables/nftables-backup-20240130_123456.conf /etc/nftables.conf
sudo systemctl restart nftables
```

#### Integration with Nomad Cluster

For Nomad cluster deployments where port 19999 is needed for Netdata:

```bash
# On each Nomad node
sudo ./open-port.sh --port 19999

# Verify across cluster
ansible nomad_nodes -m shell -a "sudo nft list chain inet filter input | grep 19999"
```

#### Troubleshooting

1. **Script fails with "nftables is not installed"**
   ```bash
   sudo apt update && sudo apt install nftables
   ```

2. **Service not starting**
   ```bash
   sudo systemctl status nftables
   sudo journalctl -u nftables -n 50
   ```

3. **Rule not persisting after reboot**
   - Check if nftables service is enabled: `systemctl is-enabled nftables`
   - Verify config file exists: `ls -la /etc/nftables.conf`

4. **Port still not accessible**
   - Check if rule exists: `sudo nft list chain inet filter input`
   - Test locally: `nc -zv localhost 19999`
   - Check for other firewalls: `sudo iptables -L -n`

#### Security Considerations

- The script validates all inputs to prevent injection attacks
- Backups are created with restrictive permissions (600)
- Logs are written with appropriate permissions (640)
- Rules are added at position 0 for immediate effect
- No hardcoded credentials or sensitive data

#### Logging

All operations are logged to `/var/log/nftables-port-management.log` with:
- Timestamps for each operation
- Success/failure status
- Detailed error messages
- Command execution details

View logs:
```bash
sudo tail -f /var/log/nftables-port-management.log
```

## Related Documentation

- [NFTables Wiki](https://wiki.nftables.org/)
- [Debian NFTables Guide](https://wiki.debian.org/nftables)
- [NFTables Quick Reference](https://wiki.nftables.org/wiki-nftables/index.php/Quick_reference-nftables_in_10_minutes)