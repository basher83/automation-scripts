# Netdata Configuration Migration Guide

This guide provides step-by-step instructions to migrate your current Netdata configuration to align with best practices.

## Pre-Migration Checklist

- [ ] Backup current configurations: `sudo tar -czf netdata-backup-$(date +%Y%m%d).tar.gz /etc/netdata/`
- [ ] Document current parent and child node IPs
- [ ] Verify 10G network connectivity between nodes
- [ ] Schedule maintenance window (minimal disruption expected)

## Migration Steps

### Phase 1: Generate Secure API Keys

1. Generate new UUID API keys:
```bash
# Generate keys on one system and document them
echo "Child streaming key: $(uuidgen)"
echo "Parent replication key: $(uuidgen)"
echo "Other subnet key (if needed): $(uuidgen)"
```

2. Save these keys securely - you'll need them for all nodes.

### Phase 2: Update Parent Nodes

#### Step 1: Update Holly (192.168.11.2)

1. Edit stream configuration:
```bash
sudo /etc/netdata/edit-config stream.conf
```

2. Update the configuration:
```ini
[stream]
    enabled = yes
    destination = 192.168.11.3:19999 192.168.11.4:19999
    api key = YOUR-PARENT-REPLICATION-UUID
    buffer size bytes = 10485760
    enable compression = yes
    
[YOUR-CHILD-STREAMING-UUID]
    enabled = yes
    allow from = 192.168.11.11-13 192.168.11.20-22
    db = dbengine
    health enabled = yes
    postpone alarms on connect = 60s
    
[YOUR-PARENT-REPLICATION-UUID]
    enabled = yes
    allow from = 192.168.11.2-4
    db = dbengine
    health enabled = no
```

3. Update netdata.conf for proper binding:
```bash
sudo /etc/netdata/edit-config netdata.conf
```

Add/update:
```ini
[web]
    bind to = 192.168.11.2:19999
```

4. Restart Netdata:
```bash
sudo systemctl restart netdata
```

#### Step 2: Repeat for Lloyd (192.168.11.3) and Mable (192.168.11.4)

Use the same process, adjusting:
- `bind to` IP address
- `destination` IPs (exclude self)

### Phase 3: Update Child Nodes

For each child node (nomad-server-1 through nomad-client-3):

1. Edit stream configuration:
```bash
sudo /etc/netdata/edit-config stream.conf
```

2. Update to use 10G network IPs:
```ini
[stream]
    enabled = yes
    destination = 192.168.11.2:19999 192.168.11.3:19999 192.168.11.4:19999
    api key = YOUR-CHILD-STREAMING-UUID
    buffer size bytes = 10485760
    enable compression = yes
    send charts matching = *
```

3. Restart Netdata:
```bash
sudo systemctl restart netdata
```

### Phase 4: Verify Connectivity

1. On each parent, check for child connections:
```bash
# Check streaming status
curl -s http://localhost:19999/api/v1/info | jq '.stream'

# Check logs for connections
journalctl -u netdata | grep "new client"
```

2. On each child, verify parent connection:
```bash
# Check for successful streaming
journalctl -u netdata | grep "established"
```

### Phase 5: Enable TLS/SSL (Optional but Recommended)

1. Generate certificates on each parent:
```bash
sudo mkdir -p /etc/netdata/ssl
cd /etc/netdata/ssl
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout key.pem -out cert.pem \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=$(hostname)"
```

2. Update parent netdata.conf:
```ini
[web]
    ssl key = /etc/netdata/ssl/key.pem
    ssl certificate = /etc/netdata/ssl/cert.pem
```

3. Update child stream.conf destinations:
```ini
destination = 192.168.11.2:19999:SSL 192.168.11.3:19999:SSL 192.168.11.4:19999:SSL
ssl skip certificate verification = yes
```

4. Restart all nodes.

## Rollback Plan

If issues occur:

1. Restore original configurations:
```bash
sudo tar -xzf netdata-backup-YYYYMMDD.tar.gz -C /
sudo systemctl restart netdata
```

2. Children will automatically reconnect to parents.

## Post-Migration Validation

1. **Check Parent Replication:**
```bash
# On each parent, verify seeing all children
for parent in 192.168.11.2 192.168.11.3 192.168.11.4; do
    echo "Checking parent $parent"
    curl -s http://$parent:19999/api/v1/info | jq '.mirrored_hosts[]'
done
```

2. **Verify Metrics Flow:**
   - Access parent dashboards
   - Confirm all child nodes visible
   - Check for data gaps

3. **Test Failover:**
   - Stop one parent: `sudo systemctl stop netdata`
   - Verify children reconnect to other parents
   - Restart stopped parent
   - Confirm replication catches up

## Troubleshooting

### Children Not Connecting

1. Check firewall rules:
```bash
# Ensure port 19999 is open on 10G network
sudo iptables -L -n | grep 19999
```

2. Verify API key matches:
```bash
# On parent
grep -A5 "YOUR-CHILD-UUID" /etc/netdata/stream.conf

# On child
grep "api key" /etc/netdata/stream.conf
```

### Replication Not Working

1. Check parent-to-parent connectivity:
```bash
# From one parent to another
nc -zv 192.168.11.3 19999
```

2. Verify replication API key matches on all parents.

### High Memory Usage

1. Adjust retention on parents:
```ini
[db]
    dbengine tier 0 retention size = 5GiB
    dbengine tier 1 retention size = 5GiB
    dbengine tier 2 retention size = 5GiB
```

2. Enable thin mode on resource-constrained children.

## Next Steps

1. Monitor the setup for 24-48 hours
2. Set up alerting for parent/child disconnections
3. Document the new configuration
4. Plan regular API key rotation (quarterly)
5. Consider implementing Netdata Cloud integration

## Support Resources

- Netdata Community: https://community.netdata.cloud/
- GitHub Issues: https://github.com/netdata/netdata/issues
- Documentation: https://learn.netdata.cloud/