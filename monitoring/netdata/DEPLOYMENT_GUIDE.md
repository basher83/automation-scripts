# Netdata Parent-Child Architecture Deployment Guide

This guide walks through deploying Netdata in a parent-child architecture with high availability and mutual replication for the Nomad cluster.

## Network Architecture

- **Management Network (2.5G)**: 192.168.10.0/24 - Used for SSH and management
- **Application Network (10G)**: 192.168.11.0/24 - Used for Netdata streaming
- All Netdata streaming traffic flows over the 10G network to optimize performance

## Quick Start

### 1. Deploy Parent Nodes

Deploy Netdata on your three parent nodes (holly, lloyd, mable) with 10G network configuration:

```bash
# On holly (Mgmt: 192.168.10.2, 10G: 192.168.11.2)
sudo ./scripts/install-netdata-parent.sh \
    --hostname holly \
    --bind-ip 192.168.11.2 \
    --peers "192.168.11.3,192.168.11.4" \
    --children "192.168.11.11 192.168.11.12 192.168.11.13 192.168.11.20 192.168.11.21 192.168.11.22" \
    --api-key "nomad-cluster-api-key" \
    --replication-key "parent-replication-key" \
    --retention 30

# On lloyd (Mgmt: 192.168.10.3, 10G: 192.168.11.3)
sudo ./scripts/install-netdata-parent.sh \
    --hostname lloyd \
    --bind-ip 192.168.11.3 \
    --peers "192.168.11.2,192.168.11.4" \
    --children "192.168.11.11 192.168.11.12 192.168.11.13 192.168.11.20 192.168.11.21 192.168.11.22" \
    --api-key "nomad-cluster-api-key" \
    --replication-key "parent-replication-key" \
    --retention 30

# On mable (Mgmt: 192.168.10.4, 10G: 192.168.11.4)
sudo ./scripts/install-netdata-parent.sh \
    --hostname mable \
    --bind-ip 192.168.11.4 \
    --peers "192.168.11.2,192.168.11.3" \
    --children "192.168.11.11 192.168.11.12 192.168.11.13 192.168.11.20 192.168.11.21 192.168.11.22" \
    --api-key "nomad-cluster-api-key" \
    --replication-key "parent-replication-key" \
    --retention 30
```

### 2. Deploy Child Nodes

Deploy Netdata on all child nodes using 10G network IPs:

```bash
# For Nomad servers with Consul monitoring
# Run on nomad-server-1 (10G: 192.168.11.11), nomad-server-2 (10G: 192.168.11.12), nomad-server-3 (10G: 192.168.11.13)
sudo ./scripts/install-netdata-child.sh \
    --parents "192.168.11.2,192.168.11.3,192.168.11.4" \
    --api-key "nomad-cluster-api-key" \
    --consul

# For Nomad clients with Consul and Docker monitoring
# Run on nomad-client-1 (10G: 192.168.11.20), nomad-client-2 (10G: 192.168.11.21), nomad-client-3 (10G: 192.168.11.22)
sudo ./scripts/install-netdata-child.sh \
    --parents "192.168.11.2,192.168.11.3,192.168.11.4" \
    --api-key "nomad-cluster-api-key" \
    --consul \
    --docker

# For thin mode (minimal resources) - if needed for any resource-constrained nodes
sudo ./scripts/install-netdata-child.sh \
    --parents "192.168.11.2,192.168.11.3,192.168.11.4" \
    --api-key "nomad-cluster-api-key" \
    --thin-mode
```

### 3. Enable Parent Replication

If you deployed parents without mutual replication, enable it using 10G network IPs:

```bash
# On holly
sudo ./scripts/configure-parent-replication.sh \
    --node-ip 192.168.11.2 \
    --peer-ips "192.168.11.3,192.168.11.4" \
    --replication-key "parent-replication-key"

# On lloyd
sudo ./scripts/configure-parent-replication.sh \
    --node-ip 192.168.11.3 \
    --peer-ips "192.168.11.2,192.168.11.4" \
    --replication-key "parent-replication-key"

# On mable
sudo ./scripts/configure-parent-replication.sh \
    --node-ip 192.168.11.4 \
    --peer-ips "192.168.11.2,192.168.11.3" \
    --replication-key "parent-replication-key"
```

### 4. Verify Deployment

Check the status on each node:

```bash
# Check parent node status
sudo ./scripts/check-netdata-status.sh --type parent --verbose

# Check child node status
sudo ./scripts/check-netdata-status.sh --type child --verbose
```

## Manual Configuration

### Network Interface Binding

