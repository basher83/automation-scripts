# Netdata Configuration Best Practices and Analysis

This document provides a comprehensive analysis of the current Netdata configuration and recommendations based on official best practices from the netdata/netdata repository.

## Configuration Analysis Summary

### Current Issues Identified

1. **Network Configuration Inconsistency**
   - Documentation references 10G network (192.168.11.0/24) for optimal streaming performance
   - Actual configurations use management network (192.168.10.0/24)
   - This mismatch could impact performance and bandwidth utilization

2. **Incomplete Parent Replication Setup**
   - Parent nodes not properly configured for mutual replication
   - Missing streaming configuration between parent nodes
   - Incorrect IP addresses in replication allow lists

3. **Security Gaps**
   - No TLS/SSL encryption configured
   - Using predictable API keys instead of UUIDs
   - Missing IP-based access restrictions

4. **Performance Optimization Missing**
   - No compression enabled for streaming
   - Default buffer sizes not optimized for 10G network
   - No selective metric streaming configured

## Best Practices Implementation Guide

### 1. Network Architecture Best Practices

#### Dedicated Streaming Network

Use the high-bandwidth network (10G) for all Netdata streaming traffic:

```ini
# Parent nodes should bind to 10G interface
[web]
    bind to = 192.168.11.X:19999  # Replace X with host-specific IP
```

#### Benefits

- Isolates monitoring traffic from management operations
- Provides ample bandwidth for scaling
- Reduces latency for real-time metrics
- Future-proof for infrastructure growth

### 2. Security Configuration

#### Generate Secure API Keys

Always use UUIDs for API keys:

```bash
# Generate unique keys for different purposes
uuidgen  # For child-to-parent streaming
uuidgen  # For parent-to-parent replication
uuidgen  # For specific node groups
```

#### Enable TLS/SSL Encryption

**On Parent Nodes:**

1. Generate SSL certificates (example using self-signed):

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/netdata/ssl/key.pem \
    -out /etc/netdata/ssl/cert.pem
```

2. Configure Netdata to use SSL:

```ini
[web]
    ssl key = /etc/netdata/ssl/key.pem
    ssl certificate = /etc/netdata/ssl/cert.pem
```

**On Child Nodes:**

```ini
[stream]
    enabled = yes
    destination = 192.168.11.2:19999:SSL 192.168.11.3:19999:SSL 192.168.11.4:19999:SSL
    ssl skip certificate verification = yes  # For self-signed certs
    api key = YOUR-UUID-HERE
```

#### IP-Based Access Control

```ini
# Parent stream.conf - restrict child connections
[child-api-key]
    enabled = yes
    allow from = 192.168.11.11-13 192.168.11.20-22  # Use ranges
    default postpone alarms on connect = 60s
```

### 3. High Availability Configuration

#### Parent-to-Parent Replication

Each parent should stream to all other parents:

**Holly (192.168.11.2):**

```ini
[stream]
    enabled = yes
    destination = 192.168.11.3:19999:SSL 192.168.11.4:19999:SSL
    api key = parent-replication-uuid
    enable compression = yes
    buffer size bytes = 10485760  # 10MB for 10G network
```

**Lloyd (192.168.11.3):**

```ini
[stream]
    enabled = yes
    destination = 192.168.11.2:19999:SSL 192.168.11.4:19999:SSL
    api key = parent-replication-uuid
    enable compression = yes
    buffer size bytes = 10485760
```

**Mable (192.168.11.4):**

```ini
[stream]
    enabled = yes
    destination = 192.168.11.2:19999:SSL 192.168.11.3:19999:SSL
    api key = parent-replication-uuid
    enable compression = yes
    buffer size bytes = 10485760
```

#### Child Failover Configuration

```ini
[stream]
    enabled = yes
    # List all parents for automatic failover
    destination = 192.168.11.2:19999:SSL 192.168.11.3:19999:SSL 192.168.11.4:19999:SSL
    api key = child-streaming-uuid
    timeout seconds = 60
    reconnect delay seconds = 5
    buffer size bytes = 10485760  # 10MB buffer
    enable compression = yes
```

### 4. Performance Optimization

#### Selective Metrics Streaming

Filter metrics to reduce bandwidth usage:

```ini
# Stream only essential metrics
[stream]
    send charts matching = system.* cpu.* mem.* disk.* net.* apps.*
    
# Exclude specific metrics
[stream]
    send charts matching = !*.docker* !users.* *
```

#### Buffer and Compression Settings

```ini
[stream]
    # Compression reduces bandwidth by 60-80%
    enable compression = yes
    
    # Larger buffer for 10G networks
    buffer size bytes = 10485760  # 10MB
    
    # Handle temporary disconnections
    buffer on failures = 30  # Keep 30 seconds of data
