# Netdata Deployment Readiness Checklist

## Current Status: ⚠️ REQUIRES CONFIGURATION

The monitoring/netdata directory contains all necessary scripts and documentation, but requires configuration updates before deployment.

## Pre-Deployment Requirements

### 🔴 Critical Items (Must Complete)

1. **Generate UUID API Keys**
   - [ ] Generate child-to-parent streaming key: `uuidgen`
   - [ ] Generate parent-to-parent replication key: `uuidgen`
   - [ ] Document keys securely for use across all nodes

2. **Update Configuration Files**
   - [ ] Update all config files to use 10G network IPs (192.168.11.0/24)
   - [ ] Replace placeholder API keys with generated UUIDs
   - [ ] Verify parent replication configuration

3. **Network Verification**
   - [ ] Confirm 10G network connectivity between all nodes
   - [ ] Verify firewall rules allow port 19999 on 10G network
   - [ ] Test connectivity: `nc -zv 192.168.11.X 19999`

### 🟡 Recommended Items (Should Complete)

1. **SSL/TLS Setup** (for production security)
   - [ ] Generate SSL certificates for each parent
   - [ ] Configure SSL in parent netdata.conf
   - [ ] Update child configurations for SSL connections

2. **Resource Planning**
   - [ ] Verify disk space on parents (minimum 50GB recommended)
   - [ ] Check memory availability (minimum 4GB per parent)
   - [ ] Plan retention settings based on available storage

3. **Backup Current Configuration**
   - [ ] Backup existing Netdata configs if upgrading
   - [ ] Document current monitoring setup

### 🟢 Ready Items (Already Complete)

1. **Scripts**
   - ✅ All installation scripts are executable
   - ✅ Scripts support both new installations and upgrades
   - ✅ Scripts include rollback capabilities

2. **Documentation**
   - ✅ Comprehensive README with architecture overview
   - ✅ Detailed deployment guide with examples
   - ✅ Best practices documentation
   - ✅ Migration guide for existing setups
   - ✅ Example configurations with comments

3. **Configuration Templates**
   - ✅ Parent stream.conf examples
   - ✅ Child stream.conf examples
   - ✅ Consul integration configs for Nomad nodes

## Deployment Order

1. **Phase 1: Parent Nodes**
   ```bash
   # Deploy in order: holly → lloyd → mable
   # Use install-netdata-parent.sh with proper UUID keys
   ```

2. **Phase 2: Verify Parent Cluster**
   ```bash
   # Check parent-to-parent replication
   # Verify all parents see each other
   ```

3. **Phase 3: Child Nodes**
   ```bash
   # Deploy all child nodes simultaneously
   # They will connect to first available parent
   ```

4. **Phase 4: Validation**
   ```bash
   # Run check-netdata-status.sh on all nodes
   # Verify metrics flow in dashboards
   ```

## Quick Deployment Commands

Once you have generated UUID keys and verified network connectivity:

```bash
# Example for holly (replace UUIDs with your generated values)
cd /workspaces/automation-scripts/monitoring/netdata
sudo ./scripts/install-netdata-parent.sh \
    --hostname holly \
    --bind-ip 192.168.11.2 \
    --peers "192.168.11.3,192.168.11.4" \
    --children "192.168.11.11 192.168.11.12 192.168.11.13 192.168.11.20 192.168.11.21 192.168.11.22" \
    --api-key "YOUR-CHILD-UUID" \
    --replication-key "YOUR-REPLICATION-UUID" \
    --retention 30
```

## Post-Deployment Verification

1. **Check Streaming Status**
   ```bash
   sudo ./scripts/check-netdata-status.sh --type parent --verbose
   ```

2. **Access Dashboards**
   - Holly: http://192.168.10.2:19999
   - Lloyd: http://192.168.10.3:19999
   - Mable: http://192.168.10.4:19999

3. **Monitor Logs**
   ```bash
   journalctl -u netdata -f
   ```

## Risk Assessment

- **Low Risk**: Scripts are idempotent and include safety checks
- **Rollback**: Original configs are backed up automatically
- **Impact**: Minimal - existing monitoring continues during migration
- **Downtime**: None required - streaming reconnects automatically

## Next Steps

1. Generate UUID API keys
2. Review MIGRATION_GUIDE.md if upgrading existing setup
3. Follow DEPLOYMENT_GUIDE.md for step-by-step instructions
4. Use BEST_PRACTICES.md for optimization after deployment

## Support

- Check SCRIPT_UPDATES.md for latest script changes
- Review logs in /var/log/netdata/error.log
- Netdata Community: https://community.netdata.cloud/