To ensure Netdata binds to the correct network interface:

```bash
# Edit /etc/netdata/netdata.conf on parent nodes
[web]
    # Bind to specific 10G interface
    bind to = 192.168.11.2:19999  # Holly
    # bind to = 192.168.11.3:19999  # Lloyd
    # bind to = 192.168.11.4:19999  # Mable
    
    # Or bind to all interfaces (default)
    # bind to = *
```

### Updating Existing Configurations

If you have existing Netdata installations, you can manually update the configurations:

1. **On Parent Nodes**: Copy the relevant sections from `examples/parent-stream.conf`
2. **On Child Nodes**: Copy the configuration from `examples/child-stream.conf`
3. Update IPs to use 10G network (192.168.11.0/24)
4. Restart Netdata: `sudo systemctl restart netdata`

### Adding New Child Nodes

To add new child nodes to the architecture:

1. Update parent `stream.conf` to include the new child IP in the `allow from` line
2. Install Netdata on the child using the install script
3. Verify connection in parent logs

### Firewall Rules

Ensure port 19999 is open on the 10G network:

```bash
# UFW example - allow from 10G network
sudo ufw allow from 192.168.11.0/24 to any port 19999

# iptables example
sudo iptables -A INPUT -p tcp --dport 19999 -s 192.168.11.0/24 -j ACCEPT

# If you need to allow management network access for dashboards
sudo ufw allow from 192.168.10.0/24 to any port 19999
```

## Monitoring

### Access Dashboards

- **Parent Dashboards**: Access via management IPs
  - Holly: `http://192.168.10.2:19999`
  - Lloyd: `http://192.168.10.3:19999`
  - Mable: `http://192.168.10.4:19999`
  - Shows all child nodes and local metrics
  - Includes replicated data from other parents

- **Child Dashboards**: Access via management IPs
  - Nomad Servers: `http://192.168.10.11-13:19999`
  - Nomad Clients: `http://192.168.10.20-22:19999`
  - Shows local metrics only (unless in thin mode)
  - Thin mode children have minimal local dashboard

### Key Metrics to Monitor

1. **Streaming Health**
   - Check "Netdata" → "Streaming" in parent dashboards
   - Monitor connection stability and bandwidth usage

2. **Replication Status**
   - Verify all parents show the same child nodes
   - Check for replication lag or gaps

3. **Resource Usage**
   - Monitor parent nodes for disk and memory usage
   - Adjust retention settings if needed

## Troubleshooting

### Common Issues

1. **Child Not Appearing in Parent**

   ```bash
   # On child
   grep "established" /var/log/netdata/error.log
   
   # On parent
   grep "new client" /var/log/netdata/error.log
   ```

2. **Replication Not Working**

   ```bash
   # Check replication connections
   ss -tnp | grep 19999
   
   # Verify API keys match
   grep "api key" /etc/netdata/stream.conf
   ```

3. **High Memory Usage**
   - Reduce retention days
   - Enable compression in stream.conf
   - Consider thin mode for children

### Log Locations

- **Error Log**: `/var/log/netdata/error.log`
- **Access Log**: `/var/log/netdata/access.log`
- **Config Backup**: `/etc/netdata/*.backup.*`

## Maintenance

### Updating Netdata

```bash
# Update all nodes
cd /opt/netdata
sudo ./netdata-updater.sh

# Or use package manager
sudo apt update && sudo apt upgrade netdata
```

### Backup Configuration

```bash
# Backup all configs
sudo tar -czf netdata-config-$(date +%Y%m%d).tar.gz /etc/netdata/

# Backup parent data
sudo tar -czf netdata-data-$(date +%Y%m%d).tar.gz /var/cache/netdata/
```

### Scaling Considerations

- **Parents**: Add more parents for redundancy, not performance
- **Children**: Can scale to hundreds per parent
- **Retention**: 30 days at ~100 children ≈ 50-100GB per parent
- **Network**: ~100-500 Kbps per child continuous bandwidth

### Network Optimization Benefits

Using the 10G network for Netdata streaming provides:

1. **Performance Isolation**: Monitoring traffic doesn't impact management operations
2. **Bandwidth Headroom**: 10G provides ample capacity for scaling
3. **Lower Latency**: Dedicated high-speed network reduces metric delivery time
4. **Future Proof**: Room to add more nodes without network bottlenecks

## Next Steps

1. Set up alerting and notifications
2. Configure Prometheus export if needed
3. Integrate with Grafana for custom dashboards
4. Set up automated backups
5. Document your specific API keys and configurations