```

#### Parent Storage Configuration

```ini
# netdata.conf on parents
[db]
    mode = dbengine
    
    # Adjust based on retention needs and available disk
    dbengine tier 0 retention size = 10GiB  # High-res data
    dbengine tier 1 retention size = 10GiB  # Medium-res data
    dbengine tier 2 retention size = 10GiB  # Low-res data
    
    # Memory for caching
    dbengine page cache size = 512MiB
```

### 5. Resource Management

#### Thin Mode for Resource-Constrained Nodes

```ini
# Child netdata.conf for minimal footprint
[ml]
    enabled = no
    
[health]
    enabled = no
    
[web]
    mode = none  # Disable local dashboard
    
# Child stream.conf
[stream]
    memory mode = ram  # Or 'none' for streaming-only
```

#### Child Retention for Replication

```ini
# Minimum retention for failover scenarios
[db]
    # With parent cluster: 5-10 minutes
    dbengine tier 0 retention time = 600  # 10 minutes
    
    # Single parent: longer retention
    dbengine tier 0 retention time = 3600  # 1 hour
```

### 6. Monitoring and Maintenance

#### Health Monitoring Configuration

```ini
# Parent accepting children
[child-api-key]
    enabled = yes
    health enabled by default = auto
    postpone alarms on connect = 60s
    
# Parent accepting replication
[parent-replication-key]
    enabled = yes
    health enabled = no  # Parents handle their own health
```

#### Ephemeral Node Settings

For temporary or auto-scaling nodes:

```ini
# netdata.conf on ephemeral nodes
[global]
    is ephemeral node = yes
```

#### Connection Monitoring

```bash
# Check streaming status on parent
curl -s http://localhost:19999/api/v1/info | jq '.stream'

# Monitor connection logs
journalctl -r --namespace=netdata MESSAGE_ID=ed4cdb8f1beb4ad3b57cb3cae2d162fa
```

### 7. Maintenance Procedures

#### Parent Maintenance with Zero Data Loss

1. Before taking a parent offline:

   ```bash
   # Block new child connections
   iptables -I INPUT -p tcp --dport 19999 -s 192.168.11.0/24 -j REJECT
   ```

2. Wait for children to reconnect to other parents:

   ```bash
   # Monitor until no active child connections
   ss -tnp | grep :19999
   ```

3. Perform maintenance

4. Before bringing back online:

   ```bash
   # Keep children blocked until sync completes
   # Let parent sync with peers first
   ```

5. After sync completes:

   ```bash
   # Remove firewall block
   iptables -D INPUT -p tcp --dport 19999 -s 192.168.11.0/24 -j REJECT
   ```

#### Creating New Parent from Existing

```bash
# Stop source parent
systemctl stop netdata

# Copy data to new parent
rsync -av /var/cache/netdata/ newparent:/var/cache/netdata/

# Configure retention on new parent BEFORE starting
# Edit /etc/netdata/netdata.conf with retention settings

# Start new parent
systemctl start netdata
```

## Implementation Priority

1. **Immediate Actions (Critical)**
   - Generate UUID API keys
   - Fix network configuration to use 10G IPs
   - Enable parent-to-parent replication

2. **Short-term (High Priority)**
   - Implement TLS/SSL encryption
   - Configure compression
   - Set proper retention policies

3. **Medium-term (Optimization)**
   - Implement selective streaming
   - Optimize buffer sizes
   - Configure thin mode where appropriate

4. **Long-term (Enhancement)**
   - Implement monitoring dashboards
   - Set up automated health checks
   - Create backup/restore procedures

## Validation Checklist

- [ ] All streaming uses 10G network IPs
- [ ] UUID API keys in use
- [ ] Parent-to-parent replication working
- [ ] Children connect to all parents
- [ ] TLS/SSL encryption enabled
- [ ] Compression enabled
- [ ] Proper retention configured
- [ ] Health monitoring active
- [ ] Connection logs monitored
- [ ] Backup procedures documented

## References

- [Official Netdata Streaming Documentation](https://github.com/netdata/netdata/tree/master/docs/observability-centralization-points/metrics-centralization-points)
- [Clustering and High Availability](https://github.com/netdata/netdata/blob/master/docs/observability-centralization-points/metrics-centralization-points/clustering-and-high-availability-of-netdata-parents.md)
- [Configuration Guide](https://github.com/netdata/netdata/blob/master/docs/observability-centralization-points/metrics-centralization-points/configuration.md)
- [Performance Analysis: Netdata vs Prometheus](https://blog.netdata.cloud/netdata-vs-prometheus-performance-analysis/)
