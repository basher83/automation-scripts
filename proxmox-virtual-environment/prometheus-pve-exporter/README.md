# Prometheus PVE Exporter

[![Prometheus](https://img.shields.io/badge/prometheus-%23E6522C.svg?style=flat&logo=prometheus&logoColor=white)](https://prometheus.io/)
[![Proxmox](https://img.shields.io/badge/proxmox-%23E57000.svg?style=flat&logo=proxmox&logoColor=white)](https://www.proxmox.com/)
[![Python](https://img.shields.io/badge/python-3670A0?style=flat&logo=python&logoColor=ffdd54)](https://www.python.org/)

Production-ready installation and management scripts for the Prometheus PVE Exporter, providing comprehensive monitoring capabilities for Proxmox Virtual Environment clusters.

## Table of Contents

1. [Overview](#overview)
1. [Prerequisites](#prerequisites)
1. [Installation](#installation)
1. [Configuration](#configuration)
1. [Usage](#usage)
1. [Metrics](#metrics)
1. [Prometheus Integration](#prometheus-integration)
1. [Uninstallation](#uninstallation)
1. [Troubleshooting](#troubleshooting)
1. [Token Management](#token-management)
1. [Security Considerations](#security-considerations)
1. [References](#references)

## Overview

The Prometheus PVE Exporter is a monitoring solution that exposes Proxmox Virtual Environment metrics in a format compatible with Prometheus. This enables comprehensive monitoring of:

- Cluster health and status
- Node resource utilization (CPU, memory, storage)
- Virtual machine and container performance
- Storage pool usage and health
- Network interface statistics
- Backup job status and history

### Why Use Prometheus PVE Exporter?

- **Native Integration**: Direct API access to Proxmox metrics without agents on VMs
- **Comprehensive Coverage**: Monitor all aspects of your Proxmox infrastructure
- **Performance**: Minimal overhead on the Proxmox host
- **Scalability**: Monitor multiple Proxmox clusters from a single Prometheus instance
- **Alerting**: Integrate with Alertmanager for proactive issue detection

## Prerequisites

### System Requirements

- **Operating System**: Proxmox VE 6.x or 7.x
- **Python**: Version 3.6 or higher (included in Proxmox)
- **Memory**: Minimal (~50MB)
- **Network**: Access to Proxmox API (port 8006)
- **Permissions**: Root access for installation

### Required Packages

The installation script automatically handles all dependencies:

- `python3-venv` for virtual environment support
- `prometheus-pve-exporter` Python package

## Installation

### Quick Installation

Run the installation script directly on your Proxmox host:

```bash
# Clone the repository
git clone https://github.com/basher83/automation-scripts.git
cd automation-scripts/proxmox-virtual-environment/prometheus-pve-exporter

# Run the installer
./install-pve-exporter.sh
```

### Remote Installation

For automated deployments:

```bash
curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/proxmox-virtual-environment/prometheus-pve-exporter/install-pve-exporter.sh | bash
```

### What the Installer Does

1. **Creates System User**: `prometheus` user for running the exporter
1. **Sets Up Python Environment**: Isolated virtual environment in `/opt/prometheus-pve-exporter`
1. **Creates PVE User**: `prometheus@pve` with read-only permissions
1. **Generates API Token**: Secure token for API authentication
1. **Configures Service**: Systemd service with automatic restart
1. **Applies Security Hardening**: Restricted file system access and privileges

### Post-Installation

The installer provides:

- Service status and control commands
- Metrics endpoint URL
- Prometheus configuration example
- Installation log location

## Configuration

### Configuration File

The exporter configuration is stored in `/etc/prometheus/pve.yml`:

```yaml
default:
  user: prometheus@pve
  token_name: monitoring
  token_value: <automatically-generated-token>
  verify_ssl: false
```

### Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `user` | Proxmox user for API access | `prometheus@pve` |
| `token_name` | API token identifier | `monitoring` |
| `token_value` | API token secret (auto-generated) | N/A |
| `verify_ssl` | Verify SSL certificates | `false` |

### Advanced Configuration

For multiple Proxmox clusters, add additional sections:

```yaml
default:
  user: prometheus@pve
  token_name: monitoring
  token_value: <token>
  verify_ssl: false

cluster2:
  user: prometheus@pve
  token_name: monitoring
  token_value: <different-token>
  verify_ssl: true
  server: cluster2.example.com
  port: 8006
```

## Usage

### Service Management

```bash
# Check service status
systemctl status prometheus-pve-exporter

# View logs
journalctl -u prometheus-pve-exporter -f

# Restart service
systemctl restart prometheus-pve-exporter

# Stop service
systemctl stop prometheus-pve-exporter
```

### Testing the Exporter

```bash
# Test local endpoint
curl http://localhost:9221/

# Get metrics for local host
curl http://localhost:9221/pve?target=localhost

# Get metrics with specific modules
curl "http://localhost:9221/pve?target=localhost&module=default&cluster=1&node=1"
```

### Query Parameters

| Parameter | Description | Values |
|-----------|-------------|--------|
| `target` | Proxmox host to query | hostname or IP |
| `module` | Configuration section | `default` or custom |
| `cluster` | Include cluster metrics | `1` or `0` |
| `node` | Include node metrics | `1` or `0` |

## Metrics

### Available Metric Categories

#### Cluster Metrics

- `pve_cluster_info` - Cluster information and version
- `pve_cluster_nodes_total` - Total number of nodes
- `pve_cluster_quorum` - Cluster quorum status

#### Node Metrics

- `pve_node_cpu_usage` - CPU utilization percentage
- `pve_node_memory_usage` - Memory usage in bytes
- `pve_node_memory_total` - Total memory in bytes
- `pve_node_disk_usage` - Root filesystem usage
- `pve_node_uptime_seconds` - Node uptime

#### Virtual Machine Metrics

- `pve_vm_status` - VM running status (1=running, 0=stopped)
- `pve_vm_cpu_usage` - VM CPU usage percentage
- `pve_vm_memory_usage` - VM memory usage in bytes
- `pve_vm_disk_read_bytes` - Disk read throughput
- `pve_vm_disk_write_bytes` - Disk write throughput
- `pve_vm_network_receive_bytes` - Network RX throughput
- `pve_vm_network_transmit_bytes` - Network TX throughput

#### Storage Metrics

- `pve_storage_usage` - Storage pool usage in bytes
- `pve_storage_total` - Storage pool capacity in bytes
- `pve_storage_available` - Available storage in bytes
- `pve_storage_status` - Storage health status

## Prometheus Integration

### Basic Configuration

Add to your `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'pve'
    static_configs:
      - targets:
        - 192.168.1.10:9221  # Your Proxmox host IP
    metrics_path: /pve
    params:
      module: [default]
      cluster: ['1']
      node: ['1']
```

### Multi-Node Configuration

For multiple Proxmox nodes:

```yaml
scrape_configs:
  - job_name: 'pve'
    static_configs:
      - targets:
        - pve1.example.com:9221
        - pve2.example.com:9221
        - pve3.example.com:9221
    metrics_path: /pve
    params:
      module: [default]
      cluster: ['1']
      node: ['1']
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
        regex: ([^:]+)(?::\d+)?
        replacement: ${1}
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: localhost:9221  # Exporter address
```

### Example Prometheus Queries

```promql
# CPU usage across all nodes
avg(pve_node_cpu_usage) by (node)

# Memory pressure on nodes
(pve_node_memory_usage / pve_node_memory_total) > 0.8

# VM count by status
count(pve_vm_status) by (status)

# Storage usage percentage
(pve_storage_usage / pve_storage_total) * 100
```

### Grafana Dashboard

Import dashboard ID `10347` from Grafana.com for a comprehensive PVE monitoring dashboard.

## Uninstallation

To completely remove the Prometheus PVE Exporter:

```bash
./uninstall-pve-exporter.sh
```

The uninstaller will:

1. Stop and disable the systemd service
1. Remove the service file
1. Delete the installation directory
1. Remove the Proxmox user and token
1. Delete the system user
1. Clean up configuration files

### Manual Uninstallation

If needed, manually clean up:

```bash
# Stop service
systemctl stop prometheus-pve-exporter
systemctl disable prometheus-pve-exporter

# Remove files
rm -f /etc/systemd/system/prometheus-pve-exporter.service
rm -rf /opt/prometheus-pve-exporter
rm -rf /etc/prometheus

# Remove Proxmox user
pveum user delete prometheus@pve

# Remove system user
userdel -r prometheus
```

## Troubleshooting

### Common Issues

#### Service Fails to Start

Check the logs:

```bash
journalctl -xeu prometheus-pve-exporter
```

Common causes:

- Port 9221 already in use
- Invalid token or permissions
- Python dependency issues

#### No Metrics Returned

1. Verify the service is running:

   ```bash
   systemctl is-active prometheus-pve-exporter
   ```

1. Test API connectivity:

   ```bash
   curl -k https://localhost:8006/api2/json/access/ticket
   ```

1. Check token permissions:

   ```bash
   pveum user permissions prometheus@pve
   ```

#### Authentication Errors

The easiest way to fix authentication errors like "401 Unauthorized: invalid token value!" is to use the automated `fix-token.sh` script:

```bash
# Fix token issues automatically
./fix-token.sh
```

This script handles the entire token recreation process safely. For manual troubleshooting:

1. Verify token exists:

   ```bash
   pveum user token list prometheus@pve
   ```

1. Regenerate token manually if needed (see [Token Management](#token-management) section for automated approach):

   ```bash
   pveum user token remove prometheus@pve monitoring
   pveum user token add prometheus@pve monitoring --privsep 1
   ```

### Debug Mode

Run the exporter manually for debugging:

```bash
sudo -u prometheus /opt/prometheus-pve-exporter/bin/pve_exporter \
  --config.file /etc/prometheus/pve.yml \
  --log.level debug
```

### Performance Issues

If experiencing high CPU usage:

1. Reduce scrape frequency in Prometheus
1. Limit metrics collection (disable cluster or node metrics)
1. Check for API rate limiting

## Token Management

### Overview

The `fix-token.sh` script provides an automated solution for managing Prometheus PVE Exporter API tokens. This script is essential for resolving authentication issues and recreating tokens when they become invalid or corrupted.

### When to Use fix-token.sh

Use the token fix script in these scenarios:

1. **401 Unauthorized Errors**: When the exporter reports "invalid token value!" errors
1. **Token Expiration**: If tokens have been manually removed or expired
1. **After Proxmox Updates**: Major Proxmox updates may invalidate existing tokens
1. **Security Rotation**: Periodic token rotation for security compliance
1. **Migration/Restore**: After restoring Proxmox from backup where tokens may be inconsistent

### Usage Examples

#### Local Execution

Run directly on the Proxmox host:

```bash
# Standard execution
cd /path/to/automation-scripts/proxmox-virtual-environment/prometheus-pve-exporter
./fix-token.sh

# Non-interactive mode (no prompts)
NON_INTERACTIVE=true ./fix-token.sh
```

#### Remote Execution

Execute via curl for automated deployments:

```bash
# Download and run in one command
curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/proxmox-virtual-environment/prometheus-pve-exporter/fix-token.sh | sudo bash

# With non-interactive mode
curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/proxmox-virtual-environment/prometheus-pve-exporter/fix-token.sh | sudo NON_INTERACTIVE=true bash
```

#### Ansible Integration

Example Ansible task for token management:

```yaml
- name: Fix Prometheus PVE Exporter token
  shell: |
    curl -fsSL https://raw.githubusercontent.com/basher83/automation-scripts/main/proxmox-virtual-environment/prometheus-pve-exporter/fix-token.sh | NON_INTERACTIVE=true bash
  become: yes
  when: prometheus_token_needs_fix | default(false)
```

#### Scheduled Maintenance

Add to crontab for periodic token rotation:

```bash
# Rotate token monthly at 2 AM on the 1st
0 2 1 * * /opt/automation-scripts/proxmox-virtual-environment/prometheus-pve-exporter/fix-token.sh > /var/log/pve-exporter-token-rotation.log 2>&1
```

### What the Script Does

The `fix-token.sh` script performs the following steps:

1. **Validation Phase**:
   - Verifies root privileges
   - Confirms Proxmox VE environment
   - Checks service installation
   - Validates required dependencies

1. **Token Removal**:
   - Checks for existing token
   - Safely removes old token if present
   - Logs removal status

1. **Token Creation**:
   - Generates new API token with privilege separation
   - Extracts token value from Proxmox output
   - Validates token format

1. **Permission Assignment**:
   - Grants PVEAuditor role to the new token
   - Ensures read-only access to cluster metrics

1. **Configuration Update**:
   - Backs up existing configuration
   - Updates `/etc/prometheus/pve.yml` with new token
   - Sets secure file permissions (640)

1. **Service Restart**:
   - Implements retry mechanism for service restart
   - Waits for service to become active
   - Maximum 3 attempts with exponential backoff

1. **Verification**:
   - Tests exporter endpoint availability
   - Validates metrics collection
   - Displays sample metrics output

1. **Logging**:
   - Records fix operation in `/var/log/prometheus-pve-exporter-token-fix.log`
   - Shows recent service logs for verification

### Integration with Monitoring Systems

When using monitoring systems that alert on authentication failures:

```bash
#!/bin/bash
# Auto-fix script for monitoring alerts

if systemctl status prometheus-pve-exporter | grep -q "401 Unauthorized"; then
    echo "Detected authentication error, running fix..."
    /path/to/fix-token.sh
    
    # Notify monitoring system
    curl -X POST https://monitoring.example.com/api/v1/alerts/resolve \
        -d '{"alert":"pve_exporter_auth_error","status":"resolved"}'
fi
```

### Security Considerations

**Important Security Notes**:

1. **Token Visibility**: The token value is briefly visible in the process list during creation. This is a limitation of the Proxmox CLI tools.

1. **Secure Storage**: Tokens are stored with restricted permissions:
   - Configuration file: `640` permissions
   - Owner: `prometheus:prometheus`
   - Location: `/etc/prometheus/pve.yml`

1. **Backup Files**: The script creates timestamped backups of the configuration before modification.

1. **Audit Trail**: All token operations are logged to `/var/log/prometheus-pve-exporter-token-fix.log`.

### Troubleshooting Token Issues

If the fix-token.sh script fails:

1. **Check Proxmox User**:
   ```bash
   pveum user list | grep prometheus
   ```

1. **Verify Service User**:
   ```bash
   id prometheus
   ```

1. **Inspect Configuration**:
   ```bash
   cat /etc/prometheus/pve.yml
   ```

1. **Review Logs**:
   ```bash
   journalctl -xeu prometheus-pve-exporter
   tail -f /var/log/prometheus-pve-exporter-token-fix.log
   ```

### Best Practices

1. **Regular Testing**: Test token validity monthly
1. **Backup Configuration**: Keep backups of working configurations
1. **Monitor Token Health**: Set up alerts for authentication failures
1. **Document Changes**: Log all manual token operations
1. **Automate Recovery**: Integrate fix-token.sh into incident response

## Security Considerations

### API Token Security

- Tokens are stored with restricted permissions (640)
- Only the `prometheus` user can read the configuration
- Tokens have minimal required permissions (PVEAuditor)

### Network Security

1. **Firewall Rules**: Restrict port 9221 to Prometheus server only

   ```bash
   iptables -A INPUT -p tcp --dport 9221 -s <prometheus-ip> -j ACCEPT
   iptables -A INPUT -p tcp --dport 9221 -j DROP
   ```

1. **SSL/TLS**: Enable HTTPS for production deployments
1. **Authentication**: Consider adding basic auth to the exporter

### Systemd Hardening

The service includes security hardening:

- `NoNewPrivileges=true` - Prevent privilege escalation
- `ProtectSystem=strict` - Read-only file system
- `ProtectHome=true` - No access to home directories
- `PrivateTmp=true` - Isolated temporary files

### Audit Recommendations

1. Regularly review token permissions
1. Monitor exporter access logs
1. Keep the exporter updated
1. Use read-only API tokens only

## References

### Official Documentation

- [Prometheus PVE Exporter GitHub](https://github.com/prometheus-pve/prometheus-pve-exporter)
- [Proxmox VE API Documentation](https://pve.proxmox.com/wiki/Proxmox_VE_API)
- [Prometheus Documentation](https://prometheus.io/docs/)

### Related Resources

- [Proxmox VE Administration Guide](https://pve.proxmox.com/pve-docs/)
- [Prometheus Best Practices](https://prometheus.io/docs/practices/)
- [Grafana PVE Dashboards](https://grafana.com/grafana/dashboards?search=proxmox)

### Community

- [Proxmox Forum](https://forum.proxmox.com/)
- [Prometheus Community](https://prometheus.io/community/)
- [r/Proxmox Reddit](https://www.reddit.com/r/Proxmox/)

---

For issues or contributions, please visit the [automation-scripts repository](https://github.com/basher83/automation-scripts).