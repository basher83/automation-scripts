# 📊 Prometheus PVE Exporter Scripts

Scripts for installing and managing the Prometheus exporter on Proxmox Virtual Environment hosts to collect metrics.

## 🚀 Quick Start

```bash
# Install the exporter
./install-pve-exporter.sh

# Check status
./manage-pve-exporter.sh status

# View metrics
curl http://localhost:9221/pve?target=localhost
```

## 📦 Scripts Overview

### install-pve-exporter.sh
Installs the Prometheus PVE exporter with automatic configuration.
- Creates Python virtual environment
- Sets up Proxmox user and API token
- Configures systemd service
- Auto-detects optimal settings

### manage-pve-exporter.sh  
Manages existing installations with these commands:
- `status` - Check service health
- `recreate-token [0|1]` - Fix authentication issues
- `test` - Test metric collection
- `logs [lines]` - View service logs
- `restart` - Restart the service

### uninstall-pve-exporter.sh
Removes the exporter completely.
- `--backup` - Save configuration before removal
- `--force` - Skip confirmation prompts

## 🔧 Common Issues

### Authentication Errors (401)
If you see 401 errors, recreate the token without privilege separation:
```bash
./manage-pve-exporter.sh recreate-token 0
```

### SSL Certificate Issues
Enable SSL verification for production:
```bash
./install-pve-exporter.sh --verify-ssl
```

## 📝 Configuration

The exporter configuration is stored at `/etc/prometheus/pve.yml`:

```yaml
default:
  user: prometheus@pve
  token_name: monitoring
  token_value: your-token-here
  verify_ssl: false
```

## 📖 Prometheus Configuration

Add this to your `prometheus.yml`:

```yaml
- job_name: 'pve'
  static_configs:
    - targets: ['your-pve-host:9221']
  metrics_path: /pve
  params:
    module: [default]
    cluster: ['1']
    node: ['1']
```

## 🔗 Resources

- [prometheus-pve-exporter](https://github.com/prometheus-pve/prometheus-pve-exporter)
- [Installation Guide](https://github.com/prometheus-pve/prometheus-pve-exporter/wiki/PVE-Exporter-on-Proxmox-VE-Node-in-a-venv)
