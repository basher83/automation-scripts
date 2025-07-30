# Prometheus PVE Exporter Scripts

This directory contains scripts for managing the Prometheus PVE (Proxmox Virtual Environment) exporter.

## Scripts Overview

### Core Scripts (Keep these)

1. **install-pve-exporter.sh** - Original installation script
   - Creates user, token, and configures the service
   - Known issue: Uses `--privsep 1` which may cause authentication errors

2. **install-pve-exporter-improved.sh** - Improved installation script
   - Auto-detects correct privilege separation setting
   - Secure token creation (avoids process list exposure)
   - Option for SSL verification
   - Better error handling

3. **uninstall-pve-exporter.sh** - Clean uninstallation
   - Removes service, user, token, and configuration

4. **manage-pve-exporter.sh** - Maintenance and troubleshooting
   - Show status
   - Recreate tokens
   - Test functionality
   - View logs
   - Restart service

### Deprecated Scripts (Consider removing)

- **fix-token.sh** - Functionality moved to manage-pve-exporter.sh
- **debug-token.sh** - Functionality moved to manage-pve-exporter.sh
- **test-exporter.sh** - Functionality moved to manage-pve-exporter.sh

## Known Issues and Solutions

### 401 Unauthorized Errors

The main issue is with the `--privsep` (privilege separation) parameter when creating tokens:

- **Problem**: Tokens created with `--privsep 1` may not work with certain versions of prometheus-pve-exporter
- **Solution**: Use `--privsep 0` or the improved install script which auto-detects the correct setting

To fix existing installations:

```bash
# Using the management script
./manage-pve-exporter.sh recreate-token 0

# Or use the improved installer
./install-pve-exporter-improved.sh --privsep 0
```

### Security Considerations

1. **Token Exposure**: The original script exposes tokens in the process list. The improved version uses secure temporary files.

2. **SSL Verification**: Disabled by default for compatibility. Enable in production:

   ```bash
   ./install-pve-exporter-improved.sh --verify-ssl
   ```

3. **Token Storage**: Tokens are stored in plain text at `/etc/prometheus/pve.yml`. Ensure proper file permissions (640).

## Usage Examples

### Fresh Installation

```bash
# Auto-detect settings
./install-pve-exporter-improved.sh

# Force specific settings
./install-pve-exporter-improved.sh --privsep 0 --verify-ssl
```

### Troubleshooting Existing Installation

```bash
# Check status
./manage-pve-exporter.sh status

# If authentication errors occur
./manage-pve-exporter.sh recreate-token 0

# Test functionality
./manage-pve-exporter.sh test

# View logs
./manage-pve-exporter.sh logs 100
```

### Uninstallation

```bash
./uninstall-pve-exporter.sh
```

## Technical Details

The prometheus-pve-exporter uses the Proxmox API to collect metrics. Authentication issues typically stem from:

1. Token privilege separation incompatibility
2. Missing or incorrect ACL permissions
3. SSL certificate verification failures

The improved scripts address these issues while maintaining security best practices.